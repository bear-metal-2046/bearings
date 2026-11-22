import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'analysis_editor.dart';
import 'design.dart';

IconData cardBlockIcon(GamePackCardBlockKind kind) => switch (kind) {
  GamePackCardBlockKind.metrics => LucideIcons.hash,
  GamePackCardBlockKind.chips => LucideIcons.tags,
  GamePackCardBlockKind.text => LucideIcons.alignLeft,
  GamePackCardBlockKind.trend => LucideIcons.trendingUp,
  GamePackCardBlockKind.table => LucideIcons.table,
  GamePackCardBlockKind.eventRank => LucideIcons.trophy,
};

String _fieldLabel(String field) =>
    field.split('.').map(gamePackKeyLabel).join(' › ');

class GamePackCardBlockEditor extends StatefulWidget {
  const GamePackCardBlockEditor({
    super.key,
    required this.id,
    required this.kind,
    required this.outputs,
    required this.options,
    required this.questionPaths,
    this.current,
  });

  final String id;
  final GamePackCardBlockKind kind;
  final Map<GameGraphOutputRef, GamePackType> outputs;
  final GamePackOptions options;
  final Map<String, String> questionPaths;
  final GamePackCardBlock? current;

  @override
  State<GamePackCardBlockEditor> createState() =>
      _GamePackCardBlockEditorState();
}

class _GamePackCardBlockEditorState extends State<GamePackCardBlockEditor> {
  late String _title = widget.current?.title ?? '';
  late List<GamePackCardMetric> _metrics = [...?widget.current?.metrics];
  late final _tableOutputs = _filterOutputs(GamePackCardTable.supports);
  late GameGraphOutputRef? _table = widget.current?.table?.output;
  late Map<String, String> _tableColumns = {...?widget.current?.table?.columns};
  late final _chartOutputs = _filterOutputs(GamePackCardChart.supports);
  late GameGraphOutputRef? _chart =
      widget.current?.chart?.output ?? _chartOutputs.keys.firstOrNull;
  late String? _x = widget.current?.chart?.x ?? _defaultX;
  late final List<GamePackCardSeries> _series = [
    ...?widget.current?.chart?.series,
  ];
  late final List<GamePackCardMarker> _markers = [
    ...?widget.current?.chart?.markers,
  ];
  late bool _shared = widget.current?.chart?.sharedScale ?? false;
  late int? _minimum = widget.current?.chart?.minimumPoints ?? 1;

  Map<GameGraphOutputRef, GamePackType> _filterOutputs(
    bool Function(GamePackType) supports,
  ) => Map.fromEntries(
    widget.outputs.entries.where((entry) => supports(entry.value)),
  );

  Map<String, GamePackType> get _columns {
    final type = _chartOutputs[_chart];
    return type == null ? const {} : GamePackCardChart.columns(type);
  }

  Iterable<String> get _xFields => _columns.entries
      .where(
        (entry) =>
            GamePackCardChart.supportsX(entry.value) &&
            _columns.entries.any(
              (other) =>
                  other.key != entry.key &&
                  GamePackType.number.accepts(other.value),
            ),
      )
      .map((entry) => entry.key);
  String? get _defaultX =>
      _xFields.where((id) => _columns[id] == GamePackType.text).firstOrNull ??
      _xFields.firstOrNull;

  bool get _canSave {
    if (_title.length > 80) return false;
    switch (widget.kind) {
      case GamePackCardBlockKind.eventRank:
        return true;
      case GamePackCardBlockKind.table:
        return _tableOutputs.containsKey(_table) &&
            _tableColumns.isNotEmpty &&
            _tableColumns.values.every(
              (value) => value.trim().isNotEmpty && value.length <= 80,
            );
      case GamePackCardBlockKind.trend:
        return _chartOutputs.containsKey(_chart) &&
            _xFields.contains(_x) &&
            _series.isNotEmpty &&
            _series.every(
              (line) =>
                  line.field != _x &&
                  GamePackType.number.accepts(
                    _columns[line.field] ?? GamePackType.any,
                  ),
            ) &&
            _markers.every(
              (marker) => _columns[marker.field] == GamePackType.boolean,
            ) &&
            _minimum != null &&
            _minimum! >= 1 &&
            _minimum! <= 20;
      default:
        final valid = _filterOutputs(GamePackCardMetric.supports);
        return _metrics.isNotEmpty &&
            _metrics.every((metric) => valid.containsKey(metric.output));
    }
  }

