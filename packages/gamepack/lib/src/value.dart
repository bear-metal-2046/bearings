enum GamePackTypeKind {
  any,
  boolean,
  integer,
  number,
  text,
  json,
  list,
  record,
  distribution,
}

/// An immutable port type. Non-value states can occur on every port.
class GamePackType {
  const GamePackType._(this.kind, {this.element, this.fields = const {}});

  const GamePackType.list(GamePackType element)
    : this._(GamePackTypeKind.list, element: element);

  const GamePackType.distribution(GamePackType element)
    : this._(GamePackTypeKind.distribution, element: element);

  GamePackType.record(Map<String, GamePackType> fields)
    : this._(GamePackTypeKind.record, fields: Map.unmodifiable(fields));

  static const any = GamePackType._(GamePackTypeKind.any);
  static const boolean = GamePackType._(GamePackTypeKind.boolean);
  static const integer = GamePackType._(GamePackTypeKind.integer);
  static const number = GamePackType._(GamePackTypeKind.number);
  static const text = GamePackType._(GamePackTypeKind.text);
  static const json = GamePackType._(GamePackTypeKind.json);

  final GamePackTypeKind kind;
  final GamePackType? element;
  final Map<String, GamePackType> fields;

  factory GamePackType.fromJson(Object? json) => _decode(json, 0);

  static GamePackType _decode(Object? json, int depth) {
    if (depth > 24)
      throw const FormatException('Port type is too deeply nested.');
    return switch (json) {
      'any' => any,
      'boolean' => boolean,
      'integer' => integer,
      'number' => number,
      'text' => text,
      'json' => GamePackType.json,
      {'list': final Object? item} => GamePackType.list(
        _decode(item, depth + 1),
      ),
      {'distribution': final Object? item} => GamePackType.distribution(
        _decode(item, depth + 1),
      ),
      {'record': final Map<String, dynamic> fields} => GamePackType.record(
        fields.map((key, value) => MapEntry(key, _decode(value, depth + 1))),
      ),
      _ => throw FormatException('Unknown port type: $json'),
    };
  }

  Object toJson() => switch (kind) {
    GamePackTypeKind.list => {'list': element!.toJson()},
    GamePackTypeKind.distribution => {'distribution': element!.toJson()},
    GamePackTypeKind.record => {
      'record': fields.map((key, value) => MapEntry(key, value.toJson())),
    },
    _ => kind.name,
  };

  bool accepts(GamePackType actual) {
    if (kind == GamePackTypeKind.any) return true;
    if (kind == GamePackTypeKind.number &&
        actual.kind == GamePackTypeKind.integer) {
      return true;
    }
    if (kind != actual.kind) return false;
    if (element case final expected?) return expected.accepts(actual.element!);
    return fields.entries.every((entry) {
      final type = actual.fields[entry.key];
      return type != null && entry.value.accepts(type);
    });
  }

  bool acceptsValue(GamePackValue value) {
    if (value.state != GamePackValueState.known) return true;
    final data = value.data;
    return switch (kind) {
      GamePackTypeKind.any => true,
      GamePackTypeKind.boolean => data is bool,
      GamePackTypeKind.integer => data is int,
      GamePackTypeKind.number => data is num && data.isFinite,
      GamePackTypeKind.text => data is String,
      GamePackTypeKind.json => _isJson(value),
      GamePackTypeKind.list =>
        data is List<GamePackValue> && data.every(element!.acceptsValue),
      GamePackTypeKind.record =>
        data is Map<String, GamePackValue> &&
            fields.entries.every(
              (entry) => entry.value.acceptsValue(
                data[entry.key] ?? GamePackValue.missing,
              ),
            ),
      GamePackTypeKind.distribution =>
        data is GamePackDistribution &&
            data.values.every(element!.acceptsValue),
    };
  }

  static bool _isJson(GamePackValue value) => switch (value.data) {
    null || bool() || String() => true,
    final num number => number.isFinite,
    final List<GamePackValue> list => list.every(_isJson),
    final Map<String, GamePackValue> map => map.values.every(_isJson),
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is GamePackType && accepts(other) && other.accepts(this);

  @override
  int get hashCode => Object.hash(
    kind,
    element,
    Object.hashAllUnordered(
      fields.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() => switch (kind) {
    GamePackTypeKind.list => 'list<$element>',
    GamePackTypeKind.distribution => 'distribution<$element>',
    GamePackTypeKind.record =>
      '{${fields.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ')}}',
    _ => kind.name,
  };
}

