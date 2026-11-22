import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'design.dart';
import 'fixture.dart';
import 'calculation_editor.dart';
import 'calculation_preview.dart';
import 'path_picker.dart';

export 'calculation_editor.dart' show editGamePackCalculation;
export 'result_picker.dart';

typedef _MetricEntry = ({
  String id,
  String label,
  String detail,
  String? operation,
  String? scope,
  String searchText,
  VoidCallback edit,
  VoidCallback remove,
});

class GamePackAnalysisEditor extends StatefulWidget {
  const GamePackAnalysisEditor({
    super.key,
    required this.design,
    required this.fixture,
    required this.compact,
    required this.onChanged,
  });

  final GamePackDesign design;
  final GamePackBuilderFixture fixture;
  final bool compact;
  final ValueChanged<GamePackDesign> onChanged;

  @override
  State<GamePackAnalysisEditor> createState() => _GamePackAnalysisEditorState();
}

class _GamePackAnalysisEditorState extends State<GamePackAnalysisEditor> {
  final _scroll = ScrollController();
  bool _official = false;
  bool _searching = false;
  String _query = '';

  GamePackDesign get design => widget.design;
  GamePackBuilderFixture get fixture => widget.fixture;
  ValueChanged<GamePackDesign> get onChanged => widget.onChanged;
  late GamePackAnalysisSession _session = fixture.analysisFor(design);

