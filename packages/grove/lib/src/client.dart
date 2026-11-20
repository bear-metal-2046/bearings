import 'dart:async';

import 'package:uuid/uuid.dart';

import 'entity.dart';
import 'query.dart';
import 'transport.dart';

class Grove {
  Grove({required this.registry, required this.transport, GroveCache? cache})
    : cache = cache ?? MemoryGroveCache() {
    final connection = transport;
    if (connection is GroveConnectionTransport) {
      _connectionSubscription = connection.watchConnection().listen((state) {
        if (state == GroveConnectionState.connected) {
          _syncTimer?.cancel();
          _scheduleSync(Duration.zero);
        }
      });
    } else {
      _scheduleSync(Duration.zero);
    }
  }
  final EntityRegistry registry;
  final GroveTransport transport;
  final GroveCache cache;
  final _localChanges = StreamController<String?>.broadcast();
  Future<void> _queueTail = Future.value();
  bool _closed = false;
  Future<void>? _closing;
  Timer? _syncTimer;
  StreamSubscription<GroveConnectionState>? _connectionSubscription;
  String? _syncError;

  GroveQuery<T> query<T>() {
    final descriptor = registry.descriptor<T>();
    return GroveQuery(
      this,
      descriptor,
      QueryDescription(
        type: descriptor.type,
        schemaVersion: descriptor.version,
      ),
    );
  }

