import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:sqlite3/sqlite3.dart';

/// One transaction atomically commits state, tombstones, audit and the durable
/// mutation receipt. Commit order defines field-level last-write-wins order.
class EntityStore {
  EntityStore(this.database, this.registry) {
    database.execute('PRAGMA journal_mode = WAL');
    database.execute('PRAGMA busy_timeout = 5000');
    database.execute('''CREATE TABLE IF NOT EXISTS entities (
      type TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL,
      revision INTEGER NOT NULL, deleted INTEGER NOT NULL, data TEXT NOT NULL,
      PRIMARY KEY (type, id))''');
    database.execute(
      'CREATE INDEX IF NOT EXISTS entities_type_live ON entities(type, deleted, revision)',
    );
    database.execute('''CREATE TABLE IF NOT EXISTS mutations (
      revision INTEGER PRIMARY KEY AUTOINCREMENT, mutation_id TEXT NOT NULL UNIQUE,
      actor TEXT NOT NULL, timestamp TEXT NOT NULL, mutation TEXT NOT NULL,
      result TEXT NOT NULL)''');
    database.execute('''CREATE TABLE IF NOT EXISTS external_revision (
      id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL)''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS external_records (
        type TEXT NOT NULL, id TEXT NOT NULL, source TEXT,
        PRIMARY KEY (type, id))
    ''');
    database.execute(
      'CREATE INDEX IF NOT EXISTS external_records_source ON external_records(source)',
    );
    database.execute('''
      CREATE TABLE IF NOT EXISTS match_teams (
        type TEXT NOT NULL, id TEXT NOT NULL, team TEXT NOT NULL,
        PRIMARY KEY (type, team, id))
    ''');
    database.execute(
      'CREATE INDEX IF NOT EXISTS match_teams_record ON match_teams(type, id)',
    );
    for (final field in _indexedFields) {
      database.execute('''
        CREATE INDEX IF NOT EXISTS entities_by_$field
        ON entities(type, json_extract(data, '\$.$field'))
        WHERE deleted = 0 AND version = 1
          AND json_extract(data, '\$.$field') IS NOT NULL
      ''');
    }
    database.execute('''
      CREATE INDEX IF NOT EXISTS entities_other_versions ON entities(type, version)
      WHERE deleted = 0 AND version <> 1
    ''');
  }
  static const _indexedFields = {'event', 'season', 'team', 'district'};

  final Database database;
  final EntityRegistry registry;
  final _changes = StreamController<String>.broadcast(sync: true);
  Stream<String> get changes => _changes.stream;
  final _externalChanges = StreamController<ExternalDatasetChange>.broadcast(
    sync: true,
  );
  Stream<ExternalDatasetChange> get externalChanges => _externalChanges.stream;

  int get revision =>
      database.select(
            '''SELECT MAX(
                  COALESCE((SELECT MAX(revision) FROM mutations), 0),
                  COALESCE((SELECT revision FROM external_revision WHERE id = 1), 0)
                ) AS value''',
          ).single['value']
          as int;
  EntityRecord _record(Row row) => EntityRecord(
    type: row['type'] as String,
    id: row['id'] as String,
    version: row['version'] as int,
    revision: row['revision'] as int,
    deleted: row['deleted'] == 1,
    data: jsonDecode(row['data'] as String) as Json,
  );
  EntityRecord? get(String type, String id) {
    final rows = database.select(
      'SELECT * FROM entities WHERE type = ? AND id = ?',
      [type, id],
    );
    return rows.isEmpty ? null : _record(rows.single);
  }

  /// Evaluates a typed query against live rows, using the primary key for IDs.
  QuerySnapshot query(QueryDescription query) {
    final id = query.filters
        .where(
          (filter) =>
              filter.field == 'id' &&
              filter.operator == FilterOperator.equal &&
              filter.value is String,
        )
        .firstOrNull
        ?.value;
    final rows = switch (id) {
      String() => database.select(
        'SELECT * FROM entities WHERE type = ? AND id = ? AND deleted = 0',
        [query.type, id],
      ),
      _
          when registry.isServerManaged(query.type) &&
              registry.named(query.type).version == 1 &&
              query.schemaVersion == 1 =>
        _queryServerManaged(query),
      _ => database.select(
        'SELECT * FROM entities WHERE type = ? AND deleted = 0',
        [query.type],
      ),
    };
    return schemaQuery(registry, query, rows.map(_record), revision);
  }

