import 'package:core/core.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';

enum PitsScoutingFilter { allTeams, notScouted, scouted }

List<Team> parsePitsTeams(List<CompetitionTeam> data) {
  return data
      .map(Team.fromCompetition)
      .where((team) => team.number > 0)
      .toList()
    ..sort((a, b) => a.number.compareTo(b.number));
}

List<Team> filterPitsTeams({
  required List<Team> teams,
  required String query,
  required Set<int> scoutedTeamNumbers,
  required PitsScoutingFilter statusFilter,
}) {
  final queryFiltered = teams
      .where((team) => teamMatchesSearch(team, query))
      .toList();

  return queryFiltered.where((team) {
    final isScouted = scoutedTeamNumbers.contains(team.number);
    return switch (statusFilter) {
      PitsScoutingFilter.allTeams => true,
      PitsScoutingFilter.notScouted => !isScouted,
      PitsScoutingFilter.scouted => isScouted,
    };
  }).toList();
}