  void _save() => BearingsModal.complete(
    context,
    GamePackCardBlock(
      id: widget.id,
      kind: widget.kind,
      title: _title.isEmpty ? null : _title,
      metrics: _metrics,
      table: widget.kind == GamePackCardBlockKind.table
          ? GamePackCardTable(
              output: _table!,
              columns: _tableColumns.map(
                (key, value) => MapEntry(key, value.trim()),
              ),
            )
          : null,
      chart: widget.kind == GamePackCardBlockKind.trend
          ? GamePackCardChart(
              output: _chart!,
              x: _x!,
              series: _series,
              markers: _markers,
              sharedScale: _shared,
              minimumPoints: _minimum!,
            )
          : null,
    ),
  );

  Future<void> _editMetric([int? index]) async {
    final selected = await BearingsModal.show<GamePackCardMetric>(
      context,
      builder: (_) => _MetricEditor(
        outputs: _filterOutputs(GamePackCardMetric.supports),
        options: widget.options,
        questionPaths: widget.questionPaths,
        current: index == null ? null : _metrics[index],
        allowFlag: widget.kind == GamePackCardBlockKind.chips,
      ),
    );
    if (!mounted || selected == null) return;
    setState(
      () => _metrics = index == null
          ? [..._metrics, selected]
          : replaceAt(_metrics, index, selected),
    );
  }

  Future<void> _editSeries([int? index]) async {
    final current = index == null ? null : _series[index];
    final palette = [
      GamePackCardTone.accent,
      GamePackCardTone.info,
      GamePackCardTone.positive,
      GamePackCardTone.warning,
      GamePackCardTone.danger,
      GamePackCardTone.neutral,
    ];
    final nextTone =
        palette
            .where((tone) => !_series.any((line) => line.tone == tone))
            .firstOrNull ??
        palette[_series.length % palette.length];
    final fields = [
      for (final entry in _columns.entries)
        if (entry.key != _x &&
            GamePackType.number.accepts(entry.value) &&
            !_series.any((line) => line != current && line.field == entry.key))
          entry.key,
    ];
    final choice =
        await BearingsModal.show<
          ({
            String field,
            String label,
            GamePackCardTone tone,
            GamePackCardMarkerIcon icon,
          })
        >(
          context,
          builder: (_) => _ChartFieldEditor(
            fields: fields,
            marker: false,
            field: current?.field,
            label: current?.label,
            tone: current?.tone ?? nextTone,
          ),
        );
    if (!mounted || choice == null) return;
    final series = GamePackCardSeries(
      field: choice.field,
      label: choice.label,
      tone: choice.tone,
    );
    setState(() {
      if (index == null) {
        _series.add(series);
      } else {
        _series[index] = series;
      }
    });
  }

  Future<void> _editMarker([int? index]) async {
    final current = index == null ? null : _markers[index];
    final fields = [
      for (final entry in _columns.entries)
        if (entry.value == GamePackType.boolean &&
            !_markers.any(
              (marker) => marker != current && marker.field == entry.key,
            ))
          entry.key,
    ];
    final choice =
        await BearingsModal.show<
          ({
            String field,
            String label,
            GamePackCardTone tone,
            GamePackCardMarkerIcon icon,
          })
        >(
          context,
          builder: (_) => _ChartFieldEditor(
            fields: fields,
            marker: true,
            field: current?.field,
            label: current?.label,
            tone: current?.tone,
            icon: current?.icon,
          ),
        );
    if (!mounted || choice == null) return;
    final marker = GamePackCardMarker(
      field: choice.field,
      label: choice.label,
      tone: choice.tone,
      icon: choice.icon,
    );
    setState(() {
      if (index == null) {
        _markers.add(marker);
      } else {
        _markers[index] = marker;
      }
    });
  }

