import 'client.dart';
import 'entity.dart';
import 'transport.dart';

enum FilterOperator { equal, greaterThan, lessThan, contains }

class EntityField<T, V> {
  const EntityField(this.path);
  final String path;
  TypedQueryFilter<T> equals(V value) =>
      TypedQueryFilter<T>(path, FilterOperator.equal, _queryValue(value));
  TypedQueryFilter<T> greaterThan(V value) =>
      TypedQueryFilter<T>(path, FilterOperator.greaterThan, value);
  TypedQueryFilter<T> lessThan(V value) =>
      TypedQueryFilter<T>(path, FilterOperator.lessThan, value);
}

class TypedQueryFilter<T> extends QueryFilter {
  const TypedQueryFilter(super.field, super.operator, super.value);
}

extension IterableEntityField<T, V> on EntityField<T, List<V>> {
  TypedQueryFilter<T> contains(V value) =>
      TypedQueryFilter<T>(path, FilterOperator.contains, _queryValue(value));
}

Object? _queryValue(Object? value) => value is EntityRef ? value.id : value;

class QueryFilter {
  const QueryFilter(this.field, this.operator, this.value);
  final String field;
  final FilterOperator operator;
  final Object? value;
  Json toJson() => {'field': field, 'operator': operator.name, 'value': value};
  factory QueryFilter.fromJson(Json json) => QueryFilter(
    json['field'] as String,
    FilterOperator.values.byName(json['operator'] as String),
    json['value'],
  );
}

class QueryOrder {
  const QueryOrder(this.field, {this.descending = false});
  final String field;
  final bool descending;
  Json toJson() => {'field': field, 'descending': descending};
}

class QueryDescription {
  QueryDescription({
    required this.type,
    this.schemaVersion,
    List<QueryFilter> filters = const [],
    List<QueryOrder> order = const [],
    this.limit,
  }) : filters = List.unmodifiable(filters),
       order = List.unmodifiable(order) {
    if (schemaVersion != null && schemaVersion! < 1) {
      throw ArgumentError('Query schema version must be positive');
    }
    if (limit != null && (limit! < 1 || limit! > 100000)) {
      throw ArgumentError('Query limit must be between 1 and 100000');
    }
    if (filters.length > 32 || order.length > 8)
      throw ArgumentError('Query too complex');
  }
  final String type;
  final int? schemaVersion;
  final List<QueryFilter> filters;
  final List<QueryOrder> order;
  final int? limit;
  Json toJson() => {
    'type': type,
    if (schemaVersion != null) 'schemaVersion': schemaVersion,
    'filters': filters.map((f) => f.toJson()).toList(),
    'order': order.map((o) => o.toJson()).toList(),
    'limit': limit,
  };
  factory QueryDescription.fromJson(Json json) => QueryDescription(
    type: json['type'] as String,
    schemaVersion: json['schemaVersion'] as int?,
    filters: (json['filters'] as List)
        .map((f) => QueryFilter.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList(),
    order: (json['order'] as List)
        .map(
          (o) => QueryOrder(
            o['field'] as String,
            descending: o['descending'] as bool,
          ),
        )
        .toList(),
    limit: json['limit'] as int?,
  );
  String get key => canonicalJson(toJson());
}

class GroveQuery<T> {
  GroveQuery(this.grove, this.descriptor, this.description);
  final Grove grove;
  final EntityDescriptor<T> descriptor;
  final QueryDescription description;