  Iterable<Row> _queryServerManaged(QueryDescription query) sync* {
    const live = "type = ? AND deleted = 0";
    final clauses = <String>[live, 'version = 1'];
    final args = <Object?>[query.type];
    for (final filter in query.filters) {
      final field = filter.field;
      final value = filter.value;
      if (filter.operator == FilterOperator.equal &&
          _indexedFields.contains(field) &&
          (value is String || value is int)) {
        clauses.add("json_extract(data, '\$.$field') = ?");
        args.add(value);
      } else if (query.type == competitionMatchEntity.type &&
          field == 'teams' &&
          filter.operator == FilterOperator.contains &&
          value is String) {
        clauses.add(
          'id IN (SELECT id FROM match_teams WHERE type = ? AND team = ?)',
        );
        args.addAll([query.type, value]);
      }
    }
    yield* database.select(
      'SELECT * FROM entities WHERE ${clauses.join(' AND ')}',
      args,
    );
    yield* database.select(
      'SELECT * FROM entities WHERE $live AND version <> 1',
      [query.type],
    );
  }

  /// Replace source-owned rows and refresh shared team profiles in one
  /// transaction with discovery and the upstream checkpoint.
  void replaceExternalDataset(
    String dataset,
    List<EntityRecord> records, {
    required void Function() checkpoint,
  }) {
    final changes = <EntityRecord>[];
    database.execute('BEGIN IMMEDIATE');
    try {
      final nextRevision = revision + 1;
      final previous = {
        for (final row in database.select(
          'SELECT type,id FROM external_records WHERE source = ?',
          [dataset],
        ))
          (row['type'] as String, row['id'] as String),
      };
      for (final record in records) {
        final type = record.type;
        final id = record.id;
        previous.remove((type, id));
        final source = type == competitionTeamEntity.type ? null : dataset;
        final old = get(type, id);
        final data = canonicalJson(record.data);
        if (old != null &&
            old.version == record.version &&
            !old.deleted &&
            canonicalJson(old.data) == data) {
          continue;
        }
        database.execute(
          '''
          INSERT INTO entities (type,id,version,revision,deleted,data)
          VALUES (?,?,?,?,0,?)
          ON CONFLICT(type,id) DO UPDATE SET version=excluded.version,
            revision=excluded.revision,deleted=0,data=excluded.data
          ''',
          [type, id, record.version, nextRevision, data],
        );
        database.execute(
          'REPLACE INTO external_records (type,id,source) VALUES (?,?,?)',
          [type, id, source],
        );
        if (old != null && !old.deleted) changes.add(old);
        changes.add(record);
        if (type == competitionMatchEntity.type) {
          _removeMatchTeams(type, id);
          for (final team
              in (record.data['teams'] as List).cast<String>().toSet()) {
            database.execute(
              'INSERT INTO match_teams (type,id,team) VALUES (?,?,?)',
              [
                type,
                id,
                team,
              ],
            );
          }
        }
      }
      for (final (type, id) in previous) {
        final old = get(type, id);
        if (old != null) changes.add(old);
        _removeMatchTeams(type, id);
        database.execute(
          'DELETE FROM external_records WHERE type = ? AND id = ?',
          [
            type,
            id,
          ],
        );
        database.execute('DELETE FROM entities WHERE type = ? AND id = ?', [
          type,
          id,
        ]);
      }
      if (changes.isNotEmpty) {
        database.execute(
          'REPLACE INTO external_revision (id,revision) VALUES (1,?)',
          [nextRevision],
        );
      }
      checkpoint();
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    if (changes.isNotEmpty)
      _externalChanges.add(ExternalDatasetChange(dataset, changes));
  }

  void _removeMatchTeams(String type, String id) => database.execute(
    'DELETE FROM match_teams WHERE type = ? AND id = ?',
    [type, id],
  );

  /// Returns a previous receipt before a retry calls an upstream service.
  EntityRecord? mutationReceipt(EntityMutation mutation, String actor) {
    final receipt = database.select(
      'SELECT actor, mutation, result FROM mutations WHERE mutation_id = ?',
      [mutation.mutationId],
    );
    if (receipt.isEmpty) return null;
    final row = receipt.single;
    if (row['actor'] != actor ||
        canonicalJson(jsonDecode(row['mutation'] as String)) !=
            canonicalJson(mutation.toJson())) {
      throw const GroveException(
        'conflict',
        'Mutation ID reused with different actor or contents',
      );
    }
    return EntityRecord.fromJson(
      jsonDecode(row['result'] as String) as Json,
    );
  }

  EntityRecord mutate(
    EntityMutation mutation,
    String actor, {
    void Function()? authorize,
    void Function()? writeRelatedRows,
    List<FieldChange>? confirmedChanges,
  }) {
    database.execute('BEGIN IMMEDIATE');
    EntityRecord result;
    var committed = false;
    try {
      // Authorization is evaluated inside the same transaction as the write.
      authorize?.call();
      final receipt = mutationReceipt(mutation, actor);
      if (receipt != null) {
        result = receipt;
      } else {
        committed = true;
        result = commitMutation(
          registry,
          confirmedChanges == null
              ? mutation
              : EntityMutation(
                  mutationId: mutation.mutationId,
                  type: mutation.type,
                  id: mutation.id,
                  version: mutation.version,
                  kind: mutation.kind,
                  data: mutation.data,
                  changes: confirmedChanges,
                ),
          get(mutation.type, mutation.id),
          revision + 1,
        );
        database.execute(
          'INSERT INTO mutations (revision,mutation_id,actor,timestamp,mutation,result) VALUES (?,?,?,?,?,?)',
          [
            result.revision,
            mutation.mutationId,
            actor,
            DateTime.now().toUtc().toIso8601String(),
            jsonEncode(mutation.toJson()),
            jsonEncode(result.toJson()),
          ],
        );
        database.execute(
          '''INSERT INTO entities (type,id,version,revision,deleted,data) VALUES (?,?,?,?,?,?)
          ON CONFLICT(type,id) DO UPDATE SET version=excluded.version, revision=excluded.revision,
          deleted=excluded.deleted,data=excluded.data''',
          [
            result.type,
            result.id,
            result.version,
            result.revision,
            result.deleted ? 1 : 0,
            jsonEncode(result.data),
          ],
        );
      }
      if (committed) writeRelatedRows?.call();
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    if (committed) _changes.add(result.type);
    return result;
  }

  List<Json> history(String type, String id) => database
      .select(
        "SELECT actor,timestamp,mutation,revision FROM mutations WHERE json_extract(mutation,'\$.type') = ? AND json_extract(mutation,'\$.id') = ? ORDER BY revision",
        [type, id],
      )
      .map(
        (row) => {
          'actor': row['actor'],
          'timestamp': row['timestamp'],
          'revision': row['revision'],
          'mutation': jsonDecode(row['mutation'] as String),
        },
      )
      .toList();
  Future<void> close() async {
    await _changes.close();
    await _externalChanges.close();
    database.close();
  }
}

class ExternalDatasetChange {
  ExternalDatasetChange(this.dataset, List<EntityRecord> records) {
    for (final record in records) {
      (_byType[record.type] ??= []).add(record);
    }
  }

  final String dataset;
  final _byType = <String, List<EntityRecord>>{};
  Set<String> get ids => {
    for (final records in _byType.values)
      for (final record in records) record.id,
  };

  bool affects(QueryDescription query) {
    final records = _byType[query.type];
    if (records == null) return false;
    return evaluateQuery(query, records).isNotEmpty;
  }
}