  Widget _entry({
    required String label,
    required VoidCallback edit,
    required VoidCallback remove,
    VoidCallback? moveUp,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    onTap: edit,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (moveUp != null)
          IconButton(
            tooltip: 'Move $label up',
            icon: const Icon(LucideIcons.arrowUp, size: 17),
            onPressed: moveUp,
          ),
        IconButton(
          tooltip: 'Remove $label',
          icon: const Icon(LucideIcons.trash2, size: 17),
          onPressed: remove,
        ),
      ],
    ),
  );

  List<Widget> _metricOptions() => [
    for (final (i, metric) in _metrics.indexed)
      _entry(
        label: metric.label,
        edit: () => _editMetric(i),
        remove: () => setState(() => _metrics = [..._metrics]..removeAt(i)),
        moveUp: i == 0
            ? null
            : () => setState(() {
                final item = _metrics.removeAt(i);
                _metrics.insert(i - 1, item);
              }),
      ),
    if (_metrics.length < (widget.kind == GamePackCardBlockKind.text ? 1 : 12))
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: _filterOutputs(GamePackCardMetric.supports).isEmpty
              ? null
              : _editMetric,
          icon: const Icon(LucideIcons.plus),
          label: const Text('Add value'),
        ),
      ),
  ];

  List<Widget> _chartOptions() {
    final xChoices = _xFields.toList();
    return [
      _OutputMenu(
        label: 'Match records',
        outputs: _chartOutputs,
        options: widget.options,
        questionPaths: widget.questionPaths,
        selected: _chart,
        onChanged: (value) => setState(() {
          _chart = value;
          _x = _defaultX;
          _series.clear();
          _markers.clear();
        }),
      ),
      BearingsSelect<String>(
        key: ValueKey((_chart, _x)),
        value: xChoices.contains(_x) ? _x : null,
        decoration: const InputDecoration(labelText: 'X-axis labels'),
        items: [
          for (final field in xChoices)
            BearingsSelectItem(value: field, child: Text(_fieldLabel(field))),
        ],
        onChanged: (value) => setState(() {
          _x = value;
          _series.removeWhere((series) => series.field == value);
        }),
      ),
      for (final (i, line) in _series.indexed)
        _entry(
          label: line.label,
          edit: () => _editSeries(i),
          remove: () => setState(() => _series.removeAt(i)),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed:
              _series.length < 8 &&
                  _columns.entries.any(
                    (entry) =>
                        entry.key != _x &&
                        GamePackType.number.accepts(entry.value) &&
                        !_series.any((series) => series.field == entry.key),
                  )
              ? _editSeries
              : null,
          icon: const Icon(LucideIcons.plus),
          label: const Text('Add series'),
        ),
      ),
      for (final (i, marker) in _markers.indexed)
        _entry(
          label: marker.label,
          edit: () => _editMarker(i),
          remove: () => setState(() => _markers.removeAt(i)),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed:
              _markers.length < 8 &&
                  _columns.entries.any(
                    (entry) =>
                        entry.value == GamePackType.boolean &&
                        !_markers.any((marker) => marker.field == entry.key),
                  )
              ? _editMarker
              : null,
          icon: const Icon(LucideIcons.flag),
          label: const Text('Add marker'),
        ),
      ),
      TextFormField(
        initialValue: _minimum?.toString(),
        decoration: const InputDecoration(labelText: 'Minimum points'),
        keyboardType: TextInputType.number,
        onChanged: (value) => setState(() => _minimum = int.tryParse(value)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Share y-axis across teams'),
        value: _shared,
        onChanged: (value) => setState(() => _shared = value),
      ),
    ];
  }

  List<Widget> _tableOptions() {
    final type = _tableOutputs[_table];
    final fields = type == null
        ? const <String, GamePackType>{}
        : GamePackCardChart.columns(type);
    return [
      _OutputMenu(
        label: 'Choose a team table',
        outputs: _tableOutputs,
        options: widget.options,
        questionPaths: widget.questionPaths,
        selected: _table,
        onChanged: (value) => setState(() {
          _table = value;
          final columns = value == null
              ? const <String, GamePackType>{}
              : GamePackCardChart.columns(_tableOutputs[value]!);
          _tableColumns = {
            for (final path in columns.keys.take(5)) path: _fieldLabel(path),
          };
        }),
      ),
      for (final (index, field) in _tableColumns.keys.toList().indexed)
        Row(
          key: ValueKey((_table, field)),
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _tableColumns[field],
                decoration: const InputDecoration(labelText: 'Column heading'),
                onChanged: (value) =>
                    setState(() => _tableColumns[field] = value),
              ),
            ),
            if (index > 0)
              IconButton(
                tooltip: 'Move column earlier',
                icon: const Icon(LucideIcons.arrowUp),
                onPressed: () {
                  final entries = _tableColumns.entries.toList();
                  entries.insert(index - 1, entries.removeAt(index));
                  setState(() => _tableColumns = Map.fromEntries(entries));
                },
              ),
            IconButton(
              tooltip: 'Remove table column',
              icon: const Icon(LucideIcons.x),
              onPressed: () => setState(() => _tableColumns.remove(field)),
            ),
          ],
        ),
      if (_tableColumns.length < 12 &&
          fields.keys.any((key) => !_tableColumns.containsKey(key)))
        BearingsSelect<String>(
          key: ValueKey(('columns', _tableColumns.length)),
          decoration: const InputDecoration(labelText: 'Add table column'),
          items: [
            for (final field in fields.keys)
              if (!_tableColumns.containsKey(field))
                BearingsSelectItem(
                  value: field,
                  child: Text(_fieldLabel(field)),
                ),
          ],
          onChanged: (field) {
            if (field != null)
              setState(() => _tableColumns[field] = _fieldLabel(field));
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => BearingsModal(
    title: widget.kind.label,
    actions: const [],
    primaryAction: BearingsModalPrimaryAction(
      label: 'Save block',
      icon: LucideIcons.check,
      enabled: _canSave,
      onPressed: _save,
    ),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        TextFormField(
          initialValue: _title,
          decoration: const InputDecoration(
            labelText: 'Block heading (optional)',
          ),
          onChanged: (value) => setState(() => _title = value.trim()),
        ),
        if (widget.kind == GamePackCardBlockKind.trend)
          ..._chartOptions()
        else if (widget.kind == GamePackCardBlockKind.table)
          ..._tableOptions()
        else if (widget.kind != GamePackCardBlockKind.eventRank)
          ..._metricOptions(),
      ],
    ),
  );
}

