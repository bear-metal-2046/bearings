// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Reads the current user's profile from [Auth.user] and optionally
/// downloads the profile photo bytes.
///
/// This provider is a thin layer over the user info already populated
/// by the active [AuthBackend] — it does **not** call Auth0's `/userinfo`
/// endpoint directly.  Photo bytes are loaded lazily from [UserProfile.pictureUrl].

@ProviderFor(userInfo)
final userInfoProvider = UserInfoProvider._();

/// Reads the current user's profile from [Auth.user] and optionally
/// downloads the profile photo bytes.
///
/// This provider is a thin layer over the user info already populated
/// by the active [AuthBackend] — it does **not** call Auth0's `/userinfo`
/// endpoint directly.  Photo bytes are loaded lazily from [UserProfile.pictureUrl].

final class UserInfoProvider
    extends
        $FunctionalProvider<
          AsyncValue<UserInfo?>,
          UserInfo?,
          FutureOr<UserInfo?>
        >
    with $FutureModifier<UserInfo?>, $FutureProvider<UserInfo?> {
  /// Reads the current user's profile from [Auth.user] and optionally
  /// downloads the profile photo bytes.
  ///
  /// This provider is a thin layer over the user info already populated
  /// by the active [AuthBackend] — it does **not** call Auth0's `/userinfo`
  /// endpoint directly.  Photo bytes are loaded lazily from [UserProfile.pictureUrl].
  UserInfoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userInfoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userInfoHash();

  @$internal
  @override
  $FutureProviderElement<UserInfo?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<UserInfo?> create(Ref ref) {
    return userInfo(ref);
  }
}

String _$userInfoHash() => r'5c5d99c6ebe779ad1477ce215d84a1934ea02163';

@ProviderFor(userProfileService)
final userProfileServiceProvider = UserProfileServiceProvider._();

final class UserProfileServiceProvider
    extends
        $FunctionalProvider<
          UserProfileService,
          UserProfileService,
          UserProfileService
        >
    with $Provider<UserProfileService> {
  UserProfileServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userProfileServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userProfileServiceHash();

  @$internal
  @override
  $ProviderElement<UserProfileService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  UserProfileService create(Ref ref) {
    return userProfileService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserProfileService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserProfileService>(value),
    );
  }
}

String _$userProfileServiceHash() =>
    r'5ee8eb3a7398333540af757649f470d081157c34';
