import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:auth0_flutter/auth0_flutter_web.dart';
import 'package:services/providers/auth/auth_backend.dart';

/// Auth backend for Web using the official `auth0_flutter` SDK.
class Auth0WebBackend implements AuthBackend {
  final Auth0Web _auth0;
  Credentials? _credentials;

  Auth0WebBackend({required String domain, required String clientId})
    : _auth0 = Auth0Web(domain, clientId);

  @override
  AuthUser? get user => _credentials?.user.toAuthUser();

  @override
  Future<void> login(List<String> scopes, {bool isSignup = false}) async {
    // pops up in a small window outside of the website
    _credentials = await _auth0.loginWithPopup(
      scopes: {...scopes, 'openid', 'profile', 'email', 'offline_access'},
      parameters: {if (isSignup) 'screen_hint': 'signup'},
    );
  }

  @override
  Future<String> getAccessToken(List<String> scopes) async {
    // credentials() returns cached credentials or auto-refreshes.
    _credentials = await _auth0.credentials();
    return _credentials!.accessToken;
  }

  @override
  Future<void> trySilentLogin() async {
    _credentials = await _auth0.onLoad();
  }

  @override
  Future<void> logout({bool federated = false}) async {
    await _auth0.logout(returnToUrl: Uri.base.origin);
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
