import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';
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
  final List<ScoutingMatch> matches;

  /// Every match from the same source, played ones included, for working out
  /// playoff alliances and brackets.
  final List<ScoutingMatch> allMatches;

  /// Whether the playoffs use FRC's 8-alliance double-elimination bracket.
  final bool doubleElimination;

  /// The event has finished, so Up Next shows the TBA schedule without Nexus.
  final bool eventOver;

  /// Event-level Nexus data such as `nowQueuing`, when Honeycomb returned it.
  final NexusEventStatus? nexus;

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
List<ScoutingMatch> withoutPlayedMatches(List<ScoutingMatch> playOrder) {
  bool hasGoneOnField(ScoutingMatch match) {
    final nexus = match.nexus;
    if (nexus == null) return false;
    final times = nexus['times'];
    return nexus['status']?.toString().toLowerCase() == 'on field' ||
        (times is Map && times['actualOnFieldTime'] != null);
  }

  bool hasTbaResult(ScoutingMatch match) =>
      match.actualTime != null ||
      (match.redAlliance?.score ?? -1) >= 0 ||
      (match.blueAlliance?.score ?? -1) >= 0;

  final current = playOrder.lastIndexWhere(hasGoneOnField);
  return playOrder
      .skip(current < 0 ? 0 : current)
      .where((match) => !hasTbaResult(match))
      .toList(growable: false);
}

List<ScoutingMatch> _nexusPlayOrder(String eventKey, NexusEventStatus status) {
  return status.matches
      .map((match) => match.toScoutingMatch(eventKey))
      .whereType<ScoutingMatch>()
      .where((match) => isUpNextCompLevel(match.compLevel))
      .toList(growable: false);
}

/// One match per TBA match key. A replay replaces the original match.
List<ScoutingMatch> _oneMatchPerKey(Iterable<ScoutingMatch> matches) {
  final byKey = <String, ScoutingMatch>{};
  for (final match in matches) {
    byKey[match.key] = match;
  }
  return byKey.values.toList(growable: false);
}

/// Unplayed Nexus matches, one per TBA match key.
List<ScoutingMatch> _nexusUpNextMatches(
  String eventKey,
  NexusEventStatus status,
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
bool _finalsWon(String eventKey, List<Map<String, dynamic>> schedule) {
  final wins = <String, int>{};
  for (final match in schedule) {
    if (match['event_key'] != eventKey || match['comp_level'] != 'f') continue;
    final winner = match['winning_alliance'];
    if (winner == 'red' || winner == 'blue') {
      wins[winner as String] = (wins[winner] ?? 0) + 1;
    }
  }
  return wins.values.any((count) => count >= 2);
}

List<ScoutingMatch> _scheduleMatches(
  String eventKey,
  List<Map<String, dynamic>> schedule,
) {
  return schedule
      .map(ScoutingMatch.fromJson)
      .where((match) => match.eventKey == eventKey)
      .where((match) => isUpNextCompLevel(match.compLevel))
      .toList(growable: false);
}

/// Every match in the TBA [schedule], played ones included, for after the
/// event.
UpNextFeed _eventOverFeed(
  String eventKey,
  List<Map<String, dynamic>> schedule,
) {
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
  List<Map<String, dynamic>> schedule = const [],
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
        doubleElimination: isDoubleElimination(status.playoffType, allMatches),
        nexus: status,
      );
    }
  }

  final allMatches = _scheduleMatches(eventKey, schedule);
  return UpNextFeed(
    source: UpNextSource.schedule,
    matches: withoutPlayedMatches(allMatches),
    allMatches: allMatches,
    doubleElimination: isDoubleElimination(status?.playoffType, allMatches),
    nexus: status,
    nexusProblem:
        nexus.problem ?? 'Nexus has no qualification or playoff matches yet',
  );
}

/// Disables Riverpod's automatic retry. A retrying provider reports loading,
/// and the Nexus poll resets the retry count every [nexusPollInterval], so a
/// failure anywhere in the Up Next chain would otherwise spin forever.
Duration? upNextNoRetry(int retryCount, Object error) => null;

const schedulePollInterval = Duration(minutes: 1);

/// The TBA schedule for an event, refetched [schedulePollInterval] after each
/// response while something is listening, so new results show up.
final scheduleMatchesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, eventKey) async {
      final client = ref.watch(honeycombClientProvider);
      final List<dynamic> response;
      try {
        response = await client.get<List<dynamic>>(
          '/matches',
          queryParams: {'event': eventKey},
          cachePolicy: CachePolicy.networkFirst,
        );
      } catch (error) {
        debugPrint('Up Next: schedule request for $eventKey failed: $error');
        rethrow;
      }

      if (ref.mounted) {
        final timer = Timer(schedulePollInterval, ref.invalidateSelf);
        ref.onDispose(timer.cancel);
      }
      return response
          .whereType<Map>()
          .map((match) => Map<String, dynamic>.from(match))
          .toList(growable: false);
    }, retry: upNextNoRetry);

/// TBA's last day of the event, or null when Honeycomb doesn't say.
final eventEndDateProvider = FutureProvider.autoDispose
    .family<DateTime?, String>((ref, eventKey) async {
      final client = ref.watch(honeycombClientProvider);
      try {
        final response = await client.get<dynamic>(
          '/events',
          queryParams: {'event': eventKey, 'enrich': 'false'},
          cachePolicy: CachePolicy.networkFirst,
        );
        final event = switch (response) {
          Map() => response,
          List() =>
            response
                .whereType<Map>()
                .where((event) => event['key']?.toString() == eventKey)
                .firstOrNull,
          _ => null,
        };
        final endDate = event?['endDate'] ?? event?['end_date'];
        return endDate == null ? null : DateTime.tryParse(endDate.toString());
      } catch (error) {
        debugPrint('Up Next: event request for $eventKey failed: $error');
        return null;
      }
    }, retry: upNextNoRetry);

bool _nexusHasFinals(String eventKey, NexusFetchResult nexus) {
  return nexus is NexusAvailable &&
      nexus.status.matches.any(
        (match) => match.toScoutingMatch(eventKey)?.compLevel == 'f',
      );
}

/// Up Next matches for a TBA event key: Nexus when available, otherwise the
/// schedule, and the whole schedule once the event is over. Only fetches the
/// schedule when it is needed: without Nexus, once the finals are on, or after
/// the event.
final upNextFeedProvider = FutureProvider.autoDispose
    .family<UpNextFeed, String>((ref, eventKey) async {
      final endDate = await ref.watch(eventEndDateProvider(eventKey).future);
      if (eventDayHasPassed(endDate, DateTime.now())) {
        final schedule = await ref.watch(
          scheduleMatchesProvider(eventKey).future,
        );
        return _eventOverFeed(eventKey, schedule);
      }

      final nexus = await ref.watch(nexusEventStatusProvider(eventKey).future);
      if (!needsScheduleFallback(eventKey, nexus) &&
          !_nexusHasFinals(eventKey, nexus)) {
        return selectUpNextFeed(eventKey: eventKey, nexus: nexus);
      }

      final schedule = await ref.watch(
        scheduleMatchesProvider(eventKey).future,
      );
      return selectUpNextFeed(
        eventKey: eventKey,
        nexus: nexus,
        schedule: schedule,
      );
    }, retry: upNextNoRetry);
