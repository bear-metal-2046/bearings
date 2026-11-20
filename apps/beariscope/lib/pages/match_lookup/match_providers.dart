import 'package:core/core.dart' show CompetitionMatch;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';

enum Alliances { same, opposite, all }

final team1SearchProvider = StateProvider<String?>((ref) => null);
final team2SearchProvider = StateProvider<String?>((ref) => null);
final allianceFilterProvider = StateProvider<Alliances>((ref) => Alliances.all);
final currentEventOnlyProvider = StateProvider<bool>((ref) => true);

final filteredMatchesProvider = Provider<AsyncValue<List<CompetitionMatch>>>((
  ref,
) {
  final team1 = ref.watch(team1SearchProvider);
  final team2 = ref.watch(team2SearchProvider);
  final allianceFilter = ref.watch(allianceFilterProvider);
  final eventOnly = ref.watch(currentEventOnlyProvider);

  final AsyncValue<List<CompetitionMatch>> matchesAsync;

  if (eventOnly) {
    matchesAsync = ref
        .watch(competitionMatchesProvider(ref.watch(currentEventProvider)))
        .whenData((result) => result.requireAvailable().items);
  } else {
    if (team1 == null || team1.isEmpty) {
      matchesAsync = const AsyncValue.data([]);
    } else {
      matchesAsync = ref.watch(competitionTeamMatchesProvider('frc$team1'));
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
      final redTeams = match.red?.teams.map((team) => team.id) ?? const [];
      final blueTeams = match.blue?.teams.map((team) => team.id) ?? const [];

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
