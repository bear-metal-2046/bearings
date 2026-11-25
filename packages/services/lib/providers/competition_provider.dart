import 'dart:async';

import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:riverpod/riverpod.dart';
import 'package:services/providers/grove_provider.dart';

final competitionProvider = Provider<CompetitionClient>(
  (ref) => CompetitionClient(ref.watch(bearingsGroveProvider)),
);

final competitionMatchesProvider = Provider.autoDispose
    .family<AsyncValue<QueryResult<CompetitionMatch>>, String>((ref, event) {
      if (event.isEmpty) return AsyncData(QueryResult([]));
      if (!isMirroredTbaKey(event)) {
        return ref.watch(_historicalMatchesProvider(event));
      }
      final client = ref.watch(competitionProvider);
      return ref.watch(groveQueryProvider(client._eventMatches(event)));
    });

final competitionTeamsProvider = Provider.autoDispose
    .family<AsyncValue<QueryResult<CompetitionTeam>>, String>((ref, event) {
      if (event.isEmpty) return AsyncData(QueryResult([]));
      if (!isMirroredTbaKey(event)) {
        return ref.watch(_historicalTeamsProvider(event));
      }
      final client = ref.watch(competitionProvider);
      return ref
          .watch(groveQueryProvider(client._eventTeams(event)))
          .whenData((result) => result.map((entry) => entry.profile));
    });

final competitionTeamMatchesProvider = Provider.autoDispose
    .family<AsyncValue<List<CompetitionMatch>>, String>((ref, team) {
      final client = ref.watch(competitionProvider);
      final historical = ref.watch(_historicalTeamMatchesProvider(team));
      final live = ref.watch(groveQueryProvider(client._teamMatches(team)));
      return live.flatMap((result) {
        final matches = result.requireAvailable().items;
        return historical.when(
          data: (archived) => AsyncData([...archived, ...matches]),
          error: (error, stackTrace) => _canUseLiveMatches(matches, error)
              ? AsyncData(matches)
              : AsyncError(error, stackTrace),
          loading: () =>
              matches.isEmpty ? const AsyncLoading() : AsyncData(matches),
        );
      });
    });

typedef CompetitionEventSelection = ({int year, String? team});

final competitionEventsProvider = Provider.autoDispose
    .family<AsyncValue<List<CompetitionEvent>>, CompetitionEventSelection>((
      ref,
      selection,
    ) {
      final (:year, :team) = selection;
      if (year < firstMirroredTbaSeason) {
        return ref.watch(_historicalEventsProvider(selection));
      }
      final client = ref.watch(competitionProvider);
      final events = ref.watch(groveQueryProvider(client._events(year)));
      if (team == null)
        return events.whenData((r) => r.requireAvailable().items);
      final roster = ref.watch(
        groveQueryProvider(client._teamEvents(year, team)),
      );
      return events.flatMap(
        (catalog) => roster.whenData(
          (entries) => _eventsForTeam(
            catalog.requireAvailable().items,
            entries.requireAvailable().items,
          ),
        ),
      );
    });

final competitionEventProvider = Provider.autoDispose
    .family<AsyncValue<CompetitionEvent?>, String>((ref, event) {
      if (!isMirroredTbaKey(event))
        return ref.watch(_historicalEventProvider(event));
      final grove = ref.watch(bearingsGroveProvider);
      return ref
          .watch(
            groveQueryProvider(grove.query<CompetitionEvent>().byId(event)),
          )
          .whenData((r) => r.requireAvailable().items.singleOrNull);
    });

final competitionMatchProvider = Provider.autoDispose
    .family<AsyncValue<CompetitionMatch?>, String>((ref, match) {
      if (!isMirroredTbaKey(match))
        return ref.watch(_historicalMatchProvider(match));
      final grove = ref.watch(bearingsGroveProvider);
      return ref
          .watch(
            groveQueryProvider(grove.query<CompetitionMatch>().byId(match)),
          )
          .whenData((r) => r.requireAvailable().items.singleOrNull);
    });

final competitionRankingsProvider = Provider.autoDispose
    .family<AsyncValue<List<EventRanking>>, String>((ref, event) {
      if (!isMirroredTbaKey(event))
        return ref.watch(_historicalRankingsProvider(event));
      final grove = ref.watch(bearingsGroveProvider);
      final query = grove.query<EventRanking>().where(
        EventRankingFields.event.equals(EntityRef(event)),
      );
      return ref
          .watch(groveQueryProvider(query))
          .whenData(
            (r) =>
                r.requireAvailable().items.toList()
                  ..sort((a, b) => a.result.rank.compareTo(b.result.rank)),
          );
    });

