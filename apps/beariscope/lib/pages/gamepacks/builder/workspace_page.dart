import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:ui/ui.dart';

import 'analysis_editor.dart';
import 'builder_help.dart';
import 'design.dart';
import 'fixture.dart';
import 'fixture_editor.dart';
import 'form_editor.dart';
import 'team_card_editor.dart';
import 'sorting_editor.dart';
import 'worksheet_editor.dart';
import 'workspace_dock.dart';

class GamePackWorkspacePage extends ConsumerStatefulWidget {
  const GamePackWorkspacePage({
    super.key,
    required this.event,
    this.gamePack,
    this.imported,
    this.formsLocked = false,
    this.duplicate = false,
  });
  final String event;
  final GamePack? gamePack;
  final GamePackDesign? imported;
  final bool formsLocked;
  final bool duplicate;
  @override
  ConsumerState<GamePackWorkspacePage> createState() =>
      _GamePackWorkspacePageState();
}

typedef _ReviewIssue = ({GamePackBuilderSection? section, String message});

class _GamePackWorkspacePageState extends ConsumerState<GamePackWorkspacePage> {
  GamePackBuilderSection _section = GamePackBuilderSection.forms;
  GamePackBuilderSection _outputSelection = GamePackBuilderSection.card;
  final _visited = {GamePackBuilderSection.forms};
  final _formSelection = ValueNotifier<String?>(null);
  GamePackDockTab? _dockTray;
  GamePackDockTab? _sidebarGroup = GamePackDockTab.forms;
  bool _dirty = false;
  bool _confirmingExit = false;
  GamePackDesign? _reviewed;
  List<_ReviewIssue> _issues = const [];

