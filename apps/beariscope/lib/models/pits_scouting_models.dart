import 'package:beariscope/pages/team_lookup/team_model.dart';

enum PitsScoutingFilter { allTeams, notScouted, scouted }

List<Team> parsePitsTeams(List<Map<String, dynamic>> data) {
  return data
      .map((json) => Team.fromJson(json))
      .where((team) => team.number > 0)
      .toList()
    ..sort((a, b) => a.number.compareTo(b.number));
}

List<Team> filterPitsTeams({
  required List<Team> teams,
  required String query,
  required Set<int> scoutedTeamNumbers,
  required PitsScoutingFilter statusFilter,
}) {
  final queryFiltered = teams
      .where((team) => teamMatchesSearch(team, query))
      .toList();

  return queryFiltered.where((team) {
    final isScouted = scoutedTeamNumbers.contains(team.number);
    return switch (statusFilter) {
      PitsScoutingFilter.allTeams => true,
      PitsScoutingFilter.notScouted => !isScouted,
      PitsScoutingFilter.scouted => isScouted,
    };
  }).toList();
}

class PitsScoutingSubmission {
  final String teamName;
  final int teamNumber;
  final int? hopperSize;
  final String motorType;
  final String drivetrainType;
  final String swerveBrand;
  final String swerveGearRatio;
  final String wheelType;
  final double? chassisLength;
  final double? chassisWidth;
  final double? chassisHeight;
  final double? horizontalExtensionLimit;
  final double? verticalExtensionLimit;
  final double? weight;
  final String climbMethod;
  final Set<String> climbLevel;
  final double climbConsistency;
  final String autoClimb;
  final Set<String> fuelCollectionLocation;
  final String autoPaths;
  final Set<String> pathwayDetails;
  final String trenchCapability;
  final String towerCapability;
  final String shooter;
  final int? shooterNumber;
  final String collectorType;
  final double? fuelOuttakeRate;
  final double averageAccuracy;
  final Set<String> moveWhileShooting;
  final Set<String> shootingRange;
  final String indexerType;
  final String notes;

  const PitsScoutingSubmission({
    required this.teamName,
    required this.teamNumber,
    required this.hopperSize,
    required this.motorType,
    required this.drivetrainType,
    required this.swerveBrand,
    required this.swerveGearRatio,
    required this.wheelType,
    required this.chassisLength,
    required this.chassisWidth,
    required this.chassisHeight,
    required this.horizontalExtensionLimit,
    required this.verticalExtensionLimit,
    required this.weight,
    required this.climbMethod,
    required this.climbLevel,
    required this.climbConsistency,
    required this.autoClimb,
    required this.fuelCollectionLocation,
    required this.autoPaths,
    required this.pathwayDetails,
    required this.trenchCapability,
    required this.towerCapability,
    required this.shooter,
    required this.shooterNumber,
    required this.collectorType,
    required this.fuelOuttakeRate,
    required this.averageAccuracy,
    required this.moveWhileShooting,
    required this.shootingRange,
    required this.indexerType,
    required this.notes,
  });

  Map<String, Object?> toIngestEntry({
    required String eventKey,
    required String scoutedBy,
    int season = 2026,
    String? existingId,
  }) {
    final meta = <String, Object?>{
      'type': 'pits',
      'version': 1,
      'season': season,
      'event': eventKey,
      'scoutedBy': scoutedBy,
    };
    if (existingId != null) {
      meta['existingId'] = existingId;
    }

    return {
      'meta': meta,
      'teamName': teamName,
      'teamNumber': teamNumber,
      'hopperSize': hopperSize,
      'motorType': motorType,
      'drivetrainType': drivetrainType,
      'swerveBrand': swerveBrand,
      'swerveGearRatio': swerveGearRatio,
      'wheelType': wheelType,
      'chassisLength': chassisLength,
      'chassisWidth': chassisWidth,
      'chassisHeight': chassisHeight,
      'horizontalExtensionLimit': horizontalExtensionLimit,
      'verticalExtensionLimit': verticalExtensionLimit,
      'weight': weight,
      'climbMethod': climbMethod,
      'climbLevel': climbLevel.toList(),
      'climbConsistency': climbConsistency,
      'autoClimb': autoClimb,
      'fuelCollectionLocation': fuelCollectionLocation.toList(),
      'autoPaths': autoPaths,
      'pathwayDetails': pathwayDetails.toList(),
      'trenchCapability': trenchCapability,
      'towerCapability': towerCapability,
      'shooter': shooter,
      'shooterNumber': shooterNumber,
      'collectorType': collectorType,
      'fuelOuttakeRate': fuelOuttakeRate,
      'averageAccuracy': averageAccuracy,
      'moveWhileShooting': moveWhileShooting.toList(),
      'shootingRange': shootingRange.toList(),
      'indexerType': indexerType,
      'notes': notes,
    };
  }
}
