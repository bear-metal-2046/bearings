import 'package:beariscope/models/match_nexus_info.dart';
import 'package:beariscope/models/up_next_match.dart';
import 'package:beariscope/pages/up_next/enriched_current_event_provider.dart';
import 'package:beariscope/pages/up_next/nexus_match_merge.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';

final upNextProvider = FutureProvider<List<UpNextMatch>>((ref) async {
  final client = ref.watch(honeycombClientProvider);
  final currentEventKey = ref.watch(currentEventProvider);
  final enrichedFuture = ref.watch(enrichedCurrentEventProvider.future);

  final matchesFuture = client.get<List<dynamic>>(
    '/matches',
    queryParams: {'event': currentEventKey},
    cachePolicy: CachePolicy.networkFirst,
  );
  final matches = await matchesFuture;
  final enriched = await enrichedFuture;
  final nexusMatches = enriched?.nexusMatches ?? const <MatchNexusInfo>[];

  final eventMatches =
      matches
          .whereType<Map>()
          .map((match) => Map<String, dynamic>.from(match))
          .where((match) => eventKeyForMatch(match) == currentEventKey)
          .map(
            (match) => UpNextMatch.fromMap(
              match,
              nexus: nexusMatchForTbaMatch(match, nexusMatches),
            ),
          )
          .toList()
        ..sort((a, b) => compareMatchesForUpNext(a.raw, b.raw));

  return eventMatches;
});

String? eventKeyForMatch(Map<String, dynamic> match) {
  return match['eventKey']?.toString() ?? match['event_key']?.toString();
}

int compareMatchesForUpNext(Map<String, dynamic> a, Map<String, dynamic> b) {
  final levelA = compLevelRank(compLevelForMatch(a));
  final levelB = compLevelRank(compLevelForMatch(b));
  if (levelA != levelB) return levelA.compareTo(levelB);

  final numberA = matchSortNumber(a);
  final numberB = matchSortNumber(b);
  if (numberA != numberB) return numberA.compareTo(numberB);

  return matchKeyForSort(a).compareTo(matchKeyForSort(b));
}

String matchDisplayName(Map<String, dynamic> match) {
  final compLevel = compLevelForMatch(match);
  final matchNumber = matchNumberForMatch(match);
  final setNumber = setNumberForMatch(match);

  switch (compLevel) {
    case 'qm':
      return 'Qualification Match ${matchNumber ?? ''}'.trim();
    case 'sf':
      return 'Semifinal Match ${setNumber ?? matchNumber ?? ''}'.trim();
    case 'f':
      return 'Final Match ${matchNumber ?? ''}'.trim();
    default:
      return defaultMatchName(match, compLevel, matchNumber);
  }
}

String compLevelForMatch(Map<String, dynamic> match) {
  return match['compLevel']?.toString() ??
      match['comp_level']?.toString() ??
      '';
}

int? matchNumberForMatch(Map<String, dynamic> match) {
  final value = match['matchNumber'] ?? match['match_number'];
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

int? setNumberForMatch(Map<String, dynamic> match) {
  final value = match['setNumber'] ?? match['set_number'];
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

int matchSortNumber(Map<String, dynamic> match) {
  final compLevel = compLevelForMatch(match);
  return switch (compLevel) {
    'qm' => matchNumberForMatch(match) ?? 0,
    'sf' => setNumberForMatch(match) ?? matchNumberForMatch(match) ?? 0,
    'f' => matchNumberForMatch(match) ?? 0,
    _ => matchNumberForMatch(match) ?? setNumberForMatch(match) ?? 0,
  };
}

int compLevelRank(String compLevel) {
  return switch (compLevel) {
    'qm' => 0,
    'sf' => 1,
    'f' => 2,
    _ => 3,
  };
}

String matchKeyForSort(Map<String, dynamic> match) {
  return match['key']?.toString() ?? '';
}

String defaultMatchName(
  Map<String, dynamic> match,
  String compLevel,
  int? matchNumber,
) {
  if (compLevel.isEmpty) return match['key']?.toString() ?? '';
  if (matchNumber != null) return '$compLevel $matchNumber';
  return compLevel;
}
