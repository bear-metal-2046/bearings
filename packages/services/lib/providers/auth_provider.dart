import 'package:core/providers/device_info_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/auth/auth_backend.dart';
import 'package:services/providers/auth/oidc_backend.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_provider.g.dart';

// This whole system is modular (and we were using seperate systems per platform)
// but now it's just the odic backend

class Auth0Config {
  final String domain;
  final String clientId;
  final String audience;
  final Map<DeviceOS, String> redirectUris;
  final String storageKeyPrefix;
  const Auth0Config({
    required this.domain,
    required this.clientId,
    required this.audience,
    required this.redirectUris,
    this.storageKeyPrefix = '',
  });
}

enum AuthStatus { authenticated, unauthenticated, authenticating }

@Riverpod(keepAlive: true)
class AuthStatusNotifier extends _$AuthStatusNotifier implements Listenable {
  VoidCallback? _routerListener;

  @override
  AuthStatus build() => AuthStatus.unauthenticated;

  void setStatus(AuthStatus status) {
    if (state != status) {
      state = status;
      notify();
    }
  }

  void notify() => _routerListener?.call();

  @override
  void addListener(VoidCallback listener) => _routerListener = listener;

  @override
  void removeListener(VoidCallback listener) {
    if (_routerListener == listener) _routerListener = null;
  }
}

@Riverpod(keepAlive: true)
Auth0Config auth0Config(Ref ref) {
  throw UnimplementedError(
    'auth0ConfigProvider must be overridden with app-specific configuration',
  );
}

@Riverpod(keepAlive: true)
Future<Auth> auth(Ref ref) async {
  final deviceInfo = ref.watch(deviceInfoProvider);
  final config = ref.watch(auth0ConfigProvider);

  final backend = await _createBackend(config, deviceInfo.deviceOS);
  return Auth(ref: ref, backend: backend, config: config);
}

Future<AuthBackend> _createBackend(Auth0Config config, DeviceOS os) async {
  final redirectUri = config.redirectUris[os];
  if (redirectUri == null) {
    throw StateError('No OIDC redirect URI configured for $os.');
  }

  final backend = OidcAuthBackend(
    config: config,
    redirectUri: Uri.parse(redirectUri),
  );
  await backend.init();
  return backend;
}

/// Unified authentication facade that delegates platform-specific OAuth work
/// to an [AuthBackend].
///
/// ### Public API (unchanged from previous versions)
/// - [login] / [logout] / [getAccessToken] / [trySilentLogin]
/// - [user] — the current user profile (populated by the backend)
///
/// ### Facade-level responsibilities
/// - Auth status transitions ([AuthStatusNotifier])
/// - Online connectivity checks before login
/// - Hive cache and SharedPreferences cleanup on logout
class Auth {
  final AuthBackend _backend;
  final Ref ref;
  final Auth0Config config;

  Auth({required this.ref, required this._backend, required this.config});

  /// The current user's profile, or `null` if not authenticated.
  ///
  /// Populated after a successful [login] or [trySilentLogin].
  AuthUser? get user => _backend.user;

  Future<void> login(List<String> scopes, {bool isSignup = false}) async {
    _setStatus(AuthStatus.authenticating);

    if (!await checkOnline(ref)) {
      _setStatus(AuthStatus.unauthenticated);
      throw OfflineAuthException('No internet connection available to login.');
    }

    try {
      await _backend.login(scopes, isSignup: isSignup);
      _setStatus(AuthStatus.authenticated);
    } catch (e) {
      debugPrint('Login Error: $e');
      _setStatus(AuthStatus.unauthenticated);
      rethrow;
    }
  }

  Future<String> getAccessToken(List<String> scopes) async {
    return _backend.getAccessToken(scopes);
  }

  Future<void> trySilentLogin() async {
    _setStatus(AuthStatus.authenticating);

    try {
      await _backend.trySilentLogin();
      _setStatus(
        _backend.user != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
      );
    } catch (e) {
      debugPrint('Silent login failed: $e');
      _setStatus(AuthStatus.unauthenticated);
    }
  }

  Future<void> logout({bool federated = false}) async {
    await _backend.logout(federated: federated);

    // Clear known Hive cache boxes.
    const cacheBoxNames = ['api_cache', 'scouting_data'];
    for (final name in cacheBoxNames) {
      if (Hive.isBoxOpen(name)) {
        try {
          await Hive.box(name).clear();
        } catch (_) {}
      }
    }

    // Clear SharedPreferences (app-level keys like endpoint selection).
    try {
      (await SharedPreferences.getInstance()).clear();
    } catch (_) {}

    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus status) {
    ref.read(authStatusProvider.notifier).setStatus(status);
  }
}

class OAuthToken {
  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;

  OAuthToken({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(
    expiresAt.subtract(const Duration(minutes: 2)),
  );

  factory OAuthToken.fromJson(Map<String, dynamic> json) {
    return OAuthToken(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: (json['expires_in'] as num).toInt()),
      ),
    );
  }
}

class OfflineAuthException implements Exception {
  final String message;

  OfflineAuthException([this.message = 'No internet connection available']);

  @override
  String toString() => 'OfflineAuthException: $message';
}
