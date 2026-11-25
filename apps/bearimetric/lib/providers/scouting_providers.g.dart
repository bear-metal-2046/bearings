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

String _$matchesHash() => r'80b5162b873f2abfc69065adb3fdb119ac130034';

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
    r'14fbf32cbd71588ebd6fd253a0e93fa552bfe0d3';

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
