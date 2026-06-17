// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scouting_data_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ScoutingData)
final scoutingDataProvider = ScoutingDataProvider._();

final class ScoutingDataProvider
    extends $AsyncNotifierProvider<ScoutingData, List<ScoutingDocument>> {
  ScoutingDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scoutingDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scoutingDataHash();

  @$internal
  @override
  ScoutingData create() => ScoutingData();
}

String _$scoutingDataHash() => r'577499dff7e7c0e7cd4bc210139600934345ff06';

abstract class _$ScoutingData extends $AsyncNotifier<List<ScoutingDocument>> {
  FutureOr<List<ScoutingDocument>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<ScoutingDocument>>, List<ScoutingDocument>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<ScoutingDocument>>,
                List<ScoutingDocument>
              >,
              AsyncValue<List<ScoutingDocument>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
