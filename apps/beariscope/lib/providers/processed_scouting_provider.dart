import 'package:core/core.dart'
    show CompetitionAlliance, CompetitionMatch, ScoutingReport;
import 'package:grove/grove.dart';
import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/processed_scouting_doc.dart';
import 'package:beariscope/models/alliance_fuel_score.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/competition_provider.dart';

class ProcessedScoutingBundle {
  final bool complete;
  final List<ScoutingReport> rawDocs;
  final List<ProcessedScoutingDoc> processedDocs;

  const ProcessedScoutingBundle({
    required this.complete,
    required this.rawDocs,
    required this.processedDocs,
  });
}

final processedScoutingProvider = Provider<AsyncValue<ProcessedScoutingBundle>>(
  (ref) {
    final reports = ref.watch(
      groveQueryProvider(ref.watch(scoutingQueryProvider)),
    );
    final event = ref.watch(currentEventProvider);
    final matches = ref
        .watch(competitionMatchesProvider(event))
        .whenData((result) => result.requireAvailable().items);
    return reports.flatMap((result) {
      final available = result.requireAvailable();
      return matches.when(
        data: (matches) => AsyncData(_processScouting(available, matches)),
        error: (_, _) => AsyncData(_processScouting(available, const [])),
        loading: AsyncLoading<ProcessedScoutingBundle>.new,
      );
    });
  },
);

ProcessedScoutingBundle _processScouting(
  QueryResult<ScoutingReport> reports,
  List<CompetitionMatch> matches,
) {
  final allDocs = reports.items;

  final processedById = <String, ProcessedScoutingDoc>{
    for (final doc in allDocs) doc.id: _buildProcessedDoc(doc),
  };

  final stratDocsByMatchAndAlliance = <String, ScoutingReport>{};
  for (final doc in allDocs) {
    if (doc.kind != 'strat') continue;
    final matchNumber = _matchNumberFromMeta(doc);
    final alliance = doc.meta?['alliance']?.toString().trim() ?? '';
    if (matchNumber == null || matchNumber <= 0 || alliance.isEmpty) continue;
    stratDocsByMatchAndAlliance[_stratKey(matchNumber, alliance)] = doc;
  }

  final docsByMatchNumber = <int, List<ScoutingReport>>{};
  for (final doc in allDocs) {
    if (doc.kind != 'match') continue;
    final matchNumber = TeamScoutingBundle.matchNumber(doc);
    if (matchNumber == null || matchNumber <= 0) continue;
    docsByMatchNumber.putIfAbsent(matchNumber, () => []).add(doc);
  }

  final scoredQualifications = {
    for (final match in matches)
      if (match.level == 'qm' &&
          match.matchNumber > 0 &&
          (match.red?.gameBreakdown != null ||
              match.blue?.gameBreakdown != null))
        match.matchNumber: match,
  };
  for (final match in scoredQualifications.values) {
    final matchDocs = docsByMatchNumber[match.matchNumber];
    if (matchDocs == null || matchDocs.isEmpty) continue;

    for (final (color, alliance) in [
      ('red', match.red),
      ('blue', match.blue),
    ]) {
      if (alliance == null) continue;
      _applyScalars(
        processedById: processedById,
        matchDocs: matchDocs,
        alliance: alliance,
        stratDoc:
            stratDocsByMatchAndAlliance[_stratKey(match.matchNumber, color)],
      );
    }
  }

  return ProcessedScoutingBundle(
    complete: reports.complete,
    rawDocs: allDocs,
    processedDocs: allDocs
        .map((doc) => processedById[doc.id] ?? _buildProcessedDoc(doc))
        .toList(),
  );
}

ProcessedScoutingDoc _buildProcessedDoc(ScoutingReport doc) {
  return ProcessedScoutingDoc(
    raw: doc,
    autoFuelAccuracy: _cleanAccuracyField(doc, kSectionAuto, kAutoFuelAccuracy),
    teleFuelAccuracy: _cleanAccuracyField(doc, kSectionTele, kTeleFuelAccuracy),
  );
}

void _applyScalars({
  required Map<String, ProcessedScoutingDoc> processedById,
  required List<ScoutingReport> matchDocs,
  required CompetitionAlliance alliance,
  required ScoutingReport? stratDoc,
}) {
  final teamKeys = {for (final team in alliance.teams) team.id};
  final allianceDocs = matchDocs.where((doc) {
    final teamNumber = TeamScoutingBundle.teamNumber(doc);
    if (teamNumber == null) return false;
    return teamKeys.contains('frc$teamNumber');
  }).toList();

  if (allianceDocs.isEmpty) return;

  final autoHumanPlayerScore = _stratIntField(stratDoc, 'autoHumanPlayerScore');
  final teleHumanPlayerScore = _stratIntField(stratDoc, 'teleHumanPlayerScore');

  final scoutedAuto =
      _sumFuel(allianceDocs, kSectionAuto, kAutoFuelScored) +
      autoHumanPlayerScore;
  final scoutedTele =
      _sumFuel(allianceDocs, kSectionTele, kTeleFuelScored) +
      teleHumanPlayerScore;

  final score = readAllianceFuelScore(alliance.gameBreakdown);
  final autoScalar = score.auto > 0 && scoutedAuto > 0
      ? score.auto / scoutedAuto
      : 1.0;
  final teleScalar = score.tele > 0 && scoutedTele > 0
      ? score.tele / scoutedTele
      : 1.0;

  for (final doc in allianceDocs) {
    processedById[doc.id] = ProcessedScoutingDoc(
      raw: doc,
      autoFuelScalar: autoScalar,
      teleFuelScalar: teleScalar,
      autoFuelAccuracy: _cleanAccuracyField(
        doc,
        kSectionAuto,
        kAutoFuelAccuracy,
      ),
      teleFuelAccuracy: _cleanAccuracyField(
        doc,
        kSectionTele,
        kTeleFuelAccuracy,
      ),
      autoHumanPlayerScore: autoHumanPlayerScore,
      teleHumanPlayerScore: teleHumanPlayerScore,
    );
  }
}

double _sumFuel(List<ScoutingReport> docs, String sectionId, String fieldId) {
  double sum = 0;
  for (final doc in docs) {
    final value = TeamScoutingBundle.getMatchField(doc, sectionId, fieldId);
    if (value is num) {
      sum += value.toDouble();
    }
  }
  return sum;
}

String _stratKey(int matchNumber, String alliance) =>
    '$matchNumber:${alliance.toLowerCase()}';

double? _cleanAccuracyField(
  ScoutingReport doc,
  String sectionId,
  String fieldId,
) {
  final value = TeamScoutingBundle.getMatchField(doc, sectionId, fieldId);
  if (value is! num) return null;
  final accuracy = value.toDouble();
  return accuracy == 0.0 ? null : accuracy;
}

int? _matchNumberFromMeta(ScoutingReport doc) {
  final value = doc.meta?['matchNumber'];
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

int _stratIntField(ScoutingReport? doc, String fieldId) {
  final value = doc?.data[fieldId];
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
