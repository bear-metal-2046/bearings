part of 'program.dart';

class _Execution {
  _Execution(
    this.graphs,
    this.sources, {
    required int seed,
    required int workLimit,
    this.sourceResolver,
  }) : _state = seed % 2147483646 + 1,
       _remaining = workLimit;

  final Map<String, _CompiledGraph> graphs;
  final Map<String, GamePackValue> sources;
  final GamePackValue Function(String source)? sourceResolver;
  int _state;
  int _remaining;

  // Park–Miller arithmetic uses exact integers on both native and the web.
  double random() {
    _state = (_state * 48271) % 2147483647;
    return (_state - 1) / 2147483646;
  }

  void spend([int amount = 1]) {
    _remaining -= amount;
    if (_remaining < 0) {
      throw const GameGraphLimitExceeded(
        'The calculation exceeded its work limit.',
      );
    }
  }

  _Frame frame(String graphId, Map<String, GamePackValue> arguments) {
    final graph =
        graphs[graphId] ?? (throw ArgumentError('Unknown graph: $graphId'));
    if (arguments.length != graph.graph.parameters.length ||
        graph.graph.parameters.entries.any((entry) {
          final value = arguments[entry.key];
          return value == null || !entry.value.acceptsValue(value);
        })) {
      throw ArgumentError('Invalid parameters for graph $graphId.');
    }
    return _Frame(this, graph, arguments);
  }
}

class _Frame {
  _Frame(this.execution, this.graph, this.arguments);

  final _Execution execution;
  final _CompiledGraph graph;
  final Map<String, GamePackValue> arguments;
  final values = <String, GamePackValue>{};

  GamePackValue read(String id) => values.putIfAbsent(id, () {
    execution.spend();
    return _evaluate(graph.nodes[id]!);
  });

