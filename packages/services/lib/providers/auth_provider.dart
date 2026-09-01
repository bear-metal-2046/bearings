import 'dart:convert';
import 'dart:math';

import 'package:core/providers/device_info_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/secure_storage_provider.dart';

part 'auth_provider.g.dart';

class Auth0Config {
  final String domain;
  final String clientId;
  final String audience;
  final Map<DeviceOS, String> redirectUris;
  final String storageKeyPrefix;

  const Auth0Config({
    required this.domain,
    required this.clientId,
    required this.audience,
    required this.redirectUris,
    this.storageKeyPrefix = '',
  });

  String get refreshTokenKey => '${storageKeyPrefix}refresh_token';

  Uri get authorizeEndpoint => Uri.parse('https://$domain/authorize');

  Uri get tokenEndpoint => Uri.parse('https://$domain/oauth/token');

  Uri logoutUri(String returnTo) => Uri.parse('https://$domain/v2/logout')
      .replace(queryParameters: {'client_id': clientId, 'returnTo': returnTo});
}

enum AuthStatus { authenticated, unauthenticated, authenticating }

@Riverpod(keepAlive: true)
class AuthStatusNotifier extends _$AuthStatusNotifier implements Listenable {
  VoidCallback? _routerListener;

  @override
  AuthStatus build() => AuthStatus.unauthenticated;

  void setStatus(AuthStatus status) {
    if (state != status) {
      state = status;
      notify();
    }
  }

  void notify() => _routerListener?.call();

  @override
  void addListener(VoidCallback listener) => _routerListener = listener;

  @override
  void removeListener(VoidCallback listener) {
    if (_routerListener == listener) _routerListener = null;
  }
}

@Riverpod(keepAlive: true)
Auth0Config auth0Config(Ref ref) {
  throw UnimplementedError(
    'auth0ConfigProvider must be overridden with app-specific configuration',
  );
}

@Riverpod(keepAlive: true)
Future<Auth> auth(Ref ref) async {
  final storage = await ref.watch(tokenStorageProvider.future);
  final deviceInfo = ref.watch(deviceInfoProvider);
  final config = ref.watch(auth0ConfigProvider);

  final redirectUri = config.redirectUris[deviceInfo.deviceOS];

  if (redirectUri == null) {
    throw Exception('No redirect URI configured for ${deviceInfo.deviceOS}');
  }

  return Auth(
    ref: ref,
    storage: storage,
    config: config,
    redirectUri: redirectUri,
  );
}

class Auth {
  final Ref ref;
  final TokenStorage storage;
  final Auth0Config config;
  final String redirectUri;

  final Map<String, OAuthToken> _tokenCache = {};

  Auth({
    required this.ref,
    required this.storage,
    required this.config,
    required this.redirectUri,
  });

  Future<void> login(List<String> scopes, {bool isSignup = false}) async {
    _setStatus(AuthStatus.authenticating);

    if (!await checkOnline(ref)) {
      _setStatus(AuthStatus.unauthenticated);
      throw OfflineAuthException('No internet connection available to login.');
    }

    try {
      final verifier = _generateCodeVerifier();
      final challenge = _codeChallenge(verifier);

      final requestScopes = {
        ...scopes,
        'offline_access',
        'openid',
        'profile',
        'email',
      }.join(' ');

      final authUrl = config.authorizeEndpoint.replace(
        queryParameters: {
          'client_id': config.clientId,
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'scope': requestScopes,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'audience': config.audience,
          if (isSignup) 'screen_hint': 'signup',
          if (!isSignup) 'screen_hint': 'login',
        },
      );

      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: redirectUri == 'http://localhost:4000/auth'
            ? redirectUri
            : Uri.parse(redirectUri).scheme,
        options: const FlutterWebAuth2Options(useWebview: false),
      );

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) throw Exception('No authorization code received');

      final token = await _exchangeCode(code, verifier);

