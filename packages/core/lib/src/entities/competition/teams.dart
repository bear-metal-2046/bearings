part of 'competition_entities.dart';

@GroveValue()
class CompetitionLocation {
  const CompetitionLocation({
    this.city,
    this.stateProvince,
    this.country,
    this.address,
    this.postalCode,
    this.name,
    this.mapsPlaceId,
    this.mapsUrl,
    this.latitude,
    this.longitude,
  });

  final String? city;
  final String? stateProvince;
  final String? country;
  final String? address;
  final String? postalCode;
  final String? name;
  final String? mapsPlaceId;
  final String? mapsUrl;
  final double? latitude;
  final double? longitude;
}

@GroveEntity('team', version: 1, serverManaged: true)
class CompetitionTeam {
  const CompetitionTeam({
    required this.id,
    required this.number,
    this.nickname,
    this.name,
    this.schoolName,
    required this.location,
    this.website,
    this.rookieYear,
    this.motto,
  });

  final String id;
  final int number;
  final String? nickname;
  final String? name;
  final String? schoolName;
  final CompetitionLocation location;
  final String? website;
  final int? rookieYear;
  final String? motto;
}

@GroveEntity('team_season', version: 1, serverManaged: true)
class TeamSeason {
  const TeamSeason({
    required this.id,
    required this.season,
    required this.team,
  });

  final String id;
  final int season;
  final EntityRef<CompetitionTeam> team;
}

@GroveEntity('team_robot', version: 1, serverManaged: true)
class TeamRobot {
  const TeamRobot({
    required this.id,
    required this.season,
    required this.team,
    required this.name,
  });

  final String id;
  final int season;
  final EntityRef<CompetitionTeam> team;
  final String name;
}
