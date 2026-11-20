import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:grove/grove.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod/riverpod.dart'
    show AsyncData, AsyncValue, FutureProvider, Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/grove_provider.dart';

part 'user_profile_provider.g.dart';

final _photoProvider = FutureProvider.autoDispose.family<Uint8List?, String>((
  ref,
  picture,
) async {
  try {
    final url = Uri.parse(picture);
    if (url.scheme != 'https' || url.host.isEmpty) return null;
    final response = await http.get(url).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) return response.bodyBytes;
  } catch (_) {
    // A missing photo does not prevent displaying the profile.
  }
  return null;
});

final userInfoProvider = Provider<AsyncValue<UserInfo?>>((ref) {
  final subject = ref.watch(groveSubjectProvider);
  return subject.flatMap((id) {
    if (id == null) return const AsyncData(null);
    final grove = ref.watch(bearingsGroveProvider);
    return ref
        .watch(groveQueryProvider(grove.query<GroveUser>().byId(id)))
        .whenData((result) {
          final profile = result.items.singleOrNull;
          if (profile == null) return null;
          final picture = profile.avatarUrl;
          return UserInfo(
            name: profile.name,
            email: profile.email,
            emailVerified: profile.emailVerified,
            pictureUrl: picture,
            photo: picture == null
                ? null
                : ref.watch(_photoProvider(picture)).value,
          );
        });
  });
});

class UserInfo {
  final String? name;
  final String? email;
  final bool? emailVerified;
  final Uint8List? photo;
  final String? pictureUrl;

  const UserInfo({
    this.name,
    this.email,
    this.emailVerified,
    this.photo,
    this.pictureUrl,
  });
}

@Riverpod(keepAlive: true)
UserProfileService userProfileService(Ref ref) => UserProfileService(ref);

class UserProfileService {
  UserProfileService(this._ref);

  final Ref _ref;

  Future<void> updateProfile({
    String? name,
    String? email,
    String? pictureUrl,
  }) async {
    final subject = await _ref.read(groveSubjectProvider.future);
    if (!_ref.mounted || subject == null) {
      throw const GroveException(
        'unauthenticated',
        'Sign in to edit your profile',
      );
    }
    final normalizedName = name?.trim();
    if (normalizedName != null || pictureUrl != null) {
      final grove = _ref.read(bearingsGroveProvider);
      await grove.update<GroveUser>(
        subject,
        (current) =>
            current.copyWith(name: normalizedName, avatarUrl: pictureUrl),
      );
    }
    if (email != null && _ref.mounted) {
      await _ref.read(honeycombActionsProvider).account('changeEmail', {
        'email': email.trim(),
      });
    }
  }

  Future<void> requestPasswordReset() async {
    await _ref.read(honeycombActionsProvider).account('resetPassword');
  }

  Future<void> refreshProfile() async {
    await _ref.read(honeycombActionsProvider).account('refreshProfile');
  }

  Future<String> uploadProfilePhoto(Uint8List bytes) async {
    if (bytes.length > 2 * 1024 * 1024) {
      throw ArgumentError('Choose a JPEG photo under 2 MiB');
    }
    final response = await _ref.read(honeycombActionsProvider).account(
      'uploadPhoto',
      {'jpeg': base64Encode(bytes)},
    );
    return response['url'] as String;
  }

  Future<void> deleteAccount() async {
    await _ref.read(honeycombActionsProvider).account('deleteAccount');
  }
}
