import 'dart:convert';
import 'dart:io';

import 'package:grove/grove.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/device_credentials_provider.dart';
import 'package:services/providers/secure_storage_provider.dart';

part 'device_auth_service.g.dart';

const _keyClientId = 'bearimetric_device_client_id';
const _keyClientSecret = 'bearimetric_device_client_secret';
const _keyDomain = 'bearimetric_device_domain';
const _keyAudience = 'bearimetric_device_audience';

typedef _DeviceCredentials = ({
  String clientId,
  String clientSecret,
  String domain,
  String audience,
});

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
  Future<String>? _tokenRequest;
  int _credentialsRevision = 0;

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
        await _saveCredentials((
          clientId: raw['clientId'] as String,
          clientSecret: raw['clientSecret'] as String,
          domain: raw['domain'] as String,
          audience: raw['audience'] as String,
        ));
        await file.delete();
      }
    } catch (_) {
      // Malformed or unreadable file — ignore and fall through to normal init.
      // Best-effort delete so a corrupt file doesn't block every future launch.
      try {
        final dir = await getApplicationDocumentsDirectory();
        await File(p.join(dir.path, _pendingCredentialsFile)).delete();
      } catch (_) {}
    }

    final credentials = await _readCredentials();
    notifier.setStatus(
      credentials == null
          ? AuthStatus.unauthenticated
          : AuthStatus.authenticated,
    );
  }

  Future<String?> groveSubject() async {
    final clientId = await _storage.read(key: _keyClientId);
    return clientId == null ? null : '$clientId@clients';
  }

  /// Shares the token exchange across startup, requests and reconnects.
  Future<String> getAccessToken({bool forceRefresh = false}) {
    if (_tokenRequest case final pending?) return pending;
    if (_cachedToken case final token? when !forceRefresh && token.isValid) {
      return Future.value(token.token);
    }
    final revision = _credentialsRevision;
    return _tokenRequest = _loadToken(revision).whenComplete(() {
      if (revision == _credentialsRevision) _tokenRequest = null;
    });
  }

  Future<String> _loadToken(int revision) async {
    final credentials = await _readCredentials();
    if (credentials == null) {
      throw const GroveException('unauthenticated', 'Provision this device');
    }
    final token = await _exchangeToken(credentials);
    if (revision != _credentialsRevision) throw const GroveOffline();
    _cachedToken = token;
    return token.token;
  }

  Future<_DeviceCredentials?> _readCredentials() async {
    final clientId = await _storage.read(key: _keyClientId);
    final clientSecret = await _storage.read(key: _keyClientSecret);
    final domain = await _storage.read(key: _keyDomain);
    final audience = await _storage.read(key: _keyAudience);
    if (clientId == null ||
        clientSecret == null ||
        domain == null ||
        audience == null) {
      return null;
    }
    return (
      clientId: clientId,
      clientSecret: clientSecret,
      domain: domain,
      audience: audience,
    );
  }

  Future<_CachedToken> _exchangeToken(_DeviceCredentials credentials) async {
    final response = await http
        .post(
          Uri.https(credentials.domain, '/oauth/token'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_id': credentials.clientId,
            'client_secret': credentials.clientSecret,
            'audience': credentials.audience,
            'grant_type': 'client_credentials',
          }),
        )
        .timeout(const Duration(seconds: 10));

    final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const GroveOffline('Could not reach the device token service');
    }
    if (payload is! Map<String, dynamic>) {
      throw const GroveOffline('Could not reach the device token service');
    }
    if (response.statusCode != 200) {
      if (const {
        'access_denied',
        'invalid_client',
        'invalid_grant',
        'unauthorized_client',
      }.contains(payload['error'])) {
        throw const GroveException(
          'unauthenticated',
          'Device credentials were rejected',
        );
      }
      throw const GroveOffline('Could not renew the device token');
    }

    return _CachedToken(
      payload['access_token'] as String,
      DateTime.now().add(Duration(seconds: payload['expires_in'] as int)),
    );
  }

  Future<void> _saveCredentials(_DeviceCredentials credentials) async {
    _clearToken();
    await Future.wait([
      _storage.write(key: _keyClientId, value: credentials.clientId),
      _storage.write(key: _keyClientSecret, value: credentials.clientSecret),
      _storage.write(key: _keyDomain, value: credentials.domain),
      _storage.write(key: _keyAudience, value: credentials.audience),
    ]);
  }

  void _clearToken() {
    _credentialsRevision++;
    _cachedToken = null;
    _tokenRequest = null;
  }

  /// Validate new credentials before replacing the device enrollment.
  Future<void> provision({
    required String clientId,
    required String clientSecret,
    required String domain,
    required String audience,
  }) async {
    final credentials = (
      clientId: clientId,
      clientSecret: clientSecret,
      domain: domain,
      audience: audience,
    );
    final token = await _exchangeToken(credentials);
    await _saveCredentials(credentials);
    _cachedToken = token;
    _ref.read(authStatusProvider.notifier).setStatus(AuthStatus.authenticated);
  }

  /// Clears all stored credentials and marks the device as unauthenticated.
  Future<void> deprovision() async {
    _ref
        .read(authStatusProvider.notifier)
        .setStatus(AuthStatus.unauthenticated);
    _clearToken();
    await Future.wait([
      _storage.delete(key: _keyClientId),
      _storage.delete(key: _keyClientSecret),
      _storage.delete(key: _keyDomain),
      _storage.delete(key: _keyAudience),
    ]);
  }
}