  GamePackValue _evaluate(GameGraphNode node) {
    final operation = node.operation;
    GamePackValue input(String name) => read(node.inputs[name]!);
    List<GamePackValue> inputs() => node.inputs.keys.map(input).toList();

    switch (operation) {
      case GameGraphOperation.source:
        final name = _stringOption(node, 'name');
        return execution.sources[name] ??
            execution.sourceResolver?.call(name) ??
            GamePackValue.missing;
      case GameGraphOperation.parameter:
        return arguments[_stringOption(node, 'name')]!;
      case GameGraphOperation.literal:
        return _literal(node);
      case GameGraphOperation.field:
        final value = input('value').atPath(_stringOption(node, 'path'));
        return graph.types[node.id]!.acceptsValue(value)
            ? value
            : GamePackValue.unknown.withEvidence(value.allEvidence);
      case GameGraphOperation.toNumber:
        final value = input('value');
        if (!value.isKnown) return value;
        final data = value.data;
        final number = data is String ? num.tryParse(data.trim()) : data;
        return _inherit(GamePackValue.of(number is num ? number : null), [
          value,
        ]);
      case GameGraphOperation.toText:
        final value = input('value');
        return value.isKnown
            ? _inherit(GamePackValue.of(value.data.toString()), [value])
            : value;
      case GameGraphOperation.record:
        return GamePackValue.record(
          node.inputs.map((key, from) => MapEntry(key, read(from))),
        );
      case GameGraphOperation.list:
        return GamePackValue.list(inputs());
      case GameGraphOperation.stateIs:
        final value = input('value');
        return _inherit(GamePackValue.of(value.state == _stateOption(node)), [
          value,
        ]);
      case GameGraphOperation.ifElse:
        final condition = input('condition');
        if (!condition.isKnown) return condition;
        return _inherit(input(condition.data as bool ? 'then' : 'else'), [
          condition,
        ]);
      case GameGraphOperation.coalesce:
        final value = input('value');
        return value.isKnown ? value : _inherit(input('fallback'), [value]);
      case GameGraphOperation.and:
      case GameGraphOperation.or:
        final left = input('left');
        if (!left.isKnown) return left;
        final stop = operation == GameGraphOperation.or;
        return left.data == stop ? left : _inherit(input('right'), [left]);
      case GameGraphOperation.not:
        final value = input('value');
        return value.isKnown
            ? _inherit(GamePackValue.of(!(value.data as bool)), [value])
            : value;
      case GameGraphOperation.equal:
      case GameGraphOperation.less:
      case GameGraphOperation.add:
      case GameGraphOperation.subtract:
      case GameGraphOperation.multiply:
      case GameGraphOperation.divide:
        return _binary(operation, input('left'), input('right'));
      case GameGraphOperation.concat:
        final left = input('left');
        final right = input('right');
        if (!left.isKnown || !right.isKnown) return _absent([left, right]);
        final first = left.data as List<GamePackValue>;
        final second = right.data as List<GamePackValue>;
        execution.spend(first.length + second.length);
        return GamePackValue.list([...first, ...second])
            .withEvidence([...left.evidence, ...right.evidence]);
      case GameGraphOperation.flatten:
        final collection = input('items');
        if (!collection.isKnown) return collection;
        final values = <GamePackValue>[];
        final evidence = {...collection.evidence};
        final lists = collection.data as List<GamePackValue>;
        execution.spend(lists.length);
        for (final list in lists) {
          if (list.data case final List<GamePackValue> present) {
            execution.spend(present.length);
            values.addAll(
              present.map((value) => value.withEvidence(list.evidence)),
            );
          } else {
            values.add(list);
          }
          evidence.addAll(list.evidence);
        }
        return GamePackValue.list(values).withEvidence(evidence);
      case GameGraphOperation.enumerate:
        final collection = input('items');
        if (!collection.isKnown) return collection;
        final rows = collection.data as List<GamePackValue>;
        execution.spend(rows.length);
        return GamePackValue.list([
          for (final (index, value) in rows.indexed)
            GamePackValue.record({
              'index': GamePackValue.of(index),
              'value': value,
            }),
        ]).withEvidence(collection.evidence);
      case GameGraphOperation.joinText:
        final collection = input('items');
        final separator = input('separator');
        if (!collection.isKnown || !separator.isKnown)
          return _absent([collection, separator]);
        final rows = collection.data as List<GamePackValue>;
        execution.spend(rows.length);
        if (rows.any((row) => !row.isKnown))
          return _inherit(_absent(rows), [collection, separator]);
        return _inherit(
          GamePackValue.of(
            rows
                .map((row) => row.data as String)
                .join(separator.data as String),
          ),
          [collection, separator],
        );
      case GameGraphOperation.first:
        final collection = input('items');
        if (!collection.isKnown) return collection;
        final item = (collection.data as List<GamePackValue>).firstOrNull;
        return (item ?? GamePackValue.missing).withEvidence(
          collection.evidence,
        );
      case GameGraphOperation.map:
      case GameGraphOperation.filter:
      case GameGraphOperation.groupBy:
      case GameGraphOperation.sortBy:
      case GameGraphOperation.rankBy:
        return _apply(node, input('items'));
      case GameGraphOperation.join:
        return _join(node, input('left'), input('right'));
      case GameGraphOperation.count:
      case GameGraphOperation.sum:
      case GameGraphOperation.mean:
      case GameGraphOperation.mode:
      case GameGraphOperation.standardDeviation:
      case GameGraphOperation.quantile:
      case GameGraphOperation.probability:
      case GameGraphOperation.empirical:
        return _aggregate(
          operation,
          input('items'),
          operation == GameGraphOperation.quantile ? input('fraction') : null,
        );
      case GameGraphOperation.bernoulli:
        final chance = input('chance');
        if (!chance.isKnown) return chance;
        final value = (chance.data as num).toDouble();
        if (value < 0 || value > 1)
          return _inherit(GamePackValue.unknown, [chance]);
        return _inherit(
          GamePackValue.of(
            GamePackDistribution(
              [GamePackValue.of(false), GamePackValue.of(true)],
              weights: [1 - value, value],
            ),
          ),
          [chance],
        );
      case GameGraphOperation.weighted:
        return _weighted(input('items'), input('weights'));
      case GameGraphOperation.sample:
        return _sample(input('distribution'));
      case GameGraphOperation.call:
        return _call(
          node,
          node.inputs.map((key, from) => MapEntry(key, read(from))),
        );
      case GameGraphOperation.simulate:
        final count = input('iterations');
        if (!count.isKnown) return count;
        final iterations = count.data as int;
        if (iterations < 1 || iterations > 25000) {
          throw const GameGraphLimitExceeded(
            'Simulation needs 1–25,000 iterations.',
          );
        }
        execution.spend(iterations);
        final parameters = {
          for (final entry in node.inputs.entries)
            if (entry.key != 'iterations') entry.key: read(entry.value),
        };
        return _inherit(
          GamePackValue.list([
            for (var index = 0; index < iterations; index++)
              _call(node, parameters),
          ]),
          [count],
        );
    }
  }

