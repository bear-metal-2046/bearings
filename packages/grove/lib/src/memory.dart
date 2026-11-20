import 'dart:async';

import 'entity.dart';
import 'query.dart';
import 'transport.dart';

/// In-memory authoritative service for tests and pure Dart consumers.
class MemoryGroveTransport implements GroveTransport {
  MemoryGroveTransport(this.registry);
  final EntityRegistry registry;
  final records = <String, EntityRecord>{};
  final _receipts = <String, EntityRecord>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  int _revision = 0;
  String _key(String type, String id) => '$type/$id';
  @override
  Future<QuerySnapshot> fetch(QueryDescription query) async =>
      schemaQuery(registry, query, records.values, _revision);
  @override
  Stream<QuerySnapshot> watch(QueryDescription query) {
    late StreamController<QuerySnapshot> controller;
    StreamSubscription<void>? subscription;
    controller = StreamController(
      onListen: () {
        void emit() {
          try {
            controller.add(
              schemaQuery(registry, query, records.values, _revision),
            );
          } catch (error, stack) {
            controller.addError(error, stack);
          }
        }

        subscription = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<EntityRecord> mutate(EntityMutation mutation) async {
    if (_receipts[mutation.mutationId] case final receipt?) return receipt;
    final key = _key(mutation.type, mutation.id);
    final record = commitMutation(
      registry,
      mutation,
      records[key],
      _revision + 1,
    );
    _revision++;
    records[key] = record;
    _receipts[mutation.mutationId] = record;
    _changes.add(null);
    return record;
  }

  @override
  Future<void> close() => _changes.close();
}

/// Transform before filtering so predicates and ordering use the latest Dart
/// schema. Return original stored records so reads never cause persistent writes.
QuerySnapshot schemaQuery(
  EntityRegistry registry,
  QueryDescription query,
  Iterable<EntityRecord> source,
  int revision,
) {
  final descriptor = registry.named(query.type);
  final originals = <String, EntityRecord>{};
  final transformed = <EntityRecord>[];
  final unsupported = <EntityRecord>[];
  final requestedId = query.filters
      .where(
        (filter) =>
            filter.field == 'id' && filter.operator == FilterOperator.equal,
      )
      .firstOrNull;
  final supportedVersion = query.schemaVersion ?? descriptor.version;
  for (final record in source.where(
    (r) =>
        r.type == query.type &&
        !r.deleted &&
        (requestedId == null || r.id == requestedId.value),
  )) {
    // Before evaluating a predicate or limit, retain records the requester
    // cannot decode. Otherwise a newer record could be silently hidden.
    if (record.version > supportedVersion) {
      unsupported.add(record);
      continue;
    }
    try {
      final latest = descriptor.latest(record.data, record.version);
      originals[record.id] = record;
      transformed.add(
        EntityRecord(
          type: record.type,
          id: record.id,
          version: descriptor.version,
          data: latest,
          revision: record.revision,
        ),
      );
    } on UnsupportedSchema {
      // An unknown schema may match even when its current representation does
      // not. Conservatively expose incomplete results instead of hiding it.
      unsupported.add(record);
    }
  }
  return QuerySnapshot([
    ...evaluateQuery(query, transformed).map((r) => originals[r.id]!),
    ...unsupported,
  ], revision: revision);
}
