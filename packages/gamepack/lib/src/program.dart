import 'dart:math' show sqrt;

import 'graph.dart';
import 'value.dart';

part 'execution.dart';

final _graphId = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// A compiled, typed set of graphs. Public output declarations are the
/// interfaces checked when graphs call one another.
class GameGraphProgram {
  GameGraphProgram({
    required List<GameGraph> graphs,
    Map<String, GamePackType> sourceTypes = const {},
  }) : graphs = List.unmodifiable(graphs),
       sourceTypes = Map.unmodifiable(sourceTypes) {
    _compiled = _compile();
  }

  final List<GameGraph> graphs;
  final Map<String, GamePackType> sourceTypes;
  late final Map<String, _CompiledGraph> _compiled;

  factory GameGraphProgram.fromJson(Map<String, dynamic> json) =>
      GameGraphProgram(
        graphs: (json['graphs'] as List<dynamic>)
            .map((graph) => GameGraph.fromJson(graph as Map<String, dynamic>))
            .toList(),
        sourceTypes: (json['sources'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, GamePackType.fromJson(value)),
        ),
      );

  Map<String, Object?> toJson() => {
    'sources': sourceTypes.map((key, value) => MapEntry(key, value.toJson())),
    'graphs': graphs.map((graph) => graph.toJson()).toList(),
  };

  GamePackType nodeType(String graph, String node) =>
      _compiled[graph]?.types[node] ??
      (throw ArgumentError('Unknown graph node: $graph.$node'));

  GamePackType outputType(GameGraphOutputRef ref) =>
      _compiled[ref.graph]?.outputs[ref.output]?.type ??
      (throw ArgumentError('Unknown graph output: ${ref.graph}.${ref.output}'));

  Map<String, GamePackType> parametersFor(String graph) =>
      _compiled[graph]?.graph.parameters ??
      (throw ArgumentError('Unknown graph: $graph'));

  /// Evaluate a public output and keep the evaluated nodes for inspection.
  /// Each call gets independent, deterministic random state and work budget.
  GameGraphEvaluation evaluate(
    GameGraphOutputRef output, {
    Map<String, GamePackValue> sources = const {},
    Map<String, GamePackValue> arguments = const {},
    int seed = 0,
    int workLimit = 150000,
    GamePackValue Function(String source)? sourceResolver,
  }) {
    if (workLimit < 1) throw ArgumentError.value(workLimit, 'workLimit');
    for (final entry in sources.entries) {
      if (sourceTypes[entry.key]?.acceptsValue(entry.value) != true) {
        throw ArgumentError('Invalid source value: ${entry.key}');
      }
    }
    final execution = _Execution(
      _compiled,
      sources,
      seed: seed,
      workLimit: workLimit,
      sourceResolver: sourceResolver,
    );
    final frame = execution.frame(output.graph, arguments);
    final graphOutput = frame.graph.outputs[output.output];
    if (graphOutput == null)
      throw ArgumentError('Unknown output: ${output.output}');
    return GameGraphEvaluation(frame.read(graphOutput.node), frame.values);
  }

  /// Evaluate an internal node directly for the authoring inspector.
  GameGraphEvaluation inspect(
    String graph,
    String node, {
    Map<String, GamePackValue> sources = const {},
    Map<String, GamePackValue> arguments = const {},
    int seed = 0,
    int workLimit = 150000,
  }) {
    nodeType(graph, node);
    if (workLimit < 1) throw ArgumentError.value(workLimit, 'workLimit');
    for (final entry in sources.entries) {
      if (sourceTypes[entry.key]?.acceptsValue(entry.value) != true) {
        throw ArgumentError('Invalid source value: ${entry.key}');
      }
    }
    final frame = _Execution(
      _compiled,
      sources,
      seed: seed,
      workLimit: workLimit,
    ).frame(graph, arguments);
    return GameGraphEvaluation(frame.read(node), frame.values);
  }