  GamePackValue _call(
    GameGraphNode node,
    Map<String, GamePackValue> arguments,
  ) {
    final target = execution.frame(_stringOption(node, 'graph'), arguments);
    return target.read(
      target.graph.outputs[_stringOption(node, 'output')]!.node,
    );
  }

  GamePackValue _apply(GameGraphNode node, GamePackValue collection) {
    if (!collection.isKnown) return collection;
    final rows = collection.data as List<GamePackValue>;
    execution.spend(rows.length);
    final target = execution.graphs[_stringOption(node, 'graph')]!;
    final parameter = _collectionParameter(target.graph, node);
    final bound = {
      for (final entry in node.inputs.entries)
        if (entry.key != 'items') entry.key: read(entry.value),
    };
    final keyed = [
      for (final (index, row) in rows.indexed)
        (row: row, key: _call(node, {...bound, parameter: row}), index: index),
    ];
    switch (node.operation) {
      case GameGraphOperation.map:
        return GamePackValue.list(keyed.map((entry) => entry.key))
            .withEvidence(collection.evidence);
      case GameGraphOperation.filter:
        return GamePackValue.list(
          keyed
              .where((entry) => entry.key.data == true)
              .map((entry) => entry.row),
        ).withEvidence([
          ...collection.evidence,
          for (final entry in keyed) ...entry.key.allEvidence,
        ]);
      case GameGraphOperation.groupBy:
        final groups =
            <
              (GamePackValueState, Object?),
              (GamePackValue, List<GamePackValue>)
            >{};
        for (final entry in keyed) {
          final key = (entry.key.state, entry.key.data);
          final known = groups[key];
          if (known == null) {
            groups[key] = (entry.key, [entry.row]);
          } else {
            known.$2.add(entry.row);
          }
        }
        return GamePackValue.list(
          groups.values.map(
            (group) => GamePackValue.record({
              'key': group.$1,
              'items': GamePackValue.list(group.$2),
            }),
          ),
        ).withEvidence(collection.evidence);
      case GameGraphOperation.sortBy:
      case GameGraphOperation.rankBy:
        final descending = node.options['descending'] == true;
        keyed.sort((a, b) {
          execution.spend();
          final order = _keyOrder(a.key, b.key, descending);
          return order == 0 ? a.index.compareTo(b.index) : order;
        });
        final results = node.operation == GameGraphOperation.sortBy
            ? keyed.map((entry) => entry.row)
            : keyed.indexed.map(
                (ranked) => GamePackValue.record({
                  'rank': ranked.$2.key.isKnown
                      ? GamePackValue.of(ranked.$1 + 1)
                      : _absent([ranked.$2.key]),
                  'value': ranked.$2.row,
                  'key': ranked.$2.key,
                }),
              );
        return GamePackValue.list(results).withEvidence([
          ...collection.evidence,
          for (final entry in keyed) ...entry.key.allEvidence,
        ]);
      default:
        throw StateError('Expected a collection operation');
    }
  }

