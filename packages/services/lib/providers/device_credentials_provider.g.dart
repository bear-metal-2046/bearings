// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_credentials_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deviceCredentials)
final deviceCredentialsProvider = DeviceCredentialsProvider._();

final class DeviceCredentialsProvider
    extends
        $FunctionalProvider<
          AsyncValue<DeviceCredentials>,
          DeviceCredentials,
          FutureOr<DeviceCredentials>
        >
    with
        $FutureModifier<DeviceCredentials>,
        $FutureProvider<DeviceCredentials> {
  DeviceCredentialsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceCredentialsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceCredentialsHash();

  @$internal
  @override
  $FutureProviderElement<DeviceCredentials> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DeviceCredentials> create(Ref ref) {
    return deviceCredentials(ref);
  }
}

String _$deviceCredentialsHash() => r'e27f8a8dc1219a7af87c471f44f8d1a62a2c65c9';
