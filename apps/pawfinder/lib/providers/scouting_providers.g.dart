// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scouting_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(events)
final eventsProvider = EventsProvider._();

final class EventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScoutingEvent>>,
          List<ScoutingEvent>,
          FutureOr<List<ScoutingEvent>>
        >
    with
        $FutureModifier<List<ScoutingEvent>>,
        $FutureProvider<List<ScoutingEvent>> {
  EventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'eventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$eventsHash();

  @$internal
  @override
  $FutureProviderElement<List<ScoutingEvent>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ScoutingEvent>> create(Ref ref) {
    return events(ref);
  }
}

String _$eventsHash() => r'cb93aaff34eda6618033533b9ce5b9155cf2d761';

@ProviderFor(matches)
final matchesProvider = MatchesFamily._();

final class MatchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScoutingMatch>>,
          List<ScoutingMatch>,
          FutureOr<List<ScoutingMatch>>
        >
    with
        $FutureModifier<List<ScoutingMatch>>,
        $FutureProvider<List<ScoutingMatch>> {
  MatchesProvider._({
    required MatchesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'matchesProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$matchesHash();

  @override
  String toString() {
    return r'matchesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ScoutingMatch>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ScoutingMatch>> create(Ref ref) {
    final argument = this.argument as String;
    return matches(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MatchesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$matchesHash() => r'd09fac8b8dd6c49251c5b502e0a0d40e7c04a4c9';

final class MatchesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ScoutingMatch>>, String> {
  MatchesFamily._()
    : super(
        retry: null,
        name: r'matchesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  MatchesProvider call(String eventKey) =>
      MatchesProvider._(argument: eventKey, from: this);

  @override
  String toString() => r'matchesProvider';
}

@ProviderFor(teamForMatchPosition)
final teamForMatchPositionProvider = TeamForMatchPositionFamily._();

final class TeamForMatchPositionProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  TeamForMatchPositionProvider._({
    required TeamForMatchPositionFamily super.from,
    required (String, int, ScoutPosition) super.argument,
  }) : super(
         retry: null,
         name: r'teamForMatchPositionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$teamForMatchPositionHash();

  @override
  String toString() {
    return r'teamForMatchPositionProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    final argument = this.argument as (String, int, ScoutPosition);
    return teamForMatchPosition(ref, argument.$1, argument.$2, argument.$3);
  }

  @override
  bool operator ==(Object other) {
    return other is TeamForMatchPositionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$teamForMatchPositionHash() =>
    r'49c90634e58a41d28ec2e4cd52880db19cd5d497';

final class TeamForMatchPositionFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<String?>,
          (String, int, ScoutPosition)
        > {
  TeamForMatchPositionFamily._()
    : super(
        retry: null,
        name: r'teamForMatchPositionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TeamForMatchPositionProvider call(
    String eventKey,
    int matchNumber,
    ScoutPosition position,
  ) => TeamForMatchPositionProvider._(
    argument: (eventKey, matchNumber, position),
    from: this,
  );

  @override
  String toString() => r'teamForMatchPositionProvider';
}

@ProviderFor(allTeamsForMatch)
final allTeamsForMatchProvider = AllTeamsForMatchFamily._();

final class AllTeamsForMatchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<ScoutPosition, String>>,
          Map<ScoutPosition, String>,
          FutureOr<Map<ScoutPosition, String>>
        >
    with
        $FutureModifier<Map<ScoutPosition, String>>,
        $FutureProvider<Map<ScoutPosition, String>> {
  AllTeamsForMatchProvider._({
    required AllTeamsForMatchFamily super.from,
    required (String, int) super.argument,
  }) : super(
         retry: null,
         name: r'allTeamsForMatchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$allTeamsForMatchHash();

  @override
  String toString() {
    return r'allTeamsForMatchProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Map<ScoutPosition, String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<ScoutPosition, String>> create(Ref ref) {
    final argument = this.argument as (String, int);
    return allTeamsForMatch(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is AllTeamsForMatchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$allTeamsForMatchHash() => r'36de2ef0628cb20738e3582e01b7c4500aaf76ec';

final class AllTeamsForMatchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Map<ScoutPosition, String>>,
          (String, int)
        > {
  AllTeamsForMatchFamily._()
    : super(
        retry: null,
        name: r'allTeamsForMatchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AllTeamsForMatchProvider call(String eventKey, int matchNumber) =>
      AllTeamsForMatchProvider._(argument: (eventKey, matchNumber), from: this);

  @override
  String toString() => r'allTeamsForMatchProvider';
}

@ProviderFor(scouts)
final scoutsProvider = ScoutsProvider._();

final class ScoutsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Scout>>,
          List<Scout>,
          FutureOr<List<Scout>>
        >
    with $FutureModifier<List<Scout>>, $FutureProvider<List<Scout>> {
  ScoutsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scoutsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scoutsHash();

  @$internal
  @override
  $FutureProviderElement<List<Scout>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Scout>> create(Ref ref) {
    return scouts(ref);
  }
}

String _$scoutsHash() => r'b69d30cd5b385fdc5ea3426a920bfd684e57bf75';

@ProviderFor(ScoutingSessionNotifier)
final scoutingSessionProvider = ScoutingSessionNotifierProvider._();

final class ScoutingSessionNotifierProvider
    extends $NotifierProvider<ScoutingSessionNotifier, ScoutingSession> {
  ScoutingSessionNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scoutingSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scoutingSessionNotifierHash();

  @$internal
  @override
  ScoutingSessionNotifier create() => ScoutingSessionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScoutingSession value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScoutingSession>(value),
    );
  }
}

String _$scoutingSessionNotifierHash() =>
    r'f03175de972d1cb09c4008f5ad7558d949d385fa';

abstract class _$ScoutingSessionNotifier extends $Notifier<ScoutingSession> {
  ScoutingSession build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ScoutingSession, ScoutingSession>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ScoutingSession, ScoutingSession>,
              ScoutingSession,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(teamNumberForSession)
final teamNumberForSessionProvider = TeamNumberForSessionProvider._();

final class TeamNumberForSessionProvider
    extends $FunctionalProvider<AsyncValue<int?>, int?, FutureOr<int?>>
    with $FutureModifier<int?>, $FutureProvider<int?> {
  TeamNumberForSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'teamNumberForSessionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$teamNumberForSessionHash();

  @$internal
  @override
  $FutureProviderElement<int?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int?> create(Ref ref) {
    return teamNumberForSession(ref);
  }
}

String _$teamNumberForSessionHash() =>
    r'2ef5e5f3a0be1f951b30dd19250179e2e951e328';

@ProviderFor(allianceTeamsForSession)
final allianceTeamsForSessionProvider = AllianceTeamsForSessionProvider._();

final class AllianceTeamsForSessionProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  AllianceTeamsForSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allianceTeamsForSessionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allianceTeamsForSessionHash();

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    return allianceTeamsForSession(ref);
  }
}

String _$allianceTeamsForSessionHash() =>
    r'546d2f251e6ae58a8e93fc963ec7a755981b9d94';
