import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:riverpod/riverpod.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

class _PausedAccounts extends AccountService {
  _PausedAccounts(EntityStore store)
    : super(
        store: store,
        issuer: Uri.https('example.invalid'),
        deviceCredentials: null,
      );

  final started = Completer<void>();
  final result = Completer<Json>();

  @override
  Future<Json> run(AuthenticatedActor actor, String action, Json args) {
    started.complete();
    return result.future;
  }
}

ScoutingReport _report(String id, String event) => ScoutingReport(
  id: id,
  timestamp: DateTime.utc(2026, 3, 15),
  data: {
    'meta': {'event': event, 'type': 'match', 'season': 2026},
    'sections': {
      'auto': {'score': 3},
      'teleop': {'score': 4},
    },
  },
);

void main() {
  test(
    'Honeycomb answers heartbeats during a pending account request',
    () async {
      final store = EntityStore(
        sqlite3.openInMemory(),
        bearingsEntityRegistry(),
      );
      addTearDown(store.close);
      final accounts = _PausedAccounts(store);
      final service = EntityService(
        store: store,
        bootstrapSubject: 'administrator',
        accounts: accounts,
        authenticate: (token) async => AuthenticatedActor(
          token,
          expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        ),
      );
      final server = await serve(
        service.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final transport = WebSocketGroveTransport(
        uri: Uri.parse('ws://127.0.0.1:${server.port}'),
        accessToken: () async => 'administrator',
      );
      addTearDown(transport.close);

      await transport.connect();
      final account = transport.account('refreshProfile');
      addTearDown(() {
        if (!accounts.result.isCompleted) accounts.result.complete({});
        return account;
      });
      await accounts.started.future.timeout(const Duration(seconds: 2));

      final previous =
          (await transport.watchConnectionInfo().first).lastReplyAt!;
      final answered = transport.watchConnectionInfo().firstWhere(
        (info) => info.lastReplyAt?.isAfter(previous) == true,
      );
      transport.checkConnection();
      expect(
        (await answered.timeout(const Duration(seconds: 2))).state,
        GroveConnectionState.connected,
      );
      accounts.result.complete({'updated': true});
      expect(await account, {'updated': true});
    },
  );

  test(
    'reconnect drains the local queue and Honeycomb answers heartbeats',
    () async {
      final registry = bearingsEntityRegistry();
      final store = EntityStore(sqlite3.openInMemory(), registry);
      addTearDown(store.close);
      final service = EntityService(
        store: store,
        bootstrapSubject: 'administrator',
        authenticate: (token) async => AuthenticatedActor(
          token,
          expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        ),
      );
      final server = await serve(
        service.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      var reachable = false;
      final transport = WebSocketGroveTransport(
        uri: Uri.parse('ws://127.0.0.1:${server.port}'),
        accessToken: () async {
          if (!reachable) throw const GroveOffline();
          return 'administrator';
        },
        reconnectDelay: const Duration(seconds: 30),
      );
      final grove = Grove(registry: registry, transport: transport);
      addTearDown(grove.close);

      await expectLater(transport.connect(), throwsA(isA<GroveOffline>()));
      await grove.stage(_report('queued-match', 'pnw'));
      expect(await grove.pendingMutationCount, 1);
      final synced = grove.watchSyncStatus().firstWhere(
        (status) => status.pending == 0,
      );
      reachable = true;
      transport.checkConnection();
      await synced.timeout(const Duration(seconds: 2));
      expect(store.get(scoutingReportEntity.type, 'queued-match'), isNotNull);

      final previous =
          (await transport.watchConnectionInfo().first).lastReplyAt!;
      final answered = transport.watchConnectionInfo().firstWhere(
        (info) => info.lastReplyAt?.isAfter(previous) == true,
      );
      transport.checkConnection();
      expect(
        (await answered.timeout(const Duration(seconds: 2))).state,
        GroveConnectionState.connected,
      );
    },
  );

  test(
    'committed Honeycomb changes reach two Grove clients and Riverpod',
    () async {
      final registry = bearingsEntityRegistry();
      final directory = await Directory.systemTemp.createTemp('honeycomb-test');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/test.sqlite';
      final store = EntityStore(sqlite3.open(path), registry);
      addTearDown(store.close);
      final service = EntityService(
        store: store,
        bootstrapSubject: 'administrator',
        authenticate: (token) async {
          if (!['administrator', 'scout'].contains(token)) {
            throw const GroveException('unauthenticated', 'Invalid token');
          }
          return AuthenticatedActor(
            token,
            expiresAt: DateTime.now().add(const Duration(minutes: 10)),
          );
        },
      );
      final server = await serve(
        service.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      Grove connect(String token) {
        final grove = Grove(
          registry: registry,
          transport: WebSocketGroveTransport(
            uri: Uri.parse('ws://127.0.0.1:${server.port}'),
            accessToken: () async => token,
            reconnectDelay: const Duration(milliseconds: 200),
            requestTimeout: const Duration(seconds: 3),
          ),
        );
        addTearDown(grove.close);
        return grove;
      }

      final admin = connect('administrator');
      final scout = connect('scout');
      final bad = connect('invalid');
      await expectLater(
        bad.query<ScoutingReport>().many(),
        throwsA(
          isA<GroveException>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
      expect(
        await (bad.transport as WebSocketGroveTransport)
            .watchConnection()
            .first,
        GroveConnectionState.signInRequired,
      );
      await expectLater(
        scout.query<ScoutingReport>().many(),
        throwsA(
          isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
        ),
      );
      await expectLater(
        scout.create(_report('rejected', 'pnw')),
        throwsA(
          isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
        ),
      );

      await admin.create(
        GroveRole(
          id: 'scout',
          name: 'Scout',
          permissions: ['scouting.report.read', 'scouting.report.mutate'],
        ),
      );
      await admin.update<GroveUser>(
        'scout',
        (user) => user.copyWith(roles: [const EntityRef<GroveRole>('scout')]),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = groveQueryProvider(
        scout.query<ScoutingReport>().where(ScoutingReport.event.equals('pnw')),
      );
      final observed =
          StreamController<AsyncValue<QueryResult<ScoutingReport>>>.broadcast();
      final subscription = container.listen(
        provider,
        (_, next) => observed.add(next),
      );
      addTearDown(() {
        subscription.close();
        unawaited(observed.close());
      });
      await container.read(provider.future);
      final second = StreamIterator(admin.watch(admin.query<ScoutingReport>()));
      addTearDown(second.cancel);
      expect(await second.moveNext(), isTrue);
      expect(second.current.items, isEmpty);

      Future<QueryResult<ScoutingReport>> waitFor(
        bool Function(QueryResult<ScoutingReport>) predicate,
      ) => observed.stream
          .map((value) => value.asData?.value)
          .where((result) => result != null && predicate(result))
          .cast<QueryResult<ScoutingReport>>()
          .first
          .timeout(const Duration(seconds: 4));
      final created = waitFor((result) => result.items.length == 1);
      await admin.create(_report('match-1', 'pnw'));
      expect((await created).items.single.id, 'match-1');
      expect(await second.moveNext(), isTrue);
      expect(second.current.items.single.id, 'match-1');

      final left = waitFor((result) => result.complete && result.items.isEmpty);
      await admin.update<ScoutingReport>(
        'match-1',
        (_) => _report('match-1', 'other'),
      );
      await left;
      final connection = (scout.transport as WebSocketGroveTransport)
          .watchConnection();
      expect(await connection.first, GroveConnectionState.connected);
      final disconnected = connection
          .firstWhere((state) => state == GroveConnectionState.disconnected)
          .timeout(const Duration(seconds: 4));
      final reconnected = connection
          .skipWhile((state) => state != GroveConnectionState.reconnecting)
          .firstWhere((state) => state == GroveConnectionState.connected)
          .timeout(const Duration(seconds: 4));
      final adminReconnected = (admin.transport as WebSocketGroveTransport)
          .watchConnection()
          .skipWhile((state) => state != GroveConnectionState.reconnecting)
          .firstWhere((state) => state == GroveConnectionState.connected)
          .timeout(const Duration(seconds: 4));
      final offline = waitFor((result) => result.offline);
      await service.disconnectClients();
      await disconnected;
      await offline;
      // No client receives this commit. A fresh snapshot recovers it.
      store.mutate(
        EntityMutation(
          mutationId: 'server-write',
          type: 'scouting.report',
          id: 'match-1',
          version: 1,
          kind: MutationKind.update,
          changes: [
            FieldChange(['data', 'meta', 'event'], 'pnw'),
          ],
        ),
        'honeycomb:processing',
      );
      await reconnected;
      final recovered = await waitFor(
        (result) => result.complete && result.items.isNotEmpty,
      );
      expect(recovered.items.single.eventKey, 'pnw');

      // Independent patches from two clients must survive either commit order.
      await adminReconnected;
      await Future.wait([
        scout.update<ScoutingReport>('match-1', (report) {
          final data = cloneJson(report.data);
          data['sections']['auto']['score'] = 10;
          return report.copyWith(data: data);
        }),
        admin.update<ScoutingReport>('match-1', (report) {
          final data = cloneJson(report.data);
          data['sections']['teleop']['score'] = 12;
          return report.copyWith(data: data);
        }),
      ]);
      final saved = await admin.query<ScoutingReport>().byId('match-1').one();
      expect(saved.data['sections']['auto']['score'], 10);
      expect(saved.data['sections']['teleop']['score'], 12);
      expect(
        store
            .history('scouting.report', 'match-1')
            .map((entry) => entry['actor']),
        containsAll(['scout', 'administrator', 'honeycomb:processing']),
      );

      final revoked = observed.stream
          .firstWhere(
            (value) => value.hasError && value.error is GroveException,
          )
          .timeout(const Duration(seconds: 4));
      await admin.update<GroveRole>(
        'scout',
        (role) => role.copyWith(permissions: []),
      );
      expect(
        (await revoked).error,
        isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
      );
      await expectLater(
        scout.delete<ScoutingReport>('match-1'),
        throwsA(isA<GroveException>()),
      );
      await admin.create(
        GroveRole(
          id: 'delegator',
          name: 'Limited delegate',
          permissions: [
            'identity.user.read',
            'identity.user.mutate',
            'authorization.role.read',
            'authorization.role.mutate',
          ],
        ),
      );
      await admin.create(
        GroveRole(
          id: 'privileged',
          name: 'Privileged',
          permissions: ['scouting.report.mutate'],
        ),
      );
      await admin.update<GroveUser>(
        'scout',
        (user) =>
            user.copyWith(roles: [const EntityRef<GroveRole>('delegator')]),
      );
      final forbidden = throwsA(
        isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
      );
      await expectLater(
        scout.create(
          GroveRole(
            id: 'escalated',
            name: 'Escalated',
            permissions: ['scouting.report.mutate'],
          ),
        ),
        forbidden,
      );
      await expectLater(
        scout.update<GroveUser>(
          'scout',
          (user) =>
              user.copyWith(roles: [const EntityRef<GroveRole>('privileged')]),
        ),
        forbidden,
      );
      await admin.delete<ScoutingReport>('match-1');
      expect(
        await admin.query<ScoutingReport>().byId('match-1').oneOrNull(),
        isNull,
      );
      final reopened = EntityStore(sqlite3.open(path), registry);
      try {
        expect(reopened.get('scouting.report', 'match-1')?.deleted, isTrue);
        expect(
          reopened.history('scouting.report', 'match-1').last['actor'],
          'administrator',
        );
      } finally {
        await reopened.close();
      }
    },
  );
}