  Map<String, _CompiledGraph> _compile() {
    if (graphs.length > 64 ||
        graphs.fold(0, (sum, graph) => sum + graph.nodes.length) > 2048) {
      throw const FormatException(
        'A program supports up to 64 graphs and 2048 nodes.',
      );
    }
    final declarations = <String, GameGraph>{};
    for (final graph in graphs) {
      if (!_graphId.hasMatch(graph.id) || declarations.containsKey(graph.id)) {
        throw FormatException('Invalid or duplicate graph ID: ${graph.id}');
      }
      if (graph.outputs.isEmpty) {
        throw FormatException('Graph ${graph.id} needs a public output.');
      }
      if (![
        ...graph.outputs.keys,
        ...graph.parameters.keys,
      ].every(_graphId.hasMatch)) {
        throw FormatException(
          'Invalid parameter or output name in ${graph.id}.',
        );
      }
      declarations[graph.id] = graph;
    }
    final compiling = <String>{};
    final compiled = <String, _CompiledGraph>{};
    _CompiledGraph compile(String id) {
      if (compiled[id] case final prior?) return prior;
      final graph = declarations[id];
      if (graph == null) throw FormatException('Unknown graph: $id');
      if (!compiling.add(id)) throw FormatException('Graph call cycle at $id.');
      final nodes = <String, GameGraphNode>{};
      for (final node in graph.nodes) {
        if (!_graphId.hasMatch(node.id) || nodes.containsKey(node.id)) {
          throw FormatException('Invalid or duplicate node ID: $id.${node.id}');
        }
        nodes[node.id] = node;
      }
      final visiting = <String>{};
      final types = <String, GamePackType>{};
      GamePackType infer(String nodeId) {
        if (types[nodeId] case final known?) return known;
        final node = nodes[nodeId];
        if (node == null)
          throw FormatException('Unknown input node: $id.$nodeId');
        if (!visiting.add(nodeId))
          throw FormatException('Node cycle at $id.$nodeId.');
        try {
          final inputs = node.inputs.map(
            (port, from) => MapEntry(port, infer(from)),
          );
          final target = node.operation.callsGraph
              ? compile(_stringOption(node, 'graph'))
              : null;
          final result = _inferType(
            sourceTypes,
            graph,
            node,
            inputs,
            target?.graph,
          );
          types[nodeId] = result;
          return result;
        } on FormatException catch (error) {
          throw FormatException('$id.$nodeId — ${error.message}');
        } finally {
          visiting.remove(nodeId);
        }
      }

      for (final node in graph.nodes) {
        infer(node.id);
      }
      for (final entry in graph.outputs.entries) {
        final actual = infer(entry.value.node);
        if (!entry.value.type.accepts(actual)) {
          throw FormatException(
            '$id.${entry.key} declares ${entry.value.type}, but its node emits $actual.',
          );
        }
      }
      compiling.remove(id);
      return compiled[id] = _CompiledGraph(graph, nodes, types);
    }

    for (final graph in graphs) {
      compile(graph.id);
    }
    return Map.unmodifiable(compiled);
  }
}

