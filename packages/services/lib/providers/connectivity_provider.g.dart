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

/// A single shared [InternetConnection] instance used by both the reactive
/// stream and one-off awaitable checks in the request/auth paths.

@ProviderFor(internetConnection)
final internetConnectionProvider = InternetConnectionProvider._();

/// A single shared [InternetConnection] instance used by both the reactive
/// stream and one-off awaitable checks in the request/auth paths.

final class InternetConnectionProvider
    extends
        $FunctionalProvider<
          InternetConnection,
          InternetConnection,
          InternetConnection
        >
    with $Provider<InternetConnection> {
  /// A single shared [InternetConnection] instance used by both the reactive
  /// stream and one-off awaitable checks in the request/auth paths.
  InternetConnectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'internetConnectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$internetConnectionHash();

  @$internal
  @override
  $ProviderElement<InternetConnection> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  InternetConnection create(Ref ref) {
    return internetConnection(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InternetConnection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InternetConnection>(value),
    );
  }
}

String _$internetConnectionHash() =>
    r'8ba749d98f89cacadd857d395058f84b70e2ae55';

/// Streams `true` when the device has internet access, `false` when offline.

@ProviderFor(connectivity)
final connectivityProvider = ConnectivityProvider._();

/// Streams `true` when the device has internet access, `false` when offline.

final class ConnectivityProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  /// Streams `true` when the device has internet access, `false` when offline.
  ConnectivityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectivityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectivityHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return connectivity(ref);
  }
}

String _$connectivityHash() => r'29dd9862664f30938bacc2b38db3a2c9e6cecf20';
