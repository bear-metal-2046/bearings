import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod/riverpod.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/grove_provider.dart';

class _SignedIn extends AuthStatusNotifier {
  @override
  AuthStatus build() => AuthStatus.authenticated;
}

class _Endpoint extends HoneycombEndpointPreference {
  _Endpoint(this.url);

  final String url;

  @override
  HoneycombEndpointSelection build() => HoneycombEndpointSelection(
    mode: HoneycombEndpointMode.custom,
    customUrl: url,
  );
}

ProviderContainer _container(String subject, {String? endpoint}) =>
    ProviderContainer(
      overrides: [
        authStatusProvider.overrideWith(_SignedIn.new),
        groveSubjectProvider.overrideWith((ref) async => subject),
        groveAccessTokenProvider.overrideWithValue(
          ({required forceRefresh}) async => throw const GroveOffline(),
        ),
        if (endpoint != null)
          honeycombEndpointPreferenceProvider.overrideWith(
            () => _Endpoint(endpoint),
          ),
      ],
    );

void main() {
  test(
    'native Grove discards the old cache and persists the new cache',
    () async {
      final directory = await Directory.systemTemp.createTemp('grove-access');
      addTearDown(() async {
        await Hive.close();
        await directory.delete(recursive: true);
      });
      Hive.init(directory.path);
      final oldCache = await Hive.openBox<String>('grove_v1');
      await oldCache.put(
        'pending',
        jsonEncode({
          'mutations': ['old'],
        }),
      );
      await oldCache.close();
      await initializeGroveStorage();
      expect(await Hive.boxExists('grove_v1'), isFalse);
      expect(Hive.isBoxOpen('grove_v2'), isTrue);

      const endpoint = 'https://bearings-honeycomb.westus2.cloudapp.azure.com';
      const subject = 'auth0|abcde12345abcde12345abcd';
      final first = _container(subject, endpoint: endpoint);
      final grove = first.read(bearingsGroveProvider);
      final query = grove.query<GroveAccess>().byId(subject);
      final key = 'query:${query.description.key}';
      final legacyKey = jsonEncode(['$endpoint/api', subject, key]);
      expect(legacyKey.length, greaterThan(255));

      const pending = {'mutations': <Object>[]};
      await grove.cache.write('pending', pending);
      await grove.cache.write(
        key,
        QuerySnapshot([
          EntityRecord(
            type: query.description.type,
            id: subject,
            version: 1,
            data: GroveAccess(subject, ['external.read']).toJson(),
          ),
        ]).toJson(),
      );
      final utf8Key = 'query:${List.filled(55, '🦉').join()}';
      final snapshot = QuerySnapshot([], revision: 1).toJson();
      await grove.cache.write(utf8Key, snapshot);
      await grove.close();
      first.dispose();
      await Hive.close();
      await initializeGroveStorage();

      Grove open(String user, String url) {
        final container = _container(user, endpoint: url);
        addTearDown(container.dispose);
        final grove = container.read(bearingsGroveProvider);
        addTearDown(grove.close);
        return grove;
      }

      final restored = open(subject, endpoint);
      final result = await restored.query<GroveAccess>().byId(subject).result();
      expect(result.offline, isTrue);
      expect(result.items.single.permissions, {'external.read'});
      expect(await restored.cache.read('pending'), pending);
      expect(await restored.cache.read(utf8Key), snapshot);
      expect(await open('other-user', endpoint).cache.read(key), isNull);
      expect(
        await open(subject, 'https://other.example.org').cache.read(key),
        isNull,
      );

      await restored.cache.remove(key);
      expect(await restored.cache.read(key), isNull);

      const shortQuery = 'query:teams';
      final draftKey = 'draft:${List.filled(55, '🦉').join()}';
      const draft = {'id': 'original', 'data': <String, Object?>{}};
      await restored.cache.write(shortQuery, snapshot);
      await restored.cache.write(draftKey, draft);

      await restored.cache.clearQuerySnapshots();

      expect(await restored.cache.read(shortQuery), isNull);
      expect(await restored.cache.read(utf8Key), isNull);
      expect(await restored.cache.read(draftKey), draft);
      expect(await restored.cache.read('pending'), pending);
    },
  );

  test(
    'native Grove staging survives Hive reopen and is scoped by subject',
    () async {
      final directory = await Directory.systemTemp.createTemp('grove-native');
      addTearDown(() async {
        await Hive.close();
        await directory.delete(recursive: true);
      });
      Hive.init(directory.path);
      await initializeGroveStorage();

      final first = _container('device-a');
      final grove = first.read(bearingsGroveProvider);
      final report = GamePackObservation(
        id: 'cached-observation',
        gamePack: const EntityRef('pack'),
        event: const EntityRef('2026test'),
        capturedAt: DateTime.utc(2026),
        answers: const {'auto_score': 6, 'teleop_score': 8},
      );
      await grove.stageCreate(report);
      await grove.stageCreate(report);
      expect(await grove.pendingMutationCount, 1);
      await grove.close();
      first.dispose();
      await Hive.close();
      await initializeGroveStorage();

      final reopened = _container('device-a');
      addTearDown(reopened.dispose);
      final restored = reopened.read(bearingsGroveProvider);
      addTearDown(restored.close);
      final result = await restored
          .query<GamePackObservation>()
          .byId(report.id)
          .result();
      expect(result.offline, isTrue);
      expect(result.complete, isFalse);
      expect(result.items.single.answers['auto_score'], 6);
      expect(result.items.single.answers['teleop_score'], 8);

      final other = _container('device-b');
      addTearDown(other.dispose);
      final isolated = other.read(bearingsGroveProvider);
      addTearDown(isolated.close);
      expect(await isolated.pendingMutationCount, 0);
      expect(
        (await isolated.query<GamePackObservation>().result()).items,
        isEmpty,
      );
    },
  );
}
