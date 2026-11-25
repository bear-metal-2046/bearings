import 'dart:async';
import 'dart:io';

import 'package:bearimetric/data/scouting_store.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:hive_ce/hive.dart';

class _TabletTransport implements GroveConnectionTransport {
  _TabletTransport(this.server);

  final MemoryGroveTransport server;
  final _connection = StreamController<GroveConnectionState>.broadcast();
  bool online = false;
  Completer<void>? pause;
  bool loseAcknowledgement = false;
  final attempted = <EntityMutation>[];

  @override
  GroveConnectionState get connectionState => online
      ? GroveConnectionState.connected
      : GroveConnectionState.disconnected;

  void setOnline(bool value) {
    online = value;
    _connection.add(connectionState);
  }

  @override
  Stream<GroveConnectionState> watchConnection() => _connection.stream;
  @override
  Future<void> connect() async => setOnline(true);
  @override
  void checkConnection() {}

  @override
  Future<QuerySnapshot> fetch(QueryDescription query) => server.fetch(query);

  @override
  Stream<QuerySnapshot> watch(QueryDescription query) => server.watch(query);

  @override
  Future<EntityRecord> mutate(EntityMutation mutation) async {
    if (!online) throw const GroveOffline();
    attempted.add(mutation);
    await pause?.future;
    final answers = mutation.data?['answers'] as Json?;
    if (answers?['count'] == -1) {
      throw const GroveException('invalid_request', 'Invalid count');
    }
    final result = await server.mutate(mutation);
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw const GroveRequestTimeout();
    }
    return result;
  }

  @override
  Future<void> close() => _connection.close();
}

Future<void> eventually(
  String description,
  FutureOr<bool> Function() predicate,
) async {
  final limit = DateTime.now().add(const Duration(seconds: 9));
  while (!await predicate()) {
    if (DateTime.now().isAfter(limit)) fail(description);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'restarts offline, coalesces edits, and keeps local writes independent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bearimetric-store',
      );
      final hive = Hive;
      hive.init(directory.path);
      var box = await hive.openBox<String>(scoutingBoxName);
      final registry = bearingsEntityRegistry();
      final server = MemoryGroveTransport(registry);
      final transport = _TabletTransport(server);
      final grove = Grove(registry: registry, transport: transport);
      ScoutingStore open() => ScoutingStore(
        grove,
        box: box,
        endpoint: 'https://test',
        subject: Future.value('tablet'),
      );
      var store = open();

      Future<void> save(String match, int count, {bool complete = true}) {
        final answers = {'count': count};
        return store.save(
          match,
          subject: {
            'event': 'event',
            'match': match,
            'gamePack': 'pack',
            'station': 0,
            'form': 'match',
          },
          answers: answers,
          training: false,
          working: answers,
          defaults: const {'count': 0},
          ready: complete ? answers : null,
        );
      }

      try {
        await save('one', 1);
        await save('one', 2);
        await save('one', 3);
        await save('draft', 4, complete: false);
        expect(await grove.pendingMutationCount, 0);

        store.close();
        await box.close();
        box = await hive.openBox<String>(scoutingBoxName);
        store = open();
        expect((await store.read('draft'))?['answers'], {'count': 4});
        expect(isScoutingDraft((await store.read('draft'))!), isTrue);
        final beforeReconnect = (await store.read('one'))!;
        expect(beforeReconnect['flight'], isNull);

        transport.pause = Completer<void>();
        transport.setOnline(true);
        await eventually(
          'The first upload did not start',
          () => transport.attempted.length == 1,
        );
        final first = transport.attempted.single;
        expect(first.data?['answers'], {'count': 3});
        expect(first.data?['capturedAt'], beforeReconnect['approvedAt']);

        // These operations must finish even while Grove awaits the first reply.
        await save('one', 5).timeout(const Duration(seconds: 1));
        await save('bad', -1).timeout(const Duration(seconds: 1));
        await save('other', 8).timeout(const Duration(seconds: 1));
        transport.loseAcknowledgement = true;
        transport.pause!.complete();
        transport.pause = null;
        await grove.synchronize();

        await eventually(
          'The unrelated upload was not confirmed',
          () async => (await store.read('other'))?['head'] != null,
        );
        await eventually(
          'The in-flight edit did not become a revision',
          () async =>
              (await store.read('one'))?['confirmedAnswers']?['count'] == 5,
        );
        expect((await store.read('bad'))?['error'], contains('Invalid count'));
        expect((await store.read('bad'))?['answers'], {'count': -1});
        expect(isScoutingDraft((await store.read('draft'))!), isTrue);

        final uploads = transport.attempted
            .where((item) => item.data?['match'] == 'one')
            .toList();
        expect(uploads, hasLength(3));
        expect(uploads[1].mutationId, first.mutationId);
        expect(uploads[1].data, first.data);
        expect(uploads.last.data?['supersedes'], first.id);
        expect(uploads.last.data?['answers'], {'count': 5});
        expect(await grove.pendingMutationCount, 0);
        final confirmedHead = uploads.last.id;
        transport.setOnline(false);
        await save('one', 6);
        await save('one', 7);
        await save('one', 8);
        expect(await grove.pendingMutationCount, 0);
        transport.setOnline(true);
        await eventually(
          'The offline revision was not confirmed after reconnect',
          () async =>
              (await store.read('one'))?['confirmedAnswers']?['count'] == 8,
        );
        final latest = transport.attempted.last;
        expect(latest.data?['supersedes'], confirmedHead);
        expect(
          transport.attempted.where((item) => item.data?['match'] == 'one'),
          hasLength(4),
        );
      } finally {
        if (transport.pause case final pause?) pause.complete();
        store.close();
        await grove.close();
        await server.close();
        await box.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
