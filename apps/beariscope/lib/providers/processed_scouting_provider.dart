import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/processed_scouting_doc.dart';
import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/models/tba_match_score.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:beariscope/providers/tba_match_scores_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProcessedScoutingBundle {
  final List<ScoutingDocument> rawDocs;
  final List<ProcessedScoutingDoc> processedDocs;

  const ProcessedScoutingBundle({
    required this.rawDocs,
    required this.processedDocs,
  });
}

final processedScoutingProvider = FutureProvider<ProcessedScoutingBundle>((
  ref,
) async {
  final allDocs = await ref.watch(scoutingDataProvider.future);
  final tbaMatchScores = await ref.watch(tbaMatchScoresProvider.future);

  final processedById = <String, ProcessedScoutingDoc>{
    for (final doc in allDocs) doc.id: _buildProcessedDoc(doc),
  };

  final stratDocsByMatchAndAlliance = <String, ScoutingDocument>{};
  for (final doc in allDocs) {
    if (doc.meta?['type']?.toString() != 'strat') continue;
    final matchNumber = _matchNumberFromMeta(doc);
    final alliance = doc.meta?['alliance']?.toString().trim() ?? '';
    if (matchNumber == null || matchNumber <= 0 || alliance.isEmpty) continue;
    stratDocsByMatchAndAlliance[_stratKey(matchNumber, alliance)] = doc;
  }

  final docsByMatchNumber = <int, List<ScoutingDocument>>{};
  for (final doc in allDocs) {
    if (doc.meta?['type']?.toString() != 'match') continue;
    final matchNumber = TeamScoutingBundle.matchNumber(doc);
    if (matchNumber == null || matchNumber <= 0) continue;
    docsByMatchNumber.putIfAbsent(matchNumber, () => []).add(doc);
  }

  for (final tbaScore in tbaMatchScores.values) {
    final matchDocs = docsByMatchNumber[tbaScore.matchNumber];
    if (matchDocs == null || matchDocs.isEmpty) continue;

    _applyScalars(
      processedById: processedById,
      matchDocs: matchDocs,
      teamKeys: tbaScore.redTeams,
      score: tbaScore.red.scoreBreakdown,
      stratDoc:
          stratDocsByMatchAndAlliance[_stratKey(tbaScore.matchNumber, 'red')],
    );
    _applyScalars(
      processedById: processedById,
      matchDocs: matchDocs,
      teamKeys: tbaScore.blueTeams,
      score: tbaScore.blue.scoreBreakdown,
      stratDoc:
          stratDocsByMatchAndAlliance[_stratKey(tbaScore.matchNumber, 'blue')],
    );
  }

  return ProcessedScoutingBundle(
    rawDocs: allDocs,
    processedDocs: allDocs
        .map((doc) => processedById[doc.id] ?? _buildProcessedDoc(doc))
        .toList(),
  );
});

ProcessedScoutingDoc _buildProcessedDoc(ScoutingDocument doc) {
  return ProcessedScoutingDoc(
    raw: doc,
    autoFuelAccuracy: _cleanAccuracyField(doc, kSectionAuto, kAutoFuelAccuracy),
    teleFuelAccuracy: _cleanAccuracyField(doc, kSectionTele, kTeleFuelAccuracy),
  );
}

void _applyScalars({
  required Map<String, ProcessedScoutingDoc> processedById,
  required List<ScoutingDocument> matchDocs,
  required List<String> teamKeys,
  required TbaAllianceScore score,
  required ScoutingDocument? stratDoc,
}) {
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

  final autoScalar = score.autoFuelScored > 0 && scoutedAuto > 0
      ? score.autoFuelScored / scoutedAuto
      : 1.0;
  final teleScalar = score.teleFuelScored > 0 && scoutedTele > 0
      ? score.teleFuelScored / scoutedTele
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

double _sumFuel(List<ScoutingDocument> docs, String sectionId, String fieldId) {
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
  ScoutingDocument doc,
  String sectionId,
  String fieldId,
) {
  final value = TeamScoutingBundle.getMatchField(doc, sectionId, fieldId);
  if (value is! num) return null;
  final accuracy = value.toDouble();
  return accuracy == 0.0 ? null : accuracy;
}

int? _matchNumberFromMeta(ScoutingDocument doc) {
  final value = doc.meta?['matchNumber'];
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

int _stratIntField(ScoutingDocument? doc, String fieldId) {
  final value = doc?.data[fieldId];
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