final competitionMediaProvider = Provider.autoDispose
    .family<AsyncValue<List<CompetitionMedia>>, String>((ref, event) {
      if (!isMirroredTbaKey(event))
        return ref.watch(_historicalMediaProvider(event));
      final client = ref.watch(competitionProvider);
      return ref
          .watch(groveQueryProvider(client._eventMedia(event)))
          .whenData((r) => r.requireAvailable().items);
    });

final _historicalMatchesProvider = FutureProvider.autoDispose
    .family<QueryResult<CompetitionMatch>, String>((ref, event) async {
      final result = await ref.watch(competitionProvider).matchResults(event);
      if (ref.mounted) {
        final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
        ref.onDispose(timer.cancel);
      }
      return result;
    });

final _historicalTeamsProvider = FutureProvider.autoDispose
    .family<QueryResult<CompetitionTeam>, String>(
      (ref, event) => ref.watch(competitionProvider).teamResults(event),
    );

final _historicalTeamMatchesProvider = FutureProvider.autoDispose
    .family<List<CompetitionMatch>, String>((ref, team) async {
      final rows = await ref.watch(competitionProvider)._list(
        'historicalTeamMatches',
        {'team': team},
      );
      return rows.map(TbaApi.match).toList();
    });

final _historicalEventsProvider = FutureProvider.autoDispose
    .family<List<CompetitionEvent>, CompetitionEventSelection>(
      (ref, selection) => ref
          .watch(competitionProvider)
          .events(selection.year, team: selection.team),
    );

final _historicalEventProvider = FutureProvider.autoDispose
    .family<CompetitionEvent?, String>((ref, event) async {
      final data = await ref.watch(competitionProvider)._object('event', {
        'event': event,
      });
      return data == null ? null : TbaApi.event(data);
    });

final _historicalMatchProvider = FutureProvider.autoDispose
    .family<CompetitionMatch?, String>((ref, match) async {
      final data = await ref.watch(competitionProvider)._object('match', {
        'match': match,
      });
      return data == null ? null : TbaApi.match(data);
    });

final _historicalRankingsProvider = FutureProvider.autoDispose
    .family<List<EventRanking>, String>((ref, event) async {
      final rows = await ref.watch(competitionProvider)._list('rankings', {
        'event': event,
      });
      return rows.map((row) => TbaApi.ranking(event, row)).toList();
    });

final _historicalMediaProvider = FutureProvider.autoDispose
    .family<List<CompetitionMedia>, String>((ref, event) async {
      final rows = await ref.watch(competitionProvider)._list('media', {
        'event': event,
      });
      return rows.map((row) => TbaApi.media(event, row, event: event)).toList();
    });

// Retry the data source so an active screen can recover from a failed read.
void retryCompetitionMatches(ProviderContainer container, String event) {
  if (event.isEmpty) return;
  if (isMirroredTbaKey(event)) {
    final client = container.read(competitionProvider);
    container.invalidate(groveQueryProvider(client._eventMatches(event)));
  } else {
    container.invalidate(_historicalMatchesProvider(event));
  }
}

void retryCompetitionTeams(ProviderContainer container, String event) {
  if (event.isEmpty) return;
  if (isMirroredTbaKey(event)) {
    final client = container.read(competitionProvider);
    container.invalidate(groveQueryProvider(client._eventTeams(event)));
  } else {
    container.invalidate(_historicalTeamsProvider(event));
  }
}

void retryCompetitionEvents(
  ProviderContainer container,
  CompetitionEventSelection selection,
) {
  final (:year, :team) = selection;
  if (year < firstMirroredTbaSeason) {
    container.invalidate(_historicalEventsProvider(selection));
    return;
  }
  final client = container.read(competitionProvider);
  container.invalidate(groveQueryProvider(client._events(year)));
  if (team != null) {
    container.invalidate(groveQueryProvider(client._teamEvents(year, team)));
  }
}

void retryCompetitionMatch(ProviderContainer container, String match) {
  if (isMirroredTbaKey(match)) {
    final grove = container.read(bearingsGroveProvider);
    container.invalidate(
      groveQueryProvider(grove.query<CompetitionMatch>().byId(match)),
    );
  } else {
    container.invalidate(_historicalMatchProvider(match));
  }
}

bool _canUseLiveMatches(List<CompetitionMatch> matches, Object error) =>
    matches.isNotEmpty &&
    error is GroveException &&
    const {'offline', 'unavailable'}.contains(error.code);

