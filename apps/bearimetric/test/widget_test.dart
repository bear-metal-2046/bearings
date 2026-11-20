import 'dart:io';

import 'package:bearimetric/data/local_data.dart';
import 'package:bearimetric/models/scouting_session.dart';
import 'package:bearimetric/providers/scouting_flow_provider.dart';
import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:bearimetric/services/device_auth_service.dart';
import 'package:core/core.dart'
    show MatchFormData, ScoutingReport, bearingsEntityRegistry;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:hive_ce/hive.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/secure_storage_provider.dart';

class _StoredEnrollment implements TokenStorage {
  static const credentials = {
    'bearimetric_device_client_id': 'test-device',
    'bearimetric_device_client_secret': 'test-secret',
    'bearimetric_device_domain': 'example.invalid',
    'bearimetric_device_audience': 'test-audience',
  };

  @override
  Future<String?> read({required String key}) async => credentials[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session extends ScoutingSessionNotifier {
  _Session(this.eventKey);
  final String eventKey;
  @override
  ScoutingSession build() => ScoutingSession(
    event: ScoutingEventSelection(
      key: eventKey,
      name: 'Test Event',
      year: 2026,
    ),
    position: ScoutPosition.red1,
    matchNumber: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restores the previous saved event format', () {
    final event = ScoutingEventSelection.fromJson({
      'key': '2026test',
      'name': 'Test Event',
      'year': '2026',
      'startDate': '2026-03-14T00:00:00.000Z',
    });

    expect(event.key, '2026test');
    expect(event.name, 'Test Event');
    expect(event.year, 2026);
  });

  test(
    'startup restores stored device enrollment without a token exchange',
    () async {
      var requests = 0;
      await HttpOverrides.runZoned(
        () async {
          final container = ProviderContainer.test(
            overrides: [
              tokenStorageProvider.overrideWith(
                (ref) async => _StoredEnrollment(),
              ),
            ],
          );
          final auth = await container.read(deviceAuthServiceProvider.future);
          await auth.initialize();
          expect(container.read(authStatusProvider), AuthStatus.authenticated);
          expect(await auth.groveSubject(), 'test-device@clients');
        },
        createHttpClient: (_) {
          requests++;
          throw const SocketException('Network unavailable');
        },
      );
      expect(requests, 0);
    },
  );

  test(
    'advancing offline stages the match in Grove; training stays local',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bearimetric-test',
      );
      Hive.init(directory.path);
      await Hive.openBox(boxKey);
      addTearDown(() async {
        await Hive.close();
        await directory.delete(recursive: true);
      });

      final grove = Grove(
        registry: bearingsEntityRegistry(),
        transport: WebSocketGroveTransport(
          uri: Uri.parse('ws://127.0.0.1:1'),
          accessToken: () async => throw const GroveOffline(),
        ),
      );
      addTearDown(grove.close);
      ProviderContainer container(String eventKey) => ProviderContainer(
        overrides: [
          scoutingSessionProvider.overrideWith(() => _Session(eventKey)),
          bearingsGroveProvider.overrideWithValue(grove),
        ],
      );

      Future<MatchFormData> submit(String eventKey) async {
        final scope = container(eventKey);
        addTearDown(scope.dispose);
        final draft = MatchFormData.blank(
          eventKey: eventKey,
          matchNumber: 1,
          pos: 0,
          season: 2026,
          configVersion: 1,
        ).copyWithField('auto', 'score', 3);
        scope.read(matchFormStoreProvider).save(draft);
        expect(
          await scope.read(scoutingFlowControllerProvider).nextMatch(),
          isTrue,
        );
        expect(scope.read(scoutingSessionProvider).matchNumber, 2);
        return draft;
      }

      final draft = await submit('2026test');
      expect(await grove.pendingMutationCount, 1);
      final local = await grove.query<ScoutingReport>().byId(draft.id).result();
      expect(local.offline, isTrue);
      expect(local.items.single.toMatch().getField('auto', 'score'), 3);

      final training = await submit(trainingEventKey);
      expect(await grove.pendingMutationCount, 1);
      expect(
        (await grove.query<ScoutingReport>().byId(training.id).result()).items,
        isEmpty,
      );
    },
  );
}
