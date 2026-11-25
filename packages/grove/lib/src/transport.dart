import 'entity.dart';
import 'query.dart';

class GroveException implements Exception {
  const GroveException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class GroveOffline extends GroveException {
  const GroveOffline([String message = 'The server is unavailable'])
    : super('offline', message);
}

class GroveRequestTimeout extends GroveException {
  const GroveRequestTimeout()
    : super('request_timeout', 'The server took too long to respond');
}

enum GroveConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  signInRequired,
}

class GroveConnectionInfo {
  const GroveConnectionInfo({
    required this.state,
    this.lastReplyAt,
    this.lastFailure,
  });

  final GroveConnectionState state;
  final DateTime? lastReplyAt;
  final GroveException? lastFailure;
}

class QuerySnapshot {
  QuerySnapshot(this.records, {this.revision = 0});
  final List<EntityRecord> records;
  final int revision;
  Json toJson() => {
    'records': records.map((r) => r.toJson()).toList(),
    'revision': revision,
  };
  factory QuerySnapshot.fromJson(Json json) => QuerySnapshot(
    (json['records'] as List)
        .map((r) => EntityRecord.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
    revision: json['revision'] as int,
  );
}

class FieldChange {
  FieldChange(List<String> path, this.value, {this.remove = false})
    : path = List.unmodifiable(path) {
    if (path.isEmpty || path.any((p) => p.isEmpty))
      throw ArgumentError('Invalid field path');
  }
  final List<String> path;
  final Object? value;
  final bool remove;
  Json toJson() => {'path': path, 'value': value, 'remove': remove};
  factory FieldChange.fromJson(Json json) => FieldChange(
    (json['path'] as List).cast<String>(),
    json['value'],
    remove: json['remove'] as bool,
  );
}

enum MutationKind { create, update, delete }

class EntityMutation {
  EntityMutation({
    required this.mutationId,
    required this.type,
    required this.id,
    required this.version,
    required this.kind,
    this.data,
    this.changes = const [],
  });
  final String mutationId;
  final String type;
  final String id;
  final int version;
  final MutationKind kind;
  final Json? data;
  final List<FieldChange> changes;
  Json toJson() => {
    'mutationId': mutationId,
    'type': type,
    'id': id,
    'version': version,
    'kind': kind.name,
    'data': data,
    'changes': changes.map((c) => c.toJson()).toList(),
  };
  factory EntityMutation.fromJson(Json json) => EntityMutation(
    mutationId: json['mutationId'] as String,
    type: json['type'] as String,
    id: json['id'] as String,
    version: json['version'] as int,
    kind: MutationKind.values.byName(json['kind'] as String),
    data: (json['data'] as Map?)?.cast<String, dynamic>(),
    changes: (json['changes'] as List)
        .map((c) => FieldChange.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList(),
  );
}

abstract interface class GroveTransport {
  Future<QuerySnapshot> fetch(QueryDescription query);
  Stream<QuerySnapshot> watch(QueryDescription query);
  Future<EntityRecord> mutate(EntityMutation mutation);
  Future<void> close();
}

/// An authenticated session that can reconnect independently of its requests.
abstract interface class GroveConnectionTransport implements GroveTransport {
  GroveConnectionState get connectionState;
  Stream<GroveConnectionState> watchConnection();
  Future<void> connect();
  void checkConnection();
}

/// Cache entries are keyed by the entire query, so removals, limits and query
/// membership survive restart. Offline snapshots are always explicitly incomplete.
abstract interface class GroveCache {
  Future<Json?> read(String key);
  Future<void> write(String key, Json value);
  Future<void> remove(String key);

