import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';

class TeamRanking {
  final int teamNumber;
  final int rank;
  final int rankingPoints;
  final double rankingScore;

  const TeamRanking({
    required this.teamNumber,
    required this.rank,
    required this.rankingPoints,
    required this.rankingScore,
  });
}

final eventRankingsProvider = Provider<AsyncValue<Map<int, TeamRanking>>>((
  ref,
) {
  final eventKey = ref.watch(currentEventProvider);
  return ref.watch(competitionRankingsProvider(eventKey)).whenData((data) {
    final result = <int, TeamRanking>{};
    for (final entry in data) {
      final teamKey = entry.team.id;
      if (!teamKey.startsWith('frc')) continue;
      final teamNumber = int.tryParse(teamKey.substring(3));
      if (teamNumber == null) continue;

      final rank = entry.result.rank;
      final matches = entry.result.matchesPlayed ?? 0;
      final rs = entry.result.sortOrders.firstOrNull ?? 0.0;
      final rp = (rs * matches).round();

      result[teamNumber] = TeamRanking(
        teamNumber: teamNumber,
        rank: rank,
        rankingPoints: rp,
        rankingScore: rs,
      );
    }
    return result;
  });
});
