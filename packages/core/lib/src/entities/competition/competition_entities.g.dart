// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'competition_entities.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _CompetitionTeamToGroveJson(CompetitionTeam value) => {
  "id": value.id,
  "number": value.number,
  "nickname": value.nickname,
  "name": value.name,
  "schoolName": value.schoolName,
  "location": _CompetitionLocationToGroveJson(value.location),
  "website": value.website,
  "rookieYear": value.rookieYear,
  "motto": value.motto,
};
CompetitionTeam _CompetitionTeamFromGroveJson(Json json) => CompetitionTeam(
  id: json["id"] as String,
  number: json["number"] as int,
  nickname: json["nickname"] as String?,
  name: json["name"] as String?,
  schoolName: json["schoolName"] as String?,
  location: _CompetitionLocationFromGroveJson(json["location"] as Json),
  website: json["website"] as String?,
  rookieYear: json["rookieYear"] as int?,
  motto: json["motto"] as String?,
);

final competitionTeamEntity = EntityDescriptor<CompetitionTeam>(
  type: "team",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _CompetitionTeamToGroveJson,
  decode: _CompetitionTeamFromGroveJson,
);

abstract final class CompetitionTeamFields {
  static const id = EntityField<CompetitionTeam, String>("id");
  static const number = EntityField<CompetitionTeam, int>("number");
  static const nickname = EntityField<CompetitionTeam, String?>("nickname");
  static const name = EntityField<CompetitionTeam, String?>("name");
  static const schoolName = EntityField<CompetitionTeam, String?>("schoolName");
  static const website = EntityField<CompetitionTeam, String?>("website");
  static const rookieYear = EntityField<CompetitionTeam, int?>("rookieYear");
  static const motto = EntityField<CompetitionTeam, String?>("motto");
}

Json _TeamSeasonToGroveJson(TeamSeason value) => {
  "id": value.id,
  "season": value.season,
  "team": value.team.id,
};
TeamSeason _TeamSeasonFromGroveJson(Json json) => TeamSeason(
  id: json["id"] as String,
  season: json["season"] as int,
  team: EntityRef<CompetitionTeam>(json["team"] as String),
);

final teamSeasonEntity = EntityDescriptor<TeamSeason>(
  type: "team_season",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _TeamSeasonToGroveJson,
  decode: _TeamSeasonFromGroveJson,
);

abstract final class TeamSeasonFields {
  static const id = EntityField<TeamSeason, String>("id");
  static const season = EntityField<TeamSeason, int>("season");
  static const team = EntityField<TeamSeason, EntityRef<CompetitionTeam>>(
    "team",
  );
}

Json _TeamRobotToGroveJson(TeamRobot value) => {
  "id": value.id,
  "season": value.season,
  "team": value.team.id,
  "name": value.name,
};
TeamRobot _TeamRobotFromGroveJson(Json json) => TeamRobot(
  id: json["id"] as String,
  season: json["season"] as int,
  team: EntityRef<CompetitionTeam>(json["team"] as String),
  name: json["name"] as String,
);

final teamRobotEntity = EntityDescriptor<TeamRobot>(
  type: "team_robot",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _TeamRobotToGroveJson,
  decode: _TeamRobotFromGroveJson,
);

abstract final class TeamRobotFields {
  static const id = EntityField<TeamRobot, String>("id");
  static const season = EntityField<TeamRobot, int>("season");
  static const team = EntityField<TeamRobot, EntityRef<CompetitionTeam>>(
    "team",
  );
  static const name = EntityField<TeamRobot, String>("name");
}

Json _CompetitionEventToGroveJson(CompetitionEvent value) => {
  "id": value.id,
  "season": value.season,
  "name": value.name,
  "code": value.code,
  "eventType": value.eventType,
  "eventTypeName": value.eventTypeName,
  "shortName": value.shortName,
  "week": value.week,
  "startDate": value.startDate == null
      ? null
      : value.startDate!.toUtc().toIso8601String(),
  "endDate": value.endDate == null
      ? null
      : value.endDate!.toUtc().toIso8601String(),
  "location": _CompetitionLocationToGroveJson(value.location),
  "timezone": value.timezone,
  "website": value.website,
  "firstEventId": value.firstEventId,
  "firstEventCode": value.firstEventCode,
  "district": value.district == null ? null : value.district!.id,
  "parent": value.parent == null ? null : value.parent!.id,
  "divisions": value.divisions.map((item) => item.id).toList(),
  "playoffType": value.playoffType,
  "playoffTypeName": value.playoffTypeName,
  "webcasts": value.webcasts
      .map((item) => _EventWebcastToGroveJson(item))
      .toList(),
  "remappedTeams": value.remappedTeams.map((key, item) => MapEntry(key, item)),
};
CompetitionEvent _CompetitionEventFromGroveJson(Json json) => CompetitionEvent(
  id: json["id"] as String,
  season: json["season"] as int,
  name: json["name"] as String,
  code: json["code"] as String,
  eventType: json["eventType"] as int?,
  eventTypeName: json["eventTypeName"] as String?,
  shortName: json["shortName"] as String?,
  week: json["week"] as int?,
  startDate: json["startDate"] == null
      ? null
      : DateTime.parse(json["startDate"] as String),
  endDate: json["endDate"] == null
      ? null
      : DateTime.parse(json["endDate"] as String),
  location: _CompetitionLocationFromGroveJson(json["location"] as Json),
  timezone: json["timezone"] as String?,
  website: json["website"] as String?,
  firstEventId: json["firstEventId"] as String?,
  firstEventCode: json["firstEventCode"] as String?,
  district: json["district"] == null
      ? null
      : EntityRef<District>(json["district"] as String),
  parent: json["parent"] == null
      ? null
      : EntityRef<CompetitionEvent>(json["parent"] as String),
  divisions: (json["divisions"] as List)
      .map((item) => EntityRef<CompetitionEvent>(item as String))
      .toList(),
  playoffType: json["playoffType"] as int?,
  playoffTypeName: json["playoffTypeName"] as String?,
  webcasts: (json["webcasts"] as List)
      .map((item) => _EventWebcastFromGroveJson(item as Json))
      .toList(),
  remappedTeams: (json["remappedTeams"] as Map).map(
    (key, item) => MapEntry(key as String, item as String),
  ),
);

final competitionEventEntity = EntityDescriptor<CompetitionEvent>(
  type: "event",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _CompetitionEventToGroveJson,
  decode: _CompetitionEventFromGroveJson,
);

abstract final class CompetitionEventFields {
  static const id = EntityField<CompetitionEvent, String>("id");
  static const season = EntityField<CompetitionEvent, int>("season");
  static const name = EntityField<CompetitionEvent, String>("name");
  static const code = EntityField<CompetitionEvent, String>("code");
  static const eventType = EntityField<CompetitionEvent, int?>("eventType");
  static const eventTypeName = EntityField<CompetitionEvent, String?>(
    "eventTypeName",
  );
  static const shortName = EntityField<CompetitionEvent, String?>("shortName");
  static const week = EntityField<CompetitionEvent, int?>("week");
  static const timezone = EntityField<CompetitionEvent, String?>("timezone");
  static const website = EntityField<CompetitionEvent, String?>("website");
  static const firstEventId = EntityField<CompetitionEvent, String?>(
    "firstEventId",
  );
  static const firstEventCode = EntityField<CompetitionEvent, String?>(
    "firstEventCode",
  );
  static const district = EntityField<CompetitionEvent, EntityRef<District>?>(
    "district",
  );
  static const parent =
      EntityField<CompetitionEvent, EntityRef<CompetitionEvent>?>("parent");
  static const playoffType = EntityField<CompetitionEvent, int?>("playoffType");
  static const playoffTypeName = EntityField<CompetitionEvent, String?>(
    "playoffTypeName",
  );
}

Json _EventTeamToGroveJson(EventTeam value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "team": value.team.id,
  "profile": _CompetitionTeamToGroveJson(value.profile),
};
EventTeam _EventTeamFromGroveJson(Json json) => EventTeam(
  id: json["id"] as String,
  season: json["season"] as int,
  event: EntityRef<CompetitionEvent>(json["event"] as String),
  team: EntityRef<CompetitionTeam>(json["team"] as String),
  profile: _CompetitionTeamFromGroveJson(json["profile"] as Json),
);