  Future<List<Json>> _pending() async =>
      ((await cache.read('pending'))?['mutations'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<int> get pendingMutationCount async => (await _pending()).length;

  Future<GroveSyncStatus> _syncStatus() async {
    final state = await cache.read('pending');
    return GroveSyncStatus(
      pending: (state?['mutations'] as List?)?.length ?? 0,
      rejected: (state?['rejected'] as List?)?.length ?? 0,
      error: _syncError,
    );
  }

  Stream<GroveSyncStatus> watchSyncStatus() {
    late StreamController<GroveSyncStatus> controller;
    StreamSubscription<String?>? subscription;
    controller = StreamController(
      onListen: () {
        subscription = _localChanges.stream.listen((_) async {
          final status = await _syncStatus();
          if (controller.hasListener) controller.add(status);
        }, onDone: () => controller.close());
        unawaited(
          _syncStatus().then((status) {
            if (controller.hasListener) controller.add(status);
          }),
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  QueryDescription _idQuery(String type, String id) => QueryDescription(
    type: type,
    schemaVersion: registry.named(type).version,
    filters: [QueryFilter('id', FilterOperator.equal, id)],
  );

  Future<void> _cacheRecord(EntityRecord record) async {
    final query = _idQuery(record.type, record.id);
    final previous = await cache.read('query:${query.key}');
    if (previous != null && (previous['revision'] as int) > record.revision)
      return;
    await cache.write(
      'query:${query.key}',
      QuerySnapshot(
        record.deleted ? [] : [record],
        revision: record.revision,
      ).toJson(),
    );
  }

  void _scheduleSync(Duration delay) {
    final connection = transport;
    if (_closed ||
        _syncTimer?.isActive == true ||
        (connection is GroveConnectionTransport &&
            connection.connectionState != GroveConnectionState.connected)) {
      return;
    }
    _syncTimer = Timer(delay, () async {
      try {
        await synchronize();
      } catch (error) {
        _syncError = error.toString();
        if (!_closed) _localChanges.add(null);
      }
      if (!_closed) {
        try {
          if (await pendingMutationCount > 0)
            _scheduleSync(const Duration(seconds: 5));
        } catch (error) {
          _syncError = error.toString();
          if (!_closed) _localChanges.add(null);
        }
      }
    });
  }

  Future<R> _serialized<R>(Future<R> Function() operation) {
    final completer = Completer<R>();
    _queueTail = _queueTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<QueryResult<T>> fetch<T>(
    GroveQuery<T> query, {
    bool cacheEntities = false,
  }) async {
    QuerySnapshot snapshot;
    var offline = false;
    var hasSnapshot = true;
    try {
      snapshot = await transport.fetch(query.description);
      await cache.write('query:${query.description.key}', snapshot.toJson());
      if (cacheEntities) {
        for (final record in snapshot.records) {
          await _cacheRecord(record);
        }
      }
    } on GroveOffline {
      offline = true;
      final cached = await cache.read('query:${query.description.key}');
      hasSnapshot = cached != null;
      snapshot = cached == null
          ? QuerySnapshot([])
          : QuerySnapshot.fromJson(cached);
    }
    return _decode(query, snapshot, offline: offline, hasSnapshot: hasSnapshot);
  }

  Future<QueryResult<T>> _decode<T>(
    GroveQuery<T> query,
    QuerySnapshot snapshot, {
    bool offline = false,
    bool hasSnapshot = true,
  }) async {
    final records = {for (final record in snapshot.records) record.id: record};
    for (final entry in await _pending()) {
      final mutation = EntityMutation.fromJson(entry['mutation'] as Json);
      if (mutation.type != query.description.type) continue;
      final base =
          records[mutation.id] ??
          (entry['base'] == null
              ? null
              : EntityRecord.fromJson(entry['base'] as Json));
      if (mutation.kind == MutationKind.create && base != null) continue;
      final record = commitMutation(
        registry,
        mutation,
        base,
        snapshot.revision,
      );
      records[mutation.id] = record;
    }
    final unsupported = <EntityRecord>[];
    final latest = <EntityRecord>[];
    for (final record in records.values.where((r) => !r.deleted)) {
      try {
        latest.add(
          EntityRecord(
            type: record.type,
            id: record.id,
            version: query.descriptor.version,
            data: query.descriptor.latest(record.data, record.version),
            revision: record.revision,
          ),
        );
      } on UnsupportedSchema {
        unsupported.add(record);
      }
    }
    final selected = evaluateQuery(query.description, latest);
    return QueryResult(
      selected.map((r) => query.descriptor.decode(r.data)),
      complete: !offline && unsupported.isEmpty,
      offline: offline,
      hasSnapshot: hasSnapshot,
      unsupported: List.unmodifiable(unsupported),
      revision: snapshot.revision,
    );
  }

  Stream<QueryResult<T>> watch<T>(GroveQuery<T> query) {
    late StreamController<QueryResult<T>> controller;
    StreamSubscription<QuerySnapshot>? remote;
    StreamSubscription<String?>? local;
    QuerySnapshot? latest;
    var offline = true;
    var hasSnapshot = false;
    var cancelled = false;
    Future<void> tail = Future.value();
    void emit({QuerySnapshot? received, bool? disconnected}) {
      tail = tail
          .then((_) async {
            if (cancelled) return;
            final snapshot = received ?? latest ?? QuerySnapshot([]);
            latest = snapshot;
            offline = disconnected ?? offline;
            hasSnapshot = received != null || hasSnapshot;
            if (!offline && received != null) {
              await cache.write(
                'query:${query.description.key}',
                snapshot.toJson(),
              );
            }
            final value = await _decode(
              query,
              snapshot,
              offline: offline,
              hasSnapshot: hasSnapshot,
            );
            if (!cancelled) controller.add(value);
          })
          .catchError((Object error, StackTrace stack) {
            if (!cancelled) controller.addError(error, stack);
          });
    }

    controller = StreamController(
      onListen: () async {
        final cached = await cache.read('query:${query.description.key}');
        if (cancelled) return;
        if (cached != null)
          emit(received: QuerySnapshot.fromJson(cached), disconnected: true);
        if (query.descriptor.offlineMutable) {
          local = _localChanges.stream.listen((type) {
            if (type == query.descriptor.type && latest != null) emit();
          });
        }
        remote = transport
            .watch(query.description)
            .listen(
              (snapshot) {
                emit(received: snapshot, disconnected: false);
                _scheduleSync(Duration.zero);
              },
              onError: (Object error, StackTrace stack) {
                if (error is GroveOffline) {
                  emit(disconnected: true);
                } else {
                  tail = tail.then((_) async {
                    if (cancelled) return;
                    latest = null;
                    hasSnapshot = false;
                    await cache.remove('query:${query.description.key}');
                    if (!cancelled) controller.addError(error, stack);
                  });
                }
              },
              onDone: () {
                unawaited(tail.whenComplete(controller.close));
              },
            );
      },
      onCancel: () async {
        cancelled = true;
        await remote?.cancel();
        await local?.cancel();
      },
    );
    return controller.stream;
  }

  /// Persist a submission for an explicitly offline-enabled entity immediately.
  /// A known ID is edited against its cached or pending state; otherwise this
  /// stages a create. Honeycomb validates and commits it during synchronization.
  Future<T> stage<T>(T entity) => _serialized(() async {
    final descriptor = registry.descriptor<T>();
    if (!descriptor.offlineMutable)
      throw const GroveException(
        'online_required',
        'This entity cannot be staged offline',
      );
    final data = descriptor.encode(entity);
    final id = data['id'] as String;
    final query = _idQuery(descriptor.type, id);
    final cached = await cache.read('query:${query.key}');
    var draft = await cache.read(_draftKey(descriptor.type, id));
    EntityRecord? current = cached == null
        ? null
        : QuerySnapshot.fromJson(cached).records.firstOrNull;
    final pending = await _pending();
    for (final entry in pending) {
      final mutation = EntityMutation.fromJson(entry['mutation'] as Json);
      if (mutation.type != descriptor.type || mutation.id != id) continue;
      draft = entry['draft'] as Json? ?? draft;
      if (mutation.kind == MutationKind.create && current != null) continue;
      current ??= entry['base'] == null
          ? null
          : EntityRecord.fromJson(entry['base'] as Json);
      current = commitMutation(
        registry,
        mutation,
        current,
        current?.revision ?? 0,
      );
    }
    final changes = current == null
        ? <FieldChange>[]
        : changedFields(
            draft ?? descriptor.encode(descriptor.read(current)),
            data,
          );
    if (current != null && changes.isEmpty) {
      if (draft == null)
        await cache.write(_draftKey(descriptor.type, id), data);
      return descriptor.read(current);
    }
    final mutation = EntityMutation(
      mutationId: const Uuid().v4(),
      type: descriptor.type,
      id: id,
      version: descriptor.version,
      kind: current == null ? MutationKind.create : MutationKind.update,
      data: current == null ? data : null,
      changes: changes,
    );
    return descriptor.read(
      await _queue(mutation, current, pending, draft: data),
    );
  });

  String _draftKey(String type, String id) =>
      'draft:${canonicalJson([type, id])}';

  /// Observes other authenticated viewers of this entity while subscribed.
  Stream<List<GrovePresencePeer>> watchPresence<T>(String id) {
    final source = transport;
    if (source is! GrovePresenceTransport) return Stream.value(const []);
    return (source as GrovePresenceTransport).watchPresence(
      registry.descriptor<T>().type,
      id,
    );
  }

  Future<T> create<T>(T entity, {bool allowOffline = true}) async {
    final descriptor = registry.descriptor<T>();
    final data = descriptor.encode(entity);
    final mutation = EntityMutation(
      mutationId: const Uuid().v4(),
      type: descriptor.type,
      id: data['id'] as String,
      version: descriptor.version,
      kind: MutationKind.create,
      data: data,
    );
    return descriptor.read(
      await _mutate(descriptor, mutation, null, allowOffline: allowOffline),
    );
  }

  Future<EntityRecord> _current<T>(String id) async {
    final query = this.query<T>().byId(id);
    // Use the raw record for schema-preserving writes and the pending overlay
    // for repeated offline edits.
    QuerySnapshot snapshot;
    try {
      snapshot = await transport.fetch(query.description);
      await cache.write('query:${query.description.key}', snapshot.toJson());
    } on GroveOffline {
      final cached = await cache.read('query:${query.description.key}');
      snapshot = cached == null
          ? QuerySnapshot([])
          : QuerySnapshot.fromJson(cached);
    }
    EntityRecord? current = snapshot.records
        .where((r) => r.id == id)
        .firstOrNull;
    for (final entry in await _pending()) {
      final mutation = EntityMutation.fromJson(entry['mutation'] as Json);
      if (mutation.type != query.description.type || mutation.id != id)
        continue;
      current ??= entry['base'] == null
          ? null
          : EntityRecord.fromJson(entry['base'] as Json);
      if (mutation.kind == MutationKind.create && current != null) continue;
      current = commitMutation(registry, mutation, current, snapshot.revision);
    }
    if (current == null || current.deleted)
      throw const GroveException('not_found', 'Entity not available');
    return current;
  }

  Future<T> update<T>(
    String id,
    T Function(T current) change, {
    T? basedOn,
    bool allowOffline = true,
  }) async {
    final descriptor = registry.descriptor<T>();
    final current = await _current<T>(id);
    final before = descriptor.encode(basedOn ?? descriptor.read(current));
    if (before['id'] != id) throw ArgumentError('Base entity ID mismatch');
    final after = descriptor.encode(
      change(descriptor.decode(cloneJson(before))),
    );
    final changes = changedFields(before, after);
    if (after['id'] != id) throw ArgumentError('Entity ID is immutable');
    if (changes.isEmpty) return descriptor.read(current);
    final mutation = EntityMutation(
      mutationId: const Uuid().v4(),
      type: descriptor.type,
      id: id,
      version: descriptor.version,
      kind: MutationKind.update,
      changes: changes,
    );
    return descriptor.read(
      await _mutate(descriptor, mutation, current, allowOffline: allowOffline),
    );
  }

  Future<void> delete<T>(String id, {bool allowOffline = true}) async {
    final descriptor = registry.descriptor<T>();
    final current = await _current<T>(id);
    await _mutate(
      descriptor,
      EntityMutation(
        mutationId: const Uuid().v4(),
        type: descriptor.type,
        id: id,
        version: descriptor.version,
        kind: MutationKind.delete,
      ),
      current,
      allowOffline: allowOffline,
    );
  }

  Future<EntityRecord> _mutate<T>(
    EntityDescriptor<T> descriptor,
    EntityMutation mutation,
    EntityRecord? base, {
    required bool allowOffline,
  }) => _serialized(() async {
    final canQueue = allowOffline && descriptor.offlineMutable;
    final pending = await _pending();
    if (pending.isEmpty || !canQueue) {
      try {
        final result = await transport.mutate(mutation);
        await _cacheRecord(result);
        return result;
      } on GroveOffline {
        if (!canQueue) rethrow;
      }
    }
    return _queue(mutation, base, pending);
  });

  Future<EntityRecord> _queue(
    EntityMutation mutation,
    EntityRecord? base,
    List<Json> pending, {
    Json? draft,
  }) async {
    final local = commitMutation(registry, mutation, base, base?.revision ?? 0);
    pending.add({
      'mutation': mutation.toJson(),
      'base': base?.toJson(),
      'draft': ?draft,
    });
    final state = await cache.read('pending') ?? {};
    await cache.write('pending', {...state, 'mutations': pending});
    _localChanges.add(mutation.type);
    _scheduleSync(Duration.zero);
    return local;
  }

  /// Last accepted server commit wins per changed field. Replayed mutation IDs
  /// are idempotent; deletes retain tombstones, so stale edits cannot resurrect.
  Future<void> synchronize() => _serialized(() async {
    if (_closed) return;
    final state = await cache.read('pending') ?? {};
    final pending = (state['mutations'] as List? ?? []).cast<Json>();
    final rejected = (state['rejected'] as List? ?? []).cast<Json>();
    while (pending.isNotEmpty && !_closed) {
      final mutation = EntityMutation.fromJson(
        pending.first['mutation'] as Json,
      );
      try {
        final record = await transport.mutate(mutation);
        await _cacheRecord(record);
        // Keep the user's last submitted draft separate from the server's
        // merged result. Future form edits must not revert unrelated fields.
        if (pending.first['draft'] case final Json draft) {
          await cache.write(_draftKey(record.type, record.id), draft);
        }
      } on GroveOffline {
        return;
      } on GroveRequestTimeout {
        return;
      } on GroveException catch (error) {
        if (!const {
          'conflict',
          'not_found',
          'unsupported_schema',
          'invalid_request',
        }.contains(error.code))
          rethrow;
        rejected.add({...pending.first, 'error': error.toString()});
      }
      pending.removeAt(0);
      _syncError = null;
      await cache.write('pending', {
        'mutations': pending,
        'rejected': rejected,
      });
      _localChanges.add(null);
    }
  });

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _syncTimer?.cancel();
    await _connectionSubscription?.cancel();
    await transport.close();
    await _queueTail;
    await _localChanges.close();
  }
}

/// Submission state distinguishes durable local acceptance from server commit.
class GroveSyncStatus {
  const GroveSyncStatus({
    required this.pending,
    required this.rejected,
    this.error,
  });
  final int pending;
  final int rejected;
  final String? error;
}