class _OutputMenu extends StatelessWidget {
  const _OutputMenu({
    required this.label,
    required this.outputs,
    required this.options,
    required this.questionPaths,
    required this.selected,
    required this.onChanged,
  });
  final String label;
  final Map<GameGraphOutputRef, GamePackType> outputs;
  final GamePackOptions options;
  final Map<String, String> questionPaths;
  final GameGraphOutputRef? selected;
  final ValueChanged<GameGraphOutputRef?> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      selected == null
          ? label
          : gamePackResultLabel(selected!, options[selected]),
    ),
    subtitle: selected == null ? null : Text(label),
    trailing: const Icon(LucideIcons.chevronRight),
    enabled: outputs.isNotEmpty,
    onTap: () async {
      final chosen = await pickGamePackResult(
        context,
        title: label,
        questionPaths: questionPaths,
        options: {
          for (final entry in options.entries)
            if (outputs.containsKey(entry.key)) entry.key: entry.value,
        },
      );
      if (context.mounted && chosen != null) onChanged(chosen);
    },
  );
}

class _MetricEditor extends StatefulWidget {
  const _MetricEditor({
    required this.outputs,
    required this.options,
    required this.questionPaths,
    this.current,
    required this.allowFlag,
  });
  final Map<GameGraphOutputRef, GamePackType> outputs;
  final GamePackOptions options;
  final Map<String, String> questionPaths;
  final GamePackCardMetric? current;
  final bool allowFlag;

