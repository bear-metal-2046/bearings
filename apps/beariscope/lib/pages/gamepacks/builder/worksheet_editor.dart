import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../gamepack_displays.dart';
import 'design.dart';
import 'fixture.dart';
import 'output_view.dart';
import 'result_picker.dart';

class GamePackWorksheetEditor extends StatefulWidget {
  const GamePackWorksheetEditor({
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
  State<GamePackWorksheetEditor> createState() =>
      _GamePackWorksheetEditorState();
}

class _GamePackWorksheetEditorState extends State<GamePackWorksheetEditor> {
  String? _sheetId;
  String _columnQuery = '';

  List<GamePackWorksheet> get _sheets => widget.design.results.sheets;

  Future<void> _addSheet() async {
    final kind = await BearingsModal.show<GamePackSheetRows>(
      context,
      builder: (context) => BearingsModal(
        title: 'Add worksheet',
        actions: const [],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final rows in GamePackSheetRows.values)
              ListTile(
                leading: Icon(switch (rows) {
                  GamePackSheetRows.teams => LucideIcons.users,
                  GamePackSheetRows.matches => LucideIcons.calendar,
                  GamePackSheetRows.reports => LucideIcons.clipboardList,
                  GamePackSheetRows.calculation => LucideIcons.workflow,
                }),
                title: Text(rows.label),
                subtitle: Text(rows.description),
                trailing: const Icon(LucideIcons.chevronRight, size: 16),
                onTap: () => BearingsModal.complete(context, rows),
              ),
          ],
        ),
      ),
    );
    if (!mounted || kind == null) return;

