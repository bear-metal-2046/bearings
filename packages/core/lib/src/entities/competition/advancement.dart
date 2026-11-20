part of 'competition_entities.dart';

@GroveValue()
class AdvancementPoints {
  const AdvancementPoints({
    this.total,
    this.alliance,
    this.awards,
    this.elimination,
    this.qualification,
  });

  final int? total;
  final int? alliance;
  final int? awards;
  final int? elimination;
  final int? qualification;
}

@GroveValue()
class RankingEventPoints {
  const RankingEventPoints({
    required this.event,
    required this.points,
    this.districtChampionship,
  });

  final EntityRef<CompetitionEvent> event;
  final AdvancementPoints points;
  final bool? districtChampionship;
}

@GroveEntity('advancement_ranking', version: 1, serverManaged: true)
class AdvancementRanking {
  const AdvancementRanking({
    required this.id,
    required this.season,
    this.district,
    required this.team,
    required this.rank,
    this.totalPoints,
    this.rookieBonus,
    this.singleEventBonus,
    this.otherBonus,
    this.adjustments,
    this.events = const [],
  });

  final String id;
  final int season;
  final EntityRef<District>? district;
  final EntityRef<CompetitionTeam> team;
  final int rank;
  final int? totalPoints;
  final int? rookieBonus;
  final int? singleEventBonus;
  final int? otherBonus;
  final int? adjustments;
  final List<RankingEventPoints> events;
}

@GroveEntity('event_points', version: 1, serverManaged: true)
class EventPoints {
  const EventPoints({
    required this.id,
    required this.season,
    required this.event,
    required this.team,
    required this.pool,
    this.points,
    this.highestMatchScores = const [],
    this.qualificationWins,
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final EntityRef<CompetitionTeam> team;
  final String pool;
  final AdvancementPoints? points;
  final List<int> highestMatchScores;
  final int? qualificationWins;
}

@GroveEntity('advancement', version: 1, serverManaged: true)
class Advancement {
  const Advancement({
    required this.id,
    required this.season,
    this.district,
    required this.team,
    this.districtChampionship,
    this.championship,
    this.championshipStatus,
    this.championshipQualification,
    this.qualifyingEvent,
    this.qualifyingAwardName,
    this.qualifyingPoolWeek,
  });

  final String id;
  final int season;
  final EntityRef<District>? district;
  final EntityRef<CompetitionTeam> team;
  final bool? districtChampionship;
  final bool? championship;
  final String? championshipStatus;
  final String? championshipQualification;
  final EntityRef<CompetitionEvent>? qualifyingEvent;
  final String? qualifyingAwardName;
  final int? qualifyingPoolWeek;
}

@GroveEntity('advancement_cutoffs', version: 1, serverManaged: true)
class AdvancementCutoffs {
  const AdvancementCutoffs({
    required this.id,
    required this.season,
    required this.district,
    this.districtChampionshipOriginal,
    this.districtChampionshipEffective,
    this.districtChampionshipDeclines = const [],
    this.championshipOriginal,
    this.championshipEffective,
    this.championshipDeclines = const [],
  });

  final String id;
  final int season;
  final EntityRef<District> district;
  final int? districtChampionshipOriginal;
  final int? districtChampionshipEffective;
  final List<EntityRef<CompetitionTeam>> districtChampionshipDeclines;
  final int? championshipOriginal;
  final int? championshipEffective;
  final List<EntityRef<CompetitionTeam>> championshipDeclines;
}
