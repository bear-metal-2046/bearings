// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dio)
final dioProvider = DioProvider._();

final class DioProvider extends $FunctionalProvider<Dio, Dio, Dio>
    with $Provider<Dio> {
  DioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dioProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dioHash();

  @$internal
  @override
  $ProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Dio create(Ref ref) {
    return dio(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Dio value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Dio>(value),
    );
  }
}

String _$dioHash() => r'bddf1795c656314b551e19b22dde15213e6462e0';

@ProviderFor(honeycombClient)
final honeycombClientProvider = HoneycombClientProvider._();

final class HoneycombClientProvider
    extends
        $FunctionalProvider<HoneycombClient, HoneycombClient, HoneycombClient>
    with $Provider<HoneycombClient> {
  HoneycombClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'honeycombClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$honeycombClientHash();

  @$internal
  @override
  $ProviderElement<HoneycombClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HoneycombClient create(Ref ref) {
    return honeycombClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HoneycombClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HoneycombClient>(value),
    );
  }
}

String _$honeycombClientHash() => r'c81fae1dfd17d1050164265d7ddf997b31e772e6';

@ProviderFor(getData)
@Deprecated('Use get<Map<String, dynamic>>() in honeycombClientProvider.')
final getDataProvider = GetDataFamily._();

@Deprecated('Use get<Map<String, dynamic>>() in honeycombClientProvider.')
final class GetDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, dynamic>>,
          Map<String, dynamic>,
          FutureOr<Map<String, dynamic>>
        >
    with
        $FutureModifier<Map<String, dynamic>>,
        $FutureProvider<Map<String, dynamic>> {
  GetDataProvider._({
    required GetDataFamily super.from,
    required ({String endpoint, bool forceRefresh}) super.argument,
  }) : super(
         retry: null,
         name: r'getDataProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$getDataHash();

  @override
  String toString() {
    return r'getDataProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Map<String, dynamic>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, dynamic>> create(Ref ref) {
    final argument = this.argument as ({String endpoint, bool forceRefresh});
    return getData(
      ref,
      endpoint: argument.endpoint,
      forceRefresh: argument.forceRefresh,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GetDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$getDataHash() => r'5cba3632cc7fd42ba2e87ca0c35c8e41165c152c';

@Deprecated('Use get<Map<String, dynamic>>() in honeycombClientProvider.')
final class GetDataFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Map<String, dynamic>>,
          ({String endpoint, bool forceRefresh})
        > {
  GetDataFamily._()
    : super(
        retry: null,
        name: r'getDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  @Deprecated('Use get<Map<String, dynamic>>() in honeycombClientProvider.')
  GetDataProvider call({required String endpoint, bool forceRefresh = false}) =>
      GetDataProvider._(
        argument: (endpoint: endpoint, forceRefresh: forceRefresh),
        from: this,
      );

  @override
  String toString() => r'getDataProvider';
}

@ProviderFor(getListData)
@Deprecated('Use get<List<dynamic>>() in honeycombClientProvider.')
final getListDataProvider = GetListDataFamily._();

@Deprecated('Use get<List<dynamic>>() in honeycombClientProvider.')
final class GetListDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<dynamic>>,
          List<dynamic>,
          FutureOr<List<dynamic>>
        >
    with $FutureModifier<List<dynamic>>, $FutureProvider<List<dynamic>> {
  GetListDataProvider._({
    required GetListDataFamily super.from,
    required ({String endpoint, bool forceRefresh}) super.argument,
  }) : super(
         retry: null,
         name: r'getListDataProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$getListDataHash();

  @override
  String toString() {
    return r'getListDataProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<dynamic>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<dynamic>> create(Ref ref) {
    final argument = this.argument as ({String endpoint, bool forceRefresh});
    return getListData(
      ref,
      endpoint: argument.endpoint,
      forceRefresh: argument.forceRefresh,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GetListDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$getListDataHash() => r'524363e2046b80629b6dffcb582b6deed8566cc0';

@Deprecated('Use get<List<dynamic>>() in honeycombClientProvider.')
final class GetListDataFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<dynamic>>,
          ({String endpoint, bool forceRefresh})
        > {
  GetListDataFamily._()
    : super(
        retry: null,
        name: r'getListDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  @Deprecated('Use get<List<dynamic>>() in honeycombClientProvider.')
  GetListDataProvider call({
    required String endpoint,
    bool forceRefresh = false,
  }) => GetListDataProvider._(
    argument: (endpoint: endpoint, forceRefresh: forceRefresh),
    from: this,
  );

  @override
  String toString() => r'getListDataProvider';
}
