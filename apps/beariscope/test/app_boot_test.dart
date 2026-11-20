import 'dart:async';

import 'package:beariscope/providers/app_boot_provider.dart';
import 'package:beariscope/providers/app_phase_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/auth/auth_backend.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/grove_provider.dart';

class _RestoredSession implements AuthBackend {
  _RestoredSession(this.user);
  @override
  final AuthUser? user;

  @override
  Future<void> trySilentLogin() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection extends MemoryGroveTransport
    implements GroveConnectionTransport {
  _Connection(super.registry);

  final started = Completer<void>();
  final attempt = Completer<void>();
  int attempts = 0;

  @override
  GroveConnectionState get connectionState => GroveConnectionState.disconnected;

  @override
  Stream<GroveConnectionState> watchConnection() =>
      Stream.value(connectionState);

  @override
  Future<void> connect() {
    attempts++;
    if (!started.isCompleted) started.complete();
    return attempt.future;
  }

  @override
  void checkConnection() {}

  // Profile and permissions may have no snapshots during startup.
  @override
  Stream<QuerySnapshot> watch(QueryDescription query) => const Stream.empty();
}

void main() {
  for (final (label, failure, expected) in [
    ('connected', null, AppPhase.ready),
    ('offline', const GroveOffline(), AppPhase.ready),
    (
      'credentials rejected',
      const GroveException('unauthenticated', 'Sign in again'),
      AppPhase.loginRequired,
    ),
  ]) {
    test('startup opens the appropriate screen when $label', () async {
      final registry = bearingsEntityRegistry();
      final transport = _Connection(registry);
      final grove = Grove(registry: registry, transport: transport);
      addTearDown(grove.close);
      final container = ProviderContainer.test(
        overrides: [
          authProvider.overrideWith(
            (ref) async => Auth(
              ref: ref,
              backend: _RestoredSession(const AuthUser(subject: 'auth0|scout')),
              config: const Auth0Config(
                domain: 'example.invalid',
                clientId: 'test',
                audience: 'test',
                redirectUris: {},
              ),
            ),
          ),
          bearingsGroveProvider.overrideWithValue(grove),
        ],
      );
      final phase = container.listen(appPhaseProvider, (_, _) {});
      final boot = container.read(appBootProvider.notifier).start();
      await transport.started.future.timeout(const Duration(seconds: 2));
      expect(phase.read(), AppPhase.splashing);
      expect(container.read(appBootProvider).stage, AppBootStage.connecting);
      if (failure == null) {
        transport.attempt.complete();
      } else {
        transport.attempt.completeError(failure);
      }
      await boot.timeout(const Duration(seconds: 2));
      expect(phase.read(), expected);
      expect(transport.attempts, 1);
      expect(
        container.read(authStatusProvider),
        expected == AppPhase.ready
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
      );
    });
  }
}
