import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:services/providers/api_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';

enum Alliances { same, opposite, all }

// fetches matches only for the currently selected event
final currentEventMatchesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final selectedEvent = ref.watch(currentEventProvider);
  final client = ref.watch(honeycombClientProvider);

  if (selectedEvent.isEmpty) return [];

  final matchData = await client.get<List<dynamic>>(
    '/matches',
    queryParams: {'event': selectedEvent},
    cachePolicy: CachePolicy.networkFirst,
  );

  return _toStringKeyMaps(matchData);
});

// fetches all matches for a specific team across ALL events
final teamMatchesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      teamKey,
    ) async {
      final client = ref.watch(honeycombClientProvider);

      final matchData = await client.get<List<dynamic>>(
        '/events',
        queryParams: {'team': teamKey},
        cachePolicy: CachePolicy.networkFirst,
      );

      return _toStringKeyMaps(matchData);
    });

final team1SearchProvider = StateProvider<String?>((ref) => null);
final team2SearchProvider = StateProvider<String?>((ref) => null);
final allianceFilterProvider = StateProvider<Alliances>((ref) => Alliances.all);
final currentEventOnlyProvider = StateProvider<bool>((ref) => true);

final filteredMatchesProvider =
    Provider<AsyncValue<List<Map<String, dynamic>>>>((ref) {
      final team1 = ref.watch(team1SearchProvider);
      final team2 = ref.watch(team2SearchProvider);
      final allianceFilter = ref.watch(allianceFilterProvider);
      final eventOnly = ref.watch(currentEventOnlyProvider);

      final AsyncValue<List<Map<String, dynamic>>> matchesAsync;

      if (eventOnly) {
        matchesAsync = ref.watch(currentEventMatchesProvider);
      } else {
        if (team1 == null || team1.isEmpty) {
          matchesAsync = const AsyncValue.data([]);
        } else {
          matchesAsync = ref.watch(teamMatchesProvider('frc$team1'));
        }
      }

      // performs the filtering on the retrieved data
      return matchesAsync.whenData((allMatches) {
        if (team1 == null || team2 == null || team1.isEmpty || team2.isEmpty) {
          return [];
        }

        final t1Key = 'frc$team1';
        final t2Key = 'frc$team2';

        return allMatches.where((match) {
          final alliances = match['alliances'] ?? {};
          final redTeams = List<String>.from(
            alliances['red']?['team_keys'] ?? [],
          );
          final blueTeams = List<String>.from(
            alliances['blue']?['team_keys'] ?? [],
          );

          bool t1Red = redTeams.contains(t1Key);
          bool t1Blue = blueTeams.contains(t1Key);
          bool t2Red = redTeams.contains(t2Key);
          bool t2Blue = blueTeams.contains(t2Key);

          // both teams must be present in the match somewhere
          if (!((t1Red || t1Blue) && (t2Red || t2Blue))) return false;

          // apply the "same" vs "opposite" alliance filter
          return switch (allianceFilter) {
            Alliances.same => (t1Red && t2Red) || (t1Blue && t2Blue),
            Alliances.opposite => (t1Red && t2Blue) || (t1Blue && t2Red),
            Alliances.all => true,
          };
        }).toList();
      });
    });

// ensures the dynamic list from API is cast correctly to map<string, dynamic>
List<Map<String, dynamic>> _toStringKeyMaps(List<dynamic> data) {
  return data
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
