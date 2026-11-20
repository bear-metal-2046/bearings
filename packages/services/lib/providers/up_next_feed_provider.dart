import 'package:grove/grove.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/models/up_next_feed_match.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/nexus_provider.dart';
import 'package:services/providers/up_next_playoffs.dart';

enum UpNextSource { nexus, schedule }

class UpNextFeed {
  const UpNextFeed({
    required this.source,
    required this.matches,
    this.allMatches = const [],
    this.doubleElimination = false,
    this.eventOver = false,
    this.nexus,
    this.nexusProblem,
  });

  final UpNextSource source;

  /// Unplayed matches to show, or the whole schedule once [eventOver].
  final List<UpNextFeedMatch> matches;

  /// Every match from the same source, played ones included, for working out
  /// playoff alliances and brackets.
  final List<UpNextFeedMatch> allMatches;

  /// Whether the playoffs use FRC's 8-alliance double-elimination bracket.
  final bool doubleElimination;

  /// The event has finished, so Up Next shows the TBA schedule without Nexus.
  final bool eventOver;

  /// Event-level Nexus data such as `nowQueuing`, when Honeycomb returned it.
  final EventStatusSnapshot? nexus;

  /// Why the schedule is shown instead of Nexus, or null when using Nexus.
  final String? nexusProblem;
}

/// The comp levels Up Next shows. Practice matches are left out because TBA
/// has no match key for them, so the match preview cannot open them.
bool isUpNextCompLevel(String compLevel) =>
    const {'qm', 'sf', 'f'}.contains(compLevel);

/// Drops matches that have already been played. [playOrder] must be in the
/// order the matches are played, with replays where they are actually played.
///
/// Nexus never moves a match past "On field", so a match counts as played once
/// a later match has gone on field; the latest one on field stays as the
/// current match. Without Nexus, a match counts as played once TBA has its
/// result.
List<UpNextFeedMatch> withoutPlayedMatches(List<UpNextFeedMatch> playOrder) {
  bool hasGoneOnField(UpNextFeedMatch match) {
    final nexus = match.nexus;
    return nexus?.status?.toLowerCase() == 'on field' ||
        nexus?.times.actualOnFieldTime != null;
  }

  bool hasTbaResult(UpNextFeedMatch match) =>
      match.schedule?.playedAt != null ||
      (match.schedule?.red?.score ?? -1) >= 0 ||
      (match.schedule?.blue?.score ?? -1) >= 0;

  final current = playOrder.lastIndexWhere(hasGoneOnField);
  return playOrder
      .skip(current < 0 ? 0 : current)
      .where((match) => !hasTbaResult(match))
      .toList(growable: false);
}

List<UpNextFeedMatch> _nexusPlayOrder(
  String eventKey,
  EventStatusSnapshot status,
) {
  final matches = <UpNextFeedMatch>[];
  for (final match in status.matches) {
    final ref = match.ref;
    if (ref == null || !isUpNextCompLevel(ref.compLevel)) continue;
    final key = matchKeyForNexusRef(eventKey, ref);
    if (key != null) matches.add(UpNextFeedMatch.queued(key, match, ref));
  }
  return matches;
}

/// One match per TBA match key. A replay replaces the original match.
List<UpNextFeedMatch> _oneMatchPerKey(Iterable<UpNextFeedMatch> matches) {
  final byKey = <String, UpNextFeedMatch>{};
  for (final match in matches) {
    byKey[match.key] = match;
  }
  return byKey.values.toList(growable: false);
}

/// Unplayed Nexus matches, one per TBA match key.
List<UpNextFeedMatch> _nexusUpNextMatches(
  String eventKey,
  EventStatusSnapshot status,
) {
  return _oneMatchPerKey(
    withoutPlayedMatches(_nexusPlayOrder(eventKey, status)),
  );
}

bool needsScheduleFallback(String eventKey, NexusFetchResult nexus) {
  return switch (nexus) {
    NexusAvailable(:final status) => _nexusUpNextMatches(
      eventKey,
      status,
    ).isEmpty,
    _ => true,
  };
}

/// Whether TBA's last event day, [endDate], is over in every time zone, which
/// is noon UTC the day after.
bool eventDayHasPassed(DateTime? endDate, DateTime now) {
  if (endDate == null) return false;
  return now.isAfter(
    DateTime.utc(endDate.year, endDate.month, endDate.day + 1, 12),
  );
}

