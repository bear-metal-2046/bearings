part of 'competition_entities.dart';

@GroveEntity('district', version: 1, serverManaged: true)
class District {
  const District({
    required this.id,
    required this.season,
    required this.abbreviation,
    required this.name,
    this.officialDistrictChampionshipSpots,
    this.officialChampionshipSpots,
  });

  final String id;
  final int season;
  final String abbreviation;
  final String name;
  final int? officialDistrictChampionshipSpots;
  final int? officialChampionshipSpots;
}

@GroveEntity('district_team', version: 1, serverManaged: true)
class DistrictTeam {
  const DistrictTeam({
    required this.id,
    required this.season,
    required this.district,
    required this.team,
  });

  final String id;
  final int season;
  final EntityRef<District> district;
  final EntityRef<CompetitionTeam> team;
}
