import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/providers/processed_scouting_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final teamScoutingProvider =
    Provider.family<AsyncValue<TeamScoutingBundle>, int>(
      (ref, teamNumber) => ref
          .watch(processedScoutingProvider)
          .whenData((bundle) => _buildTeamScoutingBundle(bundle, teamNumber)),
    );

TeamScoutingBundle _buildTeamScoutingBundle(
  ProcessedScoutingBundle processedBundle,
  int teamNumber,
) {
  final allProcessed = processedBundle.processedDocs;

  final teamDocs = allProcessed.where((doc) {
    return TeamScoutingBundle.teamNumber(doc.raw) == teamNumber;
  }).toList();

  final matchDocs = teamDocs.where((doc) => doc.raw.kind == 'match').toList()
    ..sort((a, b) {
      final aMatch = TeamScoutingBundle.matchNumber(a.raw) ?? 0;
      final bMatch = TeamScoutingBundle.matchNumber(b.raw) ?? 0;
      return aMatch.compareTo(bMatch);
    });

  final pitsDocs = teamDocs
      .where((doc) => doc.raw.kind == 'pits')
      .map((doc) => doc.raw)
      .toList();

  // Take the most recently uploaded pits doc for this team (if any).
  pitsDocs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final pitsDoc = pitsDocs.firstOrNull;

  final driveTeamDocs =
      teamDocs
          .where((doc) => doc.raw.kind == 'drive_team')
          .map((doc) => doc.raw)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final observationDocs =
      teamDocs
          .where((doc) => doc.raw.kind == 'observation')
          .map((doc) => doc.raw)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  const stratRankingKeys = [
    'driverSkillRanking',
    'defensiveSkillRanking',
    'defensiveResilienceRanking',
    'mechanicalStabilityRanking',
  ];
  final teamStr = teamNumber.toString();
  final stratDocs =
      allProcessed
          .where((doc) {
            if (doc.raw.kind != 'strat') return false;
            return stratRankingKeys.any((key) {
              final v = doc.raw.data[key];
              return v is List && v.map((e) => e.toString()).contains(teamStr);
            });
          })
          .map((doc) => doc.raw)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  return TeamScoutingBundle(
    matchDocs: matchDocs,
    pitsDoc: pitsDoc,
    stratDocs: stratDocs,
    driveTeamDocs: driveTeamDocs,
    observationDocs: observationDocs,
  );
}
