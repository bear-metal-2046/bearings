import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';
import 'package:services/providers/auth/auth_backend.dart';
import 'package:services/providers/auth_provider.dart';

/// OpenID Connect authentication backend used on every supported platform.
///
/// This uses the `oidc` package's platform integrations instead of manually
/// assembling the authorization-code and PKCE flow.
class OidcAuthBackend implements AuthBackend {
  final OidcUserManager _manager;
  final Uri _postLogoutRedirectUri;
  final String _audience;

  OidcAuthBackend({required Auth0Config config, required Uri redirectUri})
    : _postLogoutRedirectUri = redirectUri,
      _audience = config.audience,
      _manager = OidcUserManager.lazy(
        id: '${config.storageKeyPrefix}experimental_oidc',
        discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(
          Uri.parse('https://${config.domain}'),
        ),
        clientCredentials: OidcClientAuthentication.none(
          clientId: config.clientId,
        ),
        store: OidcDefaultStore(
          storagePrefix: '${config.storageKeyPrefix}oidc',
          secureStorageInstance: const FlutterSecureStorage(),
        ),
        settings: OidcUserManagerSettings(
          redirectUri: redirectUri,
          postLogoutRedirectUri: redirectUri,
          scope: const ['openid', 'profile', 'email', 'offline_access'],
          supportOfflineAuth: true,
        ),
      );

  /// Initializes discovery and restores any cached OIDC session.
  Future<void> init() => _manager.init();

  @override
  AuthUser? get user {
    final oidcUser = _manager.currentUser;
    if (oidcUser == null) return null;

    final claims = oidcUser.aggregatedClaims;
    return AuthUser(
      name: _stringClaim(claims, 'name'),
      email: _stringClaim(claims, 'email'),
      emailVerified: _boolClaim(claims, 'email_verified'),
      pictureUrl: _uriClaim(claims, 'picture'),
      nickname: _stringClaim(claims, 'nickname'),
    );
  }

  @override
  Future<void> login(List<String> scopes, {bool isSignup = false}) async {
    final requestedScopes = {
      ...scopes,
      'openid',
      'profile',
      'email',
      'offline_access',
    }.toList();

    await _manager.loginAuthorizationCodeFlow(
      scopeOverride: requestedScopes,
      // `audience` and `screen_hint` are Auth0 extensions. Keeping them here
      // preserves the existing Auth0Config behavior while the flow itself is
      // handled as standard OIDC by the package.
      extraParameters: {
        if (_audience.isNotEmpty) 'audience': _audience,
        'screen_hint': isSignup ? 'signup' : 'login',
      },
    );
  }

  @override
  Future<String> getAccessToken(List<String> scopes) async {
    final accessToken = await _manager.getAccessToken();
    if (accessToken == null) {
      throw StateError('No authenticated OIDC session is available.');
    }
    return accessToken;
  }

  @override
  Future<void> trySilentLogin() async {
    await _manager.init();
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
  Future<void> dispose() => _manager.dispose();
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
