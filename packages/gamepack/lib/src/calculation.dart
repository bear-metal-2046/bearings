part of 'analysis.dart';

/// A named, typed result whose implementation is a local, editable DAG.
class GamePackCalculation {
  GamePackCalculation({
    required this.id,
    required this.label,
    required List<GamePackCalculationNode> nodes,
    required this.result,
  }) : nodes = List.unmodifiable(nodes);

  final String id;
  final String label;
  final List<GamePackCalculationNode> nodes;
  final String result;
  late final Map<String, GamePackCalculationNode> nodesById = Map.unmodifiable({
    for (final node in nodes) node.id: node,
  });

  /// Starts a small graph with field cards already wired to one operation.
  factory GamePackCalculation.recipe({
    required String id,
    required String label,
    required GamePackRecipe operation,
    required GamePackGrain grain,
    required Map<String, GameGraphOutputRef> inputs,
    GamePackGrain? rowGrain,
    bool scheduleRows = false,
    bool missingAsZero = false,
    bool positiveOnly = false,
    GamePackCondition condition = GamePackCondition.provided,
    Object? comparisonValue,
    double threshold = .4,
    int minimumReports = 3,
    bool qualificationsOnly = false,
    bool flaggedOnly = false,
    bool fallbackToScouted = true,
    bool requirePositiveOfficial = true,
    String singular = 'match',
    String plural = 'matches',
    int trials = 100,
  }) {
    final sources = <String, GamePackInputNode>{};
    var index = 0;
    final bindings = inputs.map((port, ref) {
      if (ref.graph != gamePackFieldNamespace) {
        throw ArgumentError('Choose a named field as a recipe input.');
      }
      final node = sources.putIfAbsent(
        ref.output,
        () => GamePackInputNode(id: 'field_${++index}', field: ref.output),
      );
      return MapEntry(port, node.id);
    });
    return GamePackCalculation(
      id: id,
      label: label,
      result: 'result',
      nodes: [
        ...sources.values,
        GamePackStepNode(
          id: 'result',
          operation: operation,
          grain: grain,
          inputs: bindings,
          rowGrain: rowGrain,
          scheduleRows: scheduleRows,
          missingAsZero: missingAsZero,
          positiveOnly: positiveOnly,
          condition: condition,
          comparisonValue: comparisonValue,
          threshold: threshold,
          minimumReports: minimumReports,
          qualificationsOnly: qualificationsOnly,
          flaggedOnly: flaggedOnly,
          fallbackToScouted: fallbackToScouted,
          requirePositiveOfficial: requirePositiveOfficial,
          singular: singular,
          plural: plural,
          trials: trials,
        ),
      ],
    );
  }

  factory GamePackCalculation.fromJson(Map<String, dynamic> json) =>
      GamePackCalculation(
        id: json['id'] as String,
        label: json['label'] as String,
        nodes: (json['nodes'] as List)
            .map(
              (item) => GamePackCalculationNode.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        result: json['result'] as String,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'result': result,
    'nodes': nodes.map((node) => node.toJson()).toList(),
  };
}

sealed class GamePackCalculationNode {
  const GamePackCalculationNode(this.id);
  final String id;

  Map<String, String> get inputs;
  Map<String, Object> toJson();

  factory GamePackCalculationNode.fromJson(Map<String, dynamic> json) =>
      switch (json['kind']) {
        'field' => GamePackInputNode(
          id: json['id'] as String,
          field: json['field'] == null
              ? null
              : readGamePackResult(json, key: 'field').output,
        ),
        'step' => GamePackStepNode.fromJson(json),
        _ => throw const FormatException('Unknown calculation node kind.'),
      };
}

class GamePackInputNode extends GamePackCalculationNode {
  const GamePackInputNode({required String id, required this.field})
    : super(id);
  final String? field;

  @override
  Map<String, String> get inputs => const {};

  @override
  Map<String, Object> toJson() => {
    'kind': 'field',
    'id': id,
    if (field case final name?)
      ...writeGamePackResult(gamePackFieldRef(name), key: 'field'),
  };
}

class GamePackStepNode extends GamePackCalculationNode {
  GamePackStepNode({
    required String id,
    required this.operation,
    required this.grain,
    Map<String, String> inputs = const {},
    this.rowGrain,
    this.scheduleRows = false,
    this.missingAsZero = false,
    this.positiveOnly = false,
    this.condition = GamePackCondition.provided,
    this.comparisonValue,
    this.threshold = .4,
    this.minimumReports = 3,
    this.qualificationsOnly = false,
    this.flaggedOnly = false,
    this.fallbackToScouted = true,
    this.requirePositiveOfficial = true,
    this.singular = 'match',
    this.plural = 'matches',
    this.trials = 100,
  }) : inputs = Map.unmodifiable(inputs),
       super(id);