      await _persistRefreshToken(token.refreshToken);
      _tokenCache[scopes.join(' ')] = token;
      _setStatus(AuthStatus.authenticated);
    } catch (e) {
      debugPrint('Login Error: $e');
      _setStatus(AuthStatus.unauthenticated);
      rethrow;
    }
  }

  Future<String> getAccessToken(List<String> scopes) async {
    final scopeKey = scopes.join(' ');

    final cached = _tokenCache[scopeKey];
    if (cached != null && !cached.isExpired) {
      return cached.accessToken;
    }

    final anyValid = _tokenCache.values.where((t) => !t.isExpired).firstOrNull;
    if (anyValid != null) {
      _tokenCache[scopeKey] = anyValid;
      return anyValid.accessToken;
    }

    final refreshToken = await storage.read(key: config.refreshTokenKey);
    if (refreshToken == null) {
      await logout();
      throw Exception('Session expired (No refresh token)');
    }

    if (!await checkOnline(ref)) {
      throw OfflineAuthException(
        'No internet connection: Cannot get access token',
      );
    }

    try {
      final newToken = await _fetchNewToken(refreshToken, scopes);

      if (newToken.refreshToken != null) {
        await _persistRefreshToken(newToken.refreshToken);
      }

      _tokenCache[scopeKey] = newToken;

      return newToken.accessToken;
    } catch (e) {
      await logout();
      throw Exception('Failed to refresh token: $e');
    }
  }

  Future<void> trySilentLogin() async {
    _setStatus(AuthStatus.authenticating);

    final refreshToken = await storage.read(key: config.refreshTokenKey);

    if (refreshToken == null) {
      _setStatus(AuthStatus.unauthenticated);
      return;
    }

    if (!await checkOnline(ref)) {
      _setStatus(AuthStatus.authenticated);
      return;
    }

    try {
      await getAccessToken(['openid', 'profile', 'email']);
      _setStatus(AuthStatus.authenticated);
    } catch (e) {
      await logout();
    }
  }

  Future<void> logout({bool federated = false}) async {
    if (federated) {
      try {
        final logoutUrl = config.logoutUri(redirectUri);
        await FlutterWebAuth2.authenticate(
          url: logoutUrl.toString(),
          callbackUrlScheme: redirectUri == 'http://localhost:4000/auth'
              ? redirectUri
              : Uri.parse(redirectUri).scheme,
          options: const FlutterWebAuth2Options(useWebview: false),
        );
      } catch (_) {}
    }

    try {
      await Hive.box<dynamic>('api_cache').clear();
    } catch (_) {}

    _tokenCache.clear();
    await storage.deleteAll();
    _setStatus(AuthStatus.unauthenticated);
  }

  void _setStatus(AuthStatus status) {
    ref.read(authStatusProvider.notifier).setStatus(status);
  }

  Future<void> _persistRefreshToken(String? token) async {
    if (token != null) {
      await storage.write(key: config.refreshTokenKey, value: token);
    }
  }

  Future<OAuthToken> _exchangeCode(String code, String verifier) async {
    return _postRequest({
      'client_id': config.clientId,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
    });
  }

  Future<OAuthToken> _fetchNewToken(
    String refreshToken,
    List<String> scopes,
  ) async {
    return _postRequest({
      'client_id': config.clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'scope': scopes.join(' '),
    });
  }

  Future<OAuthToken> _postRequest(Map<String, String> body) async {
    final response = await http.post(
      config.tokenEndpoint,
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

  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    return List.generate(64, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _codeChallenge(String verifier) {
    return base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
  }
}

class OAuthToken {
  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;

  OAuthToken({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(
    expiresAt.subtract(const Duration(minutes: 2)),
  );

  factory OAuthToken.fromJson(Map<String, dynamic> json) {
    return OAuthToken(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: (json['expires_in'] as num).toInt()),
      ),
    );
  }
}

class OfflineAuthException implements Exception {
  final String message;

  OfflineAuthException([this.message = 'No internet connection available']);

  @override
  String toString() => 'OfflineAuthException: $message';
}