final eventTeamEntity = EntityDescriptor<EventTeam>(
  type: "event_team",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _EventTeamToGroveJson,
  decode: _EventTeamFromGroveJson,
);

abstract final class EventTeamFields {
  static const id = EntityField<EventTeam, String>("id");
  static const season = EntityField<EventTeam, int>("season");
  static const event = EntityField<EventTeam, EntityRef<CompetitionEvent>>(
    "event",
  );
  static const team = EntityField<EventTeam, EntityRef<CompetitionTeam>>(
    "team",
  );
}

Json _EventTeamStatusToGroveJson(EventTeamStatus value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "team": value.team.id,
  "pitLocation": value.pitLocation,
  "qualificationTeamCount": value.qualificationTeamCount,
  "qualificationRanking": value.qualificationRanking == null
      ? null
      : _RankingResultToGroveJson(value.qualificationRanking!),
  "qualificationSortOrderInfo": value.qualificationSortOrderInfo
      .map((item) => _RankingMetricToGroveJson(item))
      .toList(),
  "qualificationStatus": value.qualificationStatus,
  "allianceName": value.allianceName,
  "allianceNumber": value.allianceNumber,
  "alliancePick": value.alliancePick,
  "allianceBackup": value.allianceBackup == null
      ? null
      : _AllianceBackupToGroveJson(value.allianceBackup!),
  "playoff": value.playoff == null
      ? null
      : _PlayoffStatusToGroveJson(value.playoff!),
  "allianceStatusText": value.allianceStatusText,
  "playoffStatusText": value.playoffStatusText,
  "overallStatusText": value.overallStatusText,
  "nextMatch": value.nextMatch == null ? null : value.nextMatch!.id,
  "lastMatch": value.lastMatch == null ? null : value.lastMatch!.id,
};
EventTeamStatus _EventTeamStatusFromGroveJson(Json json) => EventTeamStatus(
  id: json["id"] as String,
  season: json["season"] as int,
  event: EntityRef<CompetitionEvent>(json["event"] as String),
  team: EntityRef<CompetitionTeam>(json["team"] as String),
  pitLocation: json["pitLocation"] as String?,
  qualificationTeamCount: json["qualificationTeamCount"] as int?,
  qualificationRanking: json["qualificationRanking"] == null
      ? null
      : _RankingResultFromGroveJson(json["qualificationRanking"] as Json),
  qualificationSortOrderInfo: (json["qualificationSortOrderInfo"] as List)
      .map((item) => _RankingMetricFromGroveJson(item as Json))
      .toList(),
  qualificationStatus: json["qualificationStatus"] as String?,
  allianceName: json["allianceName"] as String?,
  allianceNumber: json["allianceNumber"] as int?,
  alliancePick: json["alliancePick"] as int?,
  allianceBackup: json["allianceBackup"] == null
      ? null
      : _AllianceBackupFromGroveJson(json["allianceBackup"] as Json),
  playoff: json["playoff"] == null
      ? null
      : _PlayoffStatusFromGroveJson(json["playoff"] as Json),
  allianceStatusText: json["allianceStatusText"] as String?,
  playoffStatusText: json["playoffStatusText"] as String?,
  overallStatusText: json["overallStatusText"] as String?,
  nextMatch: json["nextMatch"] == null
      ? null
      : EntityRef<CompetitionMatch>(json["nextMatch"] as String),
  lastMatch: json["lastMatch"] == null
      ? null
      : EntityRef<CompetitionMatch>(json["lastMatch"] as String),
);

final eventTeamStatusEntity = EntityDescriptor<EventTeamStatus>(
  type: "event_team_status",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _EventTeamStatusToGroveJson,
  decode: _EventTeamStatusFromGroveJson,
);

abstract final class EventTeamStatusFields {
  static const id = EntityField<EventTeamStatus, String>("id");
  static const season = EntityField<EventTeamStatus, int>("season");
  static const event =
      EntityField<EventTeamStatus, EntityRef<CompetitionEvent>>("event");
  static const team = EntityField<EventTeamStatus, EntityRef<CompetitionTeam>>(
    "team",
  );
  static const pitLocation = EntityField<EventTeamStatus, String?>(
    "pitLocation",
  );
  static const qualificationTeamCount = EntityField<EventTeamStatus, int?>(
    "qualificationTeamCount",
  );
  static const qualificationStatus = EntityField<EventTeamStatus, String?>(
    "qualificationStatus",
  );
  static const allianceName = EntityField<EventTeamStatus, String?>(
    "allianceName",
  );
  static const allianceNumber = EntityField<EventTeamStatus, int?>(
    "allianceNumber",
  );
  static const alliancePick = EntityField<EventTeamStatus, int?>(
    "alliancePick",
  );
  static const allianceStatusText = EntityField<EventTeamStatus, String?>(
    "allianceStatusText",
  );
  static const playoffStatusText = EntityField<EventTeamStatus, String?>(
    "playoffStatusText",
  );
  static const overallStatusText = EntityField<EventTeamStatus, String?>(
    "overallStatusText",
  );
  static const nextMatch =
      EntityField<EventTeamStatus, EntityRef<CompetitionMatch>?>("nextMatch");
  static const lastMatch =
      EntityField<EventTeamStatus, EntityRef<CompetitionMatch>?>("lastMatch");
}

Json _CompetitionMatchToGroveJson(CompetitionMatch value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "level": value.level,
  "setNumber": value.setNumber,
  "matchNumber": value.matchNumber,
  "practice": value.practice,
  "teams": value.teams.map((item) => item.id).toList(),
  "red": value.red == null ? null : _CompetitionAllianceToGroveJson(value.red!),
  "blue": value.blue == null
      ? null
      : _CompetitionAllianceToGroveJson(value.blue!),
  "winningAlliance": value.winningAlliance,
  "scheduledAt": value.scheduledAt == null
      ? null
      : value.scheduledAt!.toUtc().toIso8601String(),
  "predictedAt": value.predictedAt == null
      ? null
      : value.predictedAt!.toUtc().toIso8601String(),
  "playedAt": value.playedAt == null
      ? null
      : value.playedAt!.toUtc().toIso8601String(),
  "resultPostedAt": value.resultPostedAt == null
      ? null
      : value.resultPostedAt!.toUtc().toIso8601String(),
  "videos": value.videos.map((item) => _MatchVideoToGroveJson(item)).toList(),
};
CompetitionMatch _CompetitionMatchFromGroveJson(Json json) => CompetitionMatch(
  id: json["id"] as String,
  season: json["season"] as int,
  event: EntityRef<CompetitionEvent>(json["event"] as String),
  level: json["level"] as String,
  setNumber: json["setNumber"] as int,
  matchNumber: json["matchNumber"] as int,
  practice: json["practice"] as bool,
  teams: (json["teams"] as List)
      .map((item) => EntityRef<CompetitionTeam>(item as String))
      .toList(),
  red: json["red"] == null
      ? null
      : _CompetitionAllianceFromGroveJson(json["red"] as Json),
  blue: json["blue"] == null
      ? null
      : _CompetitionAllianceFromGroveJson(json["blue"] as Json),
  winningAlliance: json["winningAlliance"] as String?,
  scheduledAt: json["scheduledAt"] == null
      ? null
      : DateTime.parse(json["scheduledAt"] as String),
  predictedAt: json["predictedAt"] == null
      ? null
      : DateTime.parse(json["predictedAt"] as String),
  playedAt: json["playedAt"] == null
      ? null
      : DateTime.parse(json["playedAt"] as String),
  resultPostedAt: json["resultPostedAt"] == null
      ? null
      : DateTime.parse(json["resultPostedAt"] as String),
  videos: (json["videos"] as List)
      .map((item) => _MatchVideoFromGroveJson(item as Json))
      .toList(),
);

