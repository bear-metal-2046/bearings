import 'dart:convert';

import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:honeycomb/src/auth0_directory_sync.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'imports, refreshes and retires Auth0 users without changing roles',
    () async {
      final store = EntityStore(
        sqlite3.openInMemory(),
        bearingsEntityRegistry(),
      );
      addTearDown(store.close);
      const member = 'auth0|member';
      const newUser = 'auth0|new';
      const oldPhoto = 'https://honeycomb.example/api/account/photo/previous';
      final existing = GroveUser(
        id: member,
        name: 'Existing display name',
        avatarUrl: oldPhoto,
        roles: [const EntityRef<GroveRole>('scout')],
      );
      store.mutate(
        EntityMutation(
          mutationId: 'existing-user',
          type: groveUserEntity.type,
          id: member,
          version: 1,
          kind: MutationKind.create,
          data: existing.toJson(),
        ),
        'admin',
      );
      final users = <String, Json>{
        member: {
          'user_id': member,
          'name': 'Auth0 default name',
          'email': 'member@example.com',
          'email_verified': false,
          'picture': 'https://example.com/default.png',
          'updated_at': '2026-11-14T00:00:00.000Z',
        },
        newUser: {
          'user_id': newUser,
          'name': 'New member',
          'email': 'new@example.com',
          'email_verified': true,
          'updated_at': '2026-11-14T00:00:00.000Z',
        },
      };
      final indexed = {member, newUser};
      final lookedUp = <String>[];
      final accounts = AccountService(
        store: store,
        issuer: Uri.parse('https://example.auth0.com/'),
        managementClientId: 'client',
        managementClientSecret: 'secret',
        deviceCredentials: null,
        client: MockClient((request) async {
          if (request.url.path == '/oauth/token') {
            return http.Response(
              '{"access_token":"management","expires_in":600}',
              200,
            );
          }
          expect(request.headers['authorization'], 'Bearer management');
          expect(request.method, 'GET');
          if (request.url.path == '/api/v2/users') {
            final page = request.url.queryParameters['page'];
            expect(page, anyOf('0', '1'));
            final ids = page == '0'
                ? List.generate(100, (index) => 'device-$index@clients')
                : indexed;
            return http.Response(
              jsonEncode({
                'total': 100 + indexed.length,
                'users': [
                  for (final id in ids)
                    {'user_id': id, 'updated_at': users[id]?['updated_at']},
                ],
              }),
              200,
            );
          }
          final id = request.url.pathSegments.last;
          lookedUp.add(id);
          final user = users[id];
          return user == null
              ? http.Response('{}', 404)
              : http.Response(jsonEncode(user), 200);
        }),
      );
      final sync = Auth0DirectorySync(
        accounts: accounts,
        webhookToken: 'webhook',
      );
      GroveUser profile(String id) =>
          GroveUser.fromJson(store.get(groveUserEntity.type, id)!.data);

      await sync.reconcile();
      expect(lookedUp, unorderedEquals([member, newUser]));
      expect(profile(newUser).name, 'New member');
      expect(profile(newUser).emailVerified, isTrue);
      expect(profile(newUser).roles, isEmpty);
      expect(profile(member).name, existing.name);
      expect(profile(member).avatarUrl, oldPhoto);
      expect(profile(member).emailVerified, isFalse);
      expect(profile(member).roles.single.id, 'scout');

      lookedUp.clear();
      await sync.reconcile();
      expect(lookedUp, isEmpty);

      final before = Map<String, dynamic>.of(users[member]!);
      users[member]!.addAll({
        'name': 'Changed in Auth0',
        'email_verified': true,
        'picture': 'https://example.com/new.png',
        'updated_at': '2026-11-14T00:15:00.000Z',
      });
      Request webhook({String token = 'webhook'}) => Request.post(
        Uri.parse('https://honeycomb.example/api/auth0/webhook'),
        headers: {'authorization': 'Bearer $token'},
        body: jsonEncode({
          'type': 'user.updated',
          'data': {'object': users[member], 'previous_object': before},
        }),
      );
      expect((await sync.receive(webhook(token: 'wrong'))).statusCode, 401);
      expect(lookedUp, isEmpty);
      expect((await sync.receive(webhook())).statusCode, 204);
      expect(profile(member).name, 'Changed in Auth0');
      expect(profile(member).avatarUrl, 'https://example.com/new.png');
      expect(profile(member).emailVerified, isTrue);
      expect(profile(member).roles.single.id, 'scout');
      final revision = store.revision;
      expect((await sync.receive(webhook())).statusCode, 204);
      expect(store.revision, revision);

      indexed.remove(newUser);
      await sync.reconcile();
      expect(store.get(groveUserEntity.type, newUser)!.deleted, isFalse);
      users.remove(newUser);
      await sync.reconcile();
      expect(store.get(groveUserEntity.type, newUser)!.deleted, isTrue);
    },
  );
}
