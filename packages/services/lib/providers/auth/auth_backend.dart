/// Abstract interface for platform-specific Auth0 authentication backends.
///
/// Each platform (native mobile, desktop, web) provides its own implementation
/// using the most appropriate SDK:
/// - Android/iOS/macOS: [Auth0NativeBackend] via `auth0_flutter` `webAuthentication()`
/// - Windows: [Auth0WindowsBackend] via `auth0_flutter` `windowsWebAuthentication()`
/// - Web: [Auth0WebBackend] via `auth0_flutter` `Auth0Web`
/// - Linux: [FlutterWebAuthBackend] via `flutter_web_auth_2` (manual PKCE)
abstract class AuthBackend {
  /// Launches browser-based Auth0 Universal Login.
  Future<void> login(List<String> scopes, {bool isSignup = false});

  /// Returns a valid access token for the given [scopes], refreshing if needed.
  Future<String> getAccessToken(List<String> scopes);

  /// Attempts to restore a previous session from stored credentials
  /// without showing a browser.
  Future<void> trySilentLogin();

  /// Logs out, optionally clearing the federated Auth0 session.
  Future<void> logout({bool federated = false});

  /// The current user's profile, populated after [login] or [trySilentLogin].
  AuthUser? get user;

  /// Releases any resources held by the backend.
  Future<void> dispose();
}

/// Lightweight user profile from the Auth backend.
///
/// Populated from the ID token (auth0_flutter) or the /userinfo endpoint
/// (FlutterWebAuth2).  Does not contain binary photo data — that is
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
