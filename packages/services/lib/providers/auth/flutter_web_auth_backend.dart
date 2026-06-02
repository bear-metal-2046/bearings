import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:services/providers/auth/auth_backend.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/secure_storage_provider.dart';

/// Linux (and general fallback) auth backend using manual PKCE via
/// [FlutterWebAuth2].
///
/// This is the only backend that works on Linux since `auth0_flutter`
/// does not support that platform.  It implements the OAuth 2.0
/// Authorization Code flow with PKCE directly, stores refresh tokens
/// in [TokenStorage], and fetches user info from the Auth0 `/userinfo`
/// endpoint.
class FlutterWebAuthBackend implements AuthBackend {
  final TokenStorage _storage;
  final Auth0Config _config;
  final String _redirectUri;

  final Map<String, OAuthToken> _tokenCache = {};
  AuthUser? _user;

  FlutterWebAuthBackend({
    required TokenStorage storage,
    required Auth0Config config,
    required String redirectUri,
  }) : _storage = storage,
       _config = config,
       _redirectUri = redirectUri;

  // ---------------------------------------------------------------------------
  // AuthBackend
  // ---------------------------------------------------------------------------

  @override
  AuthUser? get user => _user;

  @override
  Future<void> login(List<String> scopes, {bool isSignup = false}) async {
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallenge(verifier);

    final requestScopes = {
      ...scopes,
      'offline_access',
      'openid',
      'profile',
      'email',
    }.join(' ');

    final authUrl = _config.authorizeEndpoint.replace(
      queryParameters: {
        'client_id': _config.clientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'scope': requestScopes,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'audience': _config.audience,
        if (isSignup) 'screen_hint': 'signup',
        if (!isSignup) 'screen_hint': 'login',
      },
    );

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: _redirectUri == 'http://localhost:4000/auth'
          ? _redirectUri
          : Uri.parse(_redirectUri).scheme,
      options: const FlutterWebAuth2Options(useWebview: false),
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) {
      throw Exception('No authorization code received');
    }

    final token = await _exchangeCode(code, verifier);
    await _persistRefreshToken(token.refreshToken);
    _tokenCache[scopes.join(' ')] = token;
    await _fetchAuthUser(token.accessToken);
  }

  @override
  Future<String> getAccessToken(List<String> scopes) async {
    final scopeKey = scopes.join(' ');

    final cached = _tokenCache[scopeKey];
    if (cached != null && !cached.isExpired) {
      return cached.accessToken;
    }

    // Try any valid cached token across scope keys.
    final anyValid = _tokenCache.values.where((t) => !t.isExpired).firstOrNull;
    if (anyValid != null) {
      _tokenCache[scopeKey] = anyValid;
      return anyValid.accessToken;
    }

    final refreshToken = await _storage.read(key: _config.refreshTokenKey);
    if (refreshToken == null) {
      throw Exception('Session expired (No refresh token)');
    }

    try {
      final newToken = await _fetchNewToken(refreshToken, scopes);

      if (newToken.refreshToken != null) {
        await _persistRefreshToken(newToken.refreshToken);
      }

      _tokenCache[scopeKey] = newToken;
      return newToken.accessToken;
    } catch (e) {
      // Refresh failed — clear session.
      await logout();
      throw Exception('Failed to refresh token: $e');
    }
  }

  @override
  Future<void> trySilentLogin() async {
    final refreshToken = await _storage.read(key: _config.refreshTokenKey);
    if (refreshToken == null) return;

    try {
      await getAccessToken(['openid', 'profile', 'email']);

      // Fetch user profile if we don't have one yet (e.g. after app restart).
      if (_user == null) {
        final token = _tokenCache['openid profile email'];
        if (token != null) {
          await _fetchAuthUser(token.accessToken);
        }
      }
    } catch (e) {
      await logout();
      rethrow;
    }
  }

  @override
  Future<void> logout({bool federated = false}) async {
    if (federated) {
      try {
        final logoutUrl = _config.logoutUri(_redirectUri);
        await FlutterWebAuth2.authenticate(
          url: logoutUrl.toString(),
          callbackUrlScheme: _redirectUri == 'http://localhost:4000/auth'
              ? _redirectUri
              : Uri.parse(_redirectUri).scheme,
          options: const FlutterWebAuth2Options(useWebview: false),
        );
      } catch (_) {
        // Swallow browser errors during federated logout.
      }
    }

    _tokenCache.clear();
    _user = null;
    await _storage.deleteAll();
  }

  @override
  Future<void> dispose() async {
    _tokenCache.clear();
    _user = null;
  }

  // ---------------------------------------------------------------------------
  // Token exchange helpers
  // ---------------------------------------------------------------------------

  Future<void> _persistRefreshToken(String? token) async {
    if (token != null) {
      await _storage.write(key: _config.refreshTokenKey, value: token);
    }
  }

  Future<OAuthToken> _exchangeCode(String code, String verifier) async {
    return _postRequest({
      'client_id': _config.clientId,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': _redirectUri,
      'code_verifier': verifier,
    });
  }

  Future<OAuthToken> _fetchNewToken(
    String refreshToken,
    List<String> scopes,
  ) async {
    return _postRequest({
      'client_id': _config.clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'scope': scopes.join(' '),
    });
  }

  Future<OAuthToken> _postRequest(Map<String, String> body) async {
    final response = await http.post(
      _config.tokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      payload = null;
    }

    if (response.statusCode != 200) {
      final description =
          payload?['error_description'] ?? payload?['error'] ?? response.body;
      throw Exception('Auth Error: HTTP ${response.statusCode} $description');
    }

    if (payload == null) {
      throw Exception('Auth Error: Invalid JSON response: ${response.body}');
    }

    return OAuthToken.fromJson(payload);
  }

  // ---------------------------------------------------------------------------
  // User profile (fetched from /userinfo for non-auth0_flutter platforms)
  // ---------------------------------------------------------------------------

  Future<void> _fetchAuthUser(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://${_config.domain}/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _user = AuthUser(
          name: data['name'] as String?,
          email: data['email'] as String?,
          emailVerified: data['email_verified'] as bool?,
          pictureUrl: data['picture'] != null
              ? Uri.tryParse(data['picture'] as String)
              : null,
          nickname: data['nickname'] as String?,
        );

        // Persist so it's available offline.
        await _storage.write(
          key: '${_config.storageKeyPrefix}user_profile',
          value: jsonEncode(data),
        );
      }
    } catch (e) {
      debugPrint('Failed to fetch user profile: $e');
      // Try to restore from cache.
      final cached = await _storage.read(
        key: '${_config.storageKeyPrefix}user_profile',
      );
      if (cached != null) {
        try {
          final data = jsonDecode(cached) as Map<String, dynamic>;
          _user = AuthUser(
            name: data['name'] as String?,
            email: data['email'] as String?,
            emailVerified: data['email_verified'] as bool?,
            pictureUrl: data['picture'] != null
                ? Uri.tryParse(data['picture'] as String)
                : null,
            nickname: data['nickname'] as String?,
          );
        } catch (_) {
          // Ignore corrupt cache.
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PKCE helpers
  // ---------------------------------------------------------------------------

  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    return List.generate(64, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _codeChallenge(String verifier) {
    return base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
  }
}