  @override
  void didUpdateWidget(GamePackAnalysisEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.design, design) ||
        !identical(oldWidget.fixture, fixture)) {
      _session = fixture.analysisFor(design);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _mapping([GamePackTbaField? current]) async {
    final field = await BearingsModal.show<GamePackTbaField>(
      context,
      builder: (_) =>
          _TbaMappingEditor(design: design, fixture: fixture, current: current),
    );
    if (mounted && field != null) {
      if (current == null && _searching) _toggleSearch();
      onChanged(
        design.copyWith(
          tbaFields: [
            for (final prior in design.tbaFields)
              if (current?.id != prior.id) prior else field,
            if (current == null) field,
          ],
        ),
      );
    }
  }

  Future<void> _recipe([GamePackCalculation? current]) async {
    final recipe = await editGamePackCalculation(
      context,
      design: design,
      fixture: fixture,
      current: current,
    );
    if (mounted && recipe != null) {
      if (current == null && _searching) _toggleSearch();
      onChanged(withGamePackCalculation(design, recipe));
    }
  }

  Future<void> _reportSettings() async {
    final choices = {...design.reportChoices};
    final updated = await BearingsModal.show<Map<String, GamePackReportChoice>>(
      context,
      builder: (_) => StatefulBuilder(
        builder: (context, update) => BearingsModal(
          title: 'When there are multiple reports',
          actions: const [],
          primaryAction: BearingsModalPrimaryAction(
            label: 'Done',
            icon: LucideIcons.check,
            onPressed: () => BearingsModal.complete(context, choices),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              for (final form in design.configuredForms)
                BearingsSelect<GamePackReportChoice>(
                  decoration: InputDecoration(labelText: form.label),
                  value: choices[form.id] ?? GamePackReportChoice.latest,
                  items: [
                    for (final choice in GamePackReportChoice.values)
                      BearingsSelectItem(
                        value: choice,
                        child: Text(choice.label),
                      ),
                  ],
                  onChanged: (choice) {
                    if (choice != null) update(() => choices[form.id] = choice);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted &&
        updated != null &&
        !mapEquals(updated, design.reportChoices)) {
      onChanged(design.copyWith(reportChoices: updated));
    }
  }

  void _selectView({required bool official}) {
    if (_official == official) return;
    _resetScroll();
    setState(() {
      _official = official;
      _searching = false;
      _query = '';
    });
  }

  void _toggleSearch() {
    _resetScroll();
    setState(() {
      _searching = !_searching;
      _query = '';
    });
  }

  void _resetScroll() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  _MetricEntry _calculationEntry(GamePackCalculation item) {
    final details = calculationDetails(design.catalog, item);
    final scope = design.catalog
        .tryInfo(gamePackFieldRef(item.id))
        ?.grain
        ?.label;
    final inputs = details.inputs;
    final detail = [
      details.operation,
      if (inputs.isNotEmpty)
        inputs.length == 1
            ? inputs.first
            : '${inputs.first} +${inputs.length - 1}',
    ].nonNulls.join(' · ');
    return (
      id: item.id,
      label: item.label,
      detail: detail,
      operation: details.operation,
      scope: scope,
      searchText: [
        item.label,
        details.operation,
        ...inputs,
        scope,
      ].nonNulls.join(' '),
      edit: () => _recipe(item),
      remove: () => onChanged(
        design.copyWith(
          calculations: design.calculations
              .where((entry) => entry.id != item.id)
              .toList(),
        ),
      ),
    );
  }

  _MetricEntry _officialEntry(GamePackTbaField item) {
    final path = item.paths.firstOrNull;
    final detail = path == null ? '' : _tbaPathLabel(path);
    return (
      id: item.id,
      label: item.label,
      detail: detail,
      operation: null,
      scope: item.grain.label,
      searchText:
          '${item.label} ${item.grain.label} $detail ${item.paths.join(' ')}',
      edit: () => _mapping(item),
      remove: () => onChanged(
        design.copyWith(
          tbaFields: design.tbaFields
              .where((entry) => entry.id != item.id)
              .toList(),
        ),
      ),
    );
  }

  Widget _addButton() {
    final label = Text(_official ? 'Link a TBA value' : 'Add calculation');
    final icon = Icon(
      _official ? LucideIcons.link : LucideIcons.plus,
      size: 17,
    );
    final onPressed = _official ? _mapping : _recipe;
    return FilledButton.icon(onPressed: onPressed, icon: icon, label: label);
  }

  Widget _header(BuildContext context, {required bool hasEntries}) {
    final compact = widget.compact;
    final picker = BearingsPopupMenu.button(
      label: _official ? 'Official values' : 'Calculations',
      tooltip: 'Switch metrics view',
      menuChildren: [
        BearingsMenuItem(
          selected: !_official,
          leadingIcon: const Icon(LucideIcons.calculator),
          onPressed: () => _selectView(official: false),
          child: const Text('Calculations'),
        ),
        BearingsMenuItem(
          selected: _official,
          leadingIcon: const Icon(LucideIcons.database),
          onPressed: () => _selectView(official: true),
          child: const Text('Official values'),
        ),
        if (design.configuredForms.isNotEmpty) ...[
          const Divider(height: 8),
          BearingsMenuItem(
            leadingIcon: const Icon(LucideIcons.settings2),
            onPressed: _reportSettings,
            child: const Text('When there are multiple reports'),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Row(
                spacing: 8,
                children: [
                  Text(
                    'Metrics',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Flexible(child: picker),
                  if (hasEntries)
                    IconButton(
                      tooltip: _searching ? 'Close search' : 'Find a metric',
                      onPressed: _toggleSearch,
                      icon: Icon(
                        _searching ? LucideIcons.x : LucideIcons.search,
                      ),
                    ),
                ],
              ),
            ),
            if (!compact && hasEntries) _addButton(),
          ],
        ),
        if (hasEntries && _searching)
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              labelText: _official
                  ? 'Find an official value'
                  : 'Find a calculation',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
            ),
            onChanged: (text) {
              _resetScroll();
              setState(() => _query = text.trim());
            },
          )
        else if (compact && hasEntries)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _addButton(),
          ),
      ],
    );
  }

  Widget _empty(BuildContext context, {required bool hasEntries}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, title, description) = hasEntries
        ? (LucideIcons.search, 'No matches', 'Try another search.')
        : _official
        ? (
            LucideIcons.link,
            'No official values linked',
            'Use a value from The Blue Alliance’s match breakdown in your calculations.',
          )
        : (
            LucideIcons.calculator,
            'No calculations yet',
            'Start with a scouting answer, like averaging fuel scored across matches.',
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 44, 4, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              spacing: 10,
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: colors.surfaceContainerHigh,
                  foregroundColor: colors.onSurfaceVariant,
                  child: Icon(icon, size: 22),
                ),
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (!hasEntries)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _addButton(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gutter = widget.compact ? 16.0 : 24.0;
    final source = _official
        ? design.tbaFields.map(_officialEntry)
        : design.calculations.map(_calculationEntry);
    final hasEntries = source.isNotEmpty;
    final entries = [
      for (final item in source)
        if (_query.isEmpty || matchesGamePackSearch(item.searchText, _query))
          item,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          _header(context, hasEntries: hasEntries),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: SizedBox.expand(
                  child: entries.isEmpty
                      ? _empty(context, hasEntries: hasEntries)
                      : LayoutBuilder(
                          builder: (context, bounds) => _list(
                            context,
                            entries,
                            columns: !widget.compact && bounds.maxWidth >= 560,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<_MetricEntry> entries, {
    required bool columns,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final captions = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final sampleWidth = columns ? 124.0 : 78.0;
    final sampleScope = fixture.scope;
    const scopeWidth = 144.0;
    const menuWidth = 48.0;

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
          sliver: SliverToBoxAdapter(
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    _official ? 'Official value' : 'Calculation',
                    style: captions,
                  ),
                ),
                if (columns)
                  SizedBox(
                    width: scopeWidth,
                    child: Text('Scope', style: captions),
                  ),
                SizedBox(
                  width: sampleWidth,
                  child: Text(
                    'Test value',
                    style: captions,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: menuWidth),
              ],
            ),
          ),
        ),
        SliverList.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            indent: 8,
            color: colors.outlineVariant.withValues(alpha: .55),
          ),
          itemBuilder: (context, index) {
            final item = entries[index];
            final value = _testValue(
              _session,
              gamePackFieldRef(item.id),
              sampleScope,
            );
            final sample = summarizeCalculationValue(value);
            final subtitle = columns
                ? item.detail
                : [item.scope, item.operation].nonNulls.join(' · ');
            return Row(
              key: ValueKey(item.id),
              spacing: 8,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: item.edit,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 9, 0, 9),
                      child: Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 2,
                              children: [
                                Text(
                                  item.label,
                                  style: theme.textTheme.titleSmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    style: secondary,
                                    maxLines: columns ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (columns)
                            SizedBox(
                              width: scopeWidth,
                              child: Text(item.scope ?? '—', style: secondary),
                            ),
                          SizedBox(
                            width: sampleWidth,
                            child: Text(
                              sample,
                              semanticsLabel: 'Test value: $sample',
                              textAlign: TextAlign.end,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: value.isKnown
                                  ? theme.textTheme.labelLarge
                                  : secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                BearingsPopupMenu.overflow(
                  tooltip: 'Options for ${item.label}',
                  menuChildren: [
                    BearingsMenuItem(
                      onPressed: item.remove,
                      leadingIcon: const Icon(LucideIcons.trash2),
                      destructive: true,
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }
}

class _TbaMappingEditor extends StatefulWidget {
  const _TbaMappingEditor({
    required this.design,
    required this.fixture,
    this.current,
  });

  final GamePackDesign design;
  final GamePackBuilderFixture fixture;
  final GamePackTbaField? current;

  @override
  State<_TbaMappingEditor> createState() => _TbaMappingEditorState();
}

class _TbaMappingEditorState extends State<_TbaMappingEditor> {
  late String _name = widget.current?.label ?? '';
  late GamePackGrain _grain =
      widget.current?.grain ?? GamePackGrain.allianceMatch;
  late GamePackType _type = widget.current?.type ?? GamePackType.number;
  late bool _numeric = widget.current?.numericText ?? false;
  late final _paths = [...?widget.current?.paths];
  late final _availablePaths = _eventPaths();

  Iterable<GamePackPathOption> _eventPaths() {
    final paths = <String, GamePackPathOption>{};
    for (final payload in widget.fixture.testPayloads) {
      for (final option in gamePackPathOptions(sample: payload)) {
        if (option.sample?.data case num() || String() || bool() || List()) {
          paths.putIfAbsent(option.path, () => option);
        }
      }
    }
    return paths.values;
  }

  Future<void> _addPath() async {
    final candidate = await pickGamePackPath(
      context,
      title: _paths.isEmpty ? 'Choose a TBA field' : 'Choose a fallback field',
      options: _availablePaths,
    );
    if (!mounted || candidate == null) return;
    var path = candidate.path;
    if (_grain != GamePackGrain.match) {
      path = path.replaceAllMapped(
        RegExp(r'(^|\.)(red|blue)(?=\.)'),
        (match) => '${match[1]}{alliance}',
      );
    }
    if (_grain == GamePackGrain.teamMatch) {
      path = path.replaceAllMapped(
        RegExp(r'(robot|station|position)[1-3](?![0-9])', caseSensitive: false),
        (match) => '${match[1]}{position}',
      );
      path = path.replaceFirst(RegExp(r'\.[012](?=\.|$)'), '.{slot}');
    }
    if (_paths.contains(path)) return;
    setState(() {
      if (_paths.isEmpty && widget.current == null) {
        final sample = candidate.sample?.data;
        _type = switch (sample) {
          bool() => GamePackType.boolean,
          String() => GamePackType.text,
          num() => GamePackType.number,
          List<GamePackValue>()
              when sample.every((item) => item.data is String) =>
            const GamePackType.list(GamePackType.text),
          _ => GamePackType.json,
        };
      }
      _paths.add(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final types = {
      GamePackType.number,
      GamePackType.integer,
      GamePackType.boolean,
      GamePackType.text,
      const GamePackType.list(GamePackType.text),
      GamePackType.json,
      _type,
    };
    final field = GamePackTbaField(
      id:
          widget.current?.id ??
          gamePackIdForName(_name, widget.design.resultIds, 'official_field'),
      label: _name.trim(),
      grain: _grain,
      type: _type,
      paths: _paths,
      numericText: _numeric && GamePackType.number.accepts(_type),
    );
    return BearingsModal(
      title: widget.current == null ? 'Link a TBA value' : 'Edit TBA value',
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Save mapping',
        icon: LucideIcons.check,
        onPressed: _name.trim().isEmpty || _paths.isEmpty
            ? null
            : () => BearingsModal.complete(context, field),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextFormField(
            initialValue: _name,
            decoration: const InputDecoration(labelText: 'Field name'),
            onChanged: (value) => setState(() => _name = value),
          ),
          BearingsSelect<GamePackGrain>(
            value: _grain,
            decoration: const InputDecoration(labelText: 'One value per'),
            items: [
              for (final grain in [
                GamePackGrain.match,
                GamePackGrain.allianceMatch,
                GamePackGrain.teamMatch,
              ])
                BearingsSelectItem(value: grain, child: Text(grain.label)),
            ],
            onChanged: (grain) => setState(() {
              _grain = grain!;
              _paths.clear();
            }),
          ),
          for (final (index, path) in _paths.indexed)
            ListTile(
              leading: Icon(
                index == 0
                    ? LucideIcons.circleCheck
                    : LucideIcons.cornerDownRight,
              ),
              title: Text(_tbaPathLabel(path)),
              trailing: IconButton(
                tooltip: 'Remove path',
                onPressed: () => setState(() => _paths.removeAt(index)),
                icon: const Icon(LucideIcons.x),
              ),
            ),
          if (_availablePaths.isEmpty)
            const Text(
              'Choose an event with official scores in Edit test data to find TBA fields.',
            )
          else
            OutlinedButton.icon(
              onPressed: _paths.length >= 12 ? null : _addPath,
              icon: const Icon(LucideIcons.plus),
              label: Text(
                _paths.isEmpty
                    ? 'Choose breakdown field'
                    : 'Add fallback field',
              ),
            ),
          BearingsSelect<GamePackType>(
            key: ValueKey(_type),
            value: _type,
            decoration: const InputDecoration(labelText: 'Value type'),
            items: [
              for (final type in types)
                BearingsSelectItem(
                  value: type,
                  child: Text(gamePackKeyLabel(type.toString())),
                ),
            ],
            onChanged: (type) => setState(() => _type = type!),
          ),
          if (GamePackType.number.accepts(_type))
            CheckboxListTile(
              title: const Text('Accept numbers stored as text'),
              value: _numeric,
              onChanged: (value) => setState(() => _numeric = value ?? false),
            ),
        ],
      ),
    );
  }
}

String _tbaPathLabel(String path) => path
    .split('.')
    .map(
      (part) => gamePackKeyLabel(part.replaceAll('{', '').replaceAll('}', '')),
    )
    .join(' › ');

GamePackValue _testValue(
  GamePackAnalysisSession session,
  GameGraphOutputRef ref,
  GamePackScope scope,
) {
  try {
    return session.evaluate(ref, scope: scope).result;
  } on FormatException {
    return GamePackValue.unknown;
  } on GameGraphLimitExceeded {
    return GamePackValue.unknown;
  }
}