  GroveQuery<T> where(TypedQueryFilter<T> filter) => GroveQuery(
    grove,
    descriptor,
    QueryDescription(
      type: description.type,
      schemaVersion: description.schemaVersion,
      filters: [...description.filters, filter],
      order: description.order,
      limit: description.limit,
    ),
  );
  GroveQuery<T> byId(String id) =>
      where(EntityField<T, String>('id').equals(id));
  GroveQuery<T> orderBy<V>(
    EntityField<T, V> field, {
    bool descending = false,
  }) => GroveQuery(
    grove,
    descriptor,
    QueryDescription(
      type: description.type,
      schemaVersion: description.schemaVersion,
      filters: description.filters,
      order: [
        ...description.order,
        QueryOrder(field.path, descending: descending),
      ],
      limit: description.limit,
    ),
  );
  GroveQuery<T> limit(int count) => GroveQuery(
    grove,
    descriptor,
    QueryDescription(
      type: description.type,
      schemaVersion: description.schemaVersion,
      filters: description.filters,
      order: description.order,
      limit: count,
    ),
  );
  Future<QueryResult<T>> result() => grove.fetch(this);
  Future<List<T>> many() async => (await result()).requireComplete().items;
  Future<T?> oneOrNull() async {
    final items = await many();
    if (items.length > 1)
      throw StateError('Expected at most one entity, found ${items.length}');
    return items.isEmpty ? null : items.single;
  }

  Future<T> one() async {
    final item = await oneOrNull();
    if (item == null) throw StateError('Expected one entity, found none');
    return item;
  }

  @override
  bool operator ==(Object other) =>
      other is GroveQuery<T> &&
      identical(grove, other.grove) &&
      description.key == other.description.key;
  @override
  int get hashCode => Object.hash(grove, description.key, T);
}

class QueryResult<T> {
  QueryResult(
    Iterable<T> items, {
    this.complete = true,
    this.offline = false,
    this.hasSnapshot = true,
    this.unsupported = const [],
    this.revision = 0,
  }) : items = List.unmodifiable(items);
  final List<T> items;
  final bool complete;
  final bool offline;

  /// Whether a server snapshot is available, including a cached empty result.
  final bool hasSnapshot;
  final List<EntityRecord> unsupported;
  final int revision;
  bool get updateRequired => unsupported.isNotEmpty;

  QueryResult<R> map<R>(R Function(T) transform) => QueryResult(
    items.map(transform),
    complete: complete,
    offline: offline,
    hasSnapshot: hasSnapshot,
    unsupported: unsupported,
    revision: revision,
  );

  QueryResult<T> requireAvailable() {
    if (updateRequired) return requireComplete();
    if (!hasSnapshot && items.isEmpty) throw const GroveOffline();
    return this;
  }

  QueryResult<T> requireComplete() {
    if (!complete)
      throw IncompleteQuery(updateRequired: updateRequired, offline: offline);
    return this;
  }
}

class IncompleteQuery implements Exception {
  const IncompleteQuery({required this.updateRequired, required this.offline});
  final bool updateRequired;
  final bool offline;
  @override
  String toString() =>
      'Incomplete Grove query (offline: $offline, update required: $updateRequired)';
}

Object? fieldValue(Json data, String path) {
  Object? current = data;
  for (final segment in path.split('.')) {
    if (current is! Map) return null;
    current = current[segment];
  }
  return current;
}

int compareValues(Object? a, Object? b) {
  if (a == b) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  return canonicalJson(a).compareTo(canonicalJson(b));
}

List<EntityRecord> evaluateQuery(
  QueryDescription query,
  Iterable<EntityRecord> records,
) {
  final result = records
      .where(
        (r) =>
            !r.deleted &&
            r.type == query.type &&
            query.filters.every((f) {
              final value = fieldValue(r.data, f.field);
              return switch (f.operator) {
                FilterOperator.equal =>
                  canonicalJson(value) == canonicalJson(f.value),
                FilterOperator.greaterThan =>
                  value != null && compareValues(value, f.value) > 0,
                FilterOperator.lessThan =>
                  value != null && compareValues(value, f.value) < 0,
                FilterOperator.contains =>
                  value is List &&
                      value.any(
                        (v) => canonicalJson(v) == canonicalJson(f.value),
                      ),
              };
            }),
      )
      .toList();
  result.sort((a, b) {
    for (final order in query.order) {
      final value = compareValues(
        fieldValue(a.data, order.field),
        fieldValue(b.data, order.field),
      );
      if (value != 0) return order.descending ? -value : value;
    }
    return a.id.compareTo(b.id);
  });
  return query.limit == null ? result : result.take(query.limit!).toList();
}