    final catalog = widget.design.catalog;
    GamePackForm? form;
    GameGraphOutputRef? table;
    if (kind == GamePackSheetRows.reports) {
      form = await BearingsModal.show<GamePackForm>(
        context,
        builder: (context) => BearingsModal(
          title: 'Choose a scouting form',
          actions: const [],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.design.configuredForms.isEmpty)
                const ListTile(
                  title: Text('Add a question to a scout form first.'),
                ),
              for (final entry in widget.design.configuredForms)
                ListTile(
                  title: Text(entry.label),
                  onTap: () => BearingsModal.complete(context, entry),
                ),
            ],
          ),
        ),
      );
      if (!mounted || form == null) return;
    }
    if (kind == GamePackSheetRows.calculation) {
      table = await pickGamePackResult(
        context,
        title: 'Choose a calculated table',
        options: {
          for (final entry in catalog.catalog.entries)
            if (GamePackWorksheet.supportsTable(entry.value))
              entry.key: entry.value,
        },
      );
      if (!mounted || table == null) return;
    }

    final tableInfo = table == null ? null : catalog.resultInfo(table);
    final base = form?.label ?? tableInfo?.label ?? kind.label;
    final name = _suggestName(base);
    final id = gamePackIdForName(name, [
      ..._sheets.map((item) => item.id),
      ...widget.design.results.filters.map((item) => item.id),
      ...widget.design.results.sorts.map((item) => item.id),
    ], 'sheet');
    final empty = GamePackWorksheet(
      id: id,
      name: name,
      rows: kind,
      columns: const [],
      form: form?.id,
      table: table,
    );
    final choices = _columnSources(widget.design, empty);
    final defaults = switch (kind) {
      GamePackSheetRows.teams => choices.where(
        (source) => [
          GamePackColumnInfo.teamNumber,
          GamePackColumnInfo.teamName,
        ].contains(source.column.info),
      ),
      GamePackSheetRows.matches => choices.where(
        (source) => [
          GamePackColumnInfo.match,
          GamePackColumnInfo.teamNumber,
          GamePackColumnInfo.alliance,
        ].contains(source.column.info),
      ),
      GamePackSheetRows.reports => choices.where(
        (source) =>
            source.column.path != null ||
            [
              GamePackColumnInfo.teamNumber,
              GamePackColumnInfo.match,
            ].contains(source.column.info),
      ),
      GamePackSheetRows.calculation => choices,
    };
    final columns = <GamePackWorksheetColumn>[];
    for (final choice in defaults) {
      columns.add(_newColumn(choice.column, columns));
    }
    final created = _copy(empty, columns: columns);
    widget.onChanged(widget.design.copyWith(sheets: [..._sheets, created]));
    setState(() => _sheetId = id);
  }

  String _suggestName(String original) {
    var base = original.replaceAll(RegExp(r"[\[\]:*?/\\']"), '').trim();
    if (base.isEmpty || base.toLowerCase() == 'history') base = 'Worksheet';
    String fit(String suffix) =>
        '${base.substring(0, base.length.clamp(0, 31 - suffix.length))}$suffix';
    var candidate = fit('');
    final prior = _sheets.map((sheet) => sheet.name.toLowerCase()).toSet();
    for (var i = 2; prior.contains(candidate.toLowerCase()); i++) {
      candidate = fit(' $i');
    }
    return candidate;
  }

  void _replace(GamePackWorksheet sheet) => widget.onChanged(
    widget.design.copyWith(
      sheets: [
        for (final prior in _sheets)
          if (prior.id == sheet.id) sheet else prior,
      ],
    ),
  );

  Future<void> _rename(GamePackWorksheet sheet) async {
    final name = await BearingsModal.show<String>(
      context,
      builder: (_) => _NameEditor(
        title: 'Rename worksheet',
        label: 'Sheet name',
        name: sheet.name,
        valid: (value) =>
            GamePackWorksheet.validName(value) &&
            !_sheets.any(
              (prior) =>
                  prior.id != sheet.id &&
                  prior.name.toLowerCase() == value.toLowerCase(),
            ),
      ),
    );
    if (mounted && name != null) _replace(_copy(sheet, name: name));
  }

  Map<String, String> _questionPaths(GamePackWorksheet sheet) => {
    ...widget.design.questionPaths,
    if (sheet.form != null)
      for (final question in widget.design.questions)
        if (question.form.id == sheet.form)
          '@column:path:${question.field.id}':
              widget.design.questionPaths[gamePackScoutFieldId(
                question.form.id,
                question.field.id,
              )]!,
  };

  void _selectSheet(String? id) => setState(() {
    _sheetId = id;
    _columnQuery = '';
  });

  void _moveColumn(GamePackWorksheet sheet, int from, int to) {
    final items = [...sheet.columns];
    items.insert(to, items.removeAt(from));
    _replace(_copy(sheet, columns: items));
  }

  Widget _columnList(GamePackWorksheet sheet) {
    final visible = sheet.columns.indexed
        .where((entry) => matchesGamePackSearch(entry.$2.heading, _columnQuery))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sheet.columns.length > 7)
          TextField(
            key: ValueKey(('columns', sheet.id)),
            onChanged: (value) => setState(() => _columnQuery = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(LucideIcons.search),
              labelText: 'Find a column',
            ),
          ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No matching columns.'),
          ),
        for (final (index, column) in visible)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(column.heading),
            onTap: () => _column(sheet, column),
            trailing: BearingsPopupMenu.overflow(
              tooltip: 'Options for ${column.heading}',
              menuChildren: [
                BearingsMenuItem(
                  onPressed: index > 0
                      ? () => _moveColumn(sheet, index, index - 1)
                      : null,
                  child: const Text('Move earlier'),
                ),
                BearingsMenuItem(
                  onPressed: index < sheet.columns.length - 1
                      ? () => _moveColumn(sheet, index, index + 1)
                      : null,
                  child: const Text('Move later'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _column(
    GamePackWorksheet sheet, [
    GamePackWorksheetColumn? column,
  ]) async {
    final sources = _columnSources(widget.design, sheet);
    final remaining = sheet.columns
        .where((prior) => prior.id != column?.id)
        .toList();
    final edited = await BearingsModal.show<GamePackWorksheetColumn>(
      context,
      builder: (_) => _ColumnEditor(
        sheet: sheet,
        sources: sources,
        existing: column,
        remaining: remaining,
        questionPaths: _questionPaths(sheet),
      ),
    );
    if (!mounted || edited == null) return;
    _replace(
      _copy(
        sheet,
        columns: [
          for (final prior in sheet.columns)
            if (prior.id != edited.id)
              prior
            else if (edited.heading.isNotEmpty)
              edited,
          if (column == null) edited,
        ],
      ),
    );
  }

  Future<void> _remove(GamePackWorksheet sheet) async {
    final confirmed = await BearingsModal.show<bool>(
      context,
      builder: (context) => BearingsModal(
        title: 'Remove ${sheet.name}?',
        actions: const [],
        primaryAction: BearingsModalPrimaryAction(
          label: 'Remove sheet',
          icon: LucideIcons.trash2,
          onPressed: () => BearingsModal.complete(context, true),
        ),
        content: const Text(
          'This removes the sheet and its column layout from the GamePack.',
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    widget.onChanged(
      widget.design.copyWith(
        sheets: _sheets.where((item) => item.id != sheet.id).toList(),
      ),
    );
    setState(() => _sheetId = null);
  }

  @override
  Widget build(BuildContext context) {
    final sheet =
        _sheets.where((item) => item.id == _sheetId).firstOrNull ??
        _sheets.firstOrNull;
    final addSheet = OutlinedButton.icon(
      onPressed: _sheets.length >= 32 ? null : _addSheet,
      icon: const Icon(LucideIcons.plus, size: 17),
      label: const Text(
        'Add sheet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= 740;
        return GamePackOutputView(
          title: 'Export sheets',
          compact: widget.compact,
          stackActions: !split,
          picker: split
              ? null
              : BearingsPopupMenu.button(
                  label: sheet?.name ?? 'Worksheets',
                  tooltip: 'Switch worksheet',
                  menuChildren: [
                    BearingsMenuItem(
                      leadingIcon: const Icon(LucideIcons.plus),
                      onPressed: _sheets.length >= 32 ? null : _addSheet,
                      child: const Text('Add sheet'),
                    ),
                    if (sheet != null) ...[
                      const Divider(height: 8),
                      for (final item in _sheets)
                        BearingsMenuItem(
                          selected: item.id == sheet.id,
                          leadingIcon: const Icon(null),
                          onPressed: () => _selectSheet(item.id),
                          child: Text(item.name),
                        ),
                      const Divider(height: 8),
                      ..._sheetActions(sheet, compact: true),
                    ],
                  ],
                ),
          tools: [
            if (sheet != null && split)
              BearingsPopupMenu.overflow(
                tooltip: 'Worksheet options',
                menuChildren: _sheetActions(sheet, compact: false),
              ),
          ],
          actions: [
            if (sheet != null) ...[
              if (split) addSheet,
              OutlinedButton.icon(
                onPressed: sheet.columns.length >= 256
                    ? null
                    : () => _column(sheet),
                icon: const Icon(LucideIcons.columns3, size: 17),
                label: const Text(
                  'Add column',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
          child: sheet == null
              ? GamePackOutputEmpty(
                  icon: LucideIcons.sheet,
                  title: 'No export sheets yet',
                  description: split
                      ? 'Choose what each row represents, then add the columns you want in the workbook.'
                      : 'Open Worksheets and choose Add sheet to set up the workbook.',
                  action: split
                      ? FilledButton.icon(
                          onPressed: _addSheet,
                          icon: const Icon(LucideIcons.plus, size: 17),
                          label: const Text('Add sheet'),
                        )
                      : null,
                )
              : split
              ? Row(
                  children: [
                    SizedBox(width: 216, child: _sheetList(sheet)),
                    const VerticalDivider(width: 32),
                    Expanded(child: _sheetContents(sheet, compact: false)),
                  ],
                )
              : _sheetContents(sheet, compact: true),
        );
      },
    );
  }

  List<Widget> _sheetActions(GamePackWorksheet sheet, {required bool compact}) {
    final index = _sheets.indexOf(sheet);
    return [
      BearingsMenuItem(
        leadingIcon: const Icon(LucideIcons.pencil),
        onPressed: () => _rename(sheet),
        child: const Text('Rename worksheet'),
      ),
      if (compact)
        for (final (offset, label) in [
          (-1, 'Move worksheet earlier'),
          (1, 'Move worksheet later'),
        ])
          if (index + offset >= 0 && index + offset < _sheets.length)
            BearingsMenuItem(
              leadingIcon: Icon(
                offset < 0 ? LucideIcons.arrowUp : LucideIcons.arrowDown,
              ),
              onPressed: () => _moveSheet(index, index + offset),
              child: Text(label),
            ),
      if (sheet.rows == GamePackSheetRows.matches)
        BearingsMenuItem(
          leadingIcon: const Icon(LucideIcons.clipboardCheck),
          selected: sheet.includeUnscouted,
          onPressed: () =>
              _replace(_copy(sheet, includeUnscouted: !sheet.includeUnscouted)),
          child: const Text('Include matches without scout reports'),
        ),
      BearingsMenuItem(
        leadingIcon: const Icon(LucideIcons.trash2),
        destructive: true,
        onPressed: () => _remove(sheet),
        child: const Text('Remove worksheet'),
      ),
    ];
  }

  Widget _sheetList(GamePackWorksheet sheet) => ReorderableListView.builder(
    itemCount: _sheets.length,
    buildDefaultDragHandles: false,
    onReorderItem: _moveSheet,
    itemBuilder: (context, index) {
      final item = _sheets[index];
      return ListTile(
        key: ValueKey(item.id),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: item.id == sheet.id,
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        leading: const Icon(LucideIcons.sheet, size: 17),
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Tooltip(
            message: 'Reorder sheet',
            child: Icon(LucideIcons.gripVertical, size: 16),
          ),
        ),
        onTap: () => _selectSheet(item.id),
      );
    },
  );

  void _moveSheet(int from, int to) {
    final items = [..._sheets];
    items.insert(to, items.removeAt(from));
    widget.onChanged(widget.design.copyWith(sheets: items));
  }

  Widget _sheetContents(GamePackWorksheet sheet, {required bool compact}) {
    final colors = Theme.of(context).colorScheme;
    final session = widget.fixture.analysisFor(widget.design);
    final event = widget.fixture.data;
    final names = {
      for (final team in event?.teams ?? const <String>[])
        team: event!.teamName(team) ?? event.teamLabel(team),
    };
    List<List<GamePackValue>> rows;
    try {
      rows = sheet.values(session, teamNames: names).take(7).toList();
    } on FormatException {
      rows = const [];
    } on GameGraphLimitExceeded {
      rows = const [];
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        Text(
          sheet.rows.description,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (sheet.columns.isEmpty)
          const Text('Add a column to preview rows.')
        else ...[
          ExpansionTile(
            key: ValueKey(('preview', sheet.id)),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: !compact,
            title: const Text('Worksheet preview'),
            subtitle: const Text('Test data'),
            children: [
              SizedBox(
                height: 48.0 + 38.0 * (rows.isEmpty ? 1 : rows.length),
                child: ReorderableListView.builder(
                  key: ValueKey(sheet.id),
                  scrollDirection: Axis.horizontal,
                  itemCount: sheet.columns.length,
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) => _moveColumn(sheet, from, to),
                  itemBuilder: (context, index) {
                    final column = sheet.columns[index];
                    return SizedBox(
                      key: ValueKey(column.id),
                      width: 176,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 46,
                              child: Material(
                                color: colors.surfaceContainerHighest,
                                child: InkWell(
                                  onTap: () => _column(sheet, column),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    child: Row(
                                      spacing: 5,
                                      children: [
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: const Tooltip(
                                            message: 'Reorder column',
                                            child: Icon(
                                              LucideIcons.gripVertical,
                                              size: 15,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            column.heading,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge,
                                          ),
                                        ),
                                        const Icon(
                                          LucideIcons.pencil,
                                          size: 13,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            for (final (i, row) in rows.indexed)
                              Container(
                                height: 38,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                ),
                                color: i.isOdd
                                    ? colors.surfaceContainerLow
                                    : colors.surface,
                                child: Tooltip(
                                  message: formatGamePackValue(row[index]),
                                  child: Text(
                                    row[index].isKnown
                                        ? formatGamePackValue(row[index])
                                        : '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (compact) ...[
            const SizedBox(height: 8),
            Text(
              'Columns · ${sheet.columns.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _columnList(sheet),
          ],
        ],
        if (rows.isEmpty && sheet.columns.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No sample rows for this sheet.'),
          ),
      ],
    );
  }
}

GamePackWorksheet _copy(
  GamePackWorksheet sheet, {
  String? name,
  List<GamePackWorksheetColumn>? columns,
  bool? includeUnscouted,
}) => GamePackWorksheet(
  id: sheet.id,
  name: name ?? sheet.name,
  rows: sheet.rows,
  columns: columns ?? sheet.columns,
  form: sheet.form,
  table: sheet.table,
  includeUnscouted: includeUnscouted ?? sheet.includeUnscouted,
);

typedef _ColumnSource = ({
  GameGraphOutputRef ref,
  GamePackResultInfo info,
  GamePackWorksheetColumn column,
});

List<_ColumnSource> _columnSources(
  GamePackDesign design,
  GamePackWorksheet sheet,
) {
  final form = design.configuredForms
      .where((item) => item.id == sheet.form)
      .firstOrNull;
  final fields = {for (final field in design.fields) field.id: field};
  final table = sheet.table == null
      ? null
      : design.catalog.tryInfo(sheet.table!);
  _ColumnSource special(
    String key,
    String name,
    GamePackType type, {
    GamePackColumnInfo? info,
    String? path,
  }) => (
    ref: gamePackFieldRef('@column:${info == null ? 'path' : 'info'}:$key'),
    info: (
      label: name,
      type: type,
      grain: null,
      origin: info != null
          ? GamePackResultOrigin.schedule
          : form != null
          ? GamePackResultOrigin.scouting
          : GamePackResultOrigin.calculated,
    ),
    column: GamePackWorksheetColumn(
      id: key,
      heading: name,
      info: info,
      path: path,
    ),
  );
  return [
    for (final info in GamePackColumnInfo.values)
      if (info.canUse(sheet.rows, form: form?.kind))
        special(
          info.name.toLowerCase(),
          info.label,
          [
                GamePackColumnInfo.teamNumber,
                GamePackColumnInfo.station,
              ].contains(info)
              ? GamePackType.integer
              : GamePackType.text,
          info: info,
        ),
    if (form != null)
      for (final id in form.controls.map((control) => control.field).toSet())
        if (fields[id] case final field?)
          special(
            id,
            design.catalog
                    .tryInfo(
                      gamePackFieldRef(gamePackScoutFieldId(form.id, id)),
                    )
                    ?.label
                    .split(' · ')
                    .first ??
                field.label,
            field.type,
            path: id,
          ),
    if (table != null)
      for (final entry in GamePackCardChart.columns(table.type).entries)
        special(
          entry.key,
          entry.key.split('.').map(gamePackKeyLabel).join(' › '),
          entry.value,
          path: entry.key,
        ),
    if (sheet.rows.scope case final scope?)
      for (final entry in design.catalog.catalog.entries)
        if (entry.value.grain == null || scope.canRead(entry.value.grain!))
          (
            ref: entry.key,
            info: entry.value,
            column: GamePackWorksheetColumn(
              id: entry.key.output,
              heading: entry.value.label.split(' · ').first,
              output: entry.key,
            ),
          ),
  ];
}

GamePackWorksheetColumn _newColumn(
  GamePackWorksheetColumn source,
  List<GamePackWorksheetColumn> existing, {
  String? id,
  String? heading,
}) {
  final label = heading ?? source.heading;
  var unique = label;
  final used = existing.map((item) => item.heading.toLowerCase()).toSet();
  for (var n = 2; used.contains(unique.toLowerCase()); n++) {
    unique = '$label ($n)';
  }
  return GamePackWorksheetColumn(
    id:
        id ??
        gamePackIdForName(unique, existing.map((item) => item.id), 'column'),
    heading: unique,
    info: source.info,
    output: source.output,
    path: source.path,
  );
}

class _ColumnEditor extends StatefulWidget {
  const _ColumnEditor({
    required this.sheet,
    required this.sources,
    required this.existing,
    required this.remaining,
    required this.questionPaths,
  });
  final GamePackWorksheet sheet;
  final List<_ColumnSource> sources;
  final GamePackWorksheetColumn? existing;
  final List<GamePackWorksheetColumn> remaining;
  final Map<String, String> questionPaths;
  @override
  State<_ColumnEditor> createState() => _ColumnEditorState();
}

class _ColumnEditorState extends State<_ColumnEditor> {
  late final _name = TextEditingController(
    text: widget.existing?.heading ?? '',
  );
  late GamePackWorksheetColumn? _source = widget.existing;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final selected = await pickGamePackResult(
      context,
      title: 'Choose a column source',
      preferredScope: widget.sheet.rows.scope,
      questionPaths: widget.questionPaths,
      options: {for (final choice in widget.sources) choice.ref: choice.info},
    );
    if (!mounted || selected == null) return;
    setState(() {
      _source = widget.sources
          .firstWhere((item) => item.ref == selected)
          .column;
      if (_name.text.isEmpty) {
        _name.text = _newColumn(_source!, widget.remaining).heading;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final source = _source;
    final available = source == null
        ? null
        : widget.sources
              .where(
                (item) =>
                    item.column.info == source.info &&
                    item.column.output == source.output &&
                    item.column.path == source.path,
              )
              .firstOrNull;
    final valid =
        name.isNotEmpty &&
        name.length <= 80 &&
        !widget.remaining.any(
          (prior) => prior.heading.toLowerCase() == name.toLowerCase(),
        );
    return BearingsModal(
      title: widget.existing == null ? 'Add column' : 'Edit column',
      actions: [
        if (widget.existing != null && widget.remaining.isNotEmpty)
          BearingsModalAction(
            label: 'Remove column',
            icon: LucideIcons.trash2,
            onPressed: () => BearingsModal.complete(
              context,
              GamePackWorksheetColumn(id: widget.existing!.id, heading: ''),
            ),
          ),
      ],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Save column',
        icon: LucideIcons.check,
        enabled: valid && available != null,
        onPressed: () => BearingsModal.complete(
          context,
          _newColumn(
            source!,
            widget.remaining,
            id: widget.existing?.id,
            heading: name,
          ),
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(LucideIcons.listChecks, size: 17),
            label: Text(available?.info.label ?? 'Choose field'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Column heading'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}

class _NameEditor extends StatefulWidget {
  const _NameEditor({
    required this.title,
    required this.label,
    required this.name,
    required this.valid,
  });
  final String title;
  final String label;
  final String name;
  final bool Function(String) valid;
  @override
  State<_NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<_NameEditor> {
  late String _name = widget.name;
  @override
  Widget build(BuildContext context) => BearingsModal(
    title: widget.title,
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Save name',
      icon: LucideIcons.check,
      enabled: widget.valid(_name.trim()),
      onPressed: () => BearingsModal.complete(context, _name.trim()),
    ),
    content: TextFormField(
      initialValue: _name,
      autofocus: true,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: 'Up to 31 characters',
      ),
      onChanged: (value) => setState(() => _name = value),
    ),
  );
}
