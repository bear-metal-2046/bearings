import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/auth_provider.dart';

part 'user_profile_provider.g.dart';

/// Reads the current user's profile from [Auth.user] and optionally
/// downloads the profile photo bytes.
///
/// This provider is a thin layer over the user info already populated
/// by the active [AuthBackend] — it does **not** call Auth0's `/userinfo`
/// endpoint directly.  Photo bytes are loaded lazily from [UserProfile.pictureUrl].
@Riverpod(keepAlive: true)
Future<UserInfo?> userInfo(Ref ref) async {
  final auth = await ref.watch(authProvider.future);
  final authStatus = ref.watch(authStatusProvider);

  if (authStatus != AuthStatus.authenticated) return null;

  final user = auth.user;
  if (user == null) return null;

  // Download photo bytes from the picture URL if present.
  Uint8List? photoBytes;
  final pictureUrl = user.pictureUrl;
  if (pictureUrl != null) {
    try {
      final dio = ref.watch(dioProvider);
      final photoResponse = await dio.get(
        pictureUrl.toString(),
        options: Options(responseType: ResponseType.bytes),
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
    name: user.name,
    email: user.email,
    emailVerified: user.emailVerified,
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

/// CRUD service for the user's profile via the honeycomb backend.
///
/// This is separate from [Auth.user] — it manages profile fields
/// (display name, email, photo) through the app's own API, not Auth0.
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