GamePackType _inferType(
  Map<String, GamePackType> sourceTypes,
  GameGraph graph,
  GameGraphNode node,
  Map<String, GamePackType> inputs,
  GameGraph? target,
) {
  final operation = node.operation;
  if (operation.callsGraph && target == null) {
    throw const FormatException('Choose an available graph.');
  }
  final targetOutput = target == null ? null : _outputOf(target, node);
  final boundParameters = target == null
      ? const <String, GamePackType>{}
      : _boundParameters(target, node);
  final expectedPorts = <String>{...operation.ports, ...boundParameters.keys};
  if (operation != GameGraphOperation.record &&
      operation != GameGraphOperation.list) {
    if (inputs.length != expectedPorts.length ||
        !expectedPorts.every(inputs.containsKey)) {
      throw FormatException(
        'Expected input ports ${expectedPorts.join(', ')}.',
      );
    }
  }
  GamePackType expect(String port, GamePackType type) {
    final actual = inputs[port]!;
    if (!type.accepts(actual)) {
      throw FormatException('$port expects $type, received $actual.');
    }
    return actual;
  }

  GamePackType item(String port) {
    final actual = inputs[port]!;
    if (actual.kind != GamePackTypeKind.list) {
      throw FormatException('$port expects a list, received $actual.');
    }
    return actual.element!;
  }

  for (final parameter in boundParameters.entries) {
    expect(parameter.key, parameter.value);
  }

  switch (operation) {
    case GameGraphOperation.source:
      final name = _stringOption(node, 'name');
      return sourceTypes[name] ??
          (throw FormatException('Unknown source: $name.'));
    case GameGraphOperation.parameter:
      final name = _stringOption(node, 'name');
      return graph.parameters[name] ??
          (throw FormatException('Unknown parameter: $name.'));
    case GameGraphOperation.literal:
      final type = GamePackType.fromJson(node.options['type']);
      final value = _literal(node);
      if (!type.acceptsValue(value))
        throw FormatException('Literal must be $type.');
      return type;
    case GameGraphOperation.field:
      final path = _stringOption(node, 'path');
      final inferred = _pathType(inputs['value']!, path);
      if (node.options.containsKey('type')) {
        final declared = GamePackType.fromJson(node.options['type']);
        if (inferred != null && !declared.accepts(inferred)) {
          throw FormatException(
            'Field $path has type $inferred, received $declared.',
          );
        }
        return declared;
      }
      return inferred ??
          (throw const FormatException('Set the type for a raw data field.'));
    case GameGraphOperation.toNumber:
      final type = inputs['value']!;
      if (!GamePackType.number.accepts(type) &&
          type != GamePackType.text &&
          type != GamePackType.json &&
          type != GamePackType.any) {
        throw FormatException('Cannot parse a number from $type.');
      }
      return GamePackType.number;
    case GameGraphOperation.toText:
      final type = inputs['value']!;
      if (!_isKey(type)) {
        throw FormatException('Cannot format $type as text.');
      }
      return GamePackType.text;
    case GameGraphOperation.record:
      if (!inputs.keys.every(_graphId.hasMatch)) {
        throw const FormatException(
          'Use valid field IDs for record input ports.',
        );
      }
      return GamePackType.record(inputs);
    case GameGraphOperation.list:
      final type = GamePackType.fromJson(node.options['type']);
      for (final port in inputs.keys) {
        expect(port, type);
      }
      return GamePackType.list(type);
    case GameGraphOperation.concat:
      return GamePackType.list(_commonType(item('left'), item('right')));
    case GameGraphOperation.flatten:
      final nested = item('items');
      if (nested.kind != GamePackTypeKind.list) {
        throw const FormatException('Flatten needs a list of lists.');
      }
      return nested;
    case GameGraphOperation.enumerate:
      return GamePackType.list(
        GamePackType.record({
          'index': GamePackType.integer,
          'value': item('items'),
        }),
      );
    case GameGraphOperation.joinText:
      expect('items', const GamePackType.list(GamePackType.text));
      expect('separator', GamePackType.text);
      return GamePackType.text;
    case GameGraphOperation.first:
      return item('items');
    case GameGraphOperation.ifElse:
      expect('condition', GamePackType.boolean);
      return _commonType(inputs['then']!, inputs['else']!);
    case GameGraphOperation.coalesce:
      return _commonType(inputs['value']!, inputs['fallback']!);
    case GameGraphOperation.stateIs:
      _stateOption(node);
      return GamePackType.boolean;
    case GameGraphOperation.equal:
    case GameGraphOperation.less:
      final type = _commonType(inputs['left']!, inputs['right']!);
      if (!_isKey(type))
        throw FormatException(
          'Comparison requires scalar values, received $type.',
        );
      return GamePackType.boolean;
    case GameGraphOperation.and:
    case GameGraphOperation.or:
      expect('left', GamePackType.boolean);
      expect('right', GamePackType.boolean);
      return GamePackType.boolean;
    case GameGraphOperation.not:
      expect('value', GamePackType.boolean);
      return GamePackType.boolean;
    case GameGraphOperation.add:
    case GameGraphOperation.subtract:
    case GameGraphOperation.multiply:
    case GameGraphOperation.divide:
      expect('left', GamePackType.number);
      expect('right', GamePackType.number);
      return GamePackType.number;
    case GameGraphOperation.map:
    case GameGraphOperation.filter:
    case GameGraphOperation.groupBy:
    case GameGraphOperation.sortBy:
    case GameGraphOperation.rankBy:
      final row = item('items');
      final parameter = _collectionParameter(target!, node);
      if (!target.parameters[parameter]!.accepts(row)) {
        throw FormatException('Parameter $parameter cannot accept $row.');
      }
      final output = targetOutput!;
      if (operation == GameGraphOperation.map) return GamePackType.list(output);
      if (operation == GameGraphOperation.filter) {
        if (output != GamePackType.boolean)
          throw const FormatException('Filters must return a boolean.');
        return inputs['items']!;
      }
      if (!_isKey(output))
        throw const FormatException(
          'Grouping and sorting keys must be scalar.',
        );
      if (operation == GameGraphOperation.groupBy) {
        return GamePackType.list(
          GamePackType.record({'key': output, 'items': GamePackType.list(row)}),
        );
      }
      if (operation == GameGraphOperation.rankBy) {
        return GamePackType.list(
          GamePackType.record({
            'rank': GamePackType.integer,
            'value': row,
            'key': output,
          }),
        );
      }
      return inputs['items']!;
    case GameGraphOperation.join:
      final left = item('left');
      final right = item('right');
      final leftKey = _pathType(left, _stringOption(node, 'leftKey'));
      final rightKey = _pathType(right, _stringOption(node, 'rightKey'));
      if (leftKey == null ||
          rightKey == null ||
          !_isKey(_commonType(leftKey, rightKey))) {
        throw const FormatException(
          'Join keys must have compatible scalar types.',
        );
      }
      if (node.options['mode'] != null &&
          !['inner', 'left'].contains(node.options['mode'])) {
        throw const FormatException('Join mode must be inner or left.');
      }
      return GamePackType.list(
        GamePackType.record({'left': left, 'right': right}),
      );
    case GameGraphOperation.count:
      item('items');
      return GamePackType.integer;
    case GameGraphOperation.mode:
      final scalar = item('items');
      if (!_isKey(scalar)) {
        throw const FormatException(
          'Most common value needs a list of scalar values.',
        );
      }
      return scalar;
    case GameGraphOperation.quantile:
      expect('fraction', GamePackType.number);
      expect('items', const GamePackType.list(GamePackType.number));
      return GamePackType.number;
    case GameGraphOperation.sum:
    case GameGraphOperation.mean:
    case GameGraphOperation.standardDeviation:
      expect('items', const GamePackType.list(GamePackType.number));
      return GamePackType.number;
    case GameGraphOperation.probability:
      expect('items', const GamePackType.list(GamePackType.boolean));
      return GamePackType.number;
    case GameGraphOperation.empirical:
      return GamePackType.distribution(item('items'));
    case GameGraphOperation.bernoulli:
      expect('chance', GamePackType.number);
      return const GamePackType.distribution(GamePackType.boolean);
    case GameGraphOperation.weighted:
      expect('weights', const GamePackType.list(GamePackType.number));
      return GamePackType.distribution(item('items'));
    case GameGraphOperation.sample:
      final type = inputs['distribution']!;
      if (type.kind != GamePackTypeKind.distribution) {
        throw const FormatException('Sampling requires a distribution.');
      }
      return type.element!;
    case GameGraphOperation.simulate:
      expect('iterations', GamePackType.integer);
      return GamePackType.list(targetOutput!);
    case GameGraphOperation.call:
      return targetOutput!;
  }
}