final competitionMatchEntity = EntityDescriptor<CompetitionMatch>(
  type: "match",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _CompetitionMatchToGroveJson,
  decode: _CompetitionMatchFromGroveJson,
);

abstract final class CompetitionMatchFields {
  static const id = EntityField<CompetitionMatch, String>("id");
  static const season = EntityField<CompetitionMatch, int>("season");
  static const event =
      EntityField<CompetitionMatch, EntityRef<CompetitionEvent>>("event");
  static const level = EntityField<CompetitionMatch, String>("level");
  static const setNumber = EntityField<CompetitionMatch, int>("setNumber");
  static const matchNumber = EntityField<CompetitionMatch, int>("matchNumber");
  static const practice = EntityField<CompetitionMatch, bool>("practice");
  static const winningAlliance = EntityField<CompetitionMatch, String?>(
    "winningAlliance",
  );
}

Json _EventRankingToGroveJson(EventRanking value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "team": value.team.id,
  "result": _RankingResultToGroveJson(value.result),
  "sortOrderInfo": value.sortOrderInfo
      .map((item) => _RankingMetricToGroveJson(item))
      .toList(),
  "extraStatsInfo": value.extraStatsInfo
      .map((item) => _RankingMetricToGroveJson(item))
      .toList(),
};
EventRanking _EventRankingFromGroveJson(Json json) => EventRanking(
  id: json["id"] as String,
  season: json["season"] as int,
  event: EntityRef<CompetitionEvent>(json["event"] as String),
  team: EntityRef<CompetitionTeam>(json["team"] as String),
  result: _RankingResultFromGroveJson(json["result"] as Json),
  sortOrderInfo: (json["sortOrderInfo"] as List)
      .map((item) => _RankingMetricFromGroveJson(item as Json))
      .toList(),
  extraStatsInfo: (json["extraStatsInfo"] as List)
      .map((item) => _RankingMetricFromGroveJson(item as Json))
      .toList(),
);

final eventRankingEntity = EntityDescriptor<EventRanking>(
  type: "event_ranking",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _EventRankingToGroveJson,
  decode: _EventRankingFromGroveJson,
);

abstract final class EventRankingFields {
  static const id = EntityField<EventRanking, String>("id");
  static const season = EntityField<EventRanking, int>("season");
  static const event = EntityField<EventRanking, EntityRef<CompetitionEvent>>(
    "event",
  );
  static const team = EntityField<EventRanking, EntityRef<CompetitionTeam>>(
    "team",
  );
}

Json _PlayoffAllianceToGroveJson(PlayoffAlliance value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "number": value.number,
  "name": value.name,
  "picks": value.picks.map((item) => item.id).toList(),
  "declines": value.declines.map((item) => item.id).toList(),
  "backup": value.backup == null
      ? null
      : _AllianceBackupToGroveJson(value.backup!),
  "status": value.status == null
      ? null
      : _PlayoffStatusToGroveJson(value.status!),
};
PlayoffAlliance _PlayoffAllianceFromGroveJson(Json json) => PlayoffAlliance(
  id: json["id"] as String,
  season: json["season"] as int,
  event: EntityRef<CompetitionEvent>(json["event"] as String),
  number: json["number"] as int,
  name: json["name"] as String?,
  picks: (json["picks"] as List)
      .map((item) => EntityRef<CompetitionTeam>(item as String))
      .toList(),
  declines: (json["declines"] as List)
      .map((item) => EntityRef<CompetitionTeam>(item as String))
      .toList(),
  backup: json["backup"] == null
      ? null
      : _AllianceBackupFromGroveJson(json["backup"] as Json),
  status: json["status"] == null
      ? null
      : _PlayoffStatusFromGroveJson(json["status"] as Json),
);

final playoffAllianceEntity = EntityDescriptor<PlayoffAlliance>(
  type: "playoff_alliance",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _PlayoffAllianceToGroveJson,
  decode: _PlayoffAllianceFromGroveJson,
);

abstract final class PlayoffAllianceFields {
  static const id = EntityField<PlayoffAlliance, String>("id");
  static const season = EntityField<PlayoffAlliance, int>("season");
  static const event =
      EntityField<PlayoffAlliance, EntityRef<CompetitionEvent>>("event");
  static const number = EntityField<PlayoffAlliance, int>("number");
  static const name = EntityField<PlayoffAlliance, String?>("name");
}

Json _PlayoffAdvancementToGroveJson(PlayoffAdvancement value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "level": value.level,
  "name": value.name,
  "type": value.type,
  "rankings": value.rankings == null
      ? null
      : value.rankings!
            .map((item) => _PlayoffRankingToGroveJson(item))
            .toList(),
  "sortOrderInfo": value.sortOrderInfo
      .map((item) => _RankingMetricToGroveJson(item))
      .toList(),
  "extraStatsInfo": value.extraStatsInfo
      .map((item) => _RankingMetricToGroveJson(item))
      .toList(),
};
PlayoffAdvancement _PlayoffAdvancementFromGroveJson(Json json) =>
    PlayoffAdvancement(
      id: json["id"] as String,
      season: json["season"] as int,
      event: EntityRef<CompetitionEvent>(json["event"] as String),
      level: json["level"] as String,
      name: json["name"] as String,
      type: json["type"] as String,
      rankings: json["rankings"] == null
          ? null
          : (json["rankings"] as List)
                .map((item) => _PlayoffRankingFromGroveJson(item as Json))
                .toList(),
      sortOrderInfo: (json["sortOrderInfo"] as List)
          .map((item) => _RankingMetricFromGroveJson(item as Json))
          .toList(),
      extraStatsInfo: (json["extraStatsInfo"] as List)
          .map((item) => _RankingMetricFromGroveJson(item as Json))
          .toList(),
    );

final playoffAdvancementEntity = EntityDescriptor<PlayoffAdvancement>(
  type: "playoff_advancement",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _PlayoffAdvancementToGroveJson,
  decode: _PlayoffAdvancementFromGroveJson,
);

abstract final class PlayoffAdvancementFields {
  static const id = EntityField<PlayoffAdvancement, String>("id");
  static const season = EntityField<PlayoffAdvancement, int>("season");
  static const event =
      EntityField<PlayoffAdvancement, EntityRef<CompetitionEvent>>("event");
  static const level = EntityField<PlayoffAdvancement, String>("level");
  static const name = EntityField<PlayoffAdvancement, String>("name");
  static const type = EntityField<PlayoffAdvancement, String>("type");
}

Json _EventAwardToGroveJson(EventAward value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "type": value.type,
  "name": value.name,
  "recipients": value.recipients
      .map((item) => _AwardRecipientToGroveJson(item))
      .toList(),
};
EventAward _EventAwardFromGroveJson(Json json) => EventAward(
  id: json["id"] as String,
  season: json["season"] as int,
  event: EntityRef<CompetitionEvent>(json["event"] as String),
  type: json["type"] as int,
  name: json["name"] as String,
  recipients: (json["recipients"] as List)
      .map((item) => _AwardRecipientFromGroveJson(item as Json))
      .toList(),
);

final eventAwardEntity = EntityDescriptor<EventAward>(
  type: "award",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _EventAwardToGroveJson,
  decode: _EventAwardFromGroveJson,
);

abstract final class EventAwardFields {
  static const id = EntityField<EventAward, String>("id");
  static const season = EntityField<EventAward, int>("season");
  static const event = EntityField<EventAward, EntityRef<CompetitionEvent>>(
    "event",
  );
  static const type = EntityField<EventAward, int>("type");
  static const name = EntityField<EventAward, String>("name");
}

Json _DistrictToGroveJson(District value) => {
  "id": value.id,
  "season": value.season,
  "abbreviation": value.abbreviation,
  "name": value.name,
  "officialDistrictChampionshipSpots": value.officialDistrictChampionshipSpots,
  "officialChampionshipSpots": value.officialChampionshipSpots,
};
District _DistrictFromGroveJson(Json json) => District(
  id: json["id"] as String,
  season: json["season"] as int,
  abbreviation: json["abbreviation"] as String,
  name: json["name"] as String,
  officialDistrictChampionshipSpots:
      json["officialDistrictChampionshipSpots"] as int?,
  officialChampionshipSpots: json["officialChampionshipSpots"] as int?,
);