  GamePackValue _join(
    GameGraphNode node,
    GamePackValue left,
    GamePackValue right,
  ) {
    if (!left.isKnown || !right.isKnown) return _absent([left, right]);
    final leftRows = left.data as List<GamePackValue>;
    final rightRows = right.data as List<GamePackValue>;
    execution.spend(leftRows.length + rightRows.length);
    final leftPath = _stringOption(node, 'leftKey');
    final rightPath = _stringOption(node, 'rightKey');
    final rightByKey = <Object?, List<GamePackValue>>{};
    for (final row in rightRows) {
      final key = row.atPath(rightPath);
      if (key.isKnown) (rightByKey[key.data] ??= []).add(row);
    }
    final rows = <GamePackValue>[];
    for (final row in leftRows) {
      final key = row.atPath(leftPath);
      final matched = key.isKnown ? rightByKey[key.data] : null;
      if (matched == null) {
        if (node.options['mode'] == 'left') {
          rows.add(
            GamePackValue.record({'left': row, 'right': GamePackValue.missing}),
          );
        }
        continue;
      }
      execution.spend(matched.length);
      for (final match in matched) {
        rows.add(GamePackValue.record({'left': row, 'right': match}));
      }
    }
    return _inherit(GamePackValue.list(rows), [left, right]);
  }

  GamePackValue _aggregate(
    GameGraphOperation operation,
    GamePackValue items,
    GamePackValue? fraction,
  ) {
    if (!items.isKnown) return items;
    if (fraction != null && !fraction.isKnown)
      return _inherit(fraction, [items]);
    final rows = items.data as List<GamePackValue>;
    execution.spend(rows.length);
    if (operation == GameGraphOperation.count) {
      return _inherit(GamePackValue.of(rows.length), [items]);
    }
    final known = rows.where((row) => row.isKnown).toList();
    if (known.isEmpty) return _inherit(_absent(rows), [items]);
    if (operation == GameGraphOperation.mode) {
      final counts = <Object?, int>{};
      for (final row in known) {
        counts.update(row.data, (count) => count + 1, ifAbsent: () => 1);
      }
      var winner = counts.entries.first;
      for (final entry in counts.entries.skip(1)) {
        if (entry.value > winner.value) winner = entry;
      }
      return _inherit(GamePackValue.of(winner.key), [items]);
    }
    if (operation == GameGraphOperation.empirical) {
      return _inherit(GamePackValue.of(GamePackDistribution(known)), [items]);
    }
    if (operation == GameGraphOperation.probability) {
      return _inherit(
        GamePackValue.of(
          known.where((value) => value.data == true).length / known.length,
        ),
        [items],
      );
    }
    final numbers = known
        .map((value) => (value.data as num).toDouble())
        .toList();
    final sum = numbers.fold(0.0, (sum, number) => sum + number);
    final mean = sum / numbers.length;
    final value = switch (operation) {
      GameGraphOperation.sum => sum,
      GameGraphOperation.mean => mean,
      GameGraphOperation.standardDeviation => _spread(numbers, mean),
      GameGraphOperation.quantile => _quantile(
        numbers,
        (fraction!.data as num).toDouble(),
      ),
      _ => throw StateError('Expected an aggregation operation'),
    };
    return _inherit(GamePackValue.of(value), [
      items,
      if (fraction != null) fraction,
    ]);
  }

  double? _quantile(List<double> data, double fraction) {
    if (fraction < 0 || fraction > 1) return null;
    data.sort((a, b) {
      execution.spend();
      return a.compareTo(b);
    });
    final index = fraction * (data.length - 1);
    final start = data[index.floor()];
    final end = data[index.ceil()];
    return start + (end - start) * (index % 1);
  }

