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
    this.nexus,
    this.nexusProblem,
  });

  final UpNextSource source;

  /// Unplayed matches to show.
  final List<ScoutingMatch> matches;

  /// Every match from the same source, played ones included, for working out
  /// playoff alliances and brackets.
  final List<ScoutingMatch> allMatches;

  /// Whether the playoffs use FRC's 8-alliance double-elimination bracket.
  final bool doubleElimination;

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

/// Uses Nexus when it has qualification or playoff matches, otherwise the
/// TBA [schedule] from Honeycomb `/matches`.
UpNextFeed selectUpNextFeed({
  required String eventKey,
  required NexusFetchResult nexus,
  List<Map<String, dynamic>> schedule = const [],
}) {
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

  final allMatches = schedule
      .map(ScoutingMatch.fromJson)
      .where((match) => match.eventKey == eventKey)
      .where((match) => isUpNextCompLevel(match.compLevel))
      .toList(growable: false);
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

final scheduleMatchesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, eventKey) async {
      final client = ref.watch(honeycombClientProvider);
      try {
        final response = await client.get<List<dynamic>>(
          '/matches',
          queryParams: {'event': eventKey},
          cachePolicy: CachePolicy.networkFirst,
        );
        return response
            .whereType<Map>()
            .map((match) => Map<String, dynamic>.from(match))
            .toList(growable: false);
      } catch (error) {
        debugPrint('Up Next: schedule request for $eventKey failed: $error');
        rethrow;
      }
    }, retry: upNextNoRetry);

/// Up Next matches for a TBA event key: Nexus when available, otherwise the
/// schedule. Only fetches the schedule when it is needed.
final upNextFeedProvider = FutureProvider.autoDispose
    .family<UpNextFeed, String>((ref, eventKey) async {
      final nexus = await ref.watch(nexusEventStatusProvider(eventKey).future);
      if (!needsScheduleFallback(eventKey, nexus)) {
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
