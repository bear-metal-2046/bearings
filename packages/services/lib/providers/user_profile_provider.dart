import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/auth_provider.dart';

part 'user_profile_provider.g.dart';

/// Reads the current user's profile from Auth0's live `/userinfo` endpoint
/// and optionally downloads the profile photo bytes.
///
/// The profile can be changed by the Honeycomb API while the Auth0 session
/// remains active, so the login-time ID-token profile is not authoritative.
@Riverpod(keepAlive: true)
Future<UserInfo?> userInfo(Ref ref) async {
  final auth = await ref.watch(authProvider.future);
  final authStatus = ref.watch(authStatusProvider);
  final dio = ref.watch(dioProvider);

  if (authStatus != AuthStatus.authenticated) return null;

  String? accessToken;
  var isOffline = false;

  try {
    accessToken = await auth.getAccessToken(['openid', 'profile', 'email']);
  } on OfflineAuthException {
    isOffline = true;
  }

  Map<String, dynamic> data;
  try {
    final response = await dio.get<Map<String, dynamic>>(
      'https://${auth.config.domain}/userinfo',
      options: Options(
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        extra: {
          'cachePolicy': CachePolicy.networkFirst,
          'isOffline': isOffline,
        },
      ),
    );
    data = response.data!;
  } catch (_) {
    // Keep the session usable when the profile endpoint is unavailable.
    final user = auth.user;
    if (user == null) return null;
    return UserInfo(
      name: user.name,
      email: user.email,
      emailVerified: user.emailVerified,
    );
  }

  // Download photo bytes from the live profile URL if present.
  Uint8List? photoBytes;
  final pictureUrl = data['picture'] as String?;
  if (pictureUrl != null && pictureUrl.isNotEmpty) {
    try {
      final photoResponse = await dio.get(
        pictureUrl,
        options: Options(
          responseType: ResponseType.bytes,
          extra: {'cachePolicy': CachePolicy.networkFirst},
        ),
      );

      if (photoResponse.statusCode == 200 && photoResponse.data != null) {
        photoBytes = Uint8List.fromList(
          (photoResponse.data as List).cast<int>(),
        );
      }
    } catch (_) {
      // Proceed without photo on failure.
    }
  }

  return UserInfo(
    name: data['name'] as String?,
    email: data['email'] as String?,
    emailVerified: data['email_verified'] as bool?,
    photo: photoBytes,
  );
}

class UserInfo {
  final String? name;
  final String? email;
  final bool? emailVerified;
  final Uint8List? photo;

  const UserInfo({this.name, this.email, this.emailVerified, this.photo});
}

@Riverpod(keepAlive: true)
UserProfileService userProfileService(Ref ref) {
  return UserProfileService(ref);
}

/// CRUD service for the user's profile via the Honeycomb backend.
class UserProfileService {
  final Ref _ref;

  UserProfileService(this._ref);

  Future<void> updateProfile({
    String? name,
    String? email,
    String? pictureUrl,
  }) async {
    final client = _ref.read(honeycombClientProvider);
    final payload = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) {
      payload['name'] = name.trim();
    }
    if (email != null && email.trim().isNotEmpty) {
      payload['email'] = email.trim();
    }
    if (pictureUrl != null && pictureUrl.trim().isNotEmpty) {
      payload['picture'] = pictureUrl.trim();
    }

    if (payload.isEmpty) return;

    debugPrint('Profile update payload: $payload');
    await client.patch('/profile', data: payload);

    if (_ref.mounted) {
      final config = _ref.read(auth0ConfigProvider);
      client.invalidateCache('https://${config.domain}/userinfo');
      _ref.invalidate(userInfoProvider);
    }
  }

  Future<void> requestPasswordReset() async {
    final client = _ref.read(honeycombClientProvider);
    await client.post('/profile/password-reset', data: <String, dynamic>{});
  }

  Future<String> uploadProfilePhoto(
    Uint8List bytes, {
    String? contentType,
    String? fileExtension,
  }) async {
    final client = _ref.read(honeycombClientProvider);
    final dio = _ref.read(dioProvider);

    debugPrint('Requesting photo upload URL');
    final response = await client.post<Map<String, dynamic>>(
      '/profile/photo-upload',
      data: {
        'contentType': contentType,
        'fileExtension': fileExtension,
        'fileSizeBytes': bytes.length,
      },
    );

    final uploadUrl = response['uploadUrl'] as String?;
    final publicUrl = response['publicUrl'] as String?;

    if (uploadUrl == null || publicUrl == null) {
      throw Exception('Photo upload data missing');
    }

    debugPrint('Uploading photo to blob');
    await dio.put(
      uploadUrl,
      data: bytes,
      options: Options(
        headers: {'x-ms-blob-type': 'BlockBlob', 'Content-Type': contentType},
      ),
    );

    debugPrint('Updating profile picture to $publicUrl');
    await updateProfile(pictureUrl: publicUrl);
    return publicUrl;
  }

  Future<void> deleteAccount() async {
    final client = _ref.read(honeycombClientProvider);
    await client.delete('/profile');
  }
}