  GamePackValue _weighted(GamePackValue items, GamePackValue weights) {
    if (!items.isKnown || !weights.isKnown) return _absent([items, weights]);
    final outcomes = items.data as List<GamePackValue>;
    final weightValues = weights.data as List<GamePackValue>;
    execution.spend(outcomes.length + weightValues.length);
    if (outcomes.isEmpty || outcomes.length != weightValues.length) {
      return _inherit(GamePackValue.unknown, [items, weights]);
    }
    if (outcomes.any((value) => !value.isKnown) ||
        weightValues.any((weight) => !weight.isKnown)) {
      return _inherit(_absent([...outcomes, ...weightValues]), [
        items,
        weights,
      ]);
    }
    try {
      return _inherit(
        GamePackValue.of(
          GamePackDistribution(
            outcomes,
            weights: weightValues.map(
              (weight) => (weight.data as num).toDouble(),
            ),
          ),
        ),
        [items, weights],
      );
    } on ArgumentError {
      return _inherit(GamePackValue.unknown, [items, weights]);
    }
  }

  GamePackValue _sample(GamePackValue value) {
    if (!value.isKnown) return value;
    final distribution = value.data as GamePackDistribution;
    final roll = execution.random();
    final weights = distribution.weights;
    if (weights == null) {
      return _inherit(
        distribution.values[(roll * distribution.values.length).floor()],
        [value],
      );
    }
    execution.spend(weights.length);
    var remaining = roll * weights.fold(0.0, (sum, weight) => sum + weight);
    for (final (index, weight) in weights.indexed) {
      if (remaining < weight)
        return _inherit(distribution.values[index], [value]);
      remaining -= weight;
    }
    return _inherit(
      distribution.values[weights.lastIndexWhere((weight) => weight > 0)],
      [value],
    );
  }
}

GamePackValue _inherit(GamePackValue result, Iterable<GamePackValue> inputs) =>
    result.withEvidence(inputs.expand((value) => value.allEvidence));

GamePackValue _absent(Iterable<GamePackValue> inputs) {
  final states = inputs.map((value) => value.state).toSet();
  final result = states.contains(GamePackValueState.missing) || states.isEmpty
      ? GamePackValue.missing
      : states.contains(GamePackValueState.unknown)
      ? GamePackValue.unknown
      : GamePackValue.notApplicable;
  return _inherit(result, inputs);
}

GamePackValue _binary(
  GameGraphOperation operation,
  GamePackValue left,
  GamePackValue right,
) {
  if (!left.isKnown || !right.isKnown) return _absent([left, right]);
  final a = left.data;
  final b = right.data;
  if (operation == GameGraphOperation.equal) {
    return _inherit(GamePackValue.of(a == b), [left, right]);
  }
  if (operation == GameGraphOperation.less) {
    return _inherit(GamePackValue.of(_compareKeys(a, b) < 0), [left, right]);
  }
  final first = (a as num).toDouble();
  final second = (b as num).toDouble();
  final result = switch (operation) {
    GameGraphOperation.add => first + second,
    GameGraphOperation.subtract => first - second,
    GameGraphOperation.multiply => first * second,
    GameGraphOperation.divide => second == 0 ? null : first / second,
    _ => throw StateError('Expected an arithmetic operation'),
  };
  return _inherit(GamePackValue.of(result), [left, right]);
}

int _keyOrder(GamePackValue a, GamePackValue b, bool descending) {
  if (!a.isKnown) return b.isKnown ? 1 : 0;
  if (!b.isKnown) return -1;
  final order = _compareKeys(a.data, b.data);
  return descending ? -order : order;
}

int _compareKeys(Object? a, Object? b) => switch (a) {
  final num number => number.compareTo(b as num),
  final String text => text.compareTo(b as String),
  final bool flag => (flag ? 1 : 0).compareTo(b == true ? 1 : 0),
  _ => throw StateError('Expected a comparable value'),
};

double _spread(List<double> numbers, double mean) {
  final variance =
      numbers.fold(0.0, (sum, number) {
        final deviation = number - mean;
        return sum + deviation * deviation;
      }) /
      numbers.length;
  return sqrt(variance);
}