enum GamePackValueState { missing, unknown, notApplicable, known }

/// A reference to an immutable upstream or scouting record.
typedef GamePackEvidenceRef = ({String type, String id});

/// Rows and lists store child values so each field can retain its own state
/// and evidence. Operators add the evidence that influenced their result.
class GamePackValue {
  const GamePackValue._(this.state, this.data, this.evidence);

  static const missing = GamePackValue._(GamePackValueState.missing, null, {});
  static const unknown = GamePackValue._(GamePackValueState.unknown, null, {});
  static const notApplicable = GamePackValue._(
    GamePackValueState.notApplicable,
    null,
    {},
  );

  factory GamePackValue.of(Object? data) {
    return switch (data) {
      null => unknown,
      final GamePackValue value => value,
      final num value when !value.isFinite => unknown,
      final Iterable<Object?> values => GamePackValue.list(
        values.map(GamePackValue.of),
      ),
      final Map<String, Object?> values => GamePackValue.record(
        values.map((key, value) => MapEntry(key, GamePackValue.of(value))),
      ),
      num() || bool() || String() || GamePackDistribution() => GamePackValue._(
        GamePackValueState.known,
        data,
        const {},
      ),
      _ => throw ArgumentError.value(
        data,
        'data',
        'Unsupported GamePack value',
      ),
    };
  }

  factory GamePackValue.list(Iterable<GamePackValue> values) => GamePackValue._(
    GamePackValueState.known,
    List<GamePackValue>.unmodifiable(values),
    const {},
  );

  factory GamePackValue.record(Map<String, GamePackValue> values) =>
      GamePackValue._(
        GamePackValueState.known,
        Map<String, GamePackValue>.unmodifiable(values),
        const {},
      );

  final GamePackValueState state;
  final Object? data;
  final Set<GamePackEvidenceRef> evidence;

  bool get isKnown => state == GamePackValueState.known;

  GamePackValue withEvidence(Iterable<GamePackEvidenceRef> additional) {
    final combined = {...evidence, ...additional};
    if (combined.length == evidence.length) return this;
    return GamePackValue._(state, data, Set.unmodifiable(combined));
  }

  Iterable<GamePackEvidenceRef> get allEvidence sync* {
    yield* evidence;
    if (data case final List<GamePackValue> items) {
      for (final item in items) {
        yield* item.allEvidence;
      }
    } else if (data case final Map<String, GamePackValue> row) {
      for (final item in row.values) {
        yield* item.allEvidence;
      }
    }
  }

  /// A dotted path supports record keys and zero-based array indices.
  GamePackValue atPath(String path) {
    var current = this;
    for (final key in path.split('.')) {
      if (!current.isKnown) return current;
      final parentEvidence = current.evidence;
      final value = current.data;
      if (value is Map<String, GamePackValue>) {
        current = value[key] ?? missing;
      } else if (value is List<GamePackValue>) {
        final index = int.tryParse(key);
        current = index == null || index < 0 || index >= value.length
            ? missing
            : value[index];
      } else {
        current = missing;
      }
      current = current.withEvidence(parentEvidence);
    }
    return current;
  }

  Object? get plainValue => switch (data) {
    final List<GamePackValue> values =>
      values.map((value) => value.plainValue).toList(),
    final Map<String, GamePackValue> values => values.map(
      (key, value) => MapEntry(key, value.plainValue),
    ),
    _ => data,
  };

  @override
  String toString() => isKnown ? plainValue.toString() : state.name;
}

class GamePackDistribution {
  GamePackDistribution(
    Iterable<GamePackValue> values, {
    Iterable<double>? weights,
  }) : values = List.unmodifiable(values),
       weights = weights == null ? null : List.unmodifiable(weights) {
    if (this.values.isEmpty || this.values.any((value) => !value.isKnown)) {
      throw ArgumentError('A distribution requires known values.');
    }
    if (this.weights case final weights?) {
      if (weights.length != this.values.length ||
          weights.any((weight) => weight < 0 || !weight.isFinite) ||
          !weights.any((weight) => weight > 0) ||
          !weights.fold(0.0, (sum, weight) => sum + weight).isFinite) {
        throw ArgumentError('Invalid distribution weights.');
      }
    }
  }

  final List<GamePackValue> values;
  final List<double>? weights;

  @override
  String toString() => 'Distribution (${values.length} outcomes)';
}
