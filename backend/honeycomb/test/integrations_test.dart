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

void main() {
  test(
    'competition and account actions use verified subjects and capabilities',
    () async {
      final registry = bearingsEntityRegistry();
      final store = EntityStore(sqlite3.openInMemory(), registry);
      addTearDown(store.close);
      final auth0Requests = <String>[];
      late final AccountService account;
      var rejectPhoto = false;
      final auth0 = MockClient((request) async {
        expect(request.url.host, 'example.auth0.com');
        if (request.url.path == '/oauth/token') {
          return http.Response(
            '{"access_token":"management","expires_in":600}',
            200,
          );
        }
        auth0Requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/dbconnections/change_password') {
          final body = jsonDecode(request.body) as Json;
          expect(body['email'], 'updated@example.com');
          expect(body['connection'], 'members');
          expect(body['client_id'], 'public-app');
          return http.Response('Reset sent', 200);
        }
        expect(request.headers['authorization'], 'Bearer management');
        expect(request.url.pathSegments.last, 'member');
        if (request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Json;
          if (body.containsKey('name')) {
            expect(body, {'name': ' Member '});
            return http.Response('{"name":"Member"}', 200);
          }
          if (body['picture'] case final String url) {
            final id = Uri.parse(url).pathSegments.last;
            expect(account.photo(id), [255, 216, 255, 217]);
            return rejectPhoto
                ? http.Response('{}', 400)
                : http.Response(jsonEncode({'picture': url}), 200);
          }
          expect(body, {
            'email': 'updated@example.com',
            'email_verified': false,
            'verify_email': true,
          });
          return http.Response('{"email":"updated@example.com"}', 200);
        }
        if (request.method == 'GET') {
          return http.Response(
            '{"email":"updated@example.com","identities":[{"provider":"auth0","connection":"members","isSocial":false}]}',
            200,
          );
        }
        expect(request.method, 'DELETE');
        return http.Response('', 204);
      });
      final upstreamRequests = <String>[];
      final competition = MockClient((request) async {
        upstreamRequests.add(request.url.path);
        if (request.url.host == 'frc.nexus') {
          expect(request.headers['Nexus-Api-Key'], 'nexus');
          return switch (request.url.path) {
            '/api/v1/event/2026test/map' => http.Response(
              '{"size":{"x":100,"y":100}}',
              200,
            ),
            '/api/v1/event/2026test/pits' => http.Response(
              '{"2046":"A1"}',
              200,
            ),
            _ => http.Response('{"matches":[]}', 200),
          };
        }
        fail('Unexpected live TBA request: ${request.url.path}');
      });
      void import<T>(String path, T entity) {
        final descriptor = registry.descriptor<T>();
        final data = descriptor.encode(entity);
        store.replaceExternalDataset(path, [
          EntityRecord(
            type: descriptor.type,
            id: data['id'] as String,
            version: descriptor.version,
            data: data,
          ),
        ], checkpoint: () {});
      }

      import(
        '/events/2026',
        TbaApi.event({'key': '2026test', 'playoff_type': 10}),
      );
      final match = TbaApi.match({'key': '2026test_qm1'});
      import('/event/2026test/matches', match);
      final media = TbaApi.media(
        '/event/2026test/team_media',
        {
          'type': 'avatar',
          'team_keys': ['frc2046'],
        },
        event: '2026test',
        season: 2026,
        rosterMedia: true,
      );
      import('/event/2026test/team_media', media);
      account = AccountService(
        store: store,
        issuer: Uri.parse('https://example.auth0.com/'),
        managementClientId: 'management-client',
        managementClientSecret: 'management-secret',
        publicApiUrl: Uri.parse('https://honeycomb.example/api/'),
        deviceCredentials: {
          'clientId': 'device',
          'clientSecret': 'device-secret',
        },
        client: auth0,
      );
      final server = await serve(
        EntityService(
          store: store,
          bootstrapSubject: 'admin',
          competitionSources: CompetitionSources(
            store: store,
            tbaKey: 'tba',
            nexusKey: 'nexus',
            client: competition,
          ),
          accounts: account,
          authenticate: (token) async => AuthenticatedActor(
            token,
            clientId: 'public-app',
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          ),
        ).handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      WebSocketGroveTransport connect(String id) => WebSocketGroveTransport(
        uri: Uri.parse('ws://127.0.0.1:${server.port}'),
        accessToken: () async => id,
        requestTimeout: const Duration(seconds: 3),
      );
      final adminTransport = connect('admin');
      final memberTransport = connect('member');
      final admin = Grove(registry: registry, transport: adminTransport);
      final member = Grove(registry: registry, transport: memberTransport);
      addTearDown(admin.close);
      addTearDown(member.close);
      await member.query<GroveUser>().byId('member').one();
      final forbidden = throwsA(
        isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
      );
      await expectLater(
        memberTransport.account('deviceCredentials'),
        forbidden,
      );
      await expectLater(
        memberTransport.competition('matches', {'event': '2026test'}),
        forbidden,
      );
      await expectLater(
        member.query<CompetitionMatch>().byId('2026test_qm1').one(),
        forbidden,
      );
      expect(upstreamRequests, isEmpty);
      expect(
        (await adminTransport.account('deviceCredentials'))['clientId'],
        'device',
      );

      final role = await admin.create(
        GroveRole(
          id: 'competition',
          name: 'Competition reader',
          permissions: [competitionReadPermission],
        ),
      );
      await admin.update<GroveUser>(
        'member',
        (user) => user.copyWith(
          roles: [EntityRef<GroveRole>(role.id)],
        ),
      );
      final matches = await memberTransport.competition('matches', {
        'event': '2026test',
      });
      expect(matches, [TbaApi.matchJson(match)]);
      expect(
        await adminTransport.competition('matches', {'event': '2026test'}),
        matches,
      );
      expect(upstreamRequests, isEmpty);
      final imported = await member
          .query<CompetitionMatch>()
          .byId('2026test_qm1')
          .one();
      expect(imported.event.id, '2026test');
      await expectLater(admin.create(imported), forbidden);
      expect(
        await memberTransport.competition('media', {'event': '2026test'}),
        [TbaApi.mediaJson(media)],
      );
      final pitMap = await memberTransport.competition('pitMap', {
        'event': '2026test',
      }) as Json;
      expect(pitMap['addresses'], {'2046': 'A1'});
      final nexus = await memberTransport.competition('nexus', {
        'event': '2026test',
        'nexusEvent': '2026test',
      }) as Json;
      expect(nexus['playoff_type'], 10);

      final nameEdit = EntityMutation(
        mutationId: 'name-edit',
        type: groveUserEntity.type,
        id: 'member',
        version: 1,
        kind: MutationKind.update,
        changes: [
          FieldChange(['name'], ' Member '),
        ],
      );
      final nameReceipt = await memberTransport.mutate(nameEdit);
      expect(nameReceipt.data['name'], 'Member');
      expect(
        (await memberTransport.mutate(nameEdit)).revision,
        nameReceipt.revision,
      );
      await memberTransport.account('changeEmail', {
        'email': 'updated@example.com',
        'subject': 'admin',
      });
      await memberTransport.account('resetPassword');
      final photo = await memberTransport.account('uploadPhoto', {
        'jpeg': base64Encode([255, 216, 255, 217]),
      });
      final id = Uri.parse(photo['url'] as String).pathSegments.last;
      expect(account.photo(id), [255, 216, 255, 217]);
      rejectPhoto = true;
      await expectLater(
        memberTransport.account('uploadPhoto', {
          'jpeg': base64Encode([255, 216, 255, 217]),
        }),
        throwsA(isA<GroveException>()),
      );
      expect(account.photo(id), [255, 216, 255, 217]);
      final profile = await member.query<GroveUser>().byId('member').one();
      expect(profile.name, 'Member');
      expect(profile.email, 'updated@example.com');
      expect(profile.emailVerified, isFalse);
      expect(profile.avatarUrl, photo['url']);
      await memberTransport.account('deleteAccount');
      expect(account.photo(id), isNull);
      expect(store.get('identity.user', 'member')?.deleted, isTrue);
      expect(auth0Requests, [
        'PATCH /api/v2/users/member',
        'PATCH /api/v2/users/member',
        'GET /api/v2/users/member',
        'POST /dbconnections/change_password',
        'PATCH /api/v2/users/member',
        'PATCH /api/v2/users/member',
        'DELETE /api/v2/users/member',
      ]);
      await expectLater(
        member.query<GroveUser>().byId('member').one(),
        throwsA(
          isA<GroveException>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
    },
  );
}
