/// Abstract interface for the OIDC authentication backend.
abstract class AuthBackend {
  /// Launches browser-based OIDC login and reports if it returned a user.
  Future<bool> login(List<String> scopes, {bool isSignup = false});

  /// Returns a valid access token for the given [scopes], refreshing if needed.
  Future<String> getAccessToken(
    List<String> scopes, {
    bool forceRefresh = false,
  });

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

/// Lightweight user profile from the OIDC sign-in session.
///
/// Shared profile fields are loaded from Grove by [userInfoProvider].
class AuthUser {
  final String? subject;
  final String? name;
  final String? email;
  final bool? emailVerified;
  final Uri? pictureUrl;
  final String? nickname;

  const AuthUser({
    this.subject,
    this.name,
    this.email,
    this.emailVerified,
    this.pictureUrl,
    this.nickname,
  });
}
