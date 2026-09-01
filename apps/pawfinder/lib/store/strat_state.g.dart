// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'strat_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StratStateNotifier)
final stratStateProvider = StratStateNotifierFamily._();

final class StratStateNotifierProvider
    extends $NotifierProvider<StratStateNotifier, StratState> {
  StratStateNotifierProvider._({
    required StratStateNotifierFamily super.from,
    required MatchIdentity super.argument,
  }) : super(
         retry: null,
         name: r'stratStateProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$stratStateNotifierHash();

  @override
  String toString() {
    return r'stratStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  StratStateNotifier create() => StratStateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StratState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StratState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StratStateNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$stratStateNotifierHash() =>
    r'69791c25db17c96d006285fdbcc66888192296c0';

final class StratStateNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          StratStateNotifier,
          StratState,
          StratState,
          StratState,
          MatchIdentity
        > {
  StratStateNotifierFamily._()
    : super(
        retry: null,
        name: r'stratStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  StratStateNotifierProvider call(MatchIdentity identity) =>
      StratStateNotifierProvider._(argument: identity, from: this);

  @override
  String toString() => r'stratStateProvider';
}

abstract class _$StratStateNotifier extends $Notifier<StratState> {
  late final _$args = ref.$arg as MatchIdentity;
  MatchIdentity get identity => _$args;

  StratState build(MatchIdentity identity);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StratState, StratState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StratState, StratState>,
              StratState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
