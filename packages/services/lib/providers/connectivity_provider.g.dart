// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connectivity_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HoneycombEndpointPreference)
final honeycombEndpointPreferenceProvider =
    HoneycombEndpointPreferenceProvider._();

final class HoneycombEndpointPreferenceProvider
    extends
        $NotifierProvider<
          HoneycombEndpointPreference,
          HoneycombEndpointSelection
        > {
  HoneycombEndpointPreferenceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'honeycombEndpointPreferenceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$honeycombEndpointPreferenceHash();

  @$internal
  @override
  HoneycombEndpointPreference create() => HoneycombEndpointPreference();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HoneycombEndpointSelection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HoneycombEndpointSelection>(value),
    );
  }
}

String _$honeycombEndpointPreferenceHash() =>
    r'58bec5eb8ea0a6831b02f6fd79aabfe987f54318';

abstract class _$HoneycombEndpointPreference
    extends $Notifier<HoneycombEndpointSelection> {
  HoneycombEndpointSelection build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<HoneycombEndpointSelection, HoneycombEndpointSelection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                HoneycombEndpointSelection,
                HoneycombEndpointSelection
              >,
              HoneycombEndpointSelection,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