class GameGraphEvaluation {
  GameGraphEvaluation(this.result, Map<String, GamePackValue> nodes)
    : nodes = Map.unmodifiable(nodes);

  final GamePackValue result;
  final Map<String, GamePackValue> nodes;
}

class GameGraphLimitExceeded implements Exception {
  const GameGraphLimitExceeded(this.message);
  final String message;

  @override
  String toString() => message;
}

class _CompiledGraph {
  const _CompiledGraph(this.graph, this.nodes, this.types);
  final GameGraph graph;
  final Map<String, GameGraphNode> nodes;
  final Map<String, GamePackType> types;
  Map<String, GameGraphOutput> get outputs => graph.outputs;
}

GamePackType _outputOf(GameGraph graph, GameGraphNode node) {
  final name = _stringOption(node, 'output');
  return graph.outputs[name]?.type ??
      (throw FormatException('Unknown public output: ${graph.id}.$name.'));
}

String _stringOption(GameGraphNode node, String key) {
  final option = node.options[key];
  if (option is! String || option.isEmpty || option.length > 240) {
    throw FormatException('Set $key on ${node.id}.');
  }
  return option;
}

GamePackValue _literal(GameGraphNode node) => node.options.containsKey('value')
    ? GamePackValue.of(node.options['value'])
    : switch (_stateOption(node)) {
        GamePackValueState.missing => GamePackValue.missing,
        GamePackValueState.unknown => GamePackValue.unknown,
        GamePackValueState.notApplicable => GamePackValue.notApplicable,
        GamePackValueState.known => throw const FormatException(
          'A known literal needs a value.',
        ),
      };