final districtEntity = EntityDescriptor<District>(
  type: "district",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _DistrictToGroveJson,
  decode: _DistrictFromGroveJson,
);

abstract final class DistrictFields {
  static const id = EntityField<District, String>("id");
  static const season = EntityField<District, int>("season");
  static const abbreviation = EntityField<District, String>("abbreviation");
  static const name = EntityField<District, String>("name");
  static const officialDistrictChampionshipSpots = EntityField<District, int?>(
    "officialDistrictChampionshipSpots",
  );
  static const officialChampionshipSpots = EntityField<District, int?>(
    "officialChampionshipSpots",
  );
}

Json _DistrictTeamToGroveJson(DistrictTeam value) => {
  "id": value.id,
  "season": value.season,
  "district": value.district.id,
  "team": value.team.id,
};
DistrictTeam _DistrictTeamFromGroveJson(Json json) => DistrictTeam(
  id: json["id"] as String,
  season: json["season"] as int,
  district: EntityRef<District>(json["district"] as String),
  team: EntityRef<CompetitionTeam>(json["team"] as String),
);

final districtTeamEntity = EntityDescriptor<DistrictTeam>(
  type: "district_team",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _DistrictTeamToGroveJson,
  decode: _DistrictTeamFromGroveJson,
);

abstract final class DistrictTeamFields {
  static const id = EntityField<DistrictTeam, String>("id");
  static const season = EntityField<DistrictTeam, int>("season");
  static const district = EntityField<DistrictTeam, EntityRef<District>>(
    "district",
  );
  static const team = EntityField<DistrictTeam, EntityRef<CompetitionTeam>>(
    "team",
  );
}

Json _AdvancementRankingToGroveJson(AdvancementRanking value) => {
  "id": value.id,
  "season": value.season,
  "district": value.district == null ? null : value.district!.id,
  "team": value.team.id,
  "rank": value.rank,
  "totalPoints": value.totalPoints,
  "rookieBonus": value.rookieBonus,
  "singleEventBonus": value.singleEventBonus,
  "otherBonus": value.otherBonus,
  "adjustments": value.adjustments,
  "events": value.events
      .map((item) => _RankingEventPointsToGroveJson(item))
      .toList(),
};
AdvancementRanking _AdvancementRankingFromGroveJson(Json json) =>
    AdvancementRanking(
      id: json["id"] as String,
      season: json["season"] as int,
      district: json["district"] == null
          ? null
          : EntityRef<District>(json["district"] as String),
      team: EntityRef<CompetitionTeam>(json["team"] as String),
      rank: json["rank"] as int,
      totalPoints: json["totalPoints"] as int?,
      rookieBonus: json["rookieBonus"] as int?,
      singleEventBonus: json["singleEventBonus"] as int?,
      otherBonus: json["otherBonus"] as int?,
      adjustments: json["adjustments"] as int?,
      events: (json["events"] as List)
          .map((item) => _RankingEventPointsFromGroveJson(item as Json))
          .toList(),
    );

final advancementRankingEntity = EntityDescriptor<AdvancementRanking>(
  type: "advancement_ranking",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _AdvancementRankingToGroveJson,
  decode: _AdvancementRankingFromGroveJson,
);

abstract final class AdvancementRankingFields {
  static const id = EntityField<AdvancementRanking, String>("id");
  static const season = EntityField<AdvancementRanking, int>("season");
  static const district = EntityField<AdvancementRanking, EntityRef<District>?>(
    "district",
  );
  static const team =
      EntityField<AdvancementRanking, EntityRef<CompetitionTeam>>("team");
  static const rank = EntityField<AdvancementRanking, int>("rank");
  static const totalPoints = EntityField<AdvancementRanking, int?>(
    "totalPoints",
  );
  static const rookieBonus = EntityField<AdvancementRanking, int?>(
    "rookieBonus",
  );
  static const singleEventBonus = EntityField<AdvancementRanking, int?>(
    "singleEventBonus",
  );
  static const otherBonus = EntityField<AdvancementRanking, int?>("otherBonus");
  static const adjustments = EntityField<AdvancementRanking, int?>(
    "adjustments",
  );
}

Json _EventPointsToGroveJson(EventPoints value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "team": value.team.id,
  "pool": value.pool,
  "points": value.points == null
      ? null
      : _AdvancementPointsToGroveJson(value.points!),
  "highestMatchScores": value.highestMatchScores.map((item) => item).toList(),
  "qualificationWins": value.qualificationWins,
};
EventPoints _EventPointsFromGroveJson(Json json) => EventPoints(
  id: json["id"] as String,
  season: json["season"] as int,
  event: EntityRef<CompetitionEvent>(json["event"] as String),
  team: EntityRef<CompetitionTeam>(json["team"] as String),
  pool: json["pool"] as String,
  points: json["points"] == null
      ? null
      : _AdvancementPointsFromGroveJson(json["points"] as Json),
  highestMatchScores: (json["highestMatchScores"] as List)
      .map((item) => item as int)
      .toList(),
  qualificationWins: json["qualificationWins"] as int?,
);

final eventPointsEntity = EntityDescriptor<EventPoints>(
  type: "event_points",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _EventPointsToGroveJson,
  decode: _EventPointsFromGroveJson,
);

abstract final class EventPointsFields {
  static const id = EntityField<EventPoints, String>("id");
  static const season = EntityField<EventPoints, int>("season");
  static const event = EntityField<EventPoints, EntityRef<CompetitionEvent>>(
    "event",
  );
  static const team = EntityField<EventPoints, EntityRef<CompetitionTeam>>(
    "team",
  );
  static const pool = EntityField<EventPoints, String>("pool");
  static const qualificationWins = EntityField<EventPoints, int?>(
    "qualificationWins",
  );
}

Json _AdvancementToGroveJson(Advancement value) => {
  "id": value.id,
  "season": value.season,
  "district": value.district == null ? null : value.district!.id,
  "team": value.team.id,
  "districtChampionship": value.districtChampionship,
  "championship": value.championship,
  "championshipStatus": value.championshipStatus,
  "championshipQualification": value.championshipQualification,
  "qualifyingEvent": value.qualifyingEvent == null
      ? null
      : value.qualifyingEvent!.id,
  "qualifyingAwardName": value.qualifyingAwardName,
  "qualifyingPoolWeek": value.qualifyingPoolWeek,
};
Advancement _AdvancementFromGroveJson(Json json) => Advancement(
  id: json["id"] as String,
  season: json["season"] as int,
  district: json["district"] == null
      ? null
      : EntityRef<District>(json["district"] as String),
  team: EntityRef<CompetitionTeam>(json["team"] as String),
  districtChampionship: json["districtChampionship"] as bool?,
  championship: json["championship"] as bool?,
  championshipStatus: json["championshipStatus"] as String?,
  championshipQualification: json["championshipQualification"] as String?,
  qualifyingEvent: json["qualifyingEvent"] == null
      ? null
      : EntityRef<CompetitionEvent>(json["qualifyingEvent"] as String),
  qualifyingAwardName: json["qualifyingAwardName"] as String?,
  qualifyingPoolWeek: json["qualifyingPoolWeek"] as int?,
);

final advancementEntity = EntityDescriptor<Advancement>(
  type: "advancement",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _AdvancementToGroveJson,
  decode: _AdvancementFromGroveJson,
);

abstract final class AdvancementFields {
  static const id = EntityField<Advancement, String>("id");
  static const season = EntityField<Advancement, int>("season");
  static const district = EntityField<Advancement, EntityRef<District>?>(
    "district",
  );
  static const team = EntityField<Advancement, EntityRef<CompetitionTeam>>(
    "team",
  );
  static const districtChampionship = EntityField<Advancement, bool?>(
    "districtChampionship",
  );
  static const championship = EntityField<Advancement, bool?>("championship");
  static const championshipStatus = EntityField<Advancement, String?>(
    "championshipStatus",
  );
  static const championshipQualification = EntityField<Advancement, String?>(
    "championshipQualification",
  );
  static const qualifyingEvent =
      EntityField<Advancement, EntityRef<CompetitionEvent>?>("qualifyingEvent");
  static const qualifyingAwardName = EntityField<Advancement, String?>(
    "qualifyingAwardName",
  );
  static const qualifyingPoolWeek = EntityField<Advancement, int?>(
    "qualifyingPoolWeek",
  );
}

