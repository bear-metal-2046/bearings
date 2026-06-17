import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';
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

final eventRankingsProvider = FutureProvider<Map<int, TeamRanking>>((
  ref,
) async {
  final eventKey = ref.watch(currentEventProvider);
  final client = ref.watch(honeycombClientProvider);

  try {
    final data = await client.get<List<dynamic>>(
      '/rankings',
      queryParams: {'event': eventKey},
      cachePolicy: CachePolicy.networkFirst,
    );

    final result = <int, TeamRanking>{};
    for (final entry in data) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);

      final teamKey = (map['teamKey'] ?? '').toString();
      if (!teamKey.startsWith('frc')) continue;

      final teamNumber = int.tryParse(teamKey.substring(3));
      if (teamNumber == null) continue;

      final rank = (map['rank'] as num?)?.toInt() ?? 0;
      final matches = (map['matchesPlayed'] as num?)?.toInt() ?? 0;
      final rp = (map['rankingPoints'] as num?)?.toInt() ?? 0;
      final rs = (rp / matches).toDouble();

      result[teamNumber] = TeamRanking(
        teamNumber: teamNumber,
        rank: rank,
        rankingPoints: rp,
        rankingScore: rs,
      );
    }
    return result;
  } catch (_) {
    // no rankings just return
    return {};
  }
});