  late GamePack? _saved = widget.duplicate ? null : widget.gamePack;
  late final String _id = widget.duplicate
      ? const Uuid().v4()
      : widget.gamePack?.id ?? const Uuid().v4();
  late GamePackDesign _design =
      widget.imported ??
      (widget.gamePack != null
          ? GamePackDesign.fromJson(widget.gamePack!.document)
          : GamePackDesign(
              season: int.tryParse(
                widget.event.length >= 4 ? widget.event.substring(0, 4) : '',
              ),
            ));
  late GamePackBuilderFixture _fixture = _loadFixture();
  bool _busy = false;
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _formSelection.dispose();
    super.dispose();
  }

  void _open(GamePackBuilderSection section) {
    if (section != _section) FocusScope.of(context).unfocus();
    setState(() {
      _visited.add(section);
      _section = section;
      if (GamePackBuilderSection.outputs.contains(section)) {
        _outputSelection = section;
      }
      _sidebarGroup = _selectedTab.hasChoices ? _selectedTab : null;
      _dockTray = null;
    });
  }

  void _dismissTray() => setState(() => _dockTray = null);

  void _selectDockTab(GamePackDockTab tab) {
    switch (tab) {
      case GamePackDockTab.forms || GamePackDockTab.outputs:
        setState(() => _dockTray = _dockTray == tab ? null : tab);
      case GamePackDockTab.metrics:
        _open(GamePackBuilderSection.metrics);
      case GamePackDockTab.review:
        _open(GamePackBuilderSection.review);
    }
  }

  void _selectDockChoice(String id) {
    if (_dockTray == GamePackDockTab.forms) {
      _formSelection.value = id;
      _open(GamePackBuilderSection.forms);
    } else if (_dockTray == GamePackDockTab.outputs) {
      _open(GamePackBuilderSection.values.byName(id));
    }
  }

  bool get _isOutputDetail => GamePackBuilderSection.outputs.contains(_section);

  void _applyLayout(GamePackCardEdit edited) {
    final kind = edited.layout.kind;
    final layout = edited.layout;
    _change(
      _design.copyWith(
        calculations: edited.calculations,
        teamCards: [
          for (final existing in _design.teamCards)
            if (existing.kind != kind) existing,
          if (layout.sections.isNotEmpty) layout,
        ],
      ),
    );
  }

  bool _isInSeason(String event, int? season) =>
      season != null && event.startsWith(season.toString());

  String _defaultTestEvent(int? season) =>
      _isInSeason(widget.event, season) ? widget.event : '';

  GamePackBuilderFixture _loadFixture() {
    final defaultEvent = _defaultTestEvent(_design.season);
    final fixture = GamePackBuilderFixture.fromJson(
      widget.gamePack?.document['builderFixture'],
      defaultEvent: defaultEvent,
      design: _design,
    );
    return fixture.event.isEmpty || _isInSeason(fixture.event, _design.season)
        ? fixture
        : fixture.selectEvent(defaultEvent);
  }

  void _change(GamePackDesign next) => setState(() {
    if (next.season != _design.season &&
        !_isInSeason(_fixture.event, next.season)) {
      _fixture = _fixture.selectEvent(_defaultTestEvent(next.season));
    }
    _design = next;
    _dirty = true;
    _message = null;
  });

  void _report(String message, {required bool error}) {
    if (mounted) {
      setState(() {
        _message = message;
        _error = error;
      });
    }
  }

  Future<GamePack> _persist() async {
    final grove = ref.read(bearingsGroveProvider);
    final gamePack = GamePack(
      id: _id,
      document: {..._design.toJson(), 'builderFixture': _fixture.toJson()},
    );
    final previous = _saved;
    _saved = previous == null
        ? await grove.create<GamePack>(gamePack, allowOffline: false)
        : await grove.update<GamePack>(
            _id,
            (_) => gamePack,
            allowOffline: false,
          );
    return _saved!;
  }

  Future<void> _saveGamePack() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      _validatePackDetails();
      final gamePack = await _persist();
      if (mounted) Navigator.of(context).pop(gamePack);
    } catch (error) {
      _report(_describe(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(Object error) => switch (error) {
    FormatException() => error.message,
    GroveException() => error.message,
    _ => error.toString(),
  };

  String? get _nameError => _packNameError(_design.name);
  String? get _seasonError => _packSeasonError(_design.season?.toString());

  void _validatePackDetails() {
    if ((_nameError ?? _seasonError) case final error?) {
      throw FormatException(error);
    }
  }

  Future<void> _editPackDetails(BuildContext context) async {
    if (_dockTray != null) _dismissTray();
    final details = await BearingsModal.show<({String name, int? season})>(
      context,
      builder: (_) =>
          _PackDetailsModal(name: _design.name, season: _design.season),
    );
    if (!mounted ||
        details == null ||
        (details.name == _design.name && details.season == _design.season)) {
      return;
    }
    _change(_design.copyWith(name: details.name, season: () => details.season));
  }

  Future<void> _leave() async {
    if (_confirmingExit || _busy) return;
    _confirmingExit = true;
    try {
      final discard = await BearingsAlertDialog.show<bool>(
        context: context,
        title: 'Leave this GamePack?',
        message: 'Changes since your last save will be lost.',
        actions: const [
          BearingsAlertAction(label: 'Cancel'),
          BearingsAlertAction(
            label: 'Discard changes',
            role: BearingsAlertActionRole.destructive,
            result: true,
          ),
        ],
      );
      if (mounted && discard == true) Navigator.of(context).pop();
    } finally {
      _confirmingExit = false;
    }
  }

  Future<void> _openTestData(
    BuildContext context,
    GamePackBuilderFixture fixture,
  ) async {
    if (_dockTray != null) _dismissTray();
    final updated = await BearingsModal.show<GamePackBuilderFixture>(
      context,
      builder: (_) => GamePackFixtureEditor(design: _design, fixture: fixture),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _dirty =
          _dirty ||
          jsonEncode(updated.toJson()) != jsonEncode(_fixture.toJson());
      _fixture = updated;
      _message = null;
    });
  }

  List<_ReviewIssue> _review() {
    if (identical(_reviewed, _design)) return _issues;
    final issues = <_ReviewIssue>[];
    const forms = GamePackBuilderSection.forms;
    const metrics = GamePackBuilderSection.metrics;
    void check(GamePackBuilderSection? section, VoidCallback validate) {
      try {
        validate();
      } on FormatException catch (error) {
        issues.add((section: section, message: error.message));
      }
    }

    check(null, _validatePackDetails);
    if (_design.questions.isEmpty) {
      issues.add((
        section: forms,
        message: 'Add at least one question to a scouting form.',
      ));
    }
    for (final form in _design.configuredForms) {
      check(forms, () => form.validate(_design.fieldById));
    }
    GamePackAnalysis? analysis;
    if (issues.isEmpty) {
      check(metrics, () {
        analysis = GamePackAnalysis(
          fields: _design.fields,
          forms: _design.forms,
          tbaFields: _design.tbaFields,
          calculations: _design.calculations,
          reportChoices: _design.reportChoices,
        );
      });
    }
    if (analysis case final catalog?) {
      for (final layout in _design.teamCards) {
        check(
          layout.kind == GamePackTeamCardKind.compact
              ? GamePackBuilderSection.card
              : GamePackBuilderSection.details,
          () => layout.validate(catalog),
        );
      }
      for (final sort in _design.results.sorts) {
        check(GamePackBuilderSection.sorting, () => sort.validate(catalog));
      }
      for (final filter in _design.results.filters) {
        check(GamePackBuilderSection.sorting, () => filter.validate(catalog));
      }
      for (final sheet in _design.results.sheets) {
        check(
          GamePackBuilderSection.exports,
          () => sheet.validate(catalog, _design.configuredForms),
        );
      }
    }
    if (issues.isEmpty) {
      check(forms, () => _design.compile());
    }
    _reviewed = _design;
    return _issues = issues;
  }

  Widget _reviewPage(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final issues = _review();
    final ready = issues.isEmpty;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    String count(int total, String label) =>
        '$total $label${total == 1 ? '' : 's'}';
    final summary = [
      (
        GamePackBuilderSection.forms,
        '${count(_design.configuredForms.length, 'form')} · ${count(_design.questions.length, 'question')}',
      ),
      (
        GamePackBuilderSection.metrics,
        count(_design.calculations.length, 'calculation'),
      ),
      (
        GamePackBuilderSection.card,
        count(_design.teamCards.length, 'team layout'),
      ),
      (
        GamePackBuilderSection.sorting,
        '${count(_design.results.sorts.length, 'sort')} · ${count(_design.results.filters.length, 'filter')}',
      ),
      (
        GamePackBuilderSection.exports,
        count(_design.results.sheets.length, 'sheet'),
      ),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 22 : 16, 4, 16, 24),
      children: [
        Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Icon(
                      ready ? LucideIcons.circleCheck : LucideIcons.circleAlert,
                      size: 17,
                      color: ready ? colors.onSurfaceVariant : colors.error,
                    ),
                    Expanded(
                      child: Text(
                        ready
                            ? 'Ready to assign'
                            : 'Finish these before assigning',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (ready)
                  Text(
                    'Forms with questions are included. Assign this GamePack to an event to use it for scouting.',
                    style: muted,
                  )
                else
                  for (final issue in issues)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        issue.message,
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        issue.section?.label ?? 'Pack details',
                        style: muted,
                      ),
                      trailing: Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      onTap: () => issue.section == null
                          ? _editPackDetails(context)
                          : _open(issue.section!),
                    ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed:
                          _busy || _nameError != null || _seasonError != null
                          ? null
                          : _saveGamePack,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                      child: const Text('Save GamePack'),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Text('In this GamePack', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final (section, detail) in summary)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 48,
                    title: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        Text(section.label, style: theme.textTheme.bodyMedium),
                        Text(detail, style: muted),
                      ],
                    ),
                    trailing: Icon(
                      LucideIcons.chevronRight,
                      color: colors.onSurfaceVariant,
                      size: 16,
                    ),
                    onTap: () => _open(section),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _page(
    BuildContext context,
    GamePackBuilderSection section, {
    required bool wide,
    required GamePackBuilderFixture fixture,
  }) {
    return switch (section) {
      GamePackBuilderSection.forms => Stack(
        children: [
          IgnorePointer(
            ignoring: widget.formsLocked,
            child: GamePackFormsEditor(
              design: _design,
              onChanged: _change,
              compact: !wide,
              formSelection: _formSelection,
            ),
          ),
          if (widget.formsLocked)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card.outlined(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Forms are locked because an event assigned to this GamePack has saved data. Other GamePack sections remain editable.',
                  ),
                ),
              ),
            ),
        ],
      ),
      GamePackBuilderSection.outputHome => BearingsCardList(
        maxWidth: 780,
        children: [
          for (final output in GamePackBuilderSection.outputs)
            BearingsCard(
              title: output.label,
              subtitle: output.description,
              leading: Icon(output.icon, size: 20),
              trailing: const Icon(LucideIcons.chevronRight, size: 18),
              onTap: () => _open(output),
            ),
        ],
      ),
      GamePackBuilderSection.metrics => GamePackAnalysisEditor(
        design: _design,
        fixture: fixture,
        compact: !wide,
        onChanged: _change,
      ),
      GamePackBuilderSection.card ||
      GamePackBuilderSection.details => GamePackTeamCardEditor(
        kind: section == GamePackBuilderSection.card
            ? GamePackTeamCardKind.compact
            : GamePackTeamCardKind.details,
        design: _design,
        fixture: fixture,
        compact: !wide,
        onChanged: _applyLayout,
      ),
      GamePackBuilderSection.sorting => GamePackSortingEditor(
        design: _design,
        fixture: fixture,
        compact: !wide,
        onChanged: _change,
      ),
      GamePackBuilderSection.exports => GamePackWorksheetEditor(
        design: _design,
        fixture: fixture,
        compact: !wide,
        onChanged: _change,
      ),
      GamePackBuilderSection.review => _reviewPage(context, wide: wide),
    };
  }

  GamePackDockTab get _selectedTab => switch (_section) {
    GamePackBuilderSection.forms => GamePackDockTab.forms,
    GamePackBuilderSection.metrics => GamePackDockTab.metrics,
    GamePackBuilderSection.review => GamePackDockTab.review,
    _ => GamePackDockTab.outputs,
  };

  List<GamePackDockChoice> _navigationChoices(GamePackDockTab? group) =>
      switch (group) {
        GamePackDockTab.forms => [
          for (final form in _design.forms)
            (
              id: form.id,
              label: form.label,
              icon: switch (form.kind) {
                GamePackFormKind.match => LucideIcons.clipboardList,
                GamePackFormKind.strategy => LucideIcons.workflow,
                GamePackFormKind.pit => LucideIcons.wrench,
                GamePackFormKind.observation => LucideIcons.notebookPen,
              },
            ),
        ],
        GamePackDockTab.outputs => [
          for (final output in GamePackBuilderSection.outputs)
            (id: output.name, label: output.label, icon: output.icon),
        ],
        _ => const [],
      };

  String? _selectedChoice(GamePackDockTab? group, String? form) {
    if (group == GamePackDockTab.forms) return form ?? _design.forms.first.id;
    if (group == GamePackDockTab.outputs) {
      return _outputSelection.name;
    }
    return null;
  }

  Widget _sidebar() => ValueListenableBuilder<String?>(
    valueListenable: _formSelection,
    builder: (context, form, _) => GamePackWorkspaceSidebar(
      selected: _selectedTab,
      expanded: _sidebarGroup,
      choices: _navigationChoices(_sidebarGroup),
      selectedChoice: _sidebarGroup == _selectedTab
          ? _selectedChoice(_sidebarGroup, form)
          : null,
      enabled: !_busy,
      onTab: (tab) {
        switch (tab) {
          case GamePackDockTab.forms || GamePackDockTab.outputs:
            setState(() => _sidebarGroup = _sidebarGroup == tab ? null : tab);
          case GamePackDockTab.metrics:
            _open(GamePackBuilderSection.metrics);
          case GamePackDockTab.review:
            _open(GamePackBuilderSection.review);
        }
      },
      onChoice: (id) {
        if (_sidebarGroup == GamePackDockTab.forms) {
          _formSelection.value = id;
          _open(GamePackBuilderSection.forms);
        } else {
          _open(GamePackBuilderSection.values.byName(id));
        }
      },
    ),
  );

  Widget _workspaceLayout({required bool showDock, required Widget child}) {
    final tray = showDock ? _dockTray : null;
    return ValueListenableBuilder<String?>(
      valueListenable: _formSelection,
      child: child,
      builder: (context, form, child) => GamePackWorkspaceDock(
        visible: showDock,
        selected: _selectedTab,
        expanded: tray,
        choices: _navigationChoices(tray),
        selectedChoice: _selectedChoice(tray, form),
        onTab: _selectDockTab,
        onChoice: _selectDockChoice,
        onDismiss: _dismissTray,
        enabled: !_busy,
        child: child!,
      ),
    );
  }

  Widget _pageHeader(BuildContext context, bool wide) {
    if (_section == GamePackBuilderSection.forms ||
        _section == GamePackBuilderSection.metrics ||
        _isOutputDetail) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final review = _section == GamePackBuilderSection.review;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 22 : 16, wide ? 19 : 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            _section.label,
            style: wide && !review
                ? theme.textTheme.headlineSmall
                : theme.textTheme.titleLarge,
          ),
          if (wide && !review)
            Text(
              _section.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(gamePackFixtureEventProvider(_fixture.event));
    final fixture = _fixture.withData(event.value ?? _fixture.data);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status =
        _message ??
        (_dirty
            ? 'Unsaved changes'
            : _saved == null
            ? 'Not saved to library'
            : 'Saved to library');
    return InputDecorationTheme(
      data: InputDecorationTheme.of(context).copyWith(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        isDense: true,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final showDock =
              !wide && MediaQuery.viewInsetsOf(context).bottom == 0;
          final trayOpen = showDock && _dockTray != null;
          final showTestDataLabel = constraints.maxWidth >= 420;
          final editTestData = _busy
              ? null
              : () => _openTestData(context, fixture);
          const testDataIcon = Icon(LucideIcons.flaskConical, size: 19);
          return PopScope<GamePack>(
            canPop: !_dirty && !_busy && !trayOpen,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop || _busy) return;
              if (trayOpen) {
                _dismissTray();
              } else if (_dirty) {
                _leave();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: Tooltip(
                  message: 'Edit GamePack details',
                  child: TextButton(
                    onPressed: _busy ? null : () => _editPackDetails(context),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(48, 48),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _design.name.isEmpty
                                    ? 'Untitled GamePack'
                                    : _design.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _design.season == null
                                      ? status
                                      : '${_design.season} · $status',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _error && _message != null
                                        ? colors.error
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.chevronDown, size: 16),
                      ],
                    ),
                  ),
                ),
                actions: [
                  if (showTestDataLabel)
                    TextButton.icon(
                      onPressed: editTestData,
                      icon: testDataIcon,
                      label: const Text('Edit test data'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Edit test data',
                      onPressed: editTestData,
                      icon: testDataIcon,
                    ),
                  IconButton(
                    tooltip: 'Builder help',
                    onPressed: _busy
                        ? null
                        : () {
                            if (trayOpen) _dismissTray();
                            showGamePackBuilderHelp(context, _section);
                          },
                    icon: const Icon(LucideIcons.circleHelp, size: 19),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: _workspaceLayout(
                showDock: showDock,
                child: Column(
                  children: [
                    if (_busy)
                      const LinearProgressIndicator()
                    else
                      const Divider(height: 1),
                    if (_error && _message != null)
                      Material(
                        color: colors.errorContainer,
                        child: ListTile(
                          leading: Icon(
                            LucideIcons.circleAlert,
                            color: colors.onErrorContainer,
                          ),
                          title: Text(
                            _message!,
                            style: TextStyle(color: colors.onErrorContainer),
                          ),
                          trailing: IconButton(
                            tooltip: 'Dismiss message',
                            onPressed: () => setState(() => _message = null),
                            icon: const Icon(LucideIcons.x),
                          ),
                        ),
                      ),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: _busy,
                        child: Row(
                          children: [
                            SizedBox(
                              width: wide ? 208 : 0,
                              child: wide ? _sidebar() : null,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _pageHeader(context, wide),
                                  Expanded(
                                    child: IndexedStack(
                                      index: _section.index,
                                      sizing: StackFit.expand,
                                      children: [
                                        for (final section
                                            in GamePackBuilderSection.values)
                                          if (_visited.contains(section))
                                            TickerMode(
                                              enabled: _section == section,
                                              child: ExcludeFocus(
                                                excluding: _section != section,
                                                child:
                                                    PrimaryScrollController.none(
                                                      child: _page(
                                                        context,
                                                        section,
                                                        wide: wide,
                                                        fixture: fixture,
                                                      ),
                                                    ),
                                              ),
                                            )
                                          else
                                            const SizedBox.shrink(),
                                      ],
                                    ),
                                  ),
                                ],
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
          );
        },
      ),
    );
  }
}

String? _packNameError(String? name) {
  try {
    validateGamePackLabel(name ?? '');
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

String? _packSeasonError(String? value) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) return null;
  final season = int.tryParse(input);
  return season == null || season < 1992 || season > 9999
      ? 'Enter a valid FRC season.'
      : null;
}

class _PackDetailsModal extends StatefulWidget {
  const _PackDetailsModal({required this.name, required this.season});
  final String name;
  final int? season;

  @override
  State<_PackDetailsModal> createState() => _PackDetailsModalState();
}

class _PackDetailsModalState extends State<_PackDetailsModal> {
  final _form = GlobalKey<FormState>();
  late String _name = widget.name;
  late String _season = widget.season?.toString() ?? '';

  void _apply() {
    if (!_form.currentState!.validate()) return;
    BearingsModal.complete(context, (
      name: _name.trim(),
      season: int.tryParse(_season.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) => BearingsModal(
    title: 'Pack details',
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Done',
      icon: LucideIcons.check,
      onPressed: _apply,
    ),
    content: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          TextFormField(
            initialValue: _name,
            decoration: const InputDecoration(labelText: 'Pack name'),
            textInputAction: TextInputAction.next,
            validator: _packNameError,
            onChanged: (value) => _name = value,
          ),
          TextFormField(
            initialValue: _season,
            decoration: const InputDecoration(labelText: 'Season'),
            keyboardType: TextInputType.number,
            validator: _packSeasonError,
            onChanged: (value) => _season = value,
            onFieldSubmitted: (_) => _apply(),
          ),
        ],
      ),
    ),
  );
}