Json _AdvancementCutoffsToGroveJson(AdvancementCutoffs value) => {
  "id": value.id,
  "season": value.season,
  "district": value.district.id,
  "districtChampionshipOriginal": value.districtChampionshipOriginal,
  "districtChampionshipEffective": value.districtChampionshipEffective,
  "districtChampionshipDeclines": value.districtChampionshipDeclines
      .map((item) => item.id)
      .toList(),
  "championshipOriginal": value.championshipOriginal,
  "championshipEffective": value.championshipEffective,
  "championshipDeclines": value.championshipDeclines
      .map((item) => item.id)
      .toList(),
};
AdvancementCutoffs _AdvancementCutoffsFromGroveJson(
  Json json,
) => AdvancementCutoffs(
  id: json["id"] as String,
  season: json["season"] as int,
  district: EntityRef<District>(json["district"] as String),
  districtChampionshipOriginal: json["districtChampionshipOriginal"] as int?,
  districtChampionshipEffective: json["districtChampionshipEffective"] as int?,
  districtChampionshipDeclines: (json["districtChampionshipDeclines"] as List)
      .map((item) => EntityRef<CompetitionTeam>(item as String))
      .toList(),
  championshipOriginal: json["championshipOriginal"] as int?,
  championshipEffective: json["championshipEffective"] as int?,
  championshipDeclines: (json["championshipDeclines"] as List)
      .map((item) => EntityRef<CompetitionTeam>(item as String))
      .toList(),
);

final advancementCutoffsEntity = EntityDescriptor<AdvancementCutoffs>(
  type: "advancement_cutoffs",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _AdvancementCutoffsToGroveJson,
  decode: _AdvancementCutoffsFromGroveJson,
);

abstract final class AdvancementCutoffsFields {
  static const id = EntityField<AdvancementCutoffs, String>("id");
  static const season = EntityField<AdvancementCutoffs, int>("season");
  static const district = EntityField<AdvancementCutoffs, EntityRef<District>>(
    "district",
  );
  static const districtChampionshipOriginal =
      EntityField<AdvancementCutoffs, int?>("districtChampionshipOriginal");
  static const districtChampionshipEffective =
      EntityField<AdvancementCutoffs, int?>("districtChampionshipEffective");
  static const championshipOriginal = EntityField<AdvancementCutoffs, int?>(
    "championshipOriginal",
  );
  static const championshipEffective = EntityField<AdvancementCutoffs, int?>(
    "championshipEffective",
  );
}

Json _CompetitionMediaToGroveJson(CompetitionMedia value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event == null ? null : value.event!.id,
  "team": value.team == null ? null : value.team!.id,
  "teams": value.teams.map((item) => item.id).toList(),
  "rosterMedia": value.rosterMedia,
  "tag": value.tag,
  "type": value.type,
  "foreignKey": value.foreignKey,
  "preferred": value.preferred,
  "directUrl": value.directUrl,
  "viewUrl": value.viewUrl,
  "details": _MediaDetailsToGroveJson(value.details),
};
CompetitionMedia _CompetitionMediaFromGroveJson(Json json) => CompetitionMedia(
  id: json["id"] as String,
  season: json["season"] as int?,
  event: json["event"] == null
      ? null
      : EntityRef<CompetitionEvent>(json["event"] as String),
  team: json["team"] == null
      ? null
      : EntityRef<CompetitionTeam>(json["team"] as String),
  teams: (json["teams"] as List)
      .map((item) => EntityRef<CompetitionTeam>(item as String))
      .toList(),
  rosterMedia: json["rosterMedia"] as bool,
  tag: json["tag"] as String?,
  type: json["type"] as String,
  foreignKey: json["foreignKey"] as String,
  preferred: json["preferred"] as bool,
  directUrl: json["directUrl"] as String?,
  viewUrl: json["viewUrl"] as String?,
  details: _MediaDetailsFromGroveJson(json["details"] as Json),
);

final competitionMediaEntity = EntityDescriptor<CompetitionMedia>(
  type: "media",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _CompetitionMediaToGroveJson,
  decode: _CompetitionMediaFromGroveJson,
);

abstract final class CompetitionMediaFields {
  static const id = EntityField<CompetitionMedia, String>("id");
  static const season = EntityField<CompetitionMedia, int?>("season");
  static const event =
      EntityField<CompetitionMedia, EntityRef<CompetitionEvent>?>("event");
  static const team =
      EntityField<CompetitionMedia, EntityRef<CompetitionTeam>?>("team");
  static const rosterMedia = EntityField<CompetitionMedia, bool>("rosterMedia");
  static const tag = EntityField<CompetitionMedia, String?>("tag");
  static const type = EntityField<CompetitionMedia, String>("type");
  static const foreignKey = EntityField<CompetitionMedia, String>("foreignKey");
  static const preferred = EntityField<CompetitionMedia, bool>("preferred");
  static const directUrl = EntityField<CompetitionMedia, String?>("directUrl");
  static const viewUrl = EntityField<CompetitionMedia, String?>("viewUrl");
}

Json _MediaTagToGroveJson(MediaTag value) => {
  "id": value.id,
  "name": value.name,
};
MediaTag _MediaTagFromGroveJson(Json json) =>
    MediaTag(id: json["id"] as String, name: json["name"] as String);

final mediaTagEntity = EntityDescriptor<MediaTag>(
  type: "media_tag",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _MediaTagToGroveJson,
  decode: _MediaTagFromGroveJson,
);

abstract final class MediaTagFields {
  static const id = EntityField<MediaTag, String>("id");
  static const name = EntityField<MediaTag, String>("name");
}

Json _PitLayoutToGroveJson(PitLayout value) => {
  "id": value.id,
  "map": value.map == null ? null : _PitMapBackgroundToGroveJson(value.map!),
  "pits": value.pits.map((key, item) => MapEntry(key, _PitToGroveJson(item))),
};
PitLayout _PitLayoutFromGroveJson(Json json) => PitLayout(
  id: json["id"] as String,
  map: json["map"] == null
      ? null
      : _PitMapBackgroundFromGroveJson(json["map"] as Json),
  pits: (json["pits"] as Map).map(
    (key, item) => MapEntry(key as String, _PitFromGroveJson(item as Json)),
  ),
);

final pitLayoutEntity = EntityDescriptor<PitLayout>(
  type: "pit_layout",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _PitLayoutToGroveJson,
  decode: _PitLayoutFromGroveJson,
);

abstract final class PitLayoutFields {
  static const id = EntityField<PitLayout, String>("id");
}

Json _EventQueueSummaryToGroveJson(EventQueueSummary value) => {
  "id": value.id,
  "season": value.season,
  "event": value.event.id,
  "dataAsOf": value.dataAsOf == null
      ? null
      : value.dataAsOf!.toUtc().toIso8601String(),
  "nowQueueing": value.nowQueueing == null ? null : value.nowQueueing!.id,
  "nowQueueingName": value.nowQueueingName,
  "matches": value.matches.map(
    (key, item) => MapEntry(key, _QueueMatchSummaryToGroveJson(item)),
  ),
  "pitMap": value.pitMap == null ? null : _PitMapToGroveJson(value.pitMap!),
};
EventQueueSummary _EventQueueSummaryFromGroveJson(Json json) =>
    EventQueueSummary(
      id: json["id"] as String,
      season: json["season"] as int,
      event: EntityRef<CompetitionEvent>(json["event"] as String),
      dataAsOf: json["dataAsOf"] == null
          ? null
          : DateTime.parse(json["dataAsOf"] as String),
      nowQueueing: json["nowQueueing"] == null
          ? null
          : EntityRef<CompetitionMatch>(json["nowQueueing"] as String),
      nowQueueingName: json["nowQueueingName"] as String?,
      matches: (json["matches"] as Map).map(
        (key, item) => MapEntry(
          key as String,
          _QueueMatchSummaryFromGroveJson(item as Json),
        ),
      ),
      pitMap: json["pitMap"] == null
          ? null
          : _PitMapFromGroveJson(json["pitMap"] as Json),
    );