  @override
  State<_MetricEditor> createState() => _MetricEditorState();
}

class _MetricEditorState extends State<_MetricEditor> {
  late GameGraphOutputRef? _output =
      widget.current?.output ?? widget.outputs.keys.firstOrNull;
  late String _label = widget.current?.label ?? '';
  late String _prefix = widget.current?.prefix ?? '';
  late String _suffix = widget.current?.suffix ?? '';
  late String _decimals = widget.current?.decimals?.toString() ?? '';
  late GamePackCardMissing _missing =
      widget.current?.missing ?? GamePackCardMissing.dash;
  late GamePackCardTone _tone =
      widget.current?.tone ?? GamePackCardTone.neutral;
  late bool _onlyTrue = widget.current?.onlyWhenTrue ?? false;

  @override
  Widget build(BuildContext context) {
    final type = widget.outputs[_output];
    final number = type != null && GamePackType.number.accepts(type);
    final digits = int.tryParse(_decimals);
    final label = _label.isNotEmpty
        ? _label
        : (_output == null
              ? ''
              : gamePackResultLabel(
                  _output!,
                  widget.options[_output],
                ).split(' · ').first);
    final booleanFlag = widget.allowFlag && type == GamePackType.boolean;
    return BearingsModal(
      title: 'Card value',
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Save value',
        icon: LucideIcons.check,
        enabled:
            type != null &&
            label.isNotEmpty &&
            label.length <= 80 &&
            _prefix.length <= 24 &&
            _suffix.length <= 24 &&
            (!number ||
                _decimals.isEmpty ||
                (digits != null && digits >= 0 && digits <= 6)),
        onPressed: () => BearingsModal.complete(
          context,
          GamePackCardMetric(
            label: label,
            output: _output!,
            decimals: number ? digits : null,
            prefix: _prefix,
            suffix: _suffix,
            tone: _tone,
            missing: _missing,
            onlyWhenTrue: booleanFlag && _onlyTrue,
          ),
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          _OutputMenu(
            label: 'Field or calculation',
            outputs: widget.outputs,
            options: widget.options,
            questionPaths: widget.questionPaths,
            selected: _output,
            onChanged: (value) => setState(() => _output = value),
          ),
          TextFormField(
            initialValue: _label,
            decoration: InputDecoration(
              labelText: 'Value label',
              hintText: label.isEmpty ? null : label,
            ),
            onChanged: (value) => setState(() => _label = value.trim()),
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _prefix,
                  decoration: const InputDecoration(labelText: 'Prefix'),
                  onChanged: (value) => setState(() => _prefix = value),
                ),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: _suffix,
                  decoration: const InputDecoration(labelText: 'Suffix'),
                  onChanged: (value) => setState(() => _suffix = value),
                ),
              ),
            ],
          ),
          if (number)
            TextFormField(
              initialValue: _decimals,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Decimal places',
                hintText: 'Automatic',
              ),
              onChanged: (value) => setState(() => _decimals = value.trim()),
            ),
          _toneMenu(_tone, (tone) => setState(() => _tone = tone)),
          if (!(booleanFlag && _onlyTrue))
            BearingsSelect<GamePackCardMissing>(
              value: _missing,
              decoration: const InputDecoration(
                labelText: 'When a value is missing',
              ),
              items: const [
                BearingsSelectItem(
                  value: GamePackCardMissing.dash,
                  child: Text('Show a dash'),
                ),
                BearingsSelectItem(
                  value: GamePackCardMissing.hide,
                  child: Text('Hide value'),
                ),
                BearingsSelectItem(
                  value: GamePackCardMissing.showState,
                  child: Text('Show value state'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _missing = value ?? _missing),
            ),
          if (booleanFlag)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show chip only when true'),
              value: _onlyTrue,
              onChanged: (value) => setState(() => _onlyTrue = value),
            ),
        ],
      ),
    );
  }
}

