import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'auth0_management.dart';
import 'picklists.dart';
import 'security.dart';

Future<Response> profile(Request request, Access access, String path) async {
  final auth0 = Auth0Management.instance;
  if (path == 'profile' && request.method == HttpMethod.patch) {
    final body = await readObject(request);
    if (body == null)
      return reply({'error': 'Invalid JSON payload'}, status: 400);
    final changes = <String, dynamic>{};
    if (body.containsKey('name') &&
        (body['name'] is! String || (body['name'] as String).trim().isEmpty)) {
      return reply({'error': 'Invalid payload'}, status: 400);
    }
    if (body['name'] is String && (body['name'] as String).trim().isNotEmpty) {
      changes['name'] = (body['name'] as String).trim();
    }
    final picture = body['picture'] is String
        ? Uri.tryParse(body['picture'] as String)
        : null;
    if (body.containsKey('picture') &&
        (picture == null ||
            picture.scheme != 'https' ||
            !picture.hasAuthority)) {
      return reply({'error': 'Invalid payload'}, status: 400);
    }
    if (picture != null && picture.scheme == 'https' && picture.hasAuthority) {
      changes['picture'] = body['picture'];
    }
    if (body.containsKey('email') &&
        (body['email'] is! String ||
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                .hasMatch(body['email'] as String))) {
      return reply({'error': 'Invalid payload'}, status: 400);
    }
    if (body['email'] is String) {
      changes['email'] = body['email'];
      changes['email_verified'] = false;
    }
    if (changes.isEmpty)
      return reply({'error': 'Invalid payload'}, status: 400);
    final updated = await auth0.updateUser(access.userId, changes) as Map;
    if (changes.containsKey('email')) {
      await auth0.call('POST', '/api/v2/jobs/verification-email', {
        'user_id': access.userId,
      });
    }
    return reply({
      'success': true,
      'user': {
        'name': updated['name'],
        'email': updated['email'],
        'picture': updated['picture'],
      },
    });
  }
  if (path == 'profile' && request.method == HttpMethod.delete) {
    await auth0.call(
      'DELETE',
      '/api/v2/users/' + Uri.encodeComponent(access.userId),
    );
    return Response(statusCode: 204);
  }
  if (path == 'profile/password-reset' && request.method == HttpMethod.post) {
    final user = await auth0.user(access.userId) as Map;
    final email = user['email'];
    if (email is! String || email.isEmpty)
      return reply({'error': 'Missing user email'}, status: 400);
    final env = Platform.environment;
    final response = await http
        .post(
          Uri.https(auth0.domain, '/dbconnections/change_password'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'client_id': env['AUTH0_APP_CLIENT_ID'],
            'email': email,
            'connection': env['AUTH0_DB_CONNECTION'],
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return reply({'error': 'Unexpected error'}, status: 500);
    }
    return reply({'success': true});
  }
  if (path == 'profile/photo-upload' && request.method == HttpMethod.post) {
    final body = await readObject(request) ?? {};
    final extension = body['fileExtension'] is String
        ? (body['fileExtension'] as String).replaceAll(
            RegExp(r'[^a-zA-Z0-9]'),
            '',
          )
        : 'jpg';
    if (extension.isEmpty || extension.length > 10) {
      return reply({'error': 'Invalid payload'}, status: 400);
    }
    final maxBytes =
        int.tryParse(
          Platform.environment['MAX_PROFILE_PHOTO_SIZE_BYTES'] ?? '',
        ) ??
        1048576;
    final fileSize = body['fileSizeBytes'];
    if (fileSize is num && (fileSize <= 0 || fileSize > maxBytes)) {
      return reply({'error': 'File size exceeds maximum allowed'}, status: 400);
    }
    final info = _photoUpload(access.userId, extension);
    return reply({'success': true, ...info});
  }
  return reply({'error': 'Method not allowed'}, status: 405);
}

Map<String, String> _photoUpload(String userId, String extension) {
  final env = Platform.environment;
  final connection = env['AZURE_STORAGE_CONNECTION_STRING'];
  final container = env['PROFILE_PHOTO_CONTAINER'];
  final publicBase = env['PROFILE_PHOTO_PUBLIC_BASE_URL'];
  if (connection == null || container == null || publicBase == null) {
    throw StateError('Profile photo storage is not configured');
  }
  final settings = <String, String>{};
  for (final piece in connection.split(';')) {
    final index = piece.indexOf('=');
    if (index > 0)
      settings[piece.substring(0, index)] = piece.substring(index + 1);
  }
  final account = settings['AccountName'];
  final key = settings['AccountKey'];
  if (account == null || key == null)
    throw StateError('Invalid Azure Storage connection string');
  final safeId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final name = '$safeId/' + const Uuid().v4() + '.$extension';
  const version = '2022-11-02';
  const permissions = 'cw';
  final expiry = DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 10))
      .toIso8601String()
      .replaceFirst('.000Z', 'Z');
  final canonical = '/blob/$account/$container/$name';
  final sign = [
    permissions,
    '',
    expiry,
    canonical,
    '',
    '',
    'https',
    version,
    'b',
    '',
    '',
    '',
    '',
    '',
    '',
    '',
  ].join('\n');
  final signature = base64Encode(
    Hmac(sha256, base64Decode(key)).convert(utf8.encode(sign)).bytes,
  );
  final base = Uri.https('$account.blob.core.windows.net', '/$container/$name');
  final upload = base.replace(
    queryParameters: {
      'sp': permissions,
      'se': expiry,
      'spr': 'https',
      'sv': version,
      'sr': 'b',
      'sig': signature,
    },
  );
  return {
    'blobName': name,
    'uploadUrl': upload.toString(),
    'publicUrl': publicBase.replaceFirst(RegExp(r'/$'), '') + '/$name',
  };
}
