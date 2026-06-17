import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/device_credentials_provider.dart';
import 'package:services/providers/secure_storage_provider.dart';

part 'device_auth_service.g.dart';

const _keyClientId = 'pawfinder_device_client_id';
const _keyClientSecret = 'pawfinder_device_client_secret';
const _keyDomain = 'pawfinder_device_domain';
const _keyAudience = 'pawfinder_device_audience';

class _CachedToken {
  final String token;
  final DateTime expiresAt;

  _CachedToken(this.token, this.expiresAt);

  bool get isValid =>
      DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 2)));
}

@Riverpod(keepAlive: true)
Future<DeviceAuthService> deviceAuthService(Ref ref) async {
  final storage = await ref.watch(tokenStorageProvider.future);
  return DeviceAuthService(ref, storage);
}

class DeviceAuthService {
  final Ref _ref;
  final TokenStorage _storage;
  _CachedToken? _cachedToken;

  DeviceAuthService(this._ref, this._storage);

  // Name of the file the fleet tool drops into the app's documents directory to
  // trigger automatic provisioning on the next launch.
  static const _pendingCredentialsFile = 'pending_credentials.json';

  /// Called once on app startup. Sets [AuthStatus] based on stored credentials.
  Future<void> initialize() async {
    final notifier = _ref.read(authStatusProvider.notifier);
    notifier.setStatus(AuthStatus.authenticating);

    // Check for a base64 credential payload staged by the fleet tool.
    // If found, provision automatically and delete the file so it is one-shot.
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, _pendingCredentialsFile));
      if (await file.exists()) {
        final raw = decodeProvisioningPayload(await file.readAsString());
        await provision(
          clientId: raw['clientId'] as String,
          clientSecret: raw['clientSecret'] as String,
          domain: raw['domain'] as String,
          audience: raw['audience'] as String,
        );
        await file.delete();
        return; // provision() already set AuthStatus.authenticated
      }
    } catch (_) {
      // Malformed or unreadable file — ignore and fall through to normal init.
      // Best-effort delete so a corrupt file doesn't block every future launch.
      try {
        final dir = await getApplicationDocumentsDirectory();
        await File(p.join(dir.path, _pendingCredentialsFile)).delete();
      } catch (_) {}
    }

    final clientId = await _storage.read(key: _keyClientId);
    if (clientId == null) {
      notifier.setStatus(AuthStatus.unauthenticated);
      return;
    }

    try {
      await getAccessToken();
      notifier.setStatus(AuthStatus.authenticated);
    } catch (_) {
      // Credentials stored but token fetch failed (no network or revoked).
      // Still mark authenticated so the app loads; API calls will fail loudly.
      notifier.setStatus(AuthStatus.authenticated);
    }
  }

  /// Returns a valid access token, fetching a fresh one from Auth0 when needed.
  Future<String> getAccessToken() async {
    if (_cachedToken != null && _cachedToken!.isValid) {
      return _cachedToken!.token;
    }

    final clientId = await _storage.read(key: _keyClientId);
    final clientSecret = await _storage.read(key: _keyClientSecret);
    final domain = await _storage.read(key: _keyDomain);
    final audience = await _storage.read(key: _keyAudience);

    if (clientId == null ||
        clientSecret == null ||
        domain == null ||
        audience == null) {
      throw StateError('Device credentials not provisioned');
    }

    final response = await http.post(
      Uri.https(domain, '/oauth/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': clientId,
        'client_secret': clientSecret,
        'audience': audience,
        'grant_type': 'client_credentials',
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Token request failed: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = body['access_token'] as String;
    final expiresIn = (body['expires_in'] as num).toInt();

    _cachedToken = _CachedToken(
      accessToken,
      DateTime.now().add(Duration(seconds: expiresIn)),
    );

    return accessToken;
  }

  /// Saves credentials, validates them by fetching a token, then marks the
  /// device as authenticated.
  Future<void> provision({
    required String clientId,
    required String clientSecret,
    required String domain,
    required String audience,
  }) async {
    await Future.wait([
      _storage.write(key: _keyClientId, value: clientId),
      _storage.write(key: _keyClientSecret, value: clientSecret),
      _storage.write(key: _keyDomain, value: domain),
      _storage.write(key: _keyAudience, value: audience),
    ]);
    _cachedToken = null;

    // Validate credentials now — throws if the token endpoint rejects them.
    await getAccessToken();

    _ref.read(authStatusProvider.notifier).setStatus(AuthStatus.authenticated);
  }

  /// Clears all stored credentials and marks the device as unauthenticated.
  Future<void> deprovision() async {
    await Future.wait([
      _storage.delete(key: _keyClientId),
      _storage.delete(key: _keyClientSecret),
      _storage.delete(key: _keyDomain),
      _storage.delete(key: _keyAudience),
    ]);
    _cachedToken = null;
    _ref
        .read(authStatusProvider.notifier)
        .setStatus(AuthStatus.unauthenticated);
  }
}
