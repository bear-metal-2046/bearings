import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grove/grove.dart';
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';
import 'package:services/providers/auth/auth_backend.dart';
import 'package:services/providers/auth_provider.dart';

/// OpenID Connect authentication backend used on every supported platform.
///
/// This uses the `oidc` package's platform integrations instead of manually
/// assembling the authorization-code and PKCE flow.
class OidcAuthBackend implements AuthBackend {
  late OidcUserManager _manager = _createManager();
  Future<void>? _initializing;
  bool _disposed = false;
  final Auth0Config _config;
  final Uri _postLogoutRedirectUri;
  final String _audience;

  OidcAuthBackend({required Auth0Config config, required Uri redirectUri})
    : _config = config,
      _postLogoutRedirectUri = redirectUri,
      _audience = config.audience;

  OidcUserManager _createManager() => OidcUserManager.lazy(
    id: '${_config.storageKeyPrefix}experimental_oidc',
    discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
      Uri.parse('https://${_config.domain}'),
    ),
    clientCredentials: OidcClientAuthentication.none(
      clientId: _config.clientId,
    ),
    store: OidcDefaultStore(
      storagePrefix: '${_config.storageKeyPrefix}oidc',
      secureStorageInstance: const FlutterSecureStorage(),
    ),
    settings: OidcUserManagerSettings(
      redirectUri: _postLogoutRedirectUri,
      postLogoutRedirectUri: _postLogoutRedirectUri,
      scope: const [
        'openid',
        'profile',
        'email',
        'offline_access',
        'ORLhqJbHiTfgdF3Q8hqIbmdwT1wTkkP7',
      ],
      supportOfflineAuth: true,
    ),
  );

  Future<void> _initialize() => _initializing ??= _manager.init().onError((
    Object error,
    StackTrace stack,
  ) {
    if (!_disposed) {
      final failed = _manager;
      _manager = _createManager();
      _initializing = null;
      unawaited(failed.dispose());
    }
    Error.throwWithStackTrace(error, stack);
  });

  @override
  AuthUser? get user {
    final oidcUser = _manager.currentUser;
    if (oidcUser == null) return null;

    final claims = oidcUser.aggregatedClaims;
    return AuthUser(
      subject: _stringClaim(claims, 'sub'),
      name: _stringClaim(claims, 'name'),
      email: _stringClaim(claims, 'email'),
      emailVerified: _boolClaim(claims, 'email_verified'),
      pictureUrl: _uriClaim(claims, 'picture'),
      nickname: _stringClaim(claims, 'nickname'),
    );
  }

  @override
  Future<bool> login(List<String> scopes, {bool isSignup = false}) async {
    await _initialize();
    final user = await _manager.loginAuthorizationCodeFlow(
      scopeOverride: scopes,
      // `audience` and `screen_hint` are Auth0 extensions. Keeping them here
      // preserves the existing Auth0Config behavior while the flow itself is
      // handled as standard OIDC by the package.
      extraParameters: {
        if (_audience.isNotEmpty) 'audience': _audience,
        'screen_hint': isSignup ? 'signup' : 'login',
      },
    );
    return user != null;
  }

  @override
  Future<String> getAccessToken(
    List<String> scopes, {
    bool forceRefresh = false,
  }) async {
    await _initialize();
    try {
      final accessToken = await _manager.getAccessToken(
        forceRefresh: forceRefresh,
      );
      if (accessToken == null) {
        throw const GroveException('unauthenticated', 'Sign in again');
      }
      final token = _manager.currentUser?.token;
      if ((forceRefresh && _manager.isInOfflineMode) ||
          (token != null &&
              token.expiresIn != null &&
              token.isAccessTokenAboutToExpire(tolerance: Duration.zero))) {
        // Offline restoration can return the cached token after a transient
        // exchange failure. Keep the local identity until Auth0 rejects it.
        throw const GroveOffline('Could not renew the Auth0 session');
      }
      return accessToken;
    } on OidcInteractionRequiredException {
      throw const GroveException('unauthenticated', 'Sign in again');
    }
  }

  @override
  Future<void> trySilentLogin() async {
    if (_initializing case final initialization?) return initialization;
    final manager = _manager;
    final store = manager.store;
    await store.init();
    final hasSession =
        await store.get(
          OidcStoreNamespace.secureTokens,
          key: OidcConstants_Store.currentToken,
          managerId: manager.id,
        ) !=
        null;
    // Let the SDK handle a browser return even if this is the first login.
    if (hasSession ||
        (await store.getStatesWithResponses()).isNotEmpty ||
        await store.getCurrentFrontChannelLogoutRequest() != null) {
      await _initialize();
    }
  }

  @override
  Future<void> logout({bool federated = false}) async {
    if (federated && _manager.currentUser != null) {
      try {
        await _manager.logout(
          postLogoutRedirectUriOverride: _postLogoutRedirectUri,
        );
      } catch (error) {
        debugPrint('OIDC federated logout error (non-fatal): $error');
      }
    }

    await _manager.forgetUser();
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _manager.dispose();
  }
}

String? _stringClaim(Map<String, dynamic> claims, String name) {
  final value = claims[name];
  return value is String && value.isNotEmpty ? value : null;
}

bool? _boolClaim(Map<String, dynamic> claims, String name) {
  final value = claims[name];
  if (value is bool) return value;
  if (value is String) return bool.tryParse(value);
  return null;
}

Uri? _uriClaim(Map<String, dynamic> claims, String name) {
  final value = _stringClaim(claims, name);
  if (value == null) return null;
  return Uri.tryParse(value);
}