  final GamePackRecipe operation;
  final GamePackGrain grain;
  @override
  final Map<String, String> inputs;
  final GamePackGrain? rowGrain;
  final bool scheduleRows;
  final bool missingAsZero;
  final bool positiveOnly;
  final GamePackCondition condition;
  final Object? comparisonValue;
  final double threshold;
  final int minimumReports;
  final bool qualificationsOnly;
  final bool flaggedOnly;
  final bool fallbackToScouted;
  final bool requirePositiveOfficial;
  final String singular;
  final String plural;

  final int trials;

  factory GamePackStepNode.fromJson(Map<String, dynamic> json) =>
      GamePackStepNode(
        id: json['id'] as String,
        operation: GamePackRecipe.values.byName(json['operation'] as String),
        grain: GamePackGrain.values.byName(json['grain'] as String),
        inputs: (json['inputs'] as Map<String, dynamic>).cast<String, String>(),
        rowGrain: (json['rowGrain'] as String?)?.letGrain,
        scheduleRows: json['scheduleRows'] == true,
        missingAsZero: json['missingAsZero'] == true,
        positiveOnly: json['positiveOnly'] == true,
        condition: GamePackCondition.values.byName(
          json['condition'] as String? ?? 'provided',
        ),
        comparisonValue: json['comparisonValue'],
        threshold: (json['threshold'] as num?)?.toDouble() ?? .4,
        minimumReports: json['minimumReports'] as int? ?? 3,
        qualificationsOnly: json['qualificationsOnly'] == true,
        flaggedOnly: json['flaggedOnly'] == true,
        fallbackToScouted: json['fallbackToScouted'] != false,
        requirePositiveOfficial: json['requirePositiveOfficial'] != false,
        singular: json['singular'] as String? ?? 'match',
        plural: json['plural'] as String? ?? 'matches',
        trials: json['trials'] as int? ?? 100,
      );

  @override
  Map<String, Object> toJson() => {
    'kind': 'step',
    'id': id,
    'operation': operation.name,
    'grain': grain.name,
    'inputs': inputs,
    if (rowGrain case final value?) 'rowGrain': value.name,
    if (scheduleRows) 'scheduleRows': true,
    if (missingAsZero) 'missingAsZero': true,
    if (positiveOnly) 'positiveOnly': true,
    if (operation == GamePackRecipe.condition) 'condition': condition.name,
    if (comparisonValue case final value?) 'comparisonValue': value,
    if (operation == GamePackRecipe.compare) ...{
      'threshold': threshold,
      'minimumReports': minimumReports,
      if (qualificationsOnly) 'qualificationsOnly': true,
      if (flaggedOnly) 'flaggedOnly': true,
    },
    if (!fallbackToScouted) 'fallbackToScouted': false,
    if (!requirePositiveOfficial) 'requirePositiveOfficial': false,
    if (operation == GamePackRecipe.simulate) 'trials': trials,
    if (operation == GamePackRecipe.countLabel) ...{
      'singular': singular,
      'plural': plural,
    },
  };

  GamePackStepNode withInputs(
    Map<String, String> links, {
    GamePackGrain? grain,
    GamePackGrain? inferredRow,
  }) => GamePackStepNode(
    id: id,
    operation: operation,
    grain: grain ?? this.grain,
    inputs: links,
    rowGrain: rowGrain ?? inferredRow,
    scheduleRows: scheduleRows,
    missingAsZero: missingAsZero,
    positiveOnly: positiveOnly,
    condition: condition,
    comparisonValue: comparisonValue,
    threshold: threshold,
    minimumReports: minimumReports,
    qualificationsOnly: qualificationsOnly,
    flaggedOnly: flaggedOnly,
    fallbackToScouted: fallbackToScouted,
    requirePositiveOfficial: requirePositiveOfficial,
    singular: singular,
    plural: plural,
    trials: trials,
  );
}

/// Binds local wires to the calculation that owns them.
class _Step {
  _Step(this.owner, this.node);
  final String owner;
  final GamePackStepNode node;
  late final Map<String, GameGraphOutputRef> inputs = node.inputs.map(
    (port, id) => MapEntry(port, (graph: owner, output: id)),
  );
  GamePackRecipe get operation => node.operation;
  GamePackGrain get grain => node.grain;
  String get label => node.operation.label;
}

extension on String {
  GamePackGrain get letGrain => GamePackGrain.values.byName(this);
}
