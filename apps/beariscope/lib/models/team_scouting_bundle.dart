import 'dart:math';

import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/processed_scouting_doc.dart';
import 'package:beariscope/models/scouting_document.dart';

class TeamScoutingBundle {
  final List<ProcessedScoutingDoc> matchDocs;

  final ScoutingDocument? pitsDoc;

  final List<ScoutingDocument> stratDocs;

  final List<ScoutingDocument> driveTeamDocs;

  final List<ScoutingDocument> observationDocs;

  final int weight;

  const TeamScoutingBundle({
    required this.matchDocs,
    required this.pitsDoc,
    required this.stratDocs,
    required this.driveTeamDocs,
    required this.observationDocs,
    this.weight = 1,
  });

  bool get hasMatchData => matchDocs.isNotEmpty;

  bool get hasPitsData => pitsDoc != null;

  bool get hasStratData => stratDocs.isNotEmpty;

  bool get hasObservationData => observationDocs.isNotEmpty;

  static dynamic getMatchField(
    ScoutingDocument doc,
    String sectionId,
    String fieldId,
  ) {
    final sections = doc.data['sections'];
    if (sections is! List) return null;
    for (final section in sections) {
      if (section is! Map) continue;
      if (section['sectionId']?.toString() != sectionId) continue;
      final fields = section['fields'];
      if (fields is Map) return fields[fieldId];
      return null;
    }
    return null;
  }

  double avgMatchField(String sectionId, String fieldId) {
    if (matchDocs.isEmpty) return 0.0;
    double sum = 0;
    int count = 0;
    for (final doc in matchDocs) {
      final val = getMatchField(doc.raw, sectionId, fieldId);
      if (val is num) {
        sum +=
            val.toDouble() *
            _scalarFor(doc, sectionId, fieldId) *
            pow(weight, count);
        count++;
      }
    }
    return count == 0 ? 0.0 : sum / count;
  }

  double? avgMatchAccuracy(String sectionId) {
    if (matchDocs.isEmpty) return null;
    double sum = 0;
    int count = 0;
    for (final doc in matchDocs) {
      final val = doc.accuracyForSection(sectionId);
      if (val != null && val != 0.0) {
        sum += val;
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }

  double? avgMatchAccuracyTotal() {
    final autoAccuracy = avgMatchAccuracy(kSectionAuto);
    final teleAccuracy = avgMatchAccuracy(kSectionTele);
    final values = <double>[?autoAccuracy, ?teleAccuracy];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double sumMatchField(String sectionId, String fieldId) {
    if (matchDocs.isEmpty) return 0.0;
    double sum = 0;
    for (final doc in matchDocs) {
      final val = getMatchField(doc.raw, sectionId, fieldId);
      if (val is num) {
        sum += val.toDouble() * _scalarFor(doc, sectionId, fieldId);
      }
    }
    return sum;
  }

  int countMatchField(
    String sectionId,
    String fieldId,
    bool Function(dynamic) test,
  ) {
    return matchDocs
        .where((doc) => test(getMatchField(doc.raw, sectionId, fieldId)))
        .length;
  }

  double rateMatchField(
    String sectionId,
    String fieldId,
    bool Function(dynamic) test,
  ) {
    if (matchDocs.isEmpty) return 0.0;
    return countMatchField(sectionId, fieldId, test) / matchDocs.length;
  }

  String? modalMatchField(String sectionId, String fieldId) {
    if (matchDocs.isEmpty) return null;
    final counts = <String, int>{};
    for (final doc in matchDocs) {
      final val = getMatchField(doc.raw, sectionId, fieldId)?.toString();
      if (val != null && val.isNotEmpty) {
        counts[val] = (counts[val] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  double boolRateMatchField(String sectionId, String fieldId) =>
      rateMatchField(sectionId, fieldId, (v) => v == true);

  T? getPitsField<T>(String key) {
    final val = pitsDoc?.data[key];
    if (val is T) return val;
    return null;
  }

  List<String> getPitsListField(String key) {
    final val = pitsDoc?.data[key];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [];
  }

  double? getPitsDouble(String key) {
    final val = pitsDoc?.data[key];
    if (val is num) return val.toDouble();
    return null;
  }

  int get stratAppearanceCount => stratDocs.length;

  double? get avgHumanPlayerScore {
    if (stratDocs.isEmpty) return null;
    double sum = 0;
    int count = 0;
    for (final doc in stratDocs) {
      final v = _humanPlayerScore(doc.data);
      if (v != null) {
        sum += v;
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }

  static double? _humanPlayerScore(Map<String, dynamic> data) {
    final auto = data['autoHumanPlayerScore'];
    final tele = data['teleHumanPlayerScore'];
    if (auto is num || tele is num) {
      return (auto is num ? auto.toDouble() : 0.0) +
          (tele is num ? tele.toDouble() : 0.0);
    }

    final legacy = data['humanPlayerScore'];
    if (legacy is num) {
      return legacy.toDouble();
    }

    return null;
  }

  static int? matchNumber(ScoutingDocument doc) {
    final mn = doc.data['matchNumber'];
    if (mn is int) return mn;
    if (mn is double) return mn.toInt();
    if (mn is String) return int.tryParse(mn);
    return null;
  }

  static int? teamNumber(ScoutingDocument doc) {
    final tn = doc.data['teamNumber'];
    if (tn is int) return tn;
    if (tn is double) return tn.toInt();
    if (tn is String) return int.tryParse(tn);
    return null;
  }

  double _scalarFor(
    ProcessedScoutingDoc doc,
    String sectionId,
    String fieldId,
  ) {
    if (sectionId == kSectionAuto && _scaledAutoFields.contains(fieldId)) {
      return doc.autoFuelScalar;
    }
    if (sectionId == kSectionTele && _scaledTeleFields.contains(fieldId)) {
      return doc.teleFuelScalar;
    }
    return 1.0;
  }

  static const _scaledAutoFields = {kAutoFuelScored, kAutoFuelPassed};

  static const _scaledTeleFields = {
    kTeleFuelScored,
    kTeleFuelPassed,
    kTeleFuelPoached,
  };
}