BearingsSelect<GamePackCardTone> _toneMenu(
  GamePackCardTone tone,
  ValueChanged<GamePackCardTone> onChanged,
) => BearingsSelect<GamePackCardTone>(
  value: tone,
  decoration: const InputDecoration(labelText: 'Color'),
  items: [
    for (final tone in GamePackCardTone.values)
      BearingsSelectItem(value: tone, child: Text(gamePackKeyLabel(tone.name))),
  ],
  onChanged: (value) {
    if (value != null) onChanged(value);
  },
);

class _ChartFieldEditor extends StatefulWidget {
  const _ChartFieldEditor({
    required this.fields,
    required this.marker,
    this.field,
    this.label,
    this.tone,
    this.icon,
  });
  final List<String> fields;
  final bool marker;
  final String? field;
  final String? label;
  final GamePackCardTone? tone;
  final GamePackCardMarkerIcon? icon;

  @override
  State<_ChartFieldEditor> createState() => _ChartFieldEditorState();
}

class _ChartFieldEditorState extends State<_ChartFieldEditor> {
  late String? _field = widget.fields.contains(widget.field)
      ? widget.field
      : widget.fields.firstOrNull;
  late String _label = widget.label ?? '';
  late GamePackCardTone _tone = widget.tone ?? GamePackCardTone.accent;
  late GamePackCardMarkerIcon _icon =
      widget.icon ?? GamePackCardMarkerIcon.flag;

  @override
  Widget build(BuildContext context) {
    final label = _label.isNotEmpty ? _label : _fieldLabel(_field ?? '');
    return BearingsModal(
      title: widget.marker ? 'Chart marker' : 'Chart series',
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: widget.marker ? 'Save marker' : 'Save series',
        icon: LucideIcons.check,
        enabled: _field != null && label.isNotEmpty && label.length <= 80,
        onPressed: () => BearingsModal.complete(context, (
          field: _field!,
          label: label,
          tone: _tone,
          icon: _icon,
        )),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          BearingsSelect<String>(
            value: _field,
            decoration: const InputDecoration(labelText: 'Record field'),
            items: [
              for (final field in widget.fields)
                BearingsSelectItem(
                  value: field,
                  child: Text(_fieldLabel(field)),
                ),
            ],
            onChanged: (value) => setState(() => _field = value),
          ),
          TextFormField(
            initialValue: _label,
            decoration: InputDecoration(
              labelText: 'Legend label',
              hintText: label.isEmpty ? null : label,
            ),
            onChanged: (value) => setState(() => _label = value.trim()),
          ),
          _toneMenu(_tone, (value) => setState(() => _tone = value)),
          if (widget.marker)
            BearingsSelect<GamePackCardMarkerIcon>(
              value: _icon,
              decoration: const InputDecoration(labelText: 'Marker icon'),
              items: [
                for (final icon in GamePackCardMarkerIcon.values)
                  BearingsSelectItem(
                    value: icon,
                    child: Text(gamePackKeyLabel(icon.name)),
                  ),
              ],
              onChanged: (value) => setState(() => _icon = value ?? _icon),
            ),
        ],
      ),
    );
  }
}