final eventQueueSummaryEntity = EntityDescriptor<EventQueueSummary>(
  type: "event_queue_summary",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _EventQueueSummaryToGroveJson,
  decode: _EventQueueSummaryFromGroveJson,
);

abstract final class EventQueueSummaryFields {
  static const id = EntityField<EventQueueSummary, String>("id");
  static const season = EntityField<EventQueueSummary, int>("season");
  static const event =
      EntityField<EventQueueSummary, EntityRef<CompetitionEvent>>("event");
  static const nowQueueing =
      EntityField<EventQueueSummary, EntityRef<CompetitionMatch>?>(
        "nowQueueing",
      );
  static const nowQueueingName = EntityField<EventQueueSummary, String?>(
    "nowQueueingName",
  );
}

Json _EventStatusSnapshotToGroveJson(EventStatusSnapshot value) => {
  "id": value.id,
  "dataAsOfTime": value.dataAsOfTime.toUtc().toIso8601String(),
  "nowQueuing": value.nowQueuing,
  "matches": value.matches.map((item) => _QueueMatchToGroveJson(item)).toList(),
  "announcements": value.announcements
      .map((item) => _EventAnnouncementToGroveJson(item))
      .toList(),
  "partsRequests": value.partsRequests
      .map((item) => _EventPartsRequestToGroveJson(item))
      .toList(),
};
EventStatusSnapshot _EventStatusSnapshotFromGroveJson(Json json) =>
    EventStatusSnapshot(
      id: json["id"] as String,
      dataAsOfTime: DateTime.parse(json["dataAsOfTime"] as String),
      nowQueuing: json["nowQueuing"] as String?,
      matches: (json["matches"] as List)
          .map((item) => _QueueMatchFromGroveJson(item as Json))
          .toList(),
      announcements: (json["announcements"] as List)
          .map((item) => _EventAnnouncementFromGroveJson(item as Json))
          .toList(),
      partsRequests: (json["partsRequests"] as List)
          .map((item) => _EventPartsRequestFromGroveJson(item as Json))
          .toList(),
    );

final eventStatusSnapshotEntity = EntityDescriptor<EventStatusSnapshot>(
  type: "event_status",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _EventStatusSnapshotToGroveJson,
  decode: _EventStatusSnapshotFromGroveJson,
);

abstract final class EventStatusSnapshotFields {
  static const id = EntityField<EventStatusSnapshot, String>("id");
  static const nowQueuing = EntityField<EventStatusSnapshot, String?>(
    "nowQueuing",
  );
}

// **************************************************************************
// _GroveValueGenerator
// **************************************************************************

Json _CompetitionLocationToGroveJson(CompetitionLocation value) => {
  "city": value.city,
  "stateProvince": value.stateProvince,
  "country": value.country,
  "address": value.address,
  "postalCode": value.postalCode,
  "name": value.name,
  "mapsPlaceId": value.mapsPlaceId,
  "mapsUrl": value.mapsUrl,
  "latitude": value.latitude,
  "longitude": value.longitude,
};
CompetitionLocation _CompetitionLocationFromGroveJson(Json json) =>
    CompetitionLocation(
      city: json["city"] as String?,
      stateProvince: json["stateProvince"] as String?,
      country: json["country"] as String?,
      address: json["address"] as String?,
      postalCode: json["postalCode"] as String?,
      name: json["name"] as String?,
      mapsPlaceId: json["mapsPlaceId"] as String?,
      mapsUrl: json["mapsUrl"] as String?,
      latitude: (json["latitude"] as num?)?.toDouble(),
      longitude: (json["longitude"] as num?)?.toDouble(),
    );

Json _EventWebcastToGroveJson(EventWebcast value) => {
  "type": value.type,
  "channel": value.channel,
  "date": value.date,
  "file": value.file,
  "status": value.status,
  "streamTitle": value.streamTitle,
  "viewerCount": value.viewerCount,
};
EventWebcast _EventWebcastFromGroveJson(Json json) => EventWebcast(
  type: json["type"] as String,
  channel: json["channel"] as String,
  date: json["date"] as String?,
  file: json["file"] as String?,
  status: json["status"] as String?,
  streamTitle: json["streamTitle"] as String?,
  viewerCount: json["viewerCount"] as int?,
);

Json _CompetitionAllianceToGroveJson(CompetitionAlliance value) => {
  "teams": value.teams.map((item) => item.id).toList(),
  "surrogateTeams": value.surrogateTeams.map((item) => item.id).toList(),
  "disqualifiedTeams": value.disqualifiedTeams.map((item) => item.id).toList(),
  "score": value.score,
  "gameBreakdown": value.gameBreakdown == null
      ? null
      : value.gameBreakdown!.map((key, item) => MapEntry(key, item)),
};
CompetitionAlliance _CompetitionAllianceFromGroveJson(Json json) =>
    CompetitionAlliance(
      teams: (json["teams"] as List)
          .map((item) => EntityRef<CompetitionTeam>(item as String))
          .toList(),
      surrogateTeams: (json["surrogateTeams"] as List)
          .map((item) => EntityRef<CompetitionTeam>(item as String))
          .toList(),
      disqualifiedTeams: (json["disqualifiedTeams"] as List)
          .map((item) => EntityRef<CompetitionTeam>(item as String))
          .toList(),
      score: json["score"] as int?,
      gameBreakdown: json["gameBreakdown"] == null
          ? null
          : (json["gameBreakdown"] as Map).map(
              (key, item) => MapEntry(key as String, item),
            ),
    );

Json _MatchVideoToGroveJson(MatchVideo value) => {
  "type": value.type,
  "key": value.key,
};
MatchVideo _MatchVideoFromGroveJson(Json json) =>
    MatchVideo(type: json["type"] as String, key: json["key"] as String);

Json _WinLossRecordToGroveJson(WinLossRecord value) => {
  "wins": value.wins,
  "losses": value.losses,
  "ties": value.ties,
};
WinLossRecord _WinLossRecordFromGroveJson(Json json) => WinLossRecord(
  wins: json["wins"] as int,
  losses: json["losses"] as int,
  ties: json["ties"] as int,
);

Json _RankingMetricToGroveJson(RankingMetric value) => {
  "name": value.name,
  "precision": value.precision,
  "type": value.type,
};
RankingMetric _RankingMetricFromGroveJson(Json json) => RankingMetric(
  name: json["name"] as String,
  precision: (json["precision"] as num?)?.toDouble(),
  type: json["type"] as String?,
);

Json _RankingResultToGroveJson(RankingResult value) => {
  "rank": value.rank,
  "matchesPlayed": value.matchesPlayed,
  "disqualifications": value.disqualifications,
  "record": value.record == null
      ? null
      : _WinLossRecordToGroveJson(value.record!),
  "qualificationAverage": value.qualificationAverage,
  "sortOrders": value.sortOrders.map((item) => item).toList(),
  "extraStats": value.extraStats.map((item) => item).toList(),
};
RankingResult _RankingResultFromGroveJson(Json json) => RankingResult(
  rank: json["rank"] as int,
  matchesPlayed: json["matchesPlayed"] as int?,
  disqualifications: json["disqualifications"] as int?,
  record: json["record"] == null
      ? null
      : _WinLossRecordFromGroveJson(json["record"] as Json),
  qualificationAverage: (json["qualificationAverage"] as num?)?.toDouble(),
  sortOrders: (json["sortOrders"] as List)
      .map((item) => (item as num).toDouble())
      .toList(),
  extraStats: (json["extraStats"] as List)
      .map((item) => (item as num).toDouble())
      .toList(),
);