List<CompetitionEvent> _eventsForTeam(
  List<CompetitionEvent> events,
  List<EventTeam> roster,
) {
  final ids = roster.map((entry) => entry.event.id).toSet();
  return events.where((event) => ids.contains(event.id)).toList();
}

/// One-shot competition reads for actions such as exports and picklist creation.
class CompetitionClient {
  CompetitionClient(this._grove);

  final Grove _grove;

  GroveQuery<CompetitionEvent> _events(int year) => _grove
      .query<CompetitionEvent>()
      .where(CompetitionEventFields.season.equals(year));

  GroveQuery<EventTeam> _teamEvents(int year, String team) => _grove
      .query<EventTeam>()
      .where(EventTeamFields.season.equals(year))
      .where(EventTeamFields.team.equals(EntityRef(team)));

  GroveQuery<EventTeam> _eventTeams(String event) => _grove
      .query<EventTeam>()
      .where(EventTeamFields.event.equals(EntityRef(event)));

  GroveQuery<CompetitionMedia> _eventMedia(String event) => _grove
      .query<CompetitionMedia>()
      .where(CompetitionMediaFields.event.equals(EntityRef(event)))
      .where(CompetitionMediaFields.rosterMedia.equals(true));

  GroveQuery<CompetitionMatch> _eventMatches(String event) => _grove
      .query<CompetitionMatch>()
      .where(CompetitionMatchFields.event.equals(EntityRef(event)))
      .where(CompetitionMatchFields.practice.equals(false));

  GroveQuery<CompetitionMatch> _teamMatches(String team) => _grove
      .query<CompetitionMatch>()
      .where(CompetitionMatchFields.practice.equals(false))
      .where(CompetitionMatch.participatingTeams.contains(EntityRef(team)));

  Future<List<CompetitionEvent>> events(int year, {String? team}) async {
    if (year < firstMirroredTbaSeason) {
      final rows = await _list(team == null ? 'events' : 'teamEvents', {
        'year': year,
        'team': ?team,
      });
      return rows.map(TbaApi.event).toList();
    }
    if (team == null)
      return (await _events(year).result()).requireAvailable().items;
    final (events, roster) = await (
      _events(year).result(),
      _teamEvents(year, team).result(),
    ).wait;
    return _eventsForTeam(
      events.requireAvailable().items,
      roster.requireAvailable().items,
    );
  }

  Future<QueryResult<CompetitionMatch>> matchResults(String event) {
    if (event.isEmpty) return Future.value(QueryResult([]));
    if (!isMirroredTbaKey(event)) {
      return _archive('matches', {'event': event}, TbaApi.match);
    }
    return _eventMatches(event).result();
  }

  Future<List<CompetitionTeam>> teams(String event) async =>
      (await teamResults(event)).requireAvailable().items;

  Future<QueryResult<CompetitionTeam>> teamResults(String event) async {
    if (event.isEmpty) return QueryResult([]);
    if (!isMirroredTbaKey(event)) {
      return _archive('teams', {'event': event}, TbaApi.team);
    }
    return (await _eventTeams(event).result()).map((entry) => entry.profile);
  }

  Future<List<Json>> _list(String resource, Json args) async {
    final data = (await _load(resource, args)).data;
    return (data as List? ?? []).cast<Json>();
  }

  Future<QueryResult<T>> _archive<T>(
    String resource,
    Json args,
    T Function(Json) decode,
  ) async {
    final response = await _load(resource, args);
    final data = (response.data as List? ?? []).cast<Json>();
    return QueryResult(
      data.map(decode),
      complete: !response.offline,
      offline: response.offline,
    );
  }

  Future<Json?> _object(String resource, Json args) async =>
      (await _load(resource, args)).data as Json?;

  Future<({Object? data, bool offline})> _load(
    String resource,
    Json args,
  ) async {
    final key = 'competition:$resource:${canonicalJson(args)}';
    final transport = _grove.transport;
    if (transport is! WebSocketGroveTransport) {
      throw const GroveException(
        'unavailable',
        'Competition transport is unavailable',
      );
    }
    try {
      final data = await transport.competition(resource, args);
      await _grove.cache.write(key, {'data': data, '_download': 'competition'});
      return (data: data, offline: false);
    } on GroveException catch (error) {
      if (!const {'offline', 'unavailable'}.contains(error.code)) rethrow;
      final cached = await _grove.cache.read(key);
      if (cached == null) rethrow;
      return (data: cached['data'], offline: true);
    }
  }
}
