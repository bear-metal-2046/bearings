part of 'competition_entities.dart';

@GroveValue()
class WinLossRecord {
  const WinLossRecord({
    required this.wins,
    required this.losses,
    required this.ties,
  });

  final int wins;
  final int losses;
  final int ties;
}

@GroveValue()
class RankingMetric {
  const RankingMetric({required this.name, this.precision, this.type});

  final String name;
  final double? precision;
  final String? type;
}

@GroveValue()
class RankingResult {
  const RankingResult({
    required this.rank,
    this.matchesPlayed,
    this.disqualifications,
    this.record,
    this.qualificationAverage,
    this.sortOrders = const [],
    this.extraStats = const [],
  });

  final int rank;
  final int? matchesPlayed;
  final int? disqualifications;
  final WinLossRecord? record;
  final double? qualificationAverage;
  final List<double> sortOrders;
  final List<double> extraStats;
}

@GroveEntity('event_ranking', version: 1, serverManaged: true)
class EventRanking {
  const EventRanking({
    required this.id,
    required this.season,
    required this.event,
    required this.team,
    required this.result,
    this.sortOrderInfo = const [],
    this.extraStatsInfo = const [],
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final EntityRef<CompetitionTeam> team;
  final RankingResult result;
  final List<RankingMetric> sortOrderInfo;
  final List<RankingMetric> extraStatsInfo;
}
