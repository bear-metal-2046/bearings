import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_modal.dart';

import 'calculation_canvas.dart';
import 'calculation_settings.dart';
import 'design.dart';
import 'editor_action_bar.dart';
import 'fixture.dart';
import 'result_picker.dart';

Future<GamePackCalculation?> editGamePackCalculation(
  BuildContext context, {
  required GamePackDesign design,
  required GamePackBuilderFixture fixture,
  GamePackCalculation? current,
  GamePackGrain? scope,
  bool readOnly = false,
}) => BearingsModal.show<GamePackCalculation>(
  context,
  builder: (_) => _CalculationEditor(
    design: design,
    fixture: fixture,
    current: current,
    scope: scope,
    readOnly: readOnly,
  ),
);

class _CalculationEditor extends StatefulWidget {
  const _CalculationEditor({
    required this.design,
    required this.fixture,
    this.current,
    this.scope,
    required this.readOnly,
  });

  final GamePackDesign design;
  final GamePackBuilderFixture fixture;
  final GamePackCalculation? current;
  final GamePackGrain? scope;
  final bool readOnly;

  @override
  State<_CalculationEditor> createState() => _CalculationEditorState();
}

class _CalculationEditorState extends State<_CalculationEditor> {
  late final _name = TextEditingController(text: widget.current?.label ?? '');
  late final String _draftId =
      widget.current?.id ?? availableId('calculation', widget.design.resultIds);
  late final _testScope = widget.fixture.scope;
  late String _result = widget.current?.result ?? '';
  late List<GamePackCalculationNode> _nodes = widget.current?.nodes ?? const [];
  final _canvas = GlobalKey<GamePackCalculationCanvasState>();
  String? _selected;
  String? _connecting;
  String? _message;
  late GamePackDesign _draft;
  late GamePackAnalysisSession _session;
  Map<String, CalculationCanvasPreview> _previews = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  GamePackCalculation _document({String? id}) => GamePackCalculation(
    id: id ?? _draftId,
    label: _name.text.trim(),
    nodes: _nodes,
    result: _result,
  );

  void _refresh() {
    _draft = withGamePackCalculation(widget.design, _document());
    _session = widget.fixture.analysisFor(_draft, trace: true);
    _previews = {for (final node in _nodes) node.id: _testNode(node)};
  }

  CalculationCanvasPreview _testNode(GamePackCalculationNode node) {
    try {
      final sample = _session.previewNode(_draftId, node.id, _testScope);
      return (
        value: sample.value,
        explanation: sample.explanation,
        issue: null,
      );
    } on FormatException catch (error) {
      return (value: null, explanation: null, issue: error.message);
    } on GameGraphLimitExceeded catch (error) {
      return (value: null, explanation: null, issue: error.message);
    }
  }

  GamePackResultInfo? _info(String id) =>
      _draft.catalog.tryInfo((graph: _draftId, output: id));

  String _label(GamePackCalculationNode node) => switch (node) {
    GamePackInputNode(:final field) =>
      _draft.catalog
              .tryInfo(gamePackFieldRef(field ?? ''))
              ?.label
              .split(' · ')
              .first ??
          'Unassigned field',
    final GamePackStepNode step => calculationStepTitle(step),
  };

  void _update(
    List<GamePackCalculationNode> nodes, {
    String? result,
    String? select,
  }) {
    setState(() {
      _nodes = nodes;
      if (result != null) _result = result;
      if (select != null) _selected = select;
      _connecting = null;
      _message = null;
      _refresh();
    });
  }

  void _replace(GamePackCalculationNode node) => _update([
    for (final item in _nodes)
      if (item.id == node.id) node else item,
  ], select: node.id);

  String _id(String stem, [Iterable<String> additional = const []]) =>
      availableId(stem, [..._nodes.map((node) => node.id), ...additional]);

  GamePackOptions _fields([bool Function(GamePackResultInfo)? accepts]) => {
    for (final entry in widget.design.catalog.catalog.entries)
      if (entry.key.output != _draftId &&
          gamePackRollupOf(entry.key.output)?.field != _draftId &&
          (accepts?.call(entry.value) ?? true))
        entry.key: entry.value,
  };