GamePackValueState _stateOption(GameGraphNode node) {
  final state = node.options['state'];
  return GamePackValueState.values
          .where((value) => value.name == state)
          .firstOrNull ??
      (throw const FormatException('Choose a value state.'));
}

bool _isKey(GamePackType type) => switch (type.kind) {
  GamePackTypeKind.integer ||
  GamePackTypeKind.number ||
  GamePackTypeKind.text ||
  GamePackTypeKind.boolean => true,
  _ => false,
};

GamePackType _commonType(GamePackType left, GamePackType right) {
  if (left.accepts(right)) return left;
  if (right.accepts(left)) return right;
  throw FormatException('Types do not agree: $left and $right.');
}

GamePackType? _pathType(GamePackType input, String path) {
  GamePackType? current = input;
  for (final part in path.split('.')) {
    if (part.isEmpty) throw FormatException('Invalid field path: $path.');
    current = switch (current?.kind) {
      GamePackTypeKind.record =>
        current!.fields[part] ??
            (throw FormatException('Unknown record field: $part.')),
      GamePackTypeKind.list when (int.tryParse(part) ?? -1) >= 0 =>
        current!.element,
      GamePackTypeKind.json || GamePackTypeKind.any || null => null,
      _ => throw FormatException('Cannot read $part from $current.'),
    };
  }
  return current;
}

String _collectionParameter(GameGraph graph, GameGraphNode node) {
  final declared = node.options['itemParameter'];
  if (declared == null && graph.parameters.length == 1)
    return graph.parameters.keys.single;
  if (declared is String && graph.parameters.containsKey(declared))
    return declared;
  throw FormatException('Choose a parameter for each item in ${node.id}.');
}

Map<String, GamePackType> _boundParameters(
  GameGraph target,
  GameGraphNode node,
) {
  final itemParameter = node.operation.appliesToItems
      ? _collectionParameter(target, node)
      : null;
  final bindings = Map<String, GamePackType>.of(target.parameters)
    ..remove(itemParameter);
  for (final port in node.operation.ports) {
    if (bindings.containsKey(port)) {
      throw FormatException('${node.operation.label} reserves the $port port.');
    }
  }
  return bindings;
}

