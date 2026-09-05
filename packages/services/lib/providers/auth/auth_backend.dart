/// Abstract interface for the OIDC authentication backend.
abstract class AuthBackend {
  /// Launches browser-based OIDC login.
  Future<void> login(List<String> scopes, {bool isSignup = false});

  /// Returns a valid access token for the given [scopes], refreshing if needed.
  Future<String> getAccessToken(List<String> scopes);

  /// Attempts to restore a previous session from stored credentials
  /// without showing a browser.
  Future<void> trySilentLogin();

  /// Logs out, optionally clearing the federated OIDC session.
  Future<void> logout({bool federated = false});

  /// The current user's profile, populated after [login] or [trySilentLogin].
  AuthUser? get user;

  /// Releases any resources held by the backend.
  Future<void> dispose();
}

/// Lightweight user profile from the Auth backend.
///
/// Populated from the OIDC ID token or the /userinfo endpoint. Does not contain
/// binary photo data — that is
/// loaded separately by [userInfoProvider].
class AuthUser {
  final String? name;
  final String? email;
  final bool? emailVerified;
  final Uri? pictureUrl;
  final String? nickname;

  const AuthUser({
    this.name,
    this.email,
    this.emailVerified,
    this.pictureUrl,
    this.nickname,
  });
}