Json _AllianceBackupToGroveJson(AllianceBackup value) => {
  "incoming": value.incoming.id,
  "outgoing": value.outgoing.id,
};
AllianceBackup _AllianceBackupFromGroveJson(Json json) => AllianceBackup(
  incoming: EntityRef<CompetitionTeam>(json["incoming"] as String),
  outgoing: EntityRef<CompetitionTeam>(json["outgoing"] as String),
);

Json _PlayoffStatusToGroveJson(PlayoffStatus value) => {
  "playoffType": value.playoffType,
  "level": value.level,
  "status": value.status,
  "doubleEliminationRound": value.doubleEliminationRound,
  "currentLevelRecord": value.currentLevelRecord == null
      ? null
      : _WinLossRecordToGroveJson(value.currentLevelRecord!),
  "record": value.record == null
      ? null
      : _WinLossRecordToGroveJson(value.record!),
  "playoffAverage": value.playoffAverage,
  "advancedToRoundRobinFinals": value.advancedToRoundRobinFinals,
  "roundRobinRank": value.roundRobinRank,
};
PlayoffStatus _PlayoffStatusFromGroveJson(Json json) => PlayoffStatus(
  playoffType: json["playoffType"] as int?,
  level: json["level"] as String?,
  status: json["status"] as String?,
  doubleEliminationRound: json["doubleEliminationRound"] as String?,
  currentLevelRecord: json["currentLevelRecord"] == null
      ? null
      : _WinLossRecordFromGroveJson(json["currentLevelRecord"] as Json),
  record: json["record"] == null
      ? null
      : _WinLossRecordFromGroveJson(json["record"] as Json),
  playoffAverage: (json["playoffAverage"] as num?)?.toDouble(),
  advancedToRoundRobinFinals: json["advancedToRoundRobinFinals"] as bool?,
  roundRobinRank: json["roundRobinRank"] as int?,
);

Json _PlayoffRankingToGroveJson(PlayoffRanking value) => {
  "teams": value.teams.map((item) => item.id).toList(),
  "allianceName": value.allianceName,
  "allianceColor": value.allianceColor,
  "rank": value.rank,
  "record": value.record == null
      ? null
      : _WinLossRecordToGroveJson(value.record!),
  "matchesPlayed": value.matchesPlayed,
  "sortOrders": value.sortOrders.map((item) => item).toList(),
  "extraStats": value.extraStats.map((item) => item).toList(),
};
PlayoffRanking _PlayoffRankingFromGroveJson(Json json) => PlayoffRanking(
  teams: (json["teams"] as List)
      .map((item) => EntityRef<CompetitionTeam>(item as String))
      .toList(),
  allianceName: json["allianceName"] as String,
  allianceColor: json["allianceColor"] as String?,
  rank: json["rank"] as int?,
  record: json["record"] == null
      ? null
      : _WinLossRecordFromGroveJson(json["record"] as Json),
  matchesPlayed: json["matchesPlayed"] as int?,
  sortOrders: (json["sortOrders"] as List)
      .map((item) => (item as num).toDouble())
      .toList(),
  extraStats: (json["extraStats"] as List)
      .map((item) => (item as num).toDouble())
      .toList(),
);

Json _AwardRecipientToGroveJson(AwardRecipient value) => {
  "team": value.team == null ? null : value.team!.id,
  "person": value.person,
};
AwardRecipient _AwardRecipientFromGroveJson(Json json) => AwardRecipient(
  team: json["team"] == null
      ? null
      : EntityRef<CompetitionTeam>(json["team"] as String),
  person: json["person"] as String?,
);

Json _AdvancementPointsToGroveJson(AdvancementPoints value) => {
  "total": value.total,
  "alliance": value.alliance,
  "awards": value.awards,
  "elimination": value.elimination,
  "qualification": value.qualification,
};
AdvancementPoints _AdvancementPointsFromGroveJson(Json json) =>
    AdvancementPoints(
      total: json["total"] as int?,
      alliance: json["alliance"] as int?,
      awards: json["awards"] as int?,
      elimination: json["elimination"] as int?,
      qualification: json["qualification"] as int?,
    );

Json _RankingEventPointsToGroveJson(RankingEventPoints value) => {
  "event": value.event.id,
  "points": _AdvancementPointsToGroveJson(value.points),
  "districtChampionship": value.districtChampionship,
};
RankingEventPoints _RankingEventPointsFromGroveJson(Json json) =>
    RankingEventPoints(
      event: EntityRef<CompetitionEvent>(json["event"] as String),
      points: _AdvancementPointsFromGroveJson(json["points"] as Json),
      districtChampionship: json["districtChampionship"] as bool?,
    );

Json _MediaDetailsToGroveJson(MediaDetails value) => {
  "avatarBase64": value.avatarBase64,
  "modelCreated": value.modelCreated == null
      ? null
      : value.modelCreated!.toUtc().toIso8601String(),
  "modelDescription": value.modelDescription,
  "modelImage": value.modelImage,
  "modelName": value.modelName,
  "title": value.title,
  "caption": value.caption,
  "webUri": value.webUri,
  "imageUrl": value.imageUrl,
  "mediumImageUrl": value.mediumImageUrl,
  "smallImageUrl": value.smallImageUrl,
  "imagePartial": value.imagePartial,
  "coverUrl": value.coverUrl,
  "mediumCoverUrl": value.mediumCoverUrl,
  "smallCoverUrl": value.smallCoverUrl,
  "imageCount": value.imageCount,
  "threadTitle": value.threadTitle,
};
MediaDetails _MediaDetailsFromGroveJson(Json json) => MediaDetails(
  avatarBase64: json["avatarBase64"] as String?,
  modelCreated: json["modelCreated"] == null
      ? null
      : DateTime.parse(json["modelCreated"] as String),
  modelDescription: json["modelDescription"] as String?,
  modelImage: json["modelImage"] as String?,
  modelName: json["modelName"] as String?,
  title: json["title"] as String?,
  caption: json["caption"] as String?,
  webUri: json["webUri"] as String?,
  imageUrl: json["imageUrl"] as String?,
  mediumImageUrl: json["mediumImageUrl"] as String?,
  smallImageUrl: json["smallImageUrl"] as String?,
  imagePartial: json["imagePartial"] as String?,
  coverUrl: json["coverUrl"] as String?,
  mediumCoverUrl: json["mediumCoverUrl"] as String?,
  smallCoverUrl: json["smallCoverUrl"] as String?,
  imageCount: json["imageCount"] as int?,
  threadTitle: json["threadTitle"] as String?,
);

Json _PitMapPointToGroveJson(PitMapPoint value) => {"x": value.x, "y": value.y};
PitMapPoint _PitMapPointFromGroveJson(Json json) => PitMapPoint(
  x: (json["x"] as num).toDouble(),
  y: (json["y"] as num).toDouble(),
);

Json _PitMapElementToGroveJson(PitMapElement value) => {
  "position": _PitMapPointToGroveJson(value.position),
  "size": _PitMapPointToGroveJson(value.size),
  "angle": value.angle,
  "team": value.team == null ? null : value.team!.id,
  "label": value.label,
  "arrowType": value.arrowType,
};
PitMapElement _PitMapElementFromGroveJson(Json json) => PitMapElement(
  position: _PitMapPointFromGroveJson(json["position"] as Json),
  size: _PitMapPointFromGroveJson(json["size"] as Json),
  angle: (json["angle"] as num?)?.toDouble(),
  team: json["team"] == null
      ? null
      : EntityRef<CompetitionTeam>(json["team"] as String),
  label: json["label"] as String?,
  arrowType: json["arrowType"] as String?,
);

