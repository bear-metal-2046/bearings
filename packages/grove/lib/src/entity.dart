import 'dart:convert';

typedef Json = Map<String, dynamic>;

/// Describes a Dart model once for clients and Honeycomb. Migrations must be
/// lossless and must throw when required information cannot be recovered.
class EntityDescriptor<T> {
  EntityDescriptor({
    required this.type,
    required this.version,
    required this.encode,
    required this.decode,
    this.offlineMutable = false,
    this.serverManaged = false,
    this.migrations = const {},
    this.fieldVersions = const {},
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$').hasMatch(type) ||
        version < 1) {
      throw ArgumentError('Invalid entity type or schema version');
    }
  }

  final String type;
  final int version;
  final bool offlineMutable;

  /// The application server owns writes for this type.
  final bool serverManaged;
  final Json Function(T) encode;
  final T Function(Json) decode;

  /// A transform from version N to N+1; never applied persistently on reads.
  final Map<int, Json Function(Json)> migrations;

  /// Earliest schema supporting a root field. Unlisted fields exist in v1.
  final Map<String, int> fieldVersions;

  Json latest(Json data, int storedVersion) {
    if (storedVersion < 1 || storedVersion > version) {
      throw UnsupportedSchema(type, storedVersion);
    }
    var result = cloneJson(data);
    for (var v = storedVersion; v < version; v++) {
      final migrate = migrations[v];
      if (migrate == null) throw UnsupportedSchema(type, storedVersion);
      result = migrate(result);
    }
    // Validate null safety and required information through the actual model.
    decode(result);
    return result;
  }

  T read(EntityRecord record) => decode(latest(record.data, record.version));
}

class EntityRegistry {
  final _byType = <Type, EntityDescriptor<dynamic>>{};
  final _byName = <String, EntityDescriptor<dynamic>>{};

  void register<T>(EntityDescriptor<T> descriptor) {
    if (_byType.containsKey(T) || _byName.containsKey(descriptor.type)) {
      throw StateError('Duplicate Grove registration: ${descriptor.type} / $T');
    }
    _byType[T] = descriptor;
    _byName[descriptor.type] = descriptor;
  }

  EntityDescriptor<T> descriptor<T>() {
    final value = _byType[T];
    if (value == null) throw StateError('Unregistered Grove model: $T');
    return value as EntityDescriptor<T>;
  }

  EntityDescriptor<dynamic> named(String type) {
    final value = _byName[type];
    if (value == null) throw ArgumentError('Unregistered entity type: $type');
    return value;
  }

  Iterable<EntityDescriptor<dynamic>> get descriptors => _byName.values;

  bool isServerManaged(String type) => _byName[type]?.serverManaged ?? false;
}

class EntityRef<T> {
  const EntityRef(this.id);
  final String id;
}

class EntityRecord {
  EntityRecord({
    required this.type,
    required this.id,
    required this.version,
    required Json data,
    this.revision = 0,
    this.deleted = false,
  }) : data = cloneJson(data);

  final String type;
  final String id;
  final int version;
  final Json data;
  final int revision;
  final bool deleted;

  Json toJson() => {
    'type': type,
    'id': id,
    'version': version,
    'data': data,
    'revision': revision,
    'deleted': deleted,
  };

  factory EntityRecord.fromJson(Json json) => EntityRecord(
    type: json['type'] as String,
    id: json['id'] as String,
    version: json['version'] as int,
    data: Map<String, dynamic>.from(json['data'] as Map),
    revision: json['revision'] as int,
    deleted: json['deleted'] as bool,
  );
}

class UnsupportedSchema implements Exception {
  const UnsupportedSchema(this.type, this.version);
  final String type;
  final int version;
  @override
  String toString() => 'Update required for $type schema $version';
}

Json cloneJson(Json value) => jsonDecode(jsonEncode(value)) as Json;

/// Stable encoding makes query identity and changed-field comparisons independent
/// of map insertion order.
String canonicalJson(Object? value) {
  Object? sort(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(item[key])};
    }
    if (item is List) return item.map(sort).toList();
    return item;
  }

  return jsonEncode(sort(value));
}

/// Generates codecs, an entity descriptor, and typed query fields for the
/// public fields accepted by the model's unnamed generative constructor.
class GroveEntity {
  const GroveEntity(
    this.type, {
    required this.version,
    this.idField = 'id',
    this.offlineMutable = false,
    this.serverManaged = false,
  });

  final String type;
  final int version;
  final String idField;
  final bool offlineMutable;
  final bool serverManaged;
}

/// Generates a codec for a typed value embedded in a Grove entity in the same
/// library.
class GroveValue {
  const GroveValue();
}