/// Inspect and connect a partially edited graph using the publishing rules.
class GameGraphInspector {
  GameGraphInspector({
    required this.graph,
    required Iterable<GameGraph> graphs,
    required this.sourceTypes,
  }) : graphs = {for (final item in graphs) item.id: item},
       _nodes = {for (final node in graph.nodes) node.id: node};

  final GameGraph graph;
  final Map<String, GameGraph> graphs;
  final Map<String, GamePackType> sourceTypes;
  final Map<String, GameGraphNode> _nodes;
  final _types = <String, GamePackType?>{};
  final _ancestorIds = <String, Set<String>>{};

  GamePackType? typeOf(String id) => _infer(id, {});

  String? issueFor(GameGraphNode node) {
    try {
      final inputs = <String, GamePackType>{};
      for (final entry in node.inputs.entries) {
        final type = typeOf(entry.value);
        if (type == null)
          return '${entry.key} has an incomplete or invalid connection.';
        inputs[entry.key] = type;
      }
      _inferType(sourceTypes, graph, node, inputs, _target(node));
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  Map<String, GamePackType?> inputPorts(GameGraphNode node) {
    final operation = node.operation;
    final ports = <String, GamePackType?>{
      for (final port in operation.ports) port: _portType(node, port),
    };
    if (operation == GameGraphOperation.list ||
        operation == GameGraphOperation.record) {
      for (final port in node.inputs.keys) {
        ports[port] = _portType(node, port);
      }
    }
    if (operation.callsGraph) {
      final target = graphs[node.options['graph']];
      if (target != null) {
        try {
          ports.addAll(_boundParameters(target, node));
        } on FormatException {
          // The inspector can still show the built-in inputs while the
          // referenced graph or callback parameter is being configured.
        }
      }
    }
    return ports;
  }

  String? connectionIssue(String from, GameGraphNode target, String port) {
    final ports = inputPorts(target);
    if (!ports.containsKey(port)) return 'This input is unavailable.';
    if (!_nodes.containsKey(from)) return 'The source node is unavailable.';
    if (_ancestorIds
        .putIfAbsent(from, () {
          final pending = [from];
          final visited = <String>{};
          while (pending.isNotEmpty) {
            final id = pending.removeLast();
            if (visited.add(id))
              pending.addAll(_nodes[id]?.inputs.values ?? const []);
          }
          return visited;
        })
        .contains(target.id)) {
      return 'This connection would create a cycle.';
    }
    final supplied = typeOf(from);
    final expected = ports[port];
    if (supplied != null && expected != null && !expected.accepts(supplied)) {
      return '${target.id}.$port expects $expected, received $supplied.';
    }
    if (supplied == null) return null;
    final proposed = target.copyWith(inputs: {...target.inputs, port: from});
    final types = <String, GamePackType>{};
    if (!ports.keys.every(proposed.inputs.containsKey)) return null;
    for (final entry in proposed.inputs.entries) {
      final type = typeOf(entry.value);
      if (type == null) return null;
      types[entry.key] = type;
    }
    if ([
      GameGraphOperation.field,
      GameGraphOperation.join,
      GameGraphOperation.list,
    ].contains(target.operation))
      return null;
    try {
      _inferType(sourceTypes, graph, proposed, types, _target(proposed));
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  /// Evaluate one configured dependency chain while unrelated nodes are edited.
  GameGraphEvaluation preview(
    String node, {
    Map<String, GamePackValue> sources = const {},
    Map<String, GamePackValue> arguments = const {},
    int seed = 0,
  }) {
    final type = typeOf(node);
    if (type == null)
      throw const FormatException(
        'Complete the node inputs to preview this value.',
      );
    final ids = <String>{};
    final callbacks = <String, GameGraph>{};
    void addCallback(GameGraph candidate) {
      if (candidate.id == graph.id || callbacks.containsKey(candidate.id))
        return;
      callbacks[candidate.id] = candidate;
      for (final node in candidate.nodes) {
        if (_target(node) case final called?) addCallback(called);
      }
    }

    void visit(String id) {
      if (!ids.add(id)) return;
      final item = _nodes[id]!;
      if (_target(item) case final target?) addCallback(target);
      for (final input in item.inputs.values) {
        visit(input);
      }
    }

    visit(node);
    final program = GameGraphProgram(
      graphs: [
        GameGraph(
          id: graph.id,
          parameters: graph.parameters,
          nodes: graph.nodes.where((node) => ids.contains(node.id)).toList(),
          outputs: {'preview': GameGraphOutput(node, type)},
        ),
        ...callbacks.values,
      ],
      sourceTypes: sourceTypes,
    );
    return program.inspect(
      graph.id,
      node,
      sources: sources,
      arguments: arguments,
      seed: seed,
    );
  }

  /// Preview a draft in a single pass. Incomplete branches can fail without
  /// blocking independent nodes. Deterministic nodes share their intermediates.
  /// Sampling branches keep the same seed as the single-node inspector.
  ({Map<String, GamePackValue> values, Map<String, String> issues}) previewAll({
    Map<String, GamePackValue> sources = const {},
    Map<String, GamePackValue> arguments = const {},
    int seed = 0,
    int workLimit = 45000,
  }) {
    if (workLimit < 1) throw ArgumentError.value(workLimit, 'workLimit');
    for (final entry in sources.entries) {
      if (sourceTypes[entry.key]?.acceptsValue(entry.value) != true) {
        throw ArgumentError('Invalid source value: ${entry.key}');
      }
    }
    final compiled = <String, _CompiledGraph>{};
    final brokenTargets = <String, String>{};
    bool samples(GameGraphNode node) =>
        node.operation == GameGraphOperation.sample ||
        node.operation == GameGraphOperation.simulate;

    for (final node in graph.nodes) {
      final target = _target(node);
      if (target == null ||
          typeOf(node.id) == null ||
          compiled.containsKey(target.id) ||
          brokenTargets.containsKey(target.id)) {
        continue;
      }
      final involved = <String, GameGraph>{};
      void visit(GameGraph candidate) {
        if (candidate.id == graph.id || involved.containsKey(candidate.id))
          return;
        involved[candidate.id] = candidate;
        for (final item in candidate.nodes) {
          if (_target(item) case final child?) visit(child);
        }
      }

      visit(target);
      try {
        final program = GameGraphProgram(
          graphs: involved.values.toList(),
          sourceTypes: sourceTypes,
        );
        compiled.addAll(program._compiled);
      } on FormatException catch (error) {
        brokenTargets[target.id] = error.message;
      }
    }

    final graphRandom = <String, bool>{};
    bool randomGraph(GameGraph candidate) => graphRandom.putIfAbsent(
      candidate.id,
      () => candidate.nodes.any((item) {
        final child = _target(item);
        return samples(item) || (child != null && randomGraph(child));
      }),
    );
    for (final target in compiled.values) {
      randomGraph(target.graph);
    }

    compiled[graph.id] = _CompiledGraph(graph, _nodes, {
      for (final node in graph.nodes)
        if (typeOf(node.id) case final type?) node.id: type,
    });
    final execution = _Execution(
      compiled,
      sources,
      seed: seed,
      workLimit: workLimit,
    );
    final shared = execution.frame(graph.id, arguments);
    final values = <String, GamePackValue>{};
    final issues = <String, String>{};
    final nodeRandom = <String, bool>{};
    final nodeFailure = <String, String?>{};
    bool samplesInBranch(String id) => nodeRandom.putIfAbsent(id, () {
      final node = _nodes[id]!;
      return samples(node) ||
          graphRandom[_target(node)?.id] == true ||
          node.inputs.values.any(samplesInBranch);
    });
    String? unavailableInBranch(String id) {
      if (nodeFailure.containsKey(id)) return nodeFailure[id];
      final node = _nodes[id]!;
      final target = _target(node);
      return nodeFailure[id] =
          brokenTargets[target?.id] ??
          node.inputs.values.map(unavailableInBranch).nonNulls.firstOrNull;
    }

    for (final node in graph.nodes) {
      if (typeOf(node.id) == null) {
        issues[node.id] = issueFor(node) ?? 'Complete the node inputs.';
        continue;
      }
      if (unavailableInBranch(node.id) case final issue?) {
        issues[node.id] = issue;
        continue;
      }
      if (execution._remaining < 1) {
        issues[node.id] = 'The graph preview reached its work limit.';
        continue;
      }
      final engine = samplesInBranch(node.id)
          ? _Execution(
              compiled,
              sources,
              seed: seed,
              workLimit: execution._remaining,
            )
          : execution;
      try {
        final frame = identical(engine, execution)
            ? shared
            : engine.frame(graph.id, arguments);
        values[node.id] = frame.read(node.id);
      } on GameGraphLimitExceeded catch (error) {
        issues[node.id] = error.message;
      } finally {
        execution._remaining = engine._remaining;
      }
    }
    return (values: values, issues: issues);
  }

  GamePackType? _infer(String id, Set<String> visiting) {
    if (_types.containsKey(id)) return _types[id];
    final node = _nodes[id];
    if (node == null || !visiting.add(id)) return null;
    try {
      final inputs = <String, GamePackType>{};
      for (final entry in node.inputs.entries) {
        final type = _infer(entry.value, visiting);
        if (type == null) return _types[id] = null;
        inputs[entry.key] = type;
      }
      return _types[id] = _inferType(
        sourceTypes,
        graph,
        node,
        inputs,
        _target(node),
      );
    } on FormatException {
      return _types[id] = null;
    } finally {
      visiting.remove(id);
    }
  }

  GameGraph? _target(GameGraphNode node) =>
      node.operation.callsGraph ? graphs[node.options['graph']] : null;

  GamePackType? _portType(GameGraphNode node, String port) {
    const numberList = GamePackType.list(GamePackType.number);
    const genericList = GamePackType.list(GamePackType.any);
    return switch (node.operation) {
      GameGraphOperation.add ||
      GameGraphOperation.subtract ||
      GameGraphOperation.multiply ||
      GameGraphOperation.divide ||
      GameGraphOperation.bernoulli => GamePackType.number,
      GameGraphOperation.and ||
      GameGraphOperation.or ||
      GameGraphOperation.not => GamePackType.boolean,
      GameGraphOperation.ifElse when port == 'condition' =>
        GamePackType.boolean,
      GameGraphOperation.list =>
        node.options['type'] == null
            ? null
            : GamePackType.fromJson(node.options['type']),
      GameGraphOperation.concat ||
      GameGraphOperation.join ||
      GameGraphOperation.first ||
      GameGraphOperation.map ||
      GameGraphOperation.flatten ||
      GameGraphOperation.enumerate ||
      GameGraphOperation.filter ||
      GameGraphOperation.groupBy ||
      GameGraphOperation.sortBy ||
      GameGraphOperation.rankBy ||
      GameGraphOperation.count ||
      GameGraphOperation.mode ||
      GameGraphOperation.empirical => genericList,
      GameGraphOperation.joinText =>
        port == 'separator'
            ? GamePackType.text
            : const GamePackType.list(GamePackType.text),
      GameGraphOperation.sum ||
      GameGraphOperation.mean ||
      GameGraphOperation.standardDeviation => numberList,
      GameGraphOperation.quantile =>
        port == 'fraction' ? GamePackType.number : numberList,
      GameGraphOperation.probability => const GamePackType.list(
        GamePackType.boolean,
      ),
      GameGraphOperation.weighted =>
        port == 'weights' ? numberList : genericList,
      GameGraphOperation.sample => const GamePackType.distribution(
        GamePackType.any,
      ),
      GameGraphOperation.simulate => GamePackType.integer,
      _ => null,
    };
  }
}
