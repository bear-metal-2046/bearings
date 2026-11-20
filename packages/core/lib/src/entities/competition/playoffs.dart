part of 'competition_entities.dart';

@GroveValue()
class AllianceBackup {
  const AllianceBackup({required this.incoming, required this.outgoing});

  final EntityRef<CompetitionTeam> incoming;
  final EntityRef<CompetitionTeam> outgoing;
}

@GroveValue()
class PlayoffStatus {
  const PlayoffStatus({
    this.playoffType,
    this.level,
    this.status,
    this.doubleEliminationRound,
    this.currentLevelRecord,
    this.record,
    this.playoffAverage,
    this.advancedToRoundRobinFinals,
    this.roundRobinRank,
  });

  final int? playoffType;
  final String? level;
  final String? status;
  final String? doubleEliminationRound;
  final WinLossRecord? currentLevelRecord;
  final WinLossRecord? record;
  final double? playoffAverage;
  final bool? advancedToRoundRobinFinals;
  final int? roundRobinRank;
}

@GroveEntity('playoff_alliance', version: 1, serverManaged: true)
class PlayoffAlliance {
  const PlayoffAlliance({
    required this.id,
    required this.season,
    required this.event,
    required this.number,
    this.name,
    this.picks = const [],
    this.declines = const [],
    this.backup,
    this.status,
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final int number;
  final String? name;
  final List<EntityRef<CompetitionTeam>> picks;
  final List<EntityRef<CompetitionTeam>> declines;
  final AllianceBackup? backup;
  final PlayoffStatus? status;
}

@GroveValue()
class PlayoffRanking {
  const PlayoffRanking({
    this.teams = const [],
    required this.allianceName,
    this.allianceColor,
    this.rank,
    this.record,
    this.matchesPlayed,
    this.sortOrders = const [],
    this.extraStats = const [],
  });

  final List<EntityRef<CompetitionTeam>> teams;
  final String allianceName;
  final String? allianceColor;
  final int? rank;
  final WinLossRecord? record;
  final int? matchesPlayed;
  final List<double> sortOrders;
  final List<double> extraStats;
}

@GroveEntity('playoff_advancement', version: 1, serverManaged: true)
class PlayoffAdvancement {
  const PlayoffAdvancement({
    required this.id,
    required this.season,
    required this.event,
    required this.level,
    required this.name,
    required this.type,
    this.rankings,
    this.sortOrderInfo = const [],
    this.extraStatsInfo = const [],
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final String level;
  final String name;
  final String type;
  final List<PlayoffRanking>? rankings;
  final List<RankingMetric> sortOrderInfo;
  final List<RankingMetric> extraStatsInfo;
}
