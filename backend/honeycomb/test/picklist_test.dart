import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'shared picklist edits merge and presence follows read access',
    () async {
      final registry = bearingsEntityRegistry();
      final store = EntityStore(sqlite3.openInMemory(), registry);
      addTearDown(store.close);
      final service = EntityService(
        store: store,
        bootstrapSubject: 'admin',
        authenticate: (token) async => AuthenticatedActor(
          token,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );
      final server = await serve(
        service.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      Grove connect(String id) {
        final grove = Grove(
          registry: registry,
          transport: WebSocketGroveTransport(
            uri: Uri.parse('ws://127.0.0.1:${server.port}'),
            accessToken: () async => id,
            requestTimeout: const Duration(seconds: 3),
            reconnectDelay: const Duration(milliseconds: 100),
          ),
        );
        addTearDown(grove.close);
        return grove;
      }

      final admin = connect('admin');
      final editor = connect('editor');
      final reader = connect('reader');
      await editor.query<GroveUser>().byId('editor').one();
      await reader.query<GroveUser>().byId('reader').one();
      final editRole = await admin.create(
        GroveRole(
          id: 'picklist-edit',
          name: 'Picklist editor',
          permissions: ['strategy.picklist.read', 'strategy.picklist.mutate'],
        ),
      );
      final readRole = await admin.create(
        GroveRole(
          id: 'picklist-read',
          name: 'Picklist reader',
          permissions: ['strategy.picklist.read'],
        ),
      );
      for (final (id, role) in [('editor', editRole), ('reader', readRole)]) {
        await admin.update<GroveUser>(
          id,
          (user) => user.copyWith(
            name: id,
            roles: [EntityRef<GroveRole>(role.id)],
          ),
        );
      }

      final now = DateTime.utc(2026, 11, 10);
      final picklist = await admin.create(
        GrovePicklist(
          id: 'picklist',
          eventKey: 'pnw',
          title: 'Alliance selection',
          emoji: '📋',
          createdAt: now,
          updatedAt: now,
        ).replaceTeams(['frc1', 'frc2'], at: now),
      );
      final watch = StreamIterator(
        reader.watch(
          reader.query<GrovePicklist>().where(
            GrovePicklistFields.eventKey.equals('pnw'),
          ),
        ),
      );
      addTearDown(watch.cancel);
      expect(await watch.moveNext(), isTrue);
      expect(watch.current.items.single.teamKeys, ['frc1', 'frc2']);

      await Future.wait([
        admin.update<GrovePicklist>(
          picklist.id,
          (base) => base.replaceTeams(['frc1', 'frc2', 'frc3'], at: now),
          basedOn: picklist,
        ),
        editor.update<GrovePicklist>(
          picklist.id,
          (base) => base.replaceTeams(['frc2', 'frc1', 'frc4'], at: now),
          basedOn: picklist,
        ),
      ]);
      Future<void> observeMerged() async {
        while (await watch.moveNext()) {
          final keys = watch.current.items.single.teamKeys;
          if (keys.length == 4) {
            expect(keys.toSet(), {'frc1', 'frc2', 'frc3', 'frc4'});
            expect(keys.indexOf('frc2'), lessThan(keys.indexOf('frc1')));
            return;
          }
        }
        fail('Missing merged picklist snapshot');
      }

      await observeMerged().timeout(const Duration(seconds: 3));

      await expectLater(
        reader.delete<GrovePicklist>(picklist.id),
        throwsA(
          isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
        ),
      );

      final peers = StreamIterator(
        admin.watchPresence<GrovePicklist>(picklist.id),
      );
      addTearDown(peers.cancel);
      final others = StreamIterator(
        reader.watchPresence<GrovePicklist>(picklist.id),
      );
      addTearDown(others.cancel);
      Future<List<GrovePresencePeer>> nextPeers(
        StreamIterator<List<GrovePresencePeer>> stream,
        bool Function(List<GrovePresencePeer>) predicate,
      ) async {
        while (await stream.moveNext()) {
          if (predicate(stream.current)) return stream.current;
        }
        fail('Presence stream closed');
      }

      expect(await peers.moveNext(), isTrue);
      expect(peers.current, isEmpty);
      expect(await others.moveNext(), isTrue);
      expect(others.current.single.id, 'admin');
      final present = await nextPeers(
        peers,
        (list) => list.isNotEmpty,
      ).timeout(const Duration(seconds: 3));
      expect(present.single.name, 'reader');

      await service.disconnectClients();
      await nextPeers(
        peers,
        (list) => list.isEmpty,
      ).timeout(const Duration(seconds: 3));
      // The reader's subscription has to be consuming again for the stream to
      // resume after its disconnected snapshot.
      await nextPeers(
        others,
        (list) => list.isNotEmpty,
      ).timeout(const Duration(seconds: 3));
      await nextPeers(
        peers,
        (list) => list.isNotEmpty,
      ).timeout(const Duration(seconds: 3));

      await admin.update<GroveRole>(
        readRole.id,
        (role) => role.copyWith(permissions: []),
      );
      await nextPeers(
        peers,
        (list) => list.isEmpty,
      ).timeout(const Duration(seconds: 3));
      await nextPeers(
        others,
        (list) => list.isEmpty,
      ).timeout(const Duration(seconds: 3));
      await admin.delete<GrovePicklist>(picklist.id);
      expect(
        await admin.query<GrovePicklist>().byId(picklist.id).oneOrNull(),
        isNull,
      );
    },
  );
}
