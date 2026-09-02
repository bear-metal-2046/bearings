// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_auth_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deviceAuthService)
final deviceAuthServiceProvider = DeviceAuthServiceProvider._();

final class DeviceAuthServiceProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceAuthService>,
          DeviceAuthService,
          FutureOr<DeviceAuthService>
        >
    with
        $FutureModifier<DeviceAuthService>,
        $FutureProvider<DeviceAuthService> {
  DeviceAuthServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceAuthServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceAuthServiceHash();

  @$internal
  @override
  $FutureProviderElement<DeviceAuthService> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceAuthService> create(Ref ref) {
    return deviceAuthService(ref);
  }
}

String _$deviceAuthServiceHash() => r'6c5e23c0ae3c4a9fee5c95d6e4e8fe52842b4bab';
