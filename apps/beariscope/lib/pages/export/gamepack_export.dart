import 'package:core/core.dart';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_spinner.dart';
import 'package:ui/widgets/bearings_status_view.dart';

import '../gamepacks/gamepack_displays.dart';
import '../main_view.dart';
import 'save_helper.dart';

class GamePackExportPage extends ConsumerStatefulWidget {
  const GamePackExportPage({super.key, required this.event});

  final String event;

  @override
  ConsumerState<GamePackExportPage> createState() => _GamePackExportPageState();
}

class _GamePackExportPageState extends ConsumerState<GamePackExportPage> {
  final _excluded = <String>{};
  final _firstMatch = TextEditingController();
  final _lastMatch = TextEditingController();
  final _teamNumbers = TextEditingController();
  bool _includeScout = false;
  bool _saving = false;

  @override
  void dispose() {
    _firstMatch.dispose();
    _lastMatch.dispose();
    _teamNumbers.dispose();
    super.dispose();
  }

  Future<void> _save(
    GamePackEventAnalysis analysis,
    Map<String, String> roster, {
    required bool canExportScout,
  }) async {
    setState(() => _saving = true);
    try {
      int? matchNumber(TextEditingController input) {
        final text = input.text.trim();
        if (text.isEmpty) return null;
        final number = int.tryParse(text);
        if (number == null || number < 1) {
          throw const FormatException('Enter a positive qualification number.');
        }
        return number;
      }

      final first = matchNumber(_firstMatch);
      final last = matchNumber(_lastMatch);
      if (first != null && last != null && first > last) {
        throw const FormatException(
          'The first qualification must precede the last.',
        );
      }
      final qualification = RegExp(r'_qm([0-9]+)$');
      bool withinRange(String match) {
        if (first == null && last == null) return true;
        final matchNumber = int.tryParse(
          qualification.firstMatch(match)?.group(1) ?? '',
        );
        return matchNumber != null &&
            (first == null || matchNumber >= first) &&
            (last == null || matchNumber <= last);
      }

      final teams = <String>{};
      for (final token
          in _teamNumbers.text
              .trim()
              .split(RegExp(r'[,\s]+'))
              .where((part) => part.isNotEmpty)) {
        final number = int.tryParse(
          token.toLowerCase().replaceFirst('frc', ''),
        );
        if (number == null || number < 1) {
          throw const FormatException(
            'Enter team numbers separated by commas.',
          );
        }
        teams.add('frc$number');
      }
      final bytes = buildGamePackWorkbook(
        analysis: first == null && last == null
            ? analysis
            : analysis.filterMatches(withinRange),
        sheets: analysis.analysis.definition.results.sheets.where(
          (sheet) => !_excluded.contains(sheet.id),
        ),
        teamNames: roster,
        includeScout: _includeScout && canExportScout,
        teams: teams,
      );
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      if (mounted) {
        await saveOrShareExcel(context, bytes, '${widget.event}_$stamp.xlsx');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed. $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final canExportScout =
        ref
            .watch(permissionCheckerProvider)
            ?.hasPermission(PermissionKey.scoutsRead) ==
        true;
    final analysis = ref.watch(gamePackEventAnalysisProvider(widget.event));
    final roster = {
      for (final team
          in ref.watch(competitionTeamsProvider(widget.event)).value?.items ??
              const <CompetitionTeam>[])
        team.id: team.nickname ?? team.name ?? 'Team ${team.number}',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Data'),
        leading: controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                onPressed: controller.openDrawer,
              ),
      ),
      body: analysis.when(
        loading: () => const Center(child: BearingsSpinner()),
        error: (error, _) => BearingsStatusView(
          icon: LucideIcons.circleAlert,
          title: 'Export unavailable',
          subtitle: '$error',
        ),
        data: (pack) {
          if (pack == null) {
            return const Center(child: Text('No GamePack assigned'));
          }
          final sheets = pack.analysis.definition.results.sheets;
          if (sheets.isEmpty) {
            return const BearingsStatusView(
              title: 'No export sheets',
              subtitle:
                  'Set up a workbook in GamePack Builder under Export Sheets.',
              icon: LucideIcons.table,
            );
          }
          final selectedSheets = sheets
              .where((sheet) => !_excluded.contains(sheet.id))
              .toList();
          return BearingsCardList(
            children: [
              if (pack.offline)
                const ListTile(
                  leading: Icon(LucideIcons.cloudOff),
                  title: Text('Exporting cached records'),
                ),
              for (final sheet in sheets)
                CheckboxListTile(
                  title: Text(sheet.name),
                  subtitle: Text(sheet.rows.description),
                  value: !_excluded.contains(sheet.id),
                  onChanged: _saving
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            _excluded.remove(sheet.id);
                          } else {
                            _excluded.add(sheet.id);
                          }
                        }),
                ),
              if (canExportScout &&
                  selectedSheets.any(
                    (sheet) => sheet.columns.any(
                      (column) => column.info == GamePackColumnInfo.scout,
                    ),
                  ))
                CheckboxListTile(
                  title: const Text('Include scout IDs in submissions'),
                  value: _includeScout,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            setState(() => _includeScout = value == true),
                ),
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _firstMatch,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'First qualification',
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _lastMatch,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Last qualification',
                      ),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _teamNumbers,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Team numbers',
                  helperText: 'Comma-separated. Leave blank for all teams.',
                ),
              ),
              FilledButton.icon(
                onPressed: _saving || selectedSheets.isEmpty
                    ? null
                    : () => _save(pack, roster, canExportScout: canExportScout),
                icon: const Icon(LucideIcons.download),
                label: Text(
                  _saving ? 'Preparing workbook…' : 'Export Excel workbook',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

List<int> buildGamePackWorkbook({
  required GamePackEventAnalysis analysis,
  Iterable<GamePackWorksheet>? sheets,
  Map<String, String> teamNames = const {},
  bool includeScout = false,
  Set<String> teams = const {},
}) {
  final chosen = (sheets ?? analysis.analysis.definition.results.sheets)
      .toList();
  if (chosen.isEmpty) throw StateError('Select at least one sheet to export.');
  final workbook = Excel.createExcel();
  final initial = workbook.getDefaultSheet()!;
  if (initial != chosen.first.name) workbook.rename(initial, chosen.first.name);
  final session = analysis.session(analysis.analysis.definition.analysis);
  for (final config in chosen) {
    final sheet = workbook[config.name];
    sheet.appendRow([
      for (final column in config.columns) TextCellValue(column.heading),
    ]);
    for (final row in config.values(
      session,
      teamNames: teamNames,
      teams: teams,
      includeScout: includeScout,
    )) {
      sheet.appendRow(row.map(_valueCell).toList());
    }
  }
  workbook.setDefaultSheet(chosen.first.name);
  return workbook.encode()!;
}

CellValue? _cell(Object? value) => switch (value) {
  final int value => IntCellValue(value),
  final double value => DoubleCellValue(value),
  final bool value => BoolCellValue(value),
  final String value => TextCellValue(value),
  _ => null,
};

CellValue? _valueCell(GamePackValue value) {
  if (!value.isKnown) return null;
  final data = value.data;
  return _cell(data) ??
      TextCellValue(
        data is List<GamePackValue>
            ? data.map(formatGamePackValue).join(', ')
            : formatGamePackValue(value),
      );
}
