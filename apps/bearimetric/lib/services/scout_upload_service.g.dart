// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scout_upload_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(scoutUploadService)
final scoutUploadServiceProvider = ScoutUploadServiceProvider._();

final class ScoutUploadServiceProvider
    extends
        $FunctionalProvider<
          ScoutUploadService,
          ScoutUploadService,
          ScoutUploadService
        >
    with $Provider<ScoutUploadService> {
  ScoutUploadServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scoutUploadServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scoutUploadServiceHash();

  @$internal
  @override
  $ProviderElement<ScoutUploadService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ScoutUploadService create(Ref ref) {
    return scoutUploadService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScoutUploadService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScoutUploadService>(value),
    );
  }
}

String _$scoutUploadServiceHash() =>
    r'044f55c2ab237f00e05ff295d00ff6019c2a67da';