  Future<GameGraphOutputRef?> _chooseField(
    String title, [
    bool Function(GamePackResultInfo)? test,
  ]) => pickGamePackResult(
    context,
    title: title,
    options: _fields(test),
    questionPaths: widget.design.questionPaths,
  );

  Future<void> _addStep() async {
    final op = await BearingsModal.show<GamePackRecipe>(
      context,
      builder: (_) => const _StepPicker(),
    );
    if (!mounted || op == null) return;
    final previous = _selected ?? _result;
    final info = _info(previous);
    final canConnect =
        info != null &&
        op != GamePackRecipe.constant &&
        _accepts(op, _firstPort(op), info);
    final step = _makeStep(
      op,
      source: canConnect ? previous : null,
      info: canConnect ? info : null,
    );
    _update(
      [..._nodes, step],
      result: _result.isEmpty || canConnect && previous == _result
          ? step.id
          : _result,
      select: step.id,
    );
    if (op == GamePackRecipe.constant) await _edit(step);
  }

  GamePackStepNode _makeStep(
    GamePackRecipe op, {
    String? source,
    GamePackResultInfo? info,
  }) {
    final reference = info?.grain;
    final scope = _defaultScope(op, reference, widget.scope);
    final needsTeamMatches =
        (op.reducesRows || op == GamePackRecipe.rows) &&
        scope == GamePackGrain.team &&
        reference == GamePackGrain.allianceMatch;
    return GamePackStepNode(
      id: _id(op.name.toLowerCase()),
      operation: op,
      grain: scope,
      inputs: source == null ? const {} : {_firstPort(op): source},
      rowGrain: needsTeamMatches ? GamePackGrain.teamMatch : null,
      comparisonValue: switch (op) {
        GamePackRecipe.constant => 0,
        GamePackRecipe.quantile => .5,
        _ => null,
      },
    );
  }

  bool _dependsOn(String source, String target) {
    final seen = <String>{};
    final index = {for (final node in _nodes) node.id: node};
    bool visit(String id) =>
        id == target ||
        (seen.add(id) && (index[id]?.inputs.values.any(visit) ?? false));
    return visit(source);
  }

