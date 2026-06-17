// dart format width=120

import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/export/export_options.dart';
import 'package:beariscope/pages/export/export_service.dart';
import 'package:beariscope/pages/export/save_helper.dart';
import 'package:beariscope/pages/export/ui_creator_schema.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_logic.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_preferences_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/processed_scouting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  final _matchFromController = TextEditingController();
  final _matchToController = TextEditingController();

  ExportSheets _sheets = const ExportSheets(rawMatch: true);

  bool _includeNotes = true;
  bool _colorCodeAccuracy = false;
  bool _anonymizeScouters = false;
  bool _filterByTeam = false;
  bool _filterByMatchRange = false;
  bool _isExporting = false;
  Set<int> _selectedTeams = {};

  ColorThresholds _colorThresholds = ColorThresholds.defaults;
  CorrectionThresholds _correctionThresholds = CorrectionThresholds.defaults;
  double _incorrectDataThreshold = kDefaultIncorrectDataThreshold;

  UiCreatorSchema? _schema;
  String? _schemaError;

  @override
  void initState() {
    super.initState();
    _loadSchema();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final savedThreshold = ref.read(scoutAuditIncorrectThresholdProvider);
      if (mounted && savedThreshold != _incorrectDataThreshold) {
        setState(() => _incorrectDataThreshold = savedThreshold);
      }
    });
  }

  @override
  void dispose() {
    _matchFromController.dispose();
    _matchToController.dispose();
    super.dispose();
  }

  Future<void> _loadSchema() async {
    try {
      final schema = await UiCreatorSchema.load();
      if (mounted) setState(() => _schema = schema);
    } catch (e) {
      if (mounted) setState(() => _schemaError = e.toString());
    }
  }

  ExportOptions _buildOptions() {
    final matchFrom = _filterByMatchRange ? int.tryParse(_matchFromController.text.trim()) : null;
    final matchTo = _filterByMatchRange ? int.tryParse(_matchToController.text.trim()) : null;
    return ExportOptions(
      matchFrom: matchFrom,
      matchTo: matchTo,
      teamFilter: _filterByTeam && _selectedTeams.isNotEmpty ? Set.unmodifiable(_selectedTeams) : null,
      includeNotes: _includeNotes,
      colorCodeAccuracy: _colorCodeAccuracy,
      anonymizeScouters: _anonymizeScouters,
      sheets: _sheets,
      colorThresholds: _colorThresholds,
      correctionThresholds: _correctionThresholds,
      incorrectDataThreshold: _incorrectDataThreshold,
    );
  }

  List<int> _allTeams(List<ScoutingDocument> docs, String currentEvent) {
    final teams = <int>{};

    for (final doc in docs) {
      if (doc.meta?['event']?.toString() != currentEvent) continue;
      final type = doc.meta?['type']?.toString();

      if (type == 'match') {
        final team = TeamScoutingBundle.teamNumber(doc);
        if (team != null) teams.add(team);
      } else if (type == 'strat') {
        for (final key in const [
          'driverSkillRanking',
          'defensiveSkillRanking',
          'defensiveResilienceRanking',
          'mechanicalStabilityRanking',
          'offensiveConsistencyRanking',
        ]) {
          final list = doc.data[key];
          if (list is! List) continue;
          for (final entry in list) {
            final team = int.tryParse(entry?.toString() ?? '');
            if (team != null) teams.add(team);
          }
        }
      }
    }
    return teams.toList()..sort();
  }

  Future<void> _export() async {
    if (!_sheets.hasAny) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select at least one sheet to export.')));
      return;
    }

    if (_sheets.hasMatchData && _schema == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schema not loaded yet. Please wait.')));
      return;
    }

    final processedBundle = ref.read(processedScoutingProvider).value;
    final rawDocs = processedBundle?.rawDocs ?? [];
    final processedDocs = processedBundle?.processedDocs ?? [];

    if (rawDocs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No scouting data available to export.')));
      return;
    }

    setState(() => _isExporting = true);

    try {
      final eventKey = ref.read(currentEventProvider);
      final options = _buildOptions();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      Map<int, Map<String, ({int auto, int tele, List<int> teams})>>? tbaMatchData;
      List<Map<String, dynamic>>? rawTbaMatches;
      if ((_sheets.hasMatchData && _colorCodeAccuracy) || _sheets.correctionTodoList) {
        try {
          final client = ref.read(honeycombClientProvider);
          final raw = await client.get<List<dynamic>>('/matches', queryParams: {'event': eventKey});
          rawTbaMatches = raw.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList(growable: false);
          tbaMatchData = _parseTbaMatches(raw);
        } catch (error) {
          if (_sheets.correctionTodoList && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Correction To-Do List requires TBA match data: $error')));
            return;
          }
          tbaMatchData = null;
        }
      }

      ScoutAuditSnapshot? auditSnapshot;
      if (_sheets.correctionTodoList && rawTbaMatches != null) {
        auditSnapshot = buildScoutAuditSnapshot(
          docs: rawDocs,
          tbaMatches: rawTbaMatches,
          eventKey: eventKey,
          incorrectThreshold: options.incorrectDataThreshold,
        );
      }

      final bytes = await Future.microtask(
        () => ExportService.buildConsolidatedExcel(
          rawDocs: rawDocs,
          processedDocs: processedDocs,
          schema: _schema!,
          options: options,
          eventKey: eventKey,
          tbaMatchData: tbaMatchData,
          auditSnapshot: auditSnapshot,
        ),
      );

      final filename = 'export_${eventKey}_$stamp.xlsx';

      if (mounted) {
        await saveOrShareExcel(context, bytes, filename);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final processedAsync = ref.watch(processedScoutingProvider);
    final allDocs = processedAsync.value?.rawDocs ?? [];
    final currentEvent = ref.watch(currentEventProvider);
    final permissionChecker = ref.watch(permissionCheckerProvider);
    final options = _buildOptions();
    final allTeams = _allTeams(allDocs, currentEvent);
    final colorScheme = Theme.of(context).colorScheme;

    final canExportNotes = permissionChecker?.hasPermission(PermissionKey.notesRead) ?? false;
    if (!canExportNotes && _includeNotes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _includeNotes) {
          setState(() => _includeNotes = false);
        }
      });
    }
    final includeNotes = canExportNotes && _includeNotes;
    if (!canExportNotes) {
      _includeNotes = false;
    }

    final counts = ExportService.previewCounts(allDocs, options, currentEvent);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Data'),
        leading: controller.isDesktop
            ? null
            : IconButton(icon: const Icon(Symbols.menu_rounded), onPressed: controller.openDrawer),
      ),
      body: _schemaError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Symbols.error_rounded, size: 48),
                    const SizedBox(height: 12),
                    Text('Failed to load schema: $_schemaError', textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : _schema == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SectionCard(
                                title: 'Export Sheets',
                                child: Column(
                                  children: [
                                    _SheetCheckbox(
                                      label: 'Raw Match Data',
                                      subtitle: '${counts.match} ${counts.match == 1 ? 'entry' : 'entries'}',
                                      value: _sheets.rawMatch,
                                      onChanged: (v) => setState(() {
                                        _sheets = _sheets.copyWith(rawMatch: v);
                                      }),
                                    ),
                                    _SheetCheckbox(
                                      label: 'Auto-Corrected Match Data',
                                      subtitle: 'Auto-corrects fuel counts based on TBA data',
                                      value: _sheets.processedMatch,
                                      onChanged: (v) => setState(() {
                                        _sheets = _sheets.copyWith(processedMatch: v);
                                      }),
                                    ),
                                    const Divider(height: 16),
                                    _SheetCheckbox(
                                      label: 'Strat Raw',
                                      subtitle: '${counts.stratRaw} ${counts.stratRaw == 1 ? 'row' : 'rows'}',
                                      value: _sheets.stratRaw,
                                      onChanged: (v) => setState(() {
                                        _sheets = _sheets.copyWith(stratRaw: v);
                                      }),
                                    ),
                                    _SheetCheckbox(
                                      label: 'Strat Z-Score',
                                      subtitle: '${counts.stratZScore} ${counts.stratZScore == 1 ? 'team' : 'teams'}',
                                      value: _sheets.stratZScore,
                                      onChanged: (v) => setState(() {
                                        _sheets = _sheets.copyWith(stratZScore: v);
                                      }),
                                    ),
                                    const Divider(height: 16),
                                    _SheetCheckbox(
                                      label: 'Correction To-Do List',
                                      subtitle: 'Current Scout Audit issues',
                                      value: _sheets.correctionTodoList,
                                      onChanged: (v) => setState(() {
                                        _sheets = _sheets.copyWith(correctionTodoList: v);
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              _SectionCard(
                                title: 'Filters',
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Match Range'),
                                      subtitle: const Text('Restrict to specific matches'),
                                      value: _filterByMatchRange,
                                      onChanged: (v) => setState(() {
                                        _filterByMatchRange = v;
                                        if (!v) {
                                          _matchFromController.clear();
                                          _matchToController.clear();
                                        }
                                      }),
                                    ),
                                    if (_filterByMatchRange) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _matchFromController,
                                              onChanged: (_) => setState(() {}),
                                              keyboardType: TextInputType.number,
                                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                              decoration: const InputDecoration(
                                                labelText: 'From',
                                                hintText: 'Any',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: TextField(
                                              controller: _matchToController,
                                              onChanged: (_) => setState(() {}),
                                              keyboardType: TextInputType.number,
                                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                              decoration: const InputDecoration(
                                                labelText: 'To',
                                                hintText: 'Any',
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const Divider(height: 24),

                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Team Filter'),
                                      subtitle: const Text('Select specific teams'),
                                      value: _filterByTeam,
                                      onChanged: (v) => setState(() => _filterByTeam = v),
                                    ),
                                    if (_filterByTeam) ...[
                                      const SizedBox(height: 8),
                                      if (allTeams.isEmpty)
                                        Text(
                                          'No scouting data loaded yet.',
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            FilterChip(
                                              label: const Text('All'),
                                              selected: _selectedTeams.isEmpty,
                                              onSelected: (selected) {
                                                if (selected) {
                                                  setState(() => _selectedTeams = {});
                                                }
                                              },
                                            ),
                                            ...allTeams.map(
                                              (team) => FilterChip(
                                                label: Text('$team'),
                                                selected: _selectedTeams.contains(team),
                                                onSelected: (selected) {
                                                  setState(() {
                                                    if (selected) {
                                                      _selectedTeams = {..._selectedTeams, team};
                                                    } else {
                                                      _selectedTeams = {..._selectedTeams}..remove(team);
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (_selectedTeams.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            '${_selectedTeams.length} of ${allTeams.length} teams',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              if (_sheets.hasMatchData)
                                _SectionCard(
                                  title: 'Match Content Options',
                                  child: Column(
                                    children: [
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Include Notes'),
                                        subtitle: const Text('Endgame free-text field'),
                                        value: includeNotes,
                                        onChanged: canExportNotes ? (v) => setState(() => _includeNotes = v) : null,
                                      ),
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Color-code Accuracy'),
                                        subtitle: const Text('Highlight cells by TBA deviation'),
                                        value: _colorCodeAccuracy,
                                        onChanged: (v) => setState(() => _colorCodeAccuracy = v),
                                      ),
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Anonymize Scouters'),
                                        subtitle: const Text('Remove scouter names from match exports'),
                                        value: _anonymizeScouters,
                                        onChanged: (v) => setState(() => _anonymizeScouters = v),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_sheets.hasMatchData) const SizedBox(height: 16),

                              if (_colorCodeAccuracy && _sheets.hasMatchData) ...[
                                _SectionCard(
                                  title: 'Coloring Thresholds',
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'These settings control how spreadsheet cells are colored based on how far off our scouted data is from the official TBA results. A lower percentage means the data has to be highly accurate to avoid getting marked as an error.',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          _ColorLegendDot(
                                            color: Colors.transparent,
                                            label: '0–${(_colorThresholds.good * 100).toInt()}%',
                                          ),
                                          _ColorLegendDot(
                                            color: const Color(0xFFFEF08A),
                                            label:
                                                '${(_colorThresholds.good * 100).toInt()}–${(_colorThresholds.warning * 100).toInt()}%',
                                          ),
                                          _ColorLegendDot(
                                            color: const Color(0xFFFED7AA),
                                            label:
                                                '${(_colorThresholds.warning * 100).toInt()}–${(_colorThresholds.bad * 100).toInt()}%',
                                          ),
                                          _ColorLegendDot(
                                            color: const Color(0xFFFECACA),
                                            label: '${(_colorThresholds.bad * 100).toInt()}%+',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      SfSliderTheme(
                                        data: SfSliderThemeData(
                                          activeTrackHeight: 8,
                                          inactiveTrackHeight: 8,
                                          thumbRadius: 12,
                                          overlayRadius: 20,
                                          activeTrackColor: colorScheme.primary,
                                          inactiveTrackColor: colorScheme.surfaceContainerHighest,
                                          thumbColor: colorScheme.primary,
                                          overlayColor: colorScheme.primary.withAlpha(50),
                                          tooltipBackgroundColor: colorScheme.primaryContainer,
                                          tooltipTextStyle: Theme.of(
                                            context,
                                          ).textTheme.labelSmall?.copyWith(color: colorScheme.onPrimaryContainer),
                                        ),
                                        child: Column(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 70,
                                                        child: Text(
                                                          'Good',
                                                          style: Theme.of(context).textTheme.labelSmall,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: SfSliderTheme(
                                                          data: SfSliderThemeData(
                                                            activeTrackHeight: 8,
                                                            inactiveTrackHeight: 8,
                                                            thumbRadius: 12,
                                                            overlayRadius: 20,
                                                            inactiveTrackColor: Theme.of(
                                                              context,
                                                            ).colorScheme.surfaceContainerHighest,
                                                            tooltipBackgroundColor: Theme.of(
                                                              context,
                                                            ).colorScheme.primaryContainer,
                                                            tooltipTextStyle: Theme.of(context).textTheme.labelSmall
                                                                ?.copyWith(
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.onPrimaryContainer,
                                                                ),
                                                          ),
                                                          child: SfSlider(
                                                            min: 0.0,
                                                            max: (_colorThresholds.warning - 0.01).clamp(0.0, 1.0),
                                                            value: _colorThresholds.good.clamp(
                                                              0.0,
                                                              (_colorThresholds.warning - 0.01),
                                                            ),
                                                            stepSize: 0.01,
                                                            enableTooltip: true,
                                                            tooltipTextFormatterCallback:
                                                                (actualValue, formattedText) =>
                                                                    '${(actualValue * 100).toStringAsFixed(0)}%',
                                                            onChanged: (dynamic newValue) {
                                                              final nv = (newValue as double).clamp(
                                                                0.0,
                                                                (_colorThresholds.warning - 0.01),
                                                              );
                                                              setState(() {
                                                                _colorThresholds = ColorThresholds(
                                                                  good: nv,
                                                                  warning: _colorThresholds.warning,
                                                                  bad: _colorThresholds.bad,
                                                                );
                                                              });
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 45,
                                                        child: Text(
                                                          '${(_colorThresholds.good * 100).toStringAsFixed(0)}%',
                                                          style: Theme.of(context).textTheme.labelSmall,
                                                          textAlign: TextAlign.end,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Values at or below this boundary are treated as accurate enough to stay uncolored. Crossing this boundary marks the cell with yellow.',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 70,
                                                        child: Text(
                                                          'Warning',
                                                          style: Theme.of(context).textTheme.labelSmall,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: SfSliderTheme(
                                                          data: SfSliderThemeData(
                                                            activeTrackHeight: 8,
                                                            inactiveTrackHeight: 8,
                                                            thumbRadius: 12,
                                                            overlayRadius: 20,
                                                            inactiveTrackColor: Theme.of(
                                                              context,
                                                            ).colorScheme.surfaceContainerHighest,
                                                            tooltipBackgroundColor: Theme.of(
                                                              context,
                                                            ).colorScheme.primaryContainer,
                                                            tooltipTextStyle: Theme.of(context).textTheme.labelSmall
                                                                ?.copyWith(
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.onPrimaryContainer,
                                                                ),
                                                          ),
                                                          child: SfSlider(
                                                            min: (_colorThresholds.good + 0.01).clamp(0.0, 1.0),
                                                            max: (_colorThresholds.bad - 0.01).clamp(0.0, 1.0),
                                                            value: _colorThresholds.warning.clamp(
                                                              (_colorThresholds.good + 0.01),
                                                              (_colorThresholds.bad - 0.01),
                                                            ),
                                                            stepSize: 0.01,
                                                            enableTooltip: true,
                                                            tooltipTextFormatterCallback:
                                                                (actualValue, formattedText) =>
                                                                    '${(actualValue * 100).toStringAsFixed(0)}%',
                                                            onChanged: (dynamic newValue) {
                                                              final nv = (newValue as double).clamp(
                                                                (_colorThresholds.good + 0.01),
                                                                (_colorThresholds.bad - 0.01),
                                                              );
                                                              setState(() {
                                                                _colorThresholds = ColorThresholds(
                                                                  good: _colorThresholds.good,
                                                                  warning: nv,
                                                                  bad: _colorThresholds.bad,
                                                                );
                                                              });
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 45,
                                                        child: Text(
                                                          '${(_colorThresholds.warning * 100).toStringAsFixed(0)}%',
                                                          style: Theme.of(context).textTheme.labelSmall,
                                                          textAlign: TextAlign.end,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Crossing this boundary marks the cell with orange so moderate deviation stands out.',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 70,
                                                        child: Text(
                                                          'Bad',
                                                          style: Theme.of(context).textTheme.labelSmall,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: SfSliderTheme(
                                                          data: SfSliderThemeData(
                                                            activeTrackHeight: 8,
                                                            inactiveTrackHeight: 8,
                                                            thumbRadius: 12,
                                                            overlayRadius: 20,
                                                            inactiveTrackColor: Theme.of(
                                                              context,
                                                            ).colorScheme.surfaceContainerHighest,
                                                            tooltipBackgroundColor: Theme.of(
                                                              context,
                                                            ).colorScheme.primaryContainer,
                                                            tooltipTextStyle: Theme.of(context).textTheme.labelSmall
                                                                ?.copyWith(
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.onPrimaryContainer,
                                                                ),
                                                          ),
                                                          child: SfSlider(
                                                            min: (_colorThresholds.warning + 0.01).clamp(0.0, 1.0),
                                                            max: 1.0,
                                                            value: _colorThresholds.bad.clamp(
                                                              (_colorThresholds.warning + 0.01),
                                                              1.0,
                                                            ),
                                                            stepSize: 0.01,
                                                            enableTooltip: true,
                                                            tooltipTextFormatterCallback:
                                                                (actualValue, formattedText) =>
                                                                    '${(actualValue * 100).toStringAsFixed(0)}%',
                                                            onChanged: (dynamic newValue) {
                                                              final nv = (newValue as double).clamp(
                                                                (_colorThresholds.warning + 0.01),
                                                                1.0,
                                                              );
                                                              setState(() {
                                                                _colorThresholds = ColorThresholds(
                                                                  good: _colorThresholds.good,
                                                                  warning: _colorThresholds.warning,
                                                                  bad: nv,
                                                                );
                                                              });
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 45,
                                                        child: Text(
                                                          '${(_colorThresholds.bad * 100).toStringAsFixed(0)}%',
                                                          style: Theme.of(context).textTheme.labelSmall,
                                                          textAlign: TextAlign.end,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Crossing this boundary marks the cell with red for large mismatches.',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (_sheets.processedMatch) ...[
                                _SectionCard(
                                  title: 'Auto-Correction Thresholds',
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Auto-correction tries to fix inaccurate scout data by comparing it to official TBA alliance totals',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 16),
                                      SfSliderTheme(
                                        data: SfSliderThemeData(
                                          activeTrackHeight: 8,
                                          inactiveTrackHeight: 8,
                                          thumbRadius: 12,
                                          overlayRadius: 20,
                                          activeTrackColor: colorScheme.primary,
                                          inactiveTrackColor: colorScheme.surfaceContainerHighest,
                                          thumbColor: colorScheme.primary,
                                          overlayColor: colorScheme.primary.withAlpha(50),
                                          tooltipBackgroundColor: colorScheme.primaryContainer,
                                          tooltipTextStyle: Theme.of(
                                            context,
                                          ).textTheme.labelSmall?.copyWith(color: colorScheme.onPrimaryContainer),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                SizedBox(
                                                  width: 100,
                                                  child: Text(
                                                    'Min deviation',
                                                    style: Theme.of(context).textTheme.labelSmall,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: SfSlider(
                                                    min: 0.0,
                                                    max: 0.50,
                                                    value: _correctionThresholds.minDeviation,
                                                    stepSize: 0.01,
                                                    enableTooltip: true,
                                                    tooltipTextFormatterCallback: (actualValue, formattedText) =>
                                                        '${(actualValue * 100).toStringAsFixed(0)}%',
                                                    onChanged: (dynamic v) => setState(
                                                      () => _correctionThresholds = _correctionThresholds.copyWith(
                                                        minDeviation: v as double,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 45,
                                                  child: Text(
                                                    '${(_correctionThresholds.minDeviation * 100).toStringAsFixed(0)}%',
                                                    style: Theme.of(context).textTheme.labelSmall,
                                                    textAlign: TextAlign.end,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'The app will only attempt to fix the data if it differs from the official total by more than this percentage.',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                            ),
                                            const SizedBox(height: 16),
                                            Row(
                                              children: [
                                                SizedBox(
                                                  width: 100,
                                                  child: Text(
                                                    'Max scalar',
                                                    style: Theme.of(context).textTheme.labelSmall,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: SfSlider(
                                                    min: 1.0,
                                                    max: 10.0,
                                                    value: _correctionThresholds.maxScalar,
                                                    stepSize: 0.1,
                                                    enableTooltip: true,
                                                    tooltipTextFormatterCallback: (actualValue, formattedText) =>
                                                        '${(actualValue).toStringAsFixed(1)}x',
                                                    onChanged: (dynamic v) => setState(
                                                      () => _correctionThresholds = _correctionThresholds.copyWith(
                                                        maxScalar: v as double,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 45,
                                                  child: Text(
                                                    '${_correctionThresholds.maxScalar.toStringAsFixed(1)}x',
                                                    style: Theme.of(context).textTheme.labelSmall,
                                                    textAlign: TextAlign.end,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'To prevent wildly impossible corrections (like multiplying a scouted score by 5 just to force the math to work), this sets a limit. If correcting the data requires multiplying it by more than this number, the app will cap the scalar.',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (_sheets.correctionTodoList) ...[
                                _SectionCard(
                                  title: 'Correction To-Do Threshold',
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Incorrect Data rows are included when alliance deviation is above this threshold.',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 16),
                                      SfSliderTheme(
                                        data: SfSliderThemeData(
                                          activeTrackHeight: 8,
                                          inactiveTrackHeight: 8,
                                          thumbRadius: 12,
                                          overlayRadius: 20,
                                          activeTrackColor: colorScheme.primary,
                                          inactiveTrackColor: colorScheme.surfaceContainerHighest,
                                          thumbColor: colorScheme.primary,
                                          overlayColor: colorScheme.primary.withAlpha(50),
                                          tooltipBackgroundColor: colorScheme.primaryContainer,
                                          tooltipTextStyle: Theme.of(
                                            context,
                                          ).textTheme.labelSmall?.copyWith(color: colorScheme.onPrimaryContainer),
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 100,
                                              child: Text('Threshold', style: Theme.of(context).textTheme.labelSmall),
                                            ),
                                            Expanded(
                                              child: SfSlider(
                                                min: 0.05,
                                                max: 1.0,
                                                value: _incorrectDataThreshold,
                                                stepSize: 0.01,
                                                enableTooltip: true,
                                                tooltipTextFormatterCallback: (actualValue, _) =>
                                                    '${(actualValue * 100).toStringAsFixed(0)}%',
                                                onChanged: (dynamic value) {
                                                  setState(() => _incorrectDataThreshold = value as double);
                                                },
                                              ),
                                            ),
                                            SizedBox(
                                              width: 45,
                                              child: Text(
                                                '${(_incorrectDataThreshold * 100).toStringAsFixed(0)}%',
                                                textAlign: TextAlign.end,
                                                style: Theme.of(context).textTheme.labelSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              Card(
                                color: colorScheme.surfaceContainer,
                                elevation: 0,
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (_sheets.hasAny)
                                        Wrap(
                                          spacing: 16,
                                          runSpacing: 4,
                                          children: [
                                            if (_sheets.rawMatch || _sheets.processedMatch)
                                              _PreviewChip(
                                                icon: Symbols.table_chart_rounded,
                                                label: '${counts.match} Match Entr${counts.match == 1 ? 'y' : 'ies'}',
                                              ),
                                            if (_sheets.stratRaw)
                                              _PreviewChip(
                                                icon: Symbols.analytics_rounded,
                                                label: '${counts.stratRaw} Strat Row${counts.stratRaw == 1 ? '' : 's'}',
                                              ),
                                            if (_sheets.stratZScore)
                                              _PreviewChip(
                                                icon: Symbols.trending_up_rounded,
                                                label:
                                                    '${counts.stratZScore} Z-Score${counts.stratZScore == 1 ? '' : 's'}',
                                              ),
                                            if (_sheets.correctionTodoList)
                                              const _PreviewChip(
                                                icon: Symbols.rule_rounded,
                                                label: 'Correction To-Do List',
                                              ),
                                          ],
                                        ),
                                      if (_sheets.hasAny) const SizedBox(height: 12),
                                      FilledButton.icon(
                                        onPressed: (_isExporting || !_sheets.hasAny) ? null : _export,
                                        icon: _isExporting
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Symbols.download_rounded),
                                        label: Text(
                                          _isExporting
                                              ? 'Exporting…'
                                              : _sheets.hasAny
                                              ? 'Export to Excel'
                                              : 'Select sheets to export',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }

  static Map<int, Map<String, ({int auto, int tele, List<int> teams})>> _parseTbaMatches(List<dynamic> raw) {
    final result = <int, Map<String, ({int auto, int tele, List<int> teams})>>{};
    for (final item in raw) {
      if (item is! Map) continue;
      if (item['comp_level']?.toString() != 'qm') continue;
      final matchNumber = item['match_number'];
      if (matchNumber is! int) continue;
      final breakdown = item['score_breakdown'];
      final alliances = item['alliances'];
      final allianceData = <String, ({int auto, int tele, List<int> teams})>{};
      for (final alliance in ['red', 'blue']) {
        final allianceSide = alliances is Map ? alliances[alliance] : null;
        final teamKeys = allianceSide is Map ? allianceSide['team_keys'] : null;
        final teams = <int>[];
        if (teamKeys is List) {
          for (final key in teamKeys) {
            final s = key?.toString() ?? '';
            final parsed = int.tryParse(s.startsWith('frc') ? s.substring(3) : s);
            if (parsed != null) teams.add(parsed);
          }
        }
        int auto = 0;
        int tele = 0;
        if (breakdown is Map) {
          final side = breakdown[alliance];
          if (side is Map) {
            final hubScore = side['hubScore'];
            if (hubScore is Map) {
              auto = _intFromMap(hubScore, 'autoCount');
              tele = _intFromMap(hubScore, 'teleopCount');
            }
          }
        }
        if (teams.isNotEmpty) {
          allianceData[alliance] = (auto: auto, tele: tele, teams: teams);
        }
      }
      if (allianceData.isNotEmpty) result[matchNumber] = allianceData;
    }
    return result;
  }

  static int _intFromMap(Map map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    return 0;
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child}) : trailing = null;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _SheetCheckbox extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SheetCheckbox({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

class _ColorLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _ColorLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color == Colors.transparent ? null : color,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PreviewChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
