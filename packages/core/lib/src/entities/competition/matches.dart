part of 'competition_entities.dart';

@GroveValue()
class CompetitionAlliance {
  const CompetitionAlliance({
    this.teams = const [],
    this.surrogateTeams = const [],
    this.disqualifiedTeams = const [],
    this.score,
    this.gameBreakdown,
  });

  final List<EntityRef<CompetitionTeam>> teams;
  final List<EntityRef<CompetitionTeam>> surrogateTeams;
  final List<EntityRef<CompetitionTeam>> disqualifiedTeams;
  final int? score;

  /// TBA's game-specific scoring fields vary by season.
  final Json? gameBreakdown;
}

@GroveValue()
class MatchVideo {
  const MatchVideo({required this.type, required this.key});

  final String type;
  final String key;
}

@GroveEntity('match', version: 1, serverManaged: true)
class CompetitionMatch {
  const CompetitionMatch({
    required this.id,
    required this.season,
    required this.event,
    required this.level,
    required this.setNumber,
    required this.matchNumber,
    required this.practice,
    this.teams = const [],
    this.red,
    this.blue,
    this.winningAlliance,
    this.scheduledAt,
    this.predictedAt,
    this.playedAt,
    this.resultPostedAt,
    this.videos = const [],
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final String level;
  final int setNumber;
  final int matchNumber;
  final bool practice;
  final List<EntityRef<CompetitionTeam>> teams;
  final CompetitionAlliance? red;
  final CompetitionAlliance? blue;
  final String? winningAlliance;
  final DateTime? scheduledAt;
  final DateTime? predictedAt;
  final DateTime? playedAt;
  final DateTime? resultPostedAt;
  final List<MatchVideo> videos;

  static const participatingTeams =
      EntityField<CompetitionMatch, List<EntityRef<CompetitionTeam>>>('teams');
}