  Future<void> _connectInput(
    GamePackStepNode step,
    String port,
    String label,
  ) async {
    if (_connecting case final from?) {
      _wire(step, port, from);
      return;
    }
    final alternatives = [
      for (final node in _nodes)
        if (node.id != step.inputs[port] && !_dependsOn(node.id, step.id))
          if (_info(node.id) case final info?
              when _accepts(step.operation, port, info))
            node,
    ];
    String? choice;
    if (alternatives.isNotEmpty || step.inputs.containsKey(port)) {
      choice = await BearingsModal.show<String>(
        context,
        builder: (context) => BearingsModal(
          title: label,
          actions: const [],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.search),
                title: const Text('Choose a field'),
                onTap: () => BearingsModal.complete(context, '@catalog'),
              ),
              for (final node in alternatives)
                ListTile(
                  leading: const Icon(LucideIcons.workflow),
                  title: Text(_label(node)),
                  subtitle: const Text('Already on this canvas'),
                  onTap: () => BearingsModal.complete(context, node.id),
                ),
              if (step.inputs.containsKey(port))
                ListTile(
                  leading: const Icon(LucideIcons.unlink),
                  title: const Text('Disconnect input'),
                  onTap: () => BearingsModal.complete(context, '@disconnect'),
                ),
            ],
          ),
        ),
      );
      if (!mounted || choice == null) return;
    }
    if (choice == '@disconnect') {
      _replace(step.withInputs({...step.inputs}..remove(port)));
      return;
    }
    if (choice != null && choice != '@catalog') {
      _wire(step, port, choice);
      return;
    }

    final ref = await _chooseField(
      label,
      (info) => _accepts(step.operation, port, info),
    );
    if (!mounted || ref == null) return;
    final existing = _nodes
        .whereType<GamePackInputNode>()
        .where((node) => node.field == ref.output)
        .firstOrNull;
    final source =
        existing ?? GamePackInputNode(id: _id('field'), field: ref.output);
    final column =
        step.operation == GamePackRecipe.rows && port.startsWith('column_');
    final field = widget.design.catalog.resultInfo(ref);
    final key = column
        ? gamePackIdForName(
            field.label.split(' · ').first,
            step.inputs.keys,
            'column',
          )
        : port;
    final linked = _withLink(step, key, source.id, field);
    _update([
      for (final node in _nodes)
        if (node.id == step.id) linked else node,
      if (existing == null) source,
    ], select: step.id);
  }

  void _wire(GamePackStepNode step, String port, String from) {
    final info = _info(from);
    if (info == null ||
        !_accepts(step.operation, port, info) ||
        _dependsOn(from, step.id)) {
      setState(
        () =>
            _message = 'Choose a compatible value that comes before this step.',
      );
      return;
    }
    _replace(_withLink(step, port, from, info));
  }

  GamePackStepNode _withLink(
    GamePackStepNode step,
    String port,
    String from,
    GamePackResultInfo info,
  ) {
    var inferred = step.inputs.isEmpty
        ? _defaultScope(step.operation, info.grain, widget.scope)
        : step.grain;
    final fixed =
        [
          GamePackRecipe.scale,
          GamePackRecipe.compare,
          GamePackRecipe.ballotRank,
          GamePackRecipe.ballotScore,
          GamePackRecipe.latestNote,
          GamePackRecipe.rows,
        ].contains(step.operation) ||
        step.operation.reducesRows;
    if (info.grain case final incoming?
        when !fixed && !inferred.canRead(incoming)) {
      inferred = GamePackGrain.values.firstWhere(
        (grain) => grain.canRead(inferred) && grain.canRead(incoming),
        orElse: () => inferred,
      );
    }
    return step.withInputs(
      {...step.inputs, port: from},
      grain: inferred,
      inferredRow:
          (step.operation.reducesRows ||
                  step.operation == GamePackRecipe.rows) &&
              inferred == GamePackGrain.team &&
              info.grain == GamePackGrain.allianceMatch
          ? GamePackGrain.teamMatch
          : null,
    );
  }

  Future<void> _addInput(GamePackStepNode step) async {
    final (port, label) = switch (step.operation) {
      GamePackRecipe.scale => ('extra', 'Extra alliance contribution'),
      GamePackRecipe.compare => ('scouted_other', 'Second scouting value'),
      _ => (
        availableId(
          step.operation == GamePackRecipe.rows ? 'column_1' : 'value_2',
          step.inputs.keys,
        ),
        step.operation == GamePackRecipe.rows
            ? 'Choose a column field'
            : 'Choose another value',
      ),
    };
    if (step.inputs.containsKey(port)) {
      setState(() => _message = 'All inputs for this step are connected.');
      return;
    }
    await _connectInput(step, port, label);
  }

  Future<void> _addField({String title = 'Add a field'}) async {
    final ref = await _chooseField(title);
    if (!mounted || ref == null) return;
    final node = GamePackInputNode(id: _id('field'), field: ref.output);
    if (_nodes.isEmpty && _name.text.isEmpty) {
      _name.text = _label(node);
    }
    _update(
      [..._nodes, node],
      result: _result.isEmpty ? node.id : _result,
      select: node.id,
    );
  }

  Future<void> _edit(GamePackCalculationNode node) async {
    switch (node) {
      case GamePackInputNode():
        final ref = await _chooseField('Change field');
        if (mounted && ref != null)
          _replace(GamePackInputNode(id: node.id, field: ref.output));
      case GamePackStepNode():
        final settings = await editCalculationStep(
          context,
          node: node,
          input: _info(node.inputs['value'] ?? ''),
        );
        if (mounted && settings != null) _replace(settings);
    }
  }

  Future<void> _drill(String id) async {
    if (_draft.catalog.calculationById(id) case final linked?) {
      await editGamePackCalculation(
        context,
        design: _draft,
        fixture: widget.fixture,
        current: linked,
        readOnly: true,
      );
    }
  }

  void _remove(String id) {
    final nodes = [
      for (final node in _nodes)
        if (node.id != id)
          if (node case GamePackStepNode() when node.inputs.containsValue(id))
            node.withInputs(
              {...node.inputs}..removeWhere((key, from) => from == id),
            )
          else
            node,
    ];
    _update(
      nodes,
      result: _result == id ? nodes.lastOrNull?.id ?? '' : _result,
    );
    setState(() => _selected = null);
  }

  String? get _problem {
    if (_nodes.isEmpty) return null;
    try {
      final named = _draft.catalog.resultInfo(gamePackFieldRef(_draftId));
      if (widget.scope case final fixed?) {
        if (named.grain case final grain? when !fixed.canRead(grain)) {
          return 'This display needs ${fixed.label.toLowerCase()}. Add a step that combines these values at that scope.';
        }
        if (!GamePackCardMetric.supports(named.type))
          return 'Use a number, text, or yes/no as the result.';
      }
      for (final node in _nodes) {
        _draft.catalog.nodeInfo(_draftId, node.id);
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String _scopeLabel(GamePackScope scope) {
    final team = scope.team?.replaceFirst('frc', '');
    var match = _session
        .evaluate(gamePackFieldRef('match_label'), scope: scope)
        .result
        .data
        ?.toString();
    if (match == scope.match) {
      final qualification = RegExp(r'_qm(\d+)$').firstMatch(match ?? '');
      if (qualification != null) match = qualification[1];
    }
    return [
      if (team != null) 'Team $team',
      if (match != null) 'Match $match',
      if (scope.alliance != null) gamePackKeyLabel(scope.alliance!),
    ].join(' · ');
  }

  Widget _creationControls() {
    final name = TextField(
      controller: _name,
      decoration: const InputDecoration(labelText: 'Calculation name'),
      onChanged: (_) => setState(() {}),
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (_nodes.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _addField,
            icon: const Icon(LucideIcons.plus, size: 17),
            label: const Text('Add value'),
          ),
        FilledButton.tonalIcon(
          onPressed: _addStep,
          icon: const Icon(LucideIcons.workflow, size: 17),
          label: const Text('Add step'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) => bounds.maxWidth >= 600
          ? Row(
              spacing: 12,
              children: [
                Expanded(child: name),
                actions,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [name, actions],
            ),
    );
  }

  List<Widget> _selectedActions(GamePackCalculationNode node) {
    final linked = switch (node) {
      GamePackInputNode(field: final field?) => _draft.catalog.calculationById(
        field,
      ),
      _ => null,
    };
    return [
      IconButton(
        tooltip: 'Edit selected node',
        onPressed: () => _edit(node),
        icon: const Icon(LucideIcons.pencil, size: 19),
      ),
      if (linked != null)
        IconButton(
          tooltip: 'Open ${_label(node)} calculation',
          onPressed: () => _drill(linked.id),
          icon: const Icon(LucideIcons.arrowUpRight, size: 19),
        ),
      if (_result != node.id)
        IconButton(
          tooltip: 'Use as result',
          onPressed: () => _update(_nodes, result: node.id),
          icon: const Icon(LucideIcons.flag, size: 19),
        ),
      IconButton(
        tooltip: 'Remove selected node',
        onPressed: () => _remove(node.id),
        color: Theme.of(context).colorScheme.error,
        icon: const Icon(LucideIcons.trash2, size: 19),
      ),
    ];
  }

  Widget _previewFooter(String previewLabel, String? detail) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        if (detail != null)
          Row(
            children: [
              Expanded(child: Text(detail, style: theme.textTheme.bodySmall)),
              if (_connecting != null)
                IconButton(
                  tooltip: 'Cancel connection',
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () => setState(() {
                    _connecting = null;
                    _message = null;
                  }),
                ),
            ],
          ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                [
                  'Test data',
                  if (previewLabel.isNotEmpty) previewLabel,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_nodes.isNotEmpty)
              GamePackEditorActionBar(
                children: [
                  IconButton(
                    tooltip: 'Zoom out',
                    onPressed: () => _canvas.currentState?.zoom(1 / 1.23),
                    icon: const Icon(LucideIcons.zoomOut, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Zoom in',
                    onPressed: () => _canvas.currentState?.zoom(1.23),
                    icon: const Icon(LucideIcons.zoomIn, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Fit calculation',
                    onPressed: () => _canvas.currentState?.fit(),
                    icon: const Icon(LucideIcons.scan, size: 19),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _nodes.where((node) => node.id == _selected).firstOrNull;
    final name = _name.text.trim();
    final problem = _problem;
    final canSave =
        name.isNotEmpty &&
        name.length <= 80 &&
        _nodes.isNotEmpty &&
        problem == null;
    final previewLabel = _scopeLabel(_testScope);
    final showDetail =
        _message ??
        (_connecting == null ? problem : 'Choose an input on another node.');
    return BearingsModal(
      title: widget.readOnly
          ? widget.current!.label
          : widget.current == null
          ? 'New calculation'
          : 'Edit calculation',
      size: BearingsModalSize.expansive,
      scrolling: BearingsModalScrolling.content,
      actions: const [],
      primaryAction: widget.readOnly
          ? null
          : BearingsModalPrimaryAction(
              label: 'Save calculation',
              icon: LucideIcons.check,
              enabled: canSave,
              onPressed: () => BearingsModal.complete(
                context,
                _document(
                  id:
                      widget.current?.id ??
                      gamePackIdForName(
                        name,
                        widget.design.resultIds,
                        'calculation',
                      ),
                ),
              ),
            ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 9,
        children: [
          if (!widget.readOnly) _creationControls(),
          Expanded(
            child: _nodes.isEmpty
                ? Center(
                    child: FilledButton.icon(
                      onPressed: () => _addField(title: 'Start with a value'),
                      icon: const Icon(LucideIcons.search),
                      label: const Text('Start with a value'),
                    ),
                  )
                : GamePackCalculationCanvas(
                    key: _canvas,
                    calculation: _document(),
                    catalog: _draft.catalog,
                    previews: _previews,
                    readOnly: widget.readOnly,
                    connecting: _connecting,
                    selected: _selected,
                    selectionActions: widget.readOnly || selected == null
                        ? const []
                        : _selectedActions(selected),
                    onSelect: (id) => setState(() => _selected = id),
                    onInput: _connectInput,
                    onOutput: (id) => setState(() {
                      _connecting = _connecting == id ? null : id;
                      _selected = id;
                      _message = null;
                    }),
                    onAddInput: _addInput,
                    onDrill: _drill,
                  ),
          ),
          _previewFooter(previewLabel, showDetail),
        ],
      ),
    );
  }
}

String _firstPort(GamePackRecipe operation) => switch (operation) {
  GamePackRecipe.scale || GamePackRecipe.compare => 'scouted',
  GamePackRecipe.subtract ||
  GamePackRecipe.divide ||
  GamePackRecipe.less => 'left',
  GamePackRecipe.choose => 'condition',
  _ => 'value',
};

GamePackGrain _defaultScope(
  GamePackRecipe operation,
  GamePackGrain? source,
  GamePackGrain? destination,
) {
  switch (operation) {
    case GamePackRecipe.scale:
      return GamePackGrain.teamMatch;
    case GamePackRecipe.compare:
      return GamePackGrain.event;
    case GamePackRecipe.ballotRank ||
        GamePackRecipe.ballotScore ||
        GamePackRecipe.latestNote:
      return GamePackGrain.team;
    case GamePackRecipe.constant:
      return GamePackGrain.event;
    default:
      break;
  }
  if (operation.reducesRows || operation == GamePackRecipe.rows) {
    if (destination != null &&
        (source == null ||
            source.canRead(destination) ||
            source == GamePackGrain.allianceMatch &&
                destination == GamePackGrain.team)) {
      return destination;
    }
    return switch (source) {
      GamePackGrain.teamMatch => GamePackGrain.team,
      GamePackGrain.allianceMatch => GamePackGrain.match,
      GamePackGrain.match ||
      GamePackGrain.team ||
      GamePackGrain.event => GamePackGrain.event,
      _ => GamePackGrain.team,
    };
  }
  if (source != null) return source;
  return destination ?? GamePackGrain.team;
}

bool _accepts(GamePackRecipe op, String port, GamePackResultInfo info) {
  final kind = info.type.kind;
  final numeric = GamePackType.number.accepts(info.type);
  return switch (op) {
    GamePackRecipe.scale || GamePackRecipe.compare =>
      numeric &&
          switch (port) {
            'scouted' ||
            'scouted_other' => info.grain == GamePackGrain.teamMatch,
            'official' || 'extra' => info.grain == GamePackGrain.allianceMatch,
            _ => true,
          },
    GamePackRecipe.average ||
    GamePackRecipe.sum ||
    GamePackRecipe.add ||
    GamePackRecipe.subtract ||
    GamePackRecipe.multiply ||
    GamePackRecipe.divide ||
    GamePackRecipe.less ||
    GamePackRecipe.meanOf ||
    GamePackRecipe.bernoulli => numeric,
    GamePackRecipe.rate ||
    GamePackRecipe.any ||
    GamePackRecipe.all ||
    GamePackRecipe.not => kind == GamePackTypeKind.boolean,
    GamePackRecipe.choose when port == 'condition' =>
      kind == GamePackTypeKind.boolean,
    GamePackRecipe.ballotRank || GamePackRecipe.ballotScore =>
      info.grain == GamePackGrain.allianceMatch &&
          info.type == const GamePackType.list(GamePackType.text),
    GamePackRecipe.text =>
      info.type == const GamePackType.list(GamePackType.text),
    GamePackRecipe.latestNote =>
      info.origin == GamePackResultOrigin.scouting &&
          kind == GamePackTypeKind.text,
    GamePackRecipe.flagged ||
    GamePackRecipe.countRows ||
    GamePackRecipe.empirical => kind == GamePackTypeKind.list,
    GamePackRecipe.quantile => const GamePackType.list(
      GamePackType.number,
    ).accepts(info.type),
    GamePackRecipe.sample => kind == GamePackTypeKind.distribution,
    GamePackRecipe.countLabel => kind == GamePackTypeKind.integer,
    GamePackRecipe.mostCommon =>
      numeric ||
          kind == GamePackTypeKind.text ||
          kind == GamePackTypeKind.boolean,
    _ => true,
  };
}

class _StepPicker extends StatefulWidget {
  const _StepPicker();
  @override
  State<_StepPicker> createState() => _StepPickerState();
}

class _StepPickerState extends State<_StepPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    const featured = [
      GamePackRecipe.average,
      GamePackRecipe.scale,
      GamePackRecipe.rate,
      GamePackRecipe.sum,
      GamePackRecipe.add,
    ];
    final ordered = [...GamePackRecipe.values]
      ..sort((a, b) {
        int rank(GamePackRecipe op) => featured.contains(op)
            ? featured.indexOf(op)
            : featured.length + op.index;
        return rank(a).compareTo(rank(b));
      });
    final found = ordered.where(
      (op) => op.label.toLowerCase().contains(_query),
    );
    return BearingsModal(
      title: 'Add step',
      actions: const [],
      size: BearingsModalSize.tall,
      scrolling: BearingsModalScrolling.content,
      content: SizedBox(
        height: 338,
        width: 455,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.search),
                labelText: 'Find a step',
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final op in found)
                    ListTile(
                      title: Text(op.label),
                      subtitle: switch (op) {
                        GamePackRecipe.average => const Text(
                          'Combine values across matches or teams',
                        ),
                        GamePackRecipe.scale => const Text(
                          'Adjust team counts using the official alliance total',
                        ),
                        GamePackRecipe.rate => const Text(
                          'Show the percentage of answers that are Yes',
                        ),
                        _ => null,
                      },
                      leading: Icon(
                        op == GamePackRecipe.scale
                            ? LucideIcons.scale
                            : LucideIcons.calculator,
                        size: 18,
                      ),
                      onTap: () => BearingsModal.complete(context, op),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
