import 'package:services/providers/auth/auth_backend.dart';

/// Stub implementation that throws [UnsupportedError] when instantiated
/// on a non-web platform.  Replaced by the real [Auth0WebBackend] when
/// `dart.library.js` is available (i.e. on the web).
class Auth0WebBackend implements AuthBackend {
  Auth0WebBackend({required String domain, required String clientId}) {
    throw UnsupportedError(
      'Auth0WebBackend is only available on the web platform',
    );
  }

  @override
  Future<void> login(List<String> scopes, {bool isSignup = false}) {
    throw UnsupportedError('Auth0WebBackend is only available on the web');
  }

  @override
  Future<String> getAccessToken(List<String> scopes) {
    throw UnsupportedError('Auth0WebBackend is only available on the web');
  }

  @override
  Future<void> trySilentLogin() {
    throw UnsupportedError('Auth0WebBackend is only available on the web');
  }

  @override
  Future<void> logout({bool federated = false}) {
    throw UnsupportedError('Auth0WebBackend is only available on the web');
  }

  @override
  AuthUser? get user => null;

  @override
  Future<void> dispose() async {}
}
