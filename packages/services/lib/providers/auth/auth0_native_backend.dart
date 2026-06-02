import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:services/providers/auth/auth_backend.dart';

/// Auth backend for Android, iOS, and macOS using the official `auth0_flutter` SDK.
///
/// Uses the SDK's built-in redirect URI construction: `{scheme}://{domain}/android/{package}/callback`
/// on Android and `{scheme}://{domain}/ios/{bundleId}/callback` on iOS/macOS.
/// The [scheme] controls the URL scheme portion of the redirect URI.
class Auth0NativeBackend implements AuthBackend {
  final Auth0 _auth0;
  final String? _scheme;
  final String? _audience;
  Credentials? _credentials;

  Auth0NativeBackend({
    required String domain,
    required String clientId,
    String? scheme,
    String? audience,
  }) : _auth0 = Auth0(domain, clientId),
       _scheme = scheme,
       _audience = audience;

  @override
  AuthUser? get user => _credentials?.user.toAuthUser();

  @override
  Future<void> login(List<String> scopes, {bool isSignup = false}) async {
    _credentials = await _auth0
        .webAuthentication(scheme: _scheme)
        .login(
          audience: _audience,
          scopes: {...scopes, 'openid', 'profile', 'email', 'offline_access'},
        );
  }

  @override
  Future<String> getAccessToken(List<String> scopes) async {
    // credentials() auto-refreshes if expired and a refresh token is
    // available.  It may throw if the session has expired and no refresh
    // token exists, or if the device is offline and the token is expired.
    _credentials = await _auth0.credentialsManager.credentials();
    return _credentials!.accessToken;
  }

  @override
  Future<void> trySilentLogin() async {
    final hasValid = await _auth0.credentialsManager.hasValidCredentials();
    if (!hasValid) return;

    try {
      _credentials = await _auth0.credentialsManager.credentials();
    } catch (e) {
      debugPrint('Silent login failed: $e');
      await _auth0.credentialsManager.clearCredentials();
      rethrow;
    }
  }

  @override
  Future<void> logout({bool federated = false}) async {
    if (federated) {
      try {
        await _auth0
            .webAuthentication(scheme: _scheme)
            .logout(federated: federated);
      } catch (e) {
        debugPrint('Federated logout error (non-fatal): $e');
      }
    }

    await _auth0.credentialsManager.clearCredentials();
    _credentials = null;
  }

  @override
  Future<void> dispose() async {
    _credentials = null;
  }
}

extension on UserProfile {
  AuthUser toAuthUser() => AuthUser(
    name: name,
    email: email,
    emailVerified: isEmailVerified,
    pictureUrl: pictureUrl,
    nickname: nickname,
  );
}
