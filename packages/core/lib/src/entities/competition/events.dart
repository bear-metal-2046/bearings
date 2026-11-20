part of 'competition_entities.dart';

@GroveValue()
class EventWebcast {
  const EventWebcast({
    required this.type,
    required this.channel,
    this.date,
    this.file,
    this.status,
    this.streamTitle,
    this.viewerCount,
  });

  final String type;
  final String channel;
  final String? date;
  final String? file;
  final String? status;
  final String? streamTitle;
  final int? viewerCount;
}

@GroveEntity('event', version: 1, serverManaged: true)
class CompetitionEvent {
  const CompetitionEvent({
    required this.id,
    required this.season,
    required this.name,
    required this.code,
    this.eventType,
    this.eventTypeName,
    this.shortName,
    this.week,
    this.startDate,
    this.endDate,
    required this.location,
    this.timezone,
    this.website,
    this.firstEventId,
    this.firstEventCode,
    this.district,
    this.parent,
    this.divisions = const [],
    this.playoffType,
    this.playoffTypeName,
    this.webcasts = const [],
    this.remappedTeams = const {},
  });

  final String id;
  final int season;
  final String name;
  final String code;
  final int? eventType;
  final String? eventTypeName;
  final String? shortName;
  final int? week;
  final DateTime? startDate;
  final DateTime? endDate;
  final CompetitionLocation location;
  final String? timezone;
  final String? website;
  final String? firstEventId;
  final String? firstEventCode;
  final EntityRef<District>? district;
  final EntityRef<CompetitionEvent>? parent;
  final List<EntityRef<CompetitionEvent>> divisions;
  final int? playoffType;
  final String? playoffTypeName;
  final List<EventWebcast> webcasts;
  final Map<String, String> remappedTeams;
}

@GroveEntity('event_team', version: 1, serverManaged: true)
class EventTeam {
  const EventTeam({
    required this.id,
    required this.season,
    required this.event,
    required this.team,
    required this.profile,
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final EntityRef<CompetitionTeam> team;
  final CompetitionTeam profile;
}

@GroveEntity('event_team_status', version: 1, serverManaged: true)
class EventTeamStatus {
  const EventTeamStatus({
    required this.id,
    required this.season,
    required this.event,
    required this.team,
    this.pitLocation,
    this.qualificationTeamCount,
    this.qualificationRanking,
    this.qualificationSortOrderInfo = const [],
    this.qualificationStatus,
    this.allianceName,
    this.allianceNumber,
    this.alliancePick,
    this.allianceBackup,
    this.playoff,
    this.allianceStatusText,
    this.playoffStatusText,
    this.overallStatusText,
    this.nextMatch,
    this.lastMatch,
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final EntityRef<CompetitionTeam> team;
  final String? pitLocation;
  final int? qualificationTeamCount;
  final RankingResult? qualificationRanking;
  final List<RankingMetric> qualificationSortOrderInfo;
  final String? qualificationStatus;
  final String? allianceName;
  final int? allianceNumber;
  final int? alliancePick;
  final AllianceBackup? allianceBackup;
  final PlayoffStatus? playoff;
  final String? allianceStatusText;
  final String? playoffStatusText;
  final String? overallStatusText;
  final EntityRef<CompetitionMatch>? nextMatch;
  final EntityRef<CompetitionMatch>? lastMatch;
}
