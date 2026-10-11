import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/nexus_provider.dart';

enum UpNextSource { nexus, schedule }

class UpNextFeed {
  const UpNextFeed({
    required this.source,
    required this.matches,
    this.nexus,
    this.nexusProblem,
  });

  final UpNextSource source;
  final List<ScoutingMatch> matches;

  /// Event-level Nexus data such as `nowQueuing`, when Honeycomb returned it.
  final NexusEventStatus? nexus;

  /// Why the schedule is shown instead of Nexus, or null when using Nexus.
  final String? nexusProblem;
}

/// The comp levels Up Next shows. Practice matches are left out because TBA
/// has no match key for them, so the match preview cannot open them.
bool isUpNextCompLevel(String compLevel) =>
    const {'qm', 'sf', 'f'}.contains(compLevel);

/// Nexus matches in play order, one per TBA match key. A replay replaces the
/// original match but keeps its position.
List<ScoutingMatch> nexusUpNextMatches(
  String eventKey,
  NexusEventStatus status,
) {
  final byKey = <String, ScoutingMatch>{};
  for (final match in status.matches) {
    final scoutingMatch = match.toScoutingMatch(eventKey);
    if (scoutingMatch == null || !isUpNextCompLevel(scoutingMatch.compLevel)) {
      continue;
    }
    byKey[scoutingMatch.key] = scoutingMatch;
  }
  return byKey.values.toList(growable: false);
}

bool needsScheduleFallback(String eventKey, NexusFetchResult nexus) {
  return switch (nexus) {
    NexusAvailable(:final status) => nexusUpNextMatches(
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
    final matches = nexusUpNextMatches(eventKey, status);
    if (matches.isNotEmpty) {
      return UpNextFeed(
        source: UpNextSource.nexus,
        matches: matches,
        nexus: status,
      );
    }
  }

  return UpNextFeed(
    source: UpNextSource.schedule,
    matches: schedule
        .map(ScoutingMatch.fromJson)
        .where((match) => match.eventKey == eventKey)
        .where((match) => isUpNextCompLevel(match.compLevel))
        .toList(growable: false),
    nexus: status,
    nexusProblem:
        nexus.problem ?? 'Nexus has no qualification or playoff matches yet',
  );
}

final scheduleMatchesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, eventKey) async {
      final response = await ref
          .watch(honeycombClientProvider)
          .get<List<dynamic>>(
            '/matches',
            queryParams: {'event': eventKey},
            cachePolicy: CachePolicy.networkFirst,
          );
      return response
          .whereType<Map>()
          .map((match) => Map<String, dynamic>.from(match))
          .toList(growable: false);
    });

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
    });