Json _PitMapToGroveJson(PitMap value) => {
  "size": _PitMapPointToGroveJson(value.size),
  "pits": value.pits.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
  "areas": value.areas.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
  "labels": value.labels.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
  "arrows": value.arrows.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
  "walls": value.walls.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
};
PitMap _PitMapFromGroveJson(Json json) => PitMap(
  size: _PitMapPointFromGroveJson(json["size"] as Json),
  pits: (json["pits"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
  areas: (json["areas"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
  labels: (json["labels"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
  arrows: (json["arrows"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
  walls: (json["walls"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
);

Json _PitGeometryToGroveJson(PitGeometry value) => {
  "position": _PitMapPointToGroveJson(value.position),
  "size": _PitMapPointToGroveJson(value.size),
  "angle": value.angle,
};
PitGeometry _PitGeometryFromGroveJson(Json json) => PitGeometry(
  position: _PitMapPointFromGroveJson(json["position"] as Json),
  size: _PitMapPointFromGroveJson(json["size"] as Json),
  angle: (json["angle"] as num?)?.toDouble(),
);

Json _PitToGroveJson(Pit value) => {
  "geometry": value.geometry == null
      ? null
      : _PitGeometryToGroveJson(value.geometry!),
  "team": value.team == null ? null : value.team!.id,
};
Pit _PitFromGroveJson(Json json) => Pit(
  geometry: json["geometry"] == null
      ? null
      : _PitGeometryFromGroveJson(json["geometry"] as Json),
  team: json["team"] == null
      ? null
      : EntityRef<CompetitionTeam>(json["team"] as String),
);

Json _PitMapBackgroundToGroveJson(PitMapBackground value) => {
  "size": _PitMapPointToGroveJson(value.size),
  "areas": value.areas.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
  "labels": value.labels.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
  "arrows": value.arrows.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
  "walls": value.walls.map(
    (key, item) => MapEntry(key, _PitMapElementToGroveJson(item)),
  ),
};
PitMapBackground _PitMapBackgroundFromGroveJson(Json json) => PitMapBackground(
  size: _PitMapPointFromGroveJson(json["size"] as Json),
  areas: (json["areas"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
  labels: (json["labels"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
  arrows: (json["arrows"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
  walls: (json["walls"] as Map).map(
    (key, item) =>
        MapEntry(key as String, _PitMapElementFromGroveJson(item as Json)),
  ),
);

Json _QueueMatchSummaryToGroveJson(QueueMatchSummary value) => {
  "label": value.label,
  "status": value.status,
  "played": value.played,
  "estimatedQueueAt": value.estimatedQueueAt == null
      ? null
      : value.estimatedQueueAt!.toUtc().toIso8601String(),
  "estimatedStartAt": value.estimatedStartAt == null
      ? null
      : value.estimatedStartAt!.toUtc().toIso8601String(),
};
QueueMatchSummary _QueueMatchSummaryFromGroveJson(Json json) =>
    QueueMatchSummary(
      label: json["label"] as String,
      status: json["status"] as String,
      played: json["played"] as bool,
      estimatedQueueAt: json["estimatedQueueAt"] == null
          ? null
          : DateTime.parse(json["estimatedQueueAt"] as String),
      estimatedStartAt: json["estimatedStartAt"] == null
          ? null
          : DateTime.parse(json["estimatedStartAt"] as String),
    );

Json _QueueMatchTimesToGroveJson(QueueMatchTimes value) => {
  "scheduledStartTime": value.scheduledStartTime == null
      ? null
      : value.scheduledStartTime!.toUtc().toIso8601String(),
  "estimatedQueueTime": value.estimatedQueueTime == null
      ? null
      : value.estimatedQueueTime!.toUtc().toIso8601String(),
  "estimatedOnDeckTime": value.estimatedOnDeckTime == null
      ? null
      : value.estimatedOnDeckTime!.toUtc().toIso8601String(),
  "estimatedOnFieldTime": value.estimatedOnFieldTime == null
      ? null
      : value.estimatedOnFieldTime!.toUtc().toIso8601String(),
  "estimatedStartTime": value.estimatedStartTime == null
      ? null
      : value.estimatedStartTime!.toUtc().toIso8601String(),
  "actualQueueTime": value.actualQueueTime == null
      ? null
      : value.actualQueueTime!.toUtc().toIso8601String(),
  "actualOnDeckTime": value.actualOnDeckTime == null
      ? null
      : value.actualOnDeckTime!.toUtc().toIso8601String(),
  "actualOnFieldTime": value.actualOnFieldTime == null
      ? null
      : value.actualOnFieldTime!.toUtc().toIso8601String(),
  "actualStartTime": value.actualStartTime == null
      ? null
      : value.actualStartTime!.toUtc().toIso8601String(),
  "actualCommitTime": value.actualCommitTime == null
      ? null
      : value.actualCommitTime!.toUtc().toIso8601String(),
};
QueueMatchTimes _QueueMatchTimesFromGroveJson(Json json) => QueueMatchTimes(
  scheduledStartTime: json["scheduledStartTime"] == null
      ? null
      : DateTime.parse(json["scheduledStartTime"] as String),
  estimatedQueueTime: json["estimatedQueueTime"] == null
      ? null
      : DateTime.parse(json["estimatedQueueTime"] as String),
  estimatedOnDeckTime: json["estimatedOnDeckTime"] == null
      ? null
      : DateTime.parse(json["estimatedOnDeckTime"] as String),
  estimatedOnFieldTime: json["estimatedOnFieldTime"] == null
      ? null
      : DateTime.parse(json["estimatedOnFieldTime"] as String),
  estimatedStartTime: json["estimatedStartTime"] == null
      ? null
      : DateTime.parse(json["estimatedStartTime"] as String),
  actualQueueTime: json["actualQueueTime"] == null
      ? null
      : DateTime.parse(json["actualQueueTime"] as String),
  actualOnDeckTime: json["actualOnDeckTime"] == null
      ? null
      : DateTime.parse(json["actualOnDeckTime"] as String),
  actualOnFieldTime: json["actualOnFieldTime"] == null
      ? null
      : DateTime.parse(json["actualOnFieldTime"] as String),
  actualStartTime: json["actualStartTime"] == null
      ? null
      : DateTime.parse(json["actualStartTime"] as String),
  actualCommitTime: json["actualCommitTime"] == null
      ? null
      : DateTime.parse(json["actualCommitTime"] as String),
);

Json _QueueMatchToGroveJson(QueueMatch value) => {
  "label": value.label,
  "status": value.status,
  "redTeams": value.redTeams == null
      ? null
      : value.redTeams!.map((item) => item).toList(),
  "blueTeams": value.blueTeams == null
      ? null
      : value.blueTeams!.map((item) => item).toList(),
  "times": _QueueMatchTimesToGroveJson(value.times),
  "replayOf": value.replayOf,
  "breakAfter": value.breakAfter,
};
QueueMatch _QueueMatchFromGroveJson(Json json) => QueueMatch(
  label: json["label"] as String,
  status: json["status"] as String?,
  redTeams: json["redTeams"] == null
      ? null
      : (json["redTeams"] as List).map((item) => item as String?).toList(),
  blueTeams: json["blueTeams"] == null
      ? null
      : (json["blueTeams"] as List).map((item) => item as String?).toList(),
  times: _QueueMatchTimesFromGroveJson(json["times"] as Json),
  replayOf: json["replayOf"] as String?,
  breakAfter: json["breakAfter"] as String?,
);

Json _EventAnnouncementToGroveJson(EventAnnouncement value) => {
  "id": value.id,
  "text": value.text,
  "postedAt": value.postedAt == null
      ? null
      : value.postedAt!.toUtc().toIso8601String(),
};
EventAnnouncement _EventAnnouncementFromGroveJson(Json json) =>
    EventAnnouncement(
      id: json["id"] as String?,
      text: json["text"] as String,
      postedAt: json["postedAt"] == null
          ? null
          : DateTime.parse(json["postedAt"] as String),
    );

Json _EventPartsRequestToGroveJson(EventPartsRequest value) => {
  "id": value.id,
  "parts": value.parts,
  "requestedByTeam": value.requestedByTeam,
  "postedAt": value.postedAt == null
      ? null
      : value.postedAt!.toUtc().toIso8601String(),
};
EventPartsRequest _EventPartsRequestFromGroveJson(Json json) =>
    EventPartsRequest(
      id: json["id"] as String?,
      parts: json["parts"] as String,
      requestedByTeam: json["requestedByTeam"] as String,
      postedAt: json["postedAt"] == null
          ? null
          : DateTime.parse(json["postedAt"] as String),
    );