/// Whether an alliance has won two finals matches in the TBA [schedule].
bool _finalsWon(String eventKey, List<CompetitionMatch> schedule) {
  final wins = <String, int>{};
  for (final match in schedule) {
    if (match.event.id != eventKey || match.level != 'f') continue;
    final winner = match.winningAlliance;
    if (winner == 'red' || winner == 'blue') {
      wins[winner!] = (wins[winner] ?? 0) + 1;
    }
  }
  return wins.values.any((count) => count >= 2);
}

List<UpNextFeedMatch> _scheduleMatches(
  String eventKey,
  List<CompetitionMatch> schedule,
) {
  return [
    for (final match in schedule)
      if (match.event.id == eventKey && isUpNextCompLevel(match.level))
        UpNextFeedMatch.scheduled(match),
  ];
}

/// Every match in the TBA [schedule], played ones included, for after the
/// event.
UpNextFeed _eventOverFeed(String eventKey, List<CompetitionMatch> schedule) {
  return UpNextFeed(
    source: UpNextSource.schedule,
    matches: _scheduleMatches(eventKey, schedule),
    eventOver: true,
  );
}

/// Uses Nexus when it has qualification or playoff matches, otherwise the
/// TBA [schedule] from Honeycomb `/matches`. Once the finals are won, shows
/// the whole schedule instead.
UpNextFeed selectUpNextFeed({
  required String eventKey,
  required NexusFetchResult nexus,
  int? playoffType,
  List<CompetitionMatch> schedule = const [],
}) {
  if (_finalsWon(eventKey, schedule)) return _eventOverFeed(eventKey, schedule);

  final status = switch (nexus) {
    NexusAvailable(:final status) => status,
    NexusEmpty(:final status) => status,
    NexusFailed() => null,
  };

  if (status != null && nexus is NexusAvailable) {
    final matches = _nexusUpNextMatches(eventKey, status);
    if (matches.isNotEmpty) {
      final allMatches = _oneMatchPerKey(_nexusPlayOrder(eventKey, status));
      return UpNextFeed(
        source: UpNextSource.nexus,
        matches: matches,
        allMatches: allMatches,
        doubleElimination: isDoubleElimination(playoffType, allMatches),
        nexus: status,
      );
    }
  }

  final allMatches = _scheduleMatches(eventKey, schedule);
  return UpNextFeed(
    source: UpNextSource.schedule,
    matches: withoutPlayedMatches(allMatches),
    allMatches: allMatches,
    doubleElimination: isDoubleElimination(playoffType, allMatches),
    nexus: status,
    nexusProblem:
        nexus.problem ?? 'Nexus has no qualification or playoff matches yet',
  );
}

bool _nexusHasFinals(String eventKey, NexusFetchResult nexus) {
  return eventKey.trim().isNotEmpty &&
      nexus is NexusAvailable &&
      nexus.status.matches.any((match) => match.ref?.compLevel == 'f');
}

/// Up Next matches for a TBA event key: Nexus when available, otherwise the
/// schedule, and the whole schedule once the event is over. The mirrored
/// schedule stays subscribed while Nexus is live so fallback can render at once.
final upNextFeedProvider = Provider.autoDispose
    .family<AsyncValue<UpNextFeed>, String>((ref, eventKey) {
      final event = ref.watch(competitionEventProvider(eventKey));
      final metadata = event.when(
        data: AsyncData<CompetitionEvent?>.new,
        error: (_, _) => const AsyncData<CompetitionEvent?>(null),
        loading: AsyncLoading<CompetitionEvent?>.new,
      );
      // Keep the mirrored fallback warm while the live queue is displayed.
      final liveSchedule = isMirroredTbaKey(eventKey)
          ? ref.watch(competitionMatchesProvider(eventKey))
          : null;
      AsyncValue<QueryResult<CompetitionMatch>> watchSchedule() =>
          liveSchedule ?? ref.watch(competitionMatchesProvider(eventKey));

      return metadata.flatMap((event) {
        if (eventDayHasPassed(event?.endDate, DateTime.now())) {
          return watchSchedule().whenData(
            (result) =>
                _eventOverFeed(eventKey, result.requireAvailable().items),
          );
        }
        return ref.watch(nexusEventStatusProvider(eventKey)).flatMap((nexus) {
          if (!needsScheduleFallback(eventKey, nexus) &&
              !_nexusHasFinals(eventKey, nexus)) {
            return AsyncData(
              selectUpNextFeed(
                eventKey: eventKey,
                nexus: nexus,
                playoffType: event?.playoffType,
              ),
            );
          }
          return watchSchedule().whenData(
            (result) => selectUpNextFeed(
              eventKey: eventKey,
              nexus: nexus,
              playoffType: event?.playoffType,
              schedule: result.requireAvailable().items,
            ),
          );
        });
      });
    });
