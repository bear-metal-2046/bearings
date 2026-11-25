import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:hive_ce/hive.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:uuid/uuid.dart';

const scoutingBoxName = 'bearimetric_matches';

final scoutingStoreProvider = Provider<ScoutingStore>((ref) {
  final store = ScoutingStore(
    ref.watch(bearingsGroveProvider),
    box: Hive.box<String>(scoutingBoxName),
    endpoint: ref.watch(honeycombEndpointPreferenceProvider).baseUrl,
    subject: ref.watch(groveSubjectProvider.future),
  );
  ref.onDispose(store.close);
  return store;
});

final scoutingRecordsProvider = StreamProvider.autoDispose<List<Json>>((ref) {
  final store = ref.watch(scoutingStoreProvider);
  return Stream<void>.multi((controller) {
    final subscription = store.changes.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
    controller.add(null);
  }).asyncMap((_) => store.records());
});

String scoutingRecordKey({
  required bool training,
  required String pack,
  required String form,
  required String match,
  required int station,
  required String? team,
  required String? scout,
}) =>
    'gamepack:draft:${canonicalJson([if (training) 'training', pack, form, match, station, team, ?scout])}';

/// Bearimetric owns working answers. Only immutable, eligible uploads enter Grove.
class ScoutingStore {
  ScoutingStore(
    this.grove, {
    required this.box,
    required String endpoint,
    required Future<String?> subject,
  }) {
    _subjectId = subject;
    _scope = subject.then((id) {
      if (id == null) throw StateError('Tablet identity is unavailable');
      return '${const Uuid().v5(Namespace.url.value, jsonEncode([endpoint, id]))}:';
    });
    final transport = grove.transport;
    if (transport is GroveConnectionTransport) {
      _connection = transport.watchConnection().listen((_) => _wake());
    }
    _sync = grove.watchSyncStatus().listen(
      (_) => _wake(),
      onError: (Object _) {},
    );
    _wake();
  }

  final Grove grove;
  final Box<String>? box;
  final _memory = <String, String>{};
  late final Future<String> _scope;
  late final Future<String?> _subjectId;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  StreamSubscription<GroveConnectionState>? _connection;
  late final StreamSubscription<GroveSyncStatus> _sync;
  Future<void> _writes = Future.value();
  bool _closed = false;
  bool _draining = false;
  bool _wakeAgain = false;

  bool get _online {
    final transport = grove.transport;
    return transport is! GroveConnectionTransport ||
        transport.connectionState == GroveConnectionState.connected;
  }

  Future<String> _storageKey(String key) async =>
      '${await _scope}${const Uuid().v5(Namespace.url.value, key)}';

  Future<Json?> read(String key) async {
    final scoped = await _storageKey(key);
    final value = box?.get(scoped) ?? _memory[scoped];
    return value == null ? null : jsonDecode(value) as Json;
  }

  Future<List<Json>> records() async {
    final scope = await _scope;
    final keys = (box?.keys ?? _memory.keys)
        .whereType<String>()
        .where((key) => key.startsWith(scope))
        .toList();
    return [
      for (final key in keys)
        if ((box?.get(key) ?? _memory[key]) case final value?)
          jsonDecode(value) as Json,
    ];
  }

