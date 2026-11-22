import 'analysis.dart' show GamePackGrain;
import 'value.dart';

enum GameGraphOperation {
  source('Source', []),
  parameter('Parameter', []),
  literal('Literal', []),
  field('Read field', ['value']),
  toNumber('Read number', ['value']),
  toText('Format as text', ['value']),
  record('Build record', []),
  list('Build list', []),
  concat('Combine lists', ['left', 'right']),
  flatten('Flatten lists', ['items']),
  enumerate('Number list items', ['items']),
  joinText('Join text', ['items', 'separator']),
  first('First item', ['items']),
  ifElse('If / then / else', ['condition', 'then', 'else']),
  coalesce('Use fallback', ['value', 'fallback']),
  stateIs('Value state is', ['value']),
  equal('Equal', ['left', 'right']),
  less('Less than', ['left', 'right']),
  and('And', ['left', 'right']),
  or('Or', ['left', 'right']),
  not('Not', ['value']),
  add('Add', ['left', 'right']),
  subtract('Subtract', ['left', 'right']),
  multiply('Multiply', ['left', 'right']),
  divide('Divide', ['left', 'right']),
  map('Map', ['items']),
  filter('Filter', ['items']),
  join('Join', ['left', 'right']),
  groupBy('Group by', ['items']),
  sortBy('Sort by', ['items']),
  rankBy('Rank by', ['items']),
  count('Count items', ['items']),
  sum('Sum', ['items']),
  mean('Mean', ['items']),
  mode('Most common value', ['items']),
  standardDeviation('Standard deviation', ['items']),
  quantile('Quantile', ['items', 'fraction']),
  probability('Probability', ['items']),
  empirical('Empirical distribution', ['items']),
  bernoulli('Bernoulli distribution', ['chance']),
  weighted('Weighted distribution', ['items', 'weights']),
  sample('Sample distribution', ['distribution']),
  simulate('Simulate graph', ['iterations']),
  call('Graph output', []);

  const GameGraphOperation(this.label, this.ports);

  final String label;
  final List<String> ports;

  bool get callsGraph => switch (this) {
    call || map || filter || groupBy || sortBy || rankBy || simulate => true,
    _ => false,
  };

  bool get appliesToItems => switch (this) {
    map || filter || groupBy || sortBy || rankBy => true,
    _ => false,
  };

  bool get hasDynamicPorts => switch (this) {
    record || list => true,
    _ => callsGraph,
  };
}

typedef GameGraphPosition = ({double x, double y});

class GameGraphNode {
  GameGraphNode({
    required this.id,
    required this.operation,
    Map<String, String> inputs = const {},
    Map<String, Object?> options = const {},
    this.position,
  }) : inputs = Map.unmodifiable(inputs),
       options = _freeze(options) as Map<String, Object?> {
    if (position case (x: final x, y: final y)
        when !x.isFinite || !y.isFinite) {
      throw const FormatException('Node position must be finite.');
    }
  }

  final String id;
  final GameGraphOperation operation;

  /// Input port name to upstream node ID within this graph.
  final Map<String, String> inputs;
  final Map<String, Object?> options;
  final GameGraphPosition? position;

  factory GameGraphNode.fromJson(Map<String, dynamic> json) {
    final operation = GameGraphOperation.values
        .where((operation) => operation.name == json['operation'])
        .firstOrNull;
    if (operation == null) {
      throw FormatException('Unknown operation: ${json['operation']}');
    }
    final position = json['position'] as Map<String, dynamic>?;
    return GameGraphNode(
      id: json['id'] as String,
      operation: operation,
      inputs: (json['inputs'] as Map<String, dynamic>).cast<String, String>(),
      options: json['options'] as Map<String, dynamic>,
      position: position == null
          ? null
          : (
              x: (position['x'] as num).toDouble(),
              y: (position['y'] as num).toDouble(),
            ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'operation': operation.name,
    'inputs': inputs,
    'options': options,
    if (position case (x: final x, y: final y)) 'position': {'x': x, 'y': y},
  };

  GameGraphNode copyWith({
    Map<String, String>? inputs,
    Map<String, Object?>? options,
    GameGraphPosition? position,
  }) => GameGraphNode(
    id: id,
    operation: operation,
    inputs: inputs ?? this.inputs,
    options: options ?? this.options,
    position: position ?? this.position,
  );

  static Object? _freeze(Object? value, [int depth = 0]) {
    if (depth > 24)
      throw const FormatException('Node configuration is too deeply nested.');
    return switch (value) {
      final List<Object?> list => List<Object?>.unmodifiable(
        list.map((value) => _freeze(value, depth + 1)),
      ),
      final Map<String, Object?> map => Map<String, Object?>.unmodifiable(
        map.map((key, value) => MapEntry(key, _freeze(value, depth + 1))),
      ),
      null || String() || bool() => value,
      final num value when value.isFinite => value,
      _ => throw const FormatException('Node configuration must be JSON data.'),
    };
  }
}

class GameGraphOutput {
  const GameGraphOutput(this.node, this.type);

  final String node;
  final GamePackType type;

  factory GameGraphOutput.fromJson(Map<String, dynamic> json) =>
      GameGraphOutput(
        json['node'] as String,
        GamePackType.fromJson(json['type']),
      );

  Map<String, Object> toJson() => {'node': node, 'type': type.toJson()};
}

class GameGraph {
  GameGraph({
    required this.id,
    required List<GameGraphNode> nodes,
    required Map<String, GameGraphOutput> outputs,
    Map<String, GamePackType> parameters = const {},
    this.grain,
  }) : nodes = List.unmodifiable(nodes),
       outputs = Map.unmodifiable(outputs),
       parameters = Map.unmodifiable(parameters);

  final String id;
  final List<GameGraphNode> nodes;
  final Map<String, GameGraphOutput> outputs;
  final Map<String, GamePackType> parameters;
  final GamePackGrain? grain;

  factory GameGraph.fromJson(Map<String, dynamic> json) => GameGraph(
    id: json['id'] as String,
    grain: json['grain'] is String
        ? GamePackGrain.values.byName(json['grain'] as String)
        : null,
    nodes: (json['nodes'] as List<dynamic>)
        .map((node) => GameGraphNode.fromJson(node as Map<String, dynamic>))
        .toList(),
    outputs: (json['outputs'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        GameGraphOutput.fromJson(value as Map<String, dynamic>),
      ),
    ),
    parameters: (json['parameters'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, GamePackType.fromJson(value)),
    ),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    if (grain case final scope?) 'grain': scope.name,
    'parameters': parameters.map((key, value) => MapEntry(key, value.toJson())),
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'outputs': outputs.map((key, value) => MapEntry(key, value.toJson())),
  };
}

typedef GameGraphOutputRef = ({String graph, String output});
