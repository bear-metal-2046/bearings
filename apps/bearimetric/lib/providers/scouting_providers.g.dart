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
          AsyncValue<List<CompetitionEvent>>,
          AsyncValue<List<CompetitionEvent>>,
          AsyncValue<List<CompetitionEvent>>
        >
    with $Provider<AsyncValue<List<CompetitionEvent>>> {
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
  $ProviderElement<AsyncValue<List<CompetitionEvent>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<List<CompetitionEvent>> create(Ref ref) {
    return events(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<List<CompetitionEvent>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<List<CompetitionEvent>>>(
        value,
      ),
    );
  }
}

String _$eventsHash() => r'aca659613964871efdccf70f9d15380c97bdb808';

@ProviderFor(matches)
final matchesProvider = MatchesFamily._();

final class MatchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CompetitionMatch>>,
          AsyncValue<List<CompetitionMatch>>,
          AsyncValue<List<CompetitionMatch>>
        >
    with $Provider<AsyncValue<List<CompetitionMatch>>> {
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
  $ProviderElement<AsyncValue<List<CompetitionMatch>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<List<CompetitionMatch>> create(Ref ref) {
    final argument = this.argument as String;
    return matches(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<List<CompetitionMatch>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<List<CompetitionMatch>>>(
        value,
      ),
    );
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

String _$matchesHash() => r'78fb65e62728986489f27240266ecbb5675409c9';

final class MatchesFamily extends $Family
    with $FunctionalFamilyOverride<AsyncValue<List<CompetitionMatch>>, String> {
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
    extends
        $FunctionalProvider<
          AsyncValue<String?>,
          AsyncValue<String?>,
          AsyncValue<String?>
        >
    with $Provider<AsyncValue<String?>> {
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
  $ProviderElement<AsyncValue<String?>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<String?> create(Ref ref) {
    final argument = this.argument as (String, int, ScoutPosition);
    return teamForMatchPosition(ref, argument.$1, argument.$2, argument.$3);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<String?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<String?>>(value),
    );
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
    r'7460aa956d5dfe0e45fcfc91f95880cd7f026c45';

final class TeamForMatchPositionFamily extends $Family
    with
        $FunctionalFamilyOverride<
          AsyncValue<String?>,
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
          AsyncValue<Map<ScoutPosition, String>>,
          AsyncValue<Map<ScoutPosition, String>>
        >
    with $Provider<AsyncValue<Map<ScoutPosition, String>>> {
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
  $ProviderElement<AsyncValue<Map<ScoutPosition, String>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<Map<ScoutPosition, String>> create(Ref ref) {
    final argument = this.argument as (String, int);
    return allTeamsForMatch(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<Map<ScoutPosition, String>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<AsyncValue<Map<ScoutPosition, String>>>(value),
    );
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

String _$allTeamsForMatchHash() => r'affc216e6e7237eeb673e5ad6426fcb4f046ec50';

final class AllTeamsForMatchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          AsyncValue<Map<ScoutPosition, String>>,
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
    r'c40f44e36d34a92cb599b00d823b4b58393691b4';

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
    extends
        $FunctionalProvider<
          AsyncValue<int?>,
          AsyncValue<int?>,
          AsyncValue<int?>
        >
    with $Provider<AsyncValue<int?>> {
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
  $ProviderElement<AsyncValue<int?>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AsyncValue<int?> create(Ref ref) {
    return teamNumberForSession(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<int?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<int?>>(value),
    );
  }
}

String _$teamNumberForSessionHash() =>
    r'59196c0061b3912db6c99a2b0084b540cb2bce44';

@ProviderFor(allianceTeamsForSession)
final allianceTeamsForSessionProvider = AllianceTeamsForSessionProvider._();

final class AllianceTeamsForSessionProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          AsyncValue<List<String>>,
          AsyncValue<List<String>>
        >
    with $Provider<AsyncValue<List<String>>> {
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
  $ProviderElement<AsyncValue<List<String>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<List<String>> create(Ref ref) {
    return allianceTeamsForSession(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<List<String>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<List<String>>>(value),
    );
  }
}

String _$allianceTeamsForSessionHash() =>
    r'1882df75a8ce9cfd1234e631fbeca9e56e0f69ac';