  Future<void> update(String key, Json Function(Json?) change) {
    if (_closed) {
      return Future.error(StateError('The tablet storage session ended'));
    }
    final result = _writes.then((_) async {
      final scoped = await _storageKey(key);
      final next = jsonEncode(change(await read(key)));
      if (box case final target?) {
        await target.put(scoped, next);
      } else {
        _memory[scoped] = next;
      }
      if (!_closed) _changes.add(null);
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> save(
    String key, {
    required Json subject,
    required Json answers,
    required bool training,
    required Json working,
    required Json defaults,
    Json? ready,
    Json? initial,
  }) async {
    await update(key, (current) {
      final approved = ready ?? current?['approved'] ?? initial?['approved'];
      final eligible = canonicalJson(approved) == canonicalJson(working)
          ? approved
          : null;
      return {
        ...?initial,
        ...?current,
        'key': key,
        'subject': subject,
        'answers': answers,
        'working': working,
        'defaults': defaults,
        'training': training,
        'approved': approved,
        if (ready != null &&
            (current?['approvedAt'] == null ||
                canonicalJson(ready) != canonicalJson(current?['approved'])))
          'approvedAt': DateTime.now().toUtc().toIso8601String(),
        'ready': eligible,
        if (ready != null &&
            canonicalJson(ready) != canonicalJson(current?['rejectedAnswers']))
          'error': null,
        if (training && ready != null) 'confirmedAnswers': ready,
      };
    });
    if (_online) _wake();
  }

  Future<void> retry(String key) async {
    await update(
      key,
      (current) => {...current!, 'error': null, 'rejectedAnswers': null},
    );
    _wake();
  }

  void _wake() {
    if (_closed) return;
    if (_draining) {
      _wakeAgain = true;
      return;
    }
    _draining = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      do {
        _wakeAgain = false;
        for (final row in await records()) {
          if (_closed) return;
          if (row['training'] == true) continue;
          try {
            await _deliver(row);
          } catch (error) {
            if (_closed) return;
            final key = row['key'] as String;
            await update(
              key,
              (current) => {...current!, 'error': error.toString()},
            );
          }
        }
      } while (_wakeAgain && !_closed);
    } catch (_) {
      // A storage or identity failure is surfaced when the scout tries to save.
    } finally {
      _draining = false;
    }
  }

  Future<void> _deliver(Json row) async {
    final key = row['key'] as String;
    var flight = row['flight'] as Json?;
    if (flight != null) {
      final outcome = await grove.createDelivery<GamePackObservation>(
        flight['id'] as String,
      );
      if (outcome.confirmed || outcome.error != null) {
        await update(
          key,
          (current) => {
            ...current!,
            'flight': null,
            'error': outcome.confirmed ? null : outcome.error,
            'rejectedAnswers': outcome.confirmed ? null : flight!['answers'],
            if (outcome.error != null && !outcome.confirmed)
              'rejectedIds': [
                ...?current['rejectedIds'] as List?,
                flight!['id'],
              ],
            if (outcome.confirmed) ...{
              'head': flight!['id'],
              'confirmedAnswers': flight!['answers'],
            },
          },
        );
        _wakeAgain = true;
        return;
      }
      if (outcome.queued || !_online || _closed) return;
    } else {
      if (!_online || _closed || !_hasWork(row)) return;
      if (row['legacySave'] == true && row['head'] == null) {
        if (row['error'] != null) return;
        final previous = await _findLegacyParent(row);
        await update(
          key,
          (current) => {...current!, 'head': previous, 'legacySave': false},
        );
        _wakeAgain = true;
        return;
      }
      // Persist the exact payload before any handoff. Re-read within the write
      // queue so an edit racing this scan cannot freeze a stale snapshot.
      await update(key, (current) {
        final latest = current!;
        if (!_hasWork(latest)) return latest;
        final parent = latest['head'] as String?;
        if (latest['legacySave'] == true && parent == null) return latest;
        flight = {
          ...latest['subject'] as Json,
          'id': const Uuid().v4(),
          'capturedAt':
              latest['approvedAt'] ?? DateTime.now().toUtc().toIso8601String(),
          'answers': latest['ready'],
          'supersedes': parent,
          'reason': parent == null ? null : 'Updated by the scout',
        };
        return {...latest, 'flight': flight, 'error': null};
      });
    }
    if (flight != null && !_closed && _online) {
      await grove.stageCreate(gamePackObservationEntity.decode(flight!));
    }
  }

  Future<String> _findLegacyParent(Json row) async {
    final author = await _subjectId;
    final subject = row['subject'] as Json;
    final match = subject['match'] as String;
    final scout = subject['scout'] as String?;
    final team = subject['team'] as String?;
    final rows = await grove
        .query<GamePackObservation>()
        .where(GamePackObservationFields.author.equals(author))
        .where(GamePackObservationFields.match.equals(EntityRef(match)))
        .where(
          GamePackObservationFields.station.equals(subject['station'] as int),
        )
        .where(
          GamePackObservationFields.scout.equals(
            scout == null ? null : EntityRef(scout),
          ),
        )
        .where(
          GamePackObservationFields.team.equals(
            team == null ? null : EntityRef(team),
          ),
        )
        .where(
          GamePackObservationFields.gamePack.equals(
            EntityRef(subject['gamePack'] as String),
          ),
        )
        .where(GamePackObservationFields.form.equals(subject['form'] as String))
        .many();
    final matches = activeGamePackObservations(rows)
        .where(
          (record) =>
              canonicalJson(record.answers) ==
              canonicalJson(row['confirmedAnswers']),
        )
        .toList();
    if (matches.length == 1) return matches.single.id;
    throw StateError('Could not identify the original observation.');
  }

  bool _hasWork(Json row) {
    final ready = row['ready'];
    return ready != null &&
        canonicalJson(ready) !=
            canonicalJson(row['confirmedAnswers'] ?? row['defaults']) &&
        canonicalJson(ready) != canonicalJson(row['rejectedAnswers']);
  }

  void close() {
    _closed = true;
    unawaited(_connection?.cancel());
    unawaited(_sync.cancel());
    unawaited(_changes.close());
  }
}

bool isScoutingDraft(Json row) =>
    row['ready'] == null &&
    canonicalJson(row['working']) !=
        canonicalJson(
          row['approved'] ?? row['confirmedAnswers'] ?? row['defaults'],
        );

String scoutingUploadLabel(Json row) {
  if (row['error'] != null) return 'Needs attention';
  if (row['training'] == true) {
    return isScoutingDraft(row) ? 'Draft' : 'On device';
  }
  if (isScoutingDraft(row)) return 'Draft';
  if (row['flight'] != null) return 'Queued';
  if (row['ready'] != null &&
      canonicalJson(row['ready']) !=
          canonicalJson(row['confirmedAnswers'] ?? row['defaults'])) {
    return 'Queued';
  }
  return row['head'] != null ? 'Synced' : 'On device';
}

class ScoutingUploadTarget {
  ScoutingUploadTarget(Json row)
    : event = (row['subject'] as Json)['event'] as String,
      match = (row['subject'] as Json)['match'] as String,
      station = (row['subject'] as Json)['station'] as int,
      scout = (row['subject'] as Json)['scout'] as String?;

  final String event;
  final String match;
  final int station;
  final String? scout;
}
