import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:services/providers/auth/auth_backend.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/secure_storage_provider.dart';

/// Auth backend for Windows using the official `auth0_flutter` SDK.
///
/// Uses [WindowsWebAuthentication] for login/logout.  The SDK does not
/// provide a [CredentialsManager] on Windows, so refresh tokens are stored
/// manually via [TokenStorage] and refreshed through the SDK's HTTP API
/// ([AuthenticationApi.renewCredentials]).
class Auth0WindowsBackend implements AuthBackend {
  final Auth0 _auth0;
  final TokenStorage _storage;
  final String _appCustomUrl;
  final String _storageKeyPrefix;

  Credentials? _credentials;
  AuthUser? _authUser;
  final Map<String, OAuthToken> _tokenCache = {};

  Auth0WindowsBackend({
    required String domain,
    required String clientId,
    required String appCustomUrl,
    required TokenStorage storage,
    String storageKeyPrefix = '',
  }) : _auth0 = Auth0(domain, clientId),
       _storage = storage,
       _appCustomUrl = appCustomUrl,
       _storageKeyPrefix = storageKeyPrefix;

  String get _refreshTokenKey => '${_storageKeyPrefix}refresh_token';

  // ---------------------------------------------------------------------------
  // AuthBackend
  // ---------------------------------------------------------------------------

  @override
  AuthUser? get user => _authUser;

  @override
  Future<void> login(List<String> scopes, {bool isSignup = false}) async {
    _credentials = await _auth0.windowsWebAuthentication().login(
      scopes: {...scopes, 'openid', 'profile', 'email', 'offline_access'},
      appCustomURL: _appCustomUrl,
    );

    // Store refresh token manually (no CredentialsManager on Windows).
    if (_credentials!.refreshToken != null) {
      await _storage.write(
        key: _refreshTokenKey,
        value: _credentials!.refreshToken,
      );
    }

    _authUser = _credentials!.user.toAuthUser();
  }

  @override
  Future<String> getAccessToken(List<String> scopes) async {
    final scopeKey = scopes.join(' ');

    // Check in-memory cache.
    final cached = _tokenCache[scopeKey];
    if (cached != null && !cached.isExpired) {
      return cached.accessToken;
    }

    // Any cached token will do.
    final anyValid = _tokenCache.values.where((t) => !t.isExpired).firstOrNull;
    if (anyValid != null) {
      _tokenCache[scopeKey] = anyValid;
      return anyValid.accessToken;
    }

    // Need to refresh.
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) {
      throw Exception('Session expired (No refresh token)');
    }

    try {
      final newCredentials = await _auth0.api.renewCredentials(
        refreshToken: refreshToken,
        scopes: {...scopes},
      );

      // Rotate refresh token if a new one was issued.
      if (newCredentials.refreshToken != null) {
        await _storage.write(
          key: _refreshTokenKey,
          value: newCredentials.refreshToken,
        );
      }

      _credentials = newCredentials;
      _authUser = newCredentials.user.toAuthUser();

      _tokenCache[scopeKey] = OAuthToken(
        accessToken: newCredentials.accessToken,
        expiresAt: newCredentials.expiresAt,
        refreshToken: newCredentials.refreshToken,
      );

      return newCredentials.accessToken;
    } catch (e) {
      await logout();
      throw Exception('Failed to refresh token: $e');
    }
  }

  @override
  Future<void> trySilentLogin() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return;

    try {
      await getAccessToken(['openid', 'profile', 'email']);
    } catch (e) {
      await logout();
      rethrow;
    }
  }

  @override
  Future<void> logout({bool federated = false}) async {
    if (federated) {
      try {
        await _auth0.windowsWebAuthentication().logout(
          appCustomURL: _appCustomUrl,
          federated: true,
        );
      } catch (e) {
        debugPrint('Federated logout error (non-fatal): $e');
      }
    }

    _tokenCache.clear();
    _credentials = null;
    _authUser = null;
    await _storage.deleteAll();
  }

  @override
  Future<void> dispose() async {
    _tokenCache.clear();
    _credentials = null;
    _authUser = null;
  }
}

// ---------------------------------------------------------------------------
// Mapping from auth0_flutter's UserProfile to our lightweight model
// ---------------------------------------------------------------------------

extension on UserProfile {
  AuthUser toAuthUser() => AuthUser(
    name: name,
    email: email,
    emailVerified: isEmailVerified,
    pictureUrl: pictureUrl,
    nickname: nickname,
  );
}
