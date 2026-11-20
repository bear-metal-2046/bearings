import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Json _status(String event, DateTime time, String matchStatus) => {
  'eventKey': event,
  'dataAsOfTime': time.millisecondsSinceEpoch,
  'nowQueuing': 'Qualification 1',
  'matches': [
    {
      'label': 'Qualification 1',
      'status': matchStatus,
      'redTeams': ['2046', null, '254'],
      'times': {'estimatedStartTime': time.millisecondsSinceEpoch + 60000},
    },
  ],
  'announcements': [
    {'id': 'a1', 'announcement': 'Schedule posted'},
  ],
  'partsRequests': [
    {'id': 'p1', 'parts': 'Motor', 'requestedByTeam': '2046'},
  ],
};

void main() {
  test(
    'authenticated Nexus webhooks publish the latest typed snapshot',
    () async {
      final registry = bearingsEntityRegistry();
      final store = EntityStore(sqlite3.openInMemory(), registry);
      addTearDown(store.close);
      final nexus = NexusSync(store: store, webhookToken: 'test-token');
      addTearDown(nexus.close);
      final service = EntityService(
        store: store,
        nexus: nexus,
        bootstrapSubject: 'admin',
        authenticate: (token) async => AuthenticatedActor(
          token,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );
      final server = await serve(
        (context) => context.request.uri.path == '/api/nexus/webhook'
            ? nexus.receive(context.request)
            : service.handler(context),
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final grove = Grove(
        registry: registry,
        transport: WebSocketGroveTransport(
          uri: Uri.parse('ws://127.0.0.1:${server.port}/grove/ws'),
          accessToken: () async => 'admin',
        ),
      );
      addTearDown(grove.close);
      final query = grove.query<EventStatusSnapshot>().byId('demo1234');
      final updates = StreamIterator(grove.watch(query));
      addTearDown(updates.cancel);
      expect(await updates.moveNext(), isTrue);
      expect(updates.current.items, isEmpty);

      final url = Uri.parse(
        'http://127.0.0.1:${server.port}/api/nexus/webhook',
      );
      Future<int> postBody(String body, {String? token = 'test-token'}) async =>
          (await http.post(
            url,
            headers: {if (token != null) 'Nexus-Token': token},
            body: body,
          )).statusCode;
      Future<int> post(Object? payload, {String? token = 'test-token'}) =>
          postBody(payload == null ? '' : jsonEncode(payload), token: token);
      final now = DateTime.utc(2026, 3, 12);
      final payload = _status('demo1234', now, 'Now queuing');
      expect(await post(payload, token: 'bad-token'), 401);
      expect(await post(payload, token: null), 401);
      expect(await post(null, token: null), 200);
      expect(await post({'test': true}), 200);
      expect(await postBody('Nexus webhook verification', token: null), 200);
      expect(await post('Nexus webhook verification', token: null), 200);
      expect(
        await post({
          'message': 'verification',
          'eventKey': 'demo1234',
        }, token: null),
        200,
      );
      expect(await postBody('{"eventKey":', token: 'test-token'), 400);
      expect(await post({'eventKey': 'demo1234', 'matches': <Json>[]}), 400);
      expect(await query.oneOrNull(), isNull);

      expect(await post(payload), 200);
      expect(
        await updates.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      final imported = updates.current.items.single;
      expect(imported.matches.single.redTeams, ['2046', null, '254']);
      expect(imported.partsRequests.single.requestedByTeam, '2046');
      expect(imported.announcements.single.text, 'Schedule posted');

      final revision = store.revision;
      expect(
        await post(
          _status(
            'demo1234',
            now.subtract(const Duration(seconds: 1)),
            'On deck',
          ),
        ),
        200,
      );
      expect(await post(payload), 200);
      expect(store.revision, revision);
      expect((await query.one()).matches.single.status, 'Now queuing');

      await expectLater(
        grove.create(imported),
        throwsA(
          isA<GroveException>().having(
            (error) => error.code,
            'code',
            'forbidden',
          ),
        ),
      );
    },
  );

  test(
    'discovers live events, reconciles webhook state and refreshes pit layouts',
    () async {
      final store = EntityStore(
        sqlite3.openInMemory(),
        bearingsEntityRegistry(),
      );
      addTearDown(store.close);
      const event = '2026wabon';
      var now = DateTime.utc(2026, 3, 12, 12);
      var address = 'A1';
      var pitRequests = 0;
      var statusRequests = 0;
      final nexus = NexusSync(
        store: store,
        apiKey: 'test-key',
        webhookToken: 'test-token',
        now: () => now,
        client: MockClient((request) async {
          expect(request.headers['nexus-api-key'], 'test-key');
          final path = request.url.path;
          if (path == '/api/v1/events') {
            return http.Response(
              jsonEncode({
                event: {
                  'start': DateTime.utc(2026, 3, 12, 10).millisecondsSinceEpoch,
                  'end': DateTime.utc(2026, 3, 13).millisecondsSinceEpoch,
                },
              }),
              200,
            );
          }
          if (path == '/api/v1/event/$event') {
            statusRequests++;
            return http.Response(
              jsonEncode(_status(event, now, 'On deck')),
              200,
            );
          }
          if (path == '/api/v1/event/$event/map') {
            const geometry = {
              'position': {'x': 20, 'y': 20},
              'size': {'x': 10, 'y': 10},
            };
            return http.Response(
              jsonEncode({
                'size': {'x': 100, 'y': 200},
                'pits': {
                  'A1': {...geometry, 'team': '2046'},
                  'A2': {...geometry, 'team': '254'},
                  'A3': {...geometry, 'team': '2910'},
                  'A4': geometry,
                },
              }),
              200,
            );
          }
          if (path == '/api/v1/event/$event/pits') {
            pitRequests++;
            return http.Response(
              jsonEncode({'2046': address, '1678': 'A2', '973': 'A4'}),
              200,
            );
          }
          fail('Unexpected Nexus request $path');
        }),
      );
      addTearDown(nexus.close);
      Future<void> drain() async {
        for (var count = 0; count < 10; count++) {
          if (!await nexus.syncNext()) return;
        }
        fail('Nexus refresh queue did not drain');
      }

      await drain();
      final pitRecord = store.get(pitLayoutEntity.type, event)!;
      final layout = pitLayoutEntity.read(pitRecord);
      expect(layout.map?.size.x, 100);
      expect(layout.pits['A1']?.team?.id, 'frc2046');
      expect(layout.pits['A2']?.team?.id, 'frc1678');
      expect(layout.pits['A3']?.team?.id, 'frc2910');
      expect(layout.pits['A4']?.team?.id, 'frc973');
      expect(layout.pits['A4']?.geometry?.position.x, 20);
      expect(statusRequests, 1);
      expect(pitRequests, 1);

      now = now.add(const Duration(seconds: 5));
      final push = Request.post(
        Uri.parse('http://localhost/api/nexus/webhook'),
        headers: {'Nexus-Token': 'test-token'},
        body: jsonEncode(_status(event, now, 'On field')),
      );
      expect((await nexus.receive(push)).statusCode, 200);
      now = now.add(const Duration(seconds: 30));
      await drain();
      expect(statusRequests, 1);
      expect(pitRequests, 1);

      now = now.add(const Duration(seconds: 30));
      await drain();
      expect(statusRequests, 2);
      expect(pitRequests, 1);
      expect(
        eventStatusSnapshotEntity
            .read(store.get(eventStatusSnapshotEntity.type, event)!)
            .matches
            .single
            .status,
        'On deck',
      );

      address = 'B2';
      now = now.add(const Duration(minutes: 4));
      await drain();
      expect(pitRequests, 2);
      final updated = pitLayoutEntity.read(
        store.get(pitLayoutEntity.type, event)!,
      );
      expect(updated.pits['A1']?.team, isNull);
      expect(updated.pits['A1']?.geometry, isNotNull);
      expect(updated.pits['B2']?.team?.id, 'frc2046');
      expect(updated.pits['B2']?.geometry, isNull);
    },
  );
}