  /// Discards cached query results while retaining drafts and mutation state.
  Future<void> clearQuerySnapshots();
}

class MemoryGroveCache implements GroveCache {
  final _values = <String, Json>{};
  @override
  Future<Json?> read(String key) async =>
      _values[key] == null ? null : cloneJson(_values[key]!);
  @override
  Future<void> write(String key, Json value) async {
    _values[key] = cloneJson(value);
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clearQuerySnapshots() async {
    _values.removeWhere(
      (key, value) =>
          key.startsWith('query:') || value['_download'] == 'competition',
    );
  }
}

List<FieldChange> changedFields(
  Json before,
  Json after, [
  List<String> prefix = const [],
]) {
  final changes = <FieldChange>[];
  for (final key in {...before.keys, ...after.keys}) {
    if (canonicalJson(before[key]) == canonicalJson(after[key]) &&
        before.containsKey(key) == after.containsKey(key))
      continue;
    final path = [...prefix, key];
    if (!after.containsKey(key)) {
      changes.add(FieldChange(path, null, remove: true));
    } else if (after[key] is Map &&
        (before[key] is Map || !before.containsKey(key)) &&
        (after[key] as Map).isNotEmpty) {
      changes.addAll(
        changedFields(
          Map<String, dynamic>.from(before[key] as Map? ?? const {}),
          Map<String, dynamic>.from(after[key] as Map),
          path,
        ),
      );
    } else {
      changes.add(FieldChange(path, after[key]));
    }
  }
  return changes;
}

Json applyChanges(Json data, List<FieldChange> changes) {
  final result = cloneJson(data);
  for (final change in changes) {
    var map = result;
    for (final segment in change.path.take(change.path.length - 1)) {
      if (map[segment] is! Map) map[segment] = <String, dynamic>{};
      map = map[segment] as Json;
    }
    if (change.remove) {
      map.remove(change.path.last);
    } else {
      map[change.path.last] = change.value;
    }
  }
  return cloneJson(result);
}

/// Shared mutation semantics for memory tests and the authoritative SQL store.
EntityRecord commitMutation(
  EntityRegistry registry,
  EntityMutation mutation,
  EntityRecord? current,
  int revision,
) {
  final descriptor = registry.named(mutation.type);
  if (mutation.id.isEmpty || mutation.mutationId.isEmpty)
    throw ArgumentError('IDs must not be empty');
  if (mutation.version < 1 || mutation.version > descriptor.version)
    throw UnsupportedSchema(mutation.type, mutation.version);
  bool exceedsClientSchema(String field) =>
      (descriptor.fieldVersions[field] ?? 1) > mutation.version;
  if ((mutation.data?.keys.any(exceedsClientSchema) ?? false) ||
      mutation.changes.any(
        (change) => exceedsClientSchema(change.path.first),
      )) {
    throw ArgumentError('Mutation contains fields outside its declared schema');
  }
  if (mutation.kind == MutationKind.create) {
    if (current != null) {
      throw const GroveException(
        'conflict',
        'Entity ID already exists, including tombstones',
      );
    }
    final data = cloneJson(mutation.data!);
    if (data['id'] != mutation.id) throw ArgumentError('Entity ID mismatch');
    descriptor.latest(data, mutation.version);
    return EntityRecord(
      type: mutation.type,
      id: mutation.id,
      version: mutation.version,
      data: data,
      revision: revision,
    );
  }
  if (current == null || current.deleted)
    throw const GroveException('not_found', 'Entity does not exist');
  if (current.version > mutation.version)
    throw UnsupportedSchema(mutation.type, current.version);
  if (mutation.kind == MutationKind.delete)
    return EntityRecord(
      type: current.type,
      id: current.id,
      version: current.version,
      data: current.data,
      revision: revision,
      deleted: true,
    );
  if (mutation.changes.any((c) => c.path.first == 'id'))
    throw ArgumentError('Entity ID is immutable');
  var version = current.version;
  var data = cloneJson(current.data);
  if (mutation.changes.any(
    (c) => (descriptor.fieldVersions[c.path.first] ?? 1) > version,
  )) {
    data = descriptor.latest(data, version);
    version = descriptor.version;
  }
  data = applyChanges(data, mutation.changes);
  descriptor.latest(data, version);
  return EntityRecord(
    type: current.type,
    id: current.id,
    version: version,
    data: data,
    revision: revision,
  );
}

/// Public display information about a peer observing an entity.
class GrovePresencePeer {
  const GrovePresencePeer(this.id, {this.name, this.avatarUrl});

  final String id;
  final String? name;
  final String? avatarUrl;

  Json toJson() => {'id': id, 'name': name, 'avatarUrl': avatarUrl};

  factory GrovePresencePeer.fromJson(Json data) => GrovePresencePeer(
    data['id'] as String,
    name: data['name'] as String?,
    avatarUrl: data['avatarUrl'] as String?,
  );
}

/// Optional, ephemeral presence on the transport's authenticated connection.
abstract interface class GrovePresenceTransport {
  Stream<List<GrovePresencePeer>> watchPresence(String type, String entityId);
}
