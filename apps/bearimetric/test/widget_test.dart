import 'dart:io';

import 'package:bearimetric/models/scouting_session.dart';
import 'package:bearimetric/services/device_auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services/providers/auth_provider.dart';
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
}
