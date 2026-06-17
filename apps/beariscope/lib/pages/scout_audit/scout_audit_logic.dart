import 'dart:convert';

import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:core/core.dart' show ScoutPosition;

enum ScoutAuditIssueType { incomplete, notInTba, duplicate, incorrect }

enum ScoutAuditEntryType { match, strat }

class AuditSlot {
  const AuditSlot({
    required this.pos,
    required this.label,
    required this.teamNumber,
    required this.alliance,
  });

  final int pos;
  final String label;
  final int teamNumber;
  final String alliance;
}

class IncompleteMatchIssue {
  const IncompleteMatchIssue({
    required this.matchNumber,
    required this.entryType,
    required this.expectedCount,
    required this.scoutedCount,
    required this.missingSlots,
  });

  final int matchNumber;
  final ScoutAuditEntryType entryType;
  final int expectedCount;
  final int scoutedCount;
  final List<AuditSlot> missingSlots;
}

class NotInTbaIssue {
  const NotInTbaIssue({
    required this.docId,
    required this.matchNumber,
    required this.entryType,
    required this.alliance,
    required this.teamNumber,
    required this.positionLabel,
  });

  final String docId;
  final int matchNumber;
  final ScoutAuditEntryType entryType;
  final String? alliance;
  final int? teamNumber;
  final String positionLabel;
}

class DuplicateIssue {
  const DuplicateIssue({
    required this.matchNumber,
    required this.entryType,
    required this.pos,
    required this.alliance,
    required this.teamNumber,
    required this.entries,
    required this.identical,
    required this.diffByField,
  });

  final int matchNumber;
  final ScoutAuditEntryType entryType;
  final int? pos;
  final String? alliance;
  final int? teamNumber;
  final List<ScoutingDocument> entries;
  final bool identical;
  final Map<String, List<dynamic>> diffByField;
}

class AllianceMetric {
  const AllianceMetric({
    required this.matchNumber,
    required this.alliance,
    required this.scoutedSum,
    required this.tbaScore,
    required this.deviation,
    required this.teams,
    required this.slots,
    required this.flagged,
  });

  final int matchNumber;
  final String alliance;
  final int scoutedSum;
  final int tbaScore;
  final double deviation;
  final List<int> teams;
  final List<AuditSlot> slots;
  final bool flagged;

  String get key => '${matchNumber}_$alliance';
}

class ScoutAuditSnapshot {
  const ScoutAuditSnapshot({
    required this.incompleteMatches,
    required this.notInTba,
    required this.duplicates,
    required this.incorrect,
    required this.allianceMetrics,
  });

  final List<IncompleteMatchIssue> incompleteMatches;
  final List<NotInTbaIssue> notInTba;
  final List<DuplicateIssue> duplicates;
  final List<AllianceMetric> incorrect;
  final List<AllianceMetric> allianceMetrics;

  bool get isEmpty =>
      incompleteMatches.isEmpty &&
      notInTba.isEmpty &&
      duplicates.isEmpty &&
      incorrect.isEmpty;

  AllianceMetric? metricFor(int matchNumber, String alliance) {
    final key = '${matchNumber}_${alliance.toLowerCase()}';
    for (final metric in allianceMetrics) {
      if (metric.key == key) return metric;
    }
    return null;
  }
}

Map<String, dynamic>? findTbaMatchForNumber(
  List<Map<String, dynamic>> matches,
  String eventKey,
  int matchNumber,
) {
  for (final match in matches) {
    if (!_isQualificationMatch(match)) {
      continue;
    }

    final matchEvent =
        match['event_key']?.toString() ?? match['eventKey']?.toString();
    if (matchEvent != null && matchEvent.isNotEmpty && matchEvent != eventKey) {
      continue;
    }

    final parsedMatchNumber = _toInt(
      match['match_number'] ?? match['matchNumber'],
    );
    if (parsedMatchNumber == matchNumber) {
      return match;
    }
  }

  return null;
}

AuditSlot? findAuditSlotForTeamInMatch(
  Map<String, dynamic> match,
  int teamNumber,
) {
  final alliances = _map(match['alliances']);
  if (alliances == null) return null;

  final redTeams = _parseTeamKeys(_map(alliances['red'])?['team_keys']);
  final blueTeams = _parseTeamKeys(_map(alliances['blue'])?['team_keys']);

  for (var pos = 0; pos < redTeams.length && pos < 3; pos++) {
    if (redTeams[pos] != teamNumber) continue;
    return AuditSlot(
      pos: pos,
      label: _posLabel(pos),
      teamNumber: teamNumber,
      alliance: 'red',
    );
  }

  for (var pos = 0; pos < blueTeams.length && pos < 3; pos++) {
    final slot = pos + 3;
    if (blueTeams[pos] != teamNumber) continue;
    return AuditSlot(
      pos: slot,
      label: _posLabel(slot),
      teamNumber: teamNumber,
      alliance: 'blue',
    );
  }

  return null;
}

String? matchVideoKey(Map<String, dynamic> match) {
  final videos = match['videos'];
  if (videos is! List) return null;

  for (final video in videos) {
    final entry = _map(video);
    if (entry == null) continue;
    if (entry['type']?.toString() != 'youtube') continue;

    final key = entry['key']?.toString();
    if (key == null || key.isEmpty || key == 'null') continue;
    return key;
  }

  return null;
}

class _TbaMatchGroundTruth {
  const _TbaMatchGroundTruth({
    required this.matchNumber,
    required this.teamsByPos,
    required this.redTeams,
    required this.blueTeams,
    required this.redScore,
    required this.blueScore,
  });

  final int matchNumber;
  final Map<int, int> teamsByPos;
  final List<int> redTeams;
  final List<int> blueTeams;
  final int redScore;
  final int blueScore;
}

ScoutAuditSnapshot buildScoutAuditSnapshot({
  required List<ScoutingDocument> docs,
  required List<Map<String, dynamic>> tbaMatches,
  required String eventKey,
  required double incorrectThreshold,
}) {
  final matchDocs = docs.where((doc) {
    final meta = doc.meta;
    return meta?['type']?.toString() == 'match' &&
        meta?['event']?.toString() == eventKey;
  }).toList();
  final stratDocs = docs.where((doc) {
    final meta = doc.meta;
    return meta?['type']?.toString() == 'strat' &&
        meta?['event']?.toString() == eventKey;
  }).toList();

  final schedule = _buildGroundTruthByMatch(tbaMatches, eventKey);

  final byMatch = <int, List<ScoutingDocument>>{};
  final byMatchAndPos = <String, List<ScoutingDocument>>{};
  final byStratMatchAndAlliance = <String, List<ScoutingDocument>>{};
  final stratAlliancesByMatch = <int, Set<String>>{};

  for (final doc in matchDocs) {
    final matchNumber = TeamScoutingBundle.matchNumber(doc);
    final pos = _posOf(doc);
    if (matchNumber == null || matchNumber <= 0) continue;

    byMatch.putIfAbsent(matchNumber, () => []).add(doc);

    if (pos != null) {
      final key = '${matchNumber}_$pos';
      byMatchAndPos.putIfAbsent(key, () => []).add(doc);
    }
  }

  for (final doc in stratDocs) {
    final matchNumber = _matchNumberFromMeta(doc);
    final alliance = _allianceFromDoc(doc);
    if (matchNumber == null || matchNumber <= 0 || alliance == null) continue;

    final key = '${matchNumber}_$alliance';
    byStratMatchAndAlliance.putIfAbsent(key, () => []).add(doc);
    stratAlliancesByMatch
        .putIfAbsent(matchNumber, () => <String>{})
        .add(alliance);
  }

  final incomplete = <IncompleteMatchIssue>[];

  // find the highest match number that has any scouting data
  final highestScoutedMatch = byMatch.keys.isEmpty
      ? 0
      : byMatch.keys.reduce((a, b) => a > b ? a : b);

  // check all matches in the schedule up to the highest scouted match
  for (final matchNumber in schedule.keys) {
    // only flag matches up to the highest scouted match
    if (matchNumber > highestScoutedMatch) continue;

    final truth = schedule[matchNumber];
    if (truth == null) continue;

    final seenPositions = <int>{};
    final matchDocuments = byMatch[matchNumber] ?? [];
    for (final doc in matchDocuments) {
      final pos = _posOf(doc);
      if (pos != null && pos >= 0 && pos < 6) {
        seenPositions.add(pos);
      }
    }

    if (seenPositions.length >= 6) continue;

    final missing = <AuditSlot>[];
    for (var pos = 0; pos < 6; pos++) {
      if (seenPositions.contains(pos)) continue;
      final teamNumber = truth.teamsByPos[pos];
      if (teamNumber == null) continue;
      missing.add(
        AuditSlot(
          pos: pos,
          label: _posLabel(pos),
          teamNumber: teamNumber,
          alliance: pos <= 2 ? 'red' : 'blue',
        ),
      );
    }

    if (missing.isEmpty) continue;

    incomplete.add(
      IncompleteMatchIssue(
        matchNumber: matchNumber,
        entryType: ScoutAuditEntryType.match,
        expectedCount: 6,
        scoutedCount: seenPositions.length,
        missingSlots: missing,
      ),
    );
  }

  final highestStratScoutedMatch = stratAlliancesByMatch.keys.isEmpty
      ? 0
      : stratAlliancesByMatch.keys.reduce((a, b) => a > b ? a : b);

  for (final matchNumber in schedule.keys) {
    if (matchNumber > highestStratScoutedMatch) continue;

    final truth = schedule[matchNumber];
    if (truth == null) continue;

    final seenAlliances =
        stratAlliancesByMatch[matchNumber] ?? const <String>{};
    if (seenAlliances.length >= 2) continue;

    final missing = <AuditSlot>[];
    for (final alliance in const ['red', 'blue']) {
      if (seenAlliances.contains(alliance)) continue;
      final pos = alliance == 'red' ? 0 : 3;
      final teamNumber = truth.teamsByPos[pos];
      if (teamNumber == null) continue;
      missing.add(
        AuditSlot(
          pos: alliance == 'red' ? -1 : -2,
          label: _allianceLabel(alliance),
          teamNumber: teamNumber,
          alliance: alliance,
        ),
      );
    }

    if (missing.isEmpty) continue;

    incomplete.add(
      IncompleteMatchIssue(
        matchNumber: matchNumber,
        entryType: ScoutAuditEntryType.strat,
        expectedCount: 2,
        scoutedCount: seenAlliances.length,
        missingSlots: missing,
      ),
    );
  }

  incomplete.sort((a, b) {
    final byMatch = a.matchNumber.compareTo(b.matchNumber);
    if (byMatch != 0) return byMatch;
    return a.entryType.index.compareTo(b.entryType.index);
  });

  final notInTba = <NotInTbaIssue>[];
  final highestScheduledMatchNumber = schedule.isEmpty
      ? 0
      : schedule.keys.reduce((a, b) => a > b ? a : b);

  for (final doc in [...matchDocs, ...stratDocs]) {
    final matchNumber = _auditMatchNumber(doc);
    if (matchNumber == null) continue;

    final isBeyondSchedule =
        highestScheduledMatchNumber > 0 &&
        matchNumber > highestScheduledMatchNumber;
    final isMissingFromSchedule = !schedule.containsKey(matchNumber);
    if (!isBeyondSchedule && !isMissingFromSchedule) continue;

    final entryType = _entryTypeFromDoc(doc);
    final alliance = _allianceFromDoc(doc);

    notInTba.add(
      NotInTbaIssue(
        docId: doc.id,
        matchNumber: matchNumber,
        entryType: entryType,
        alliance: alliance,
        teamNumber: entryType == ScoutAuditEntryType.match
            ? TeamScoutingBundle.teamNumber(doc)
            : null,
        positionLabel: entryType == ScoutAuditEntryType.match
            ? _posLabel(_posOf(doc))
            : _allianceLabel(alliance),
      ),
    );
  }
  notInTba.sort((a, b) {
    final byMatch = a.matchNumber.compareTo(b.matchNumber);
    if (byMatch != 0) return byMatch;
    return a.entryType.index.compareTo(b.entryType.index);
  });

  final duplicates = <DuplicateIssue>[];
  for (final entry in byMatchAndPos.entries) {
    final docsInGroup = entry.value;
    if (docsInGroup.length < 2) continue;

    docsInGroup.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final first = docsInGroup.first;
    final matchNumber = TeamScoutingBundle.matchNumber(first) ?? 0;
    final pos = _posOf(first) ?? -1;

    final canonicalByDoc = {
      for (final doc in docsInGroup) doc.id: _canonicalComparableData(doc),
    };

    final unique = canonicalByDoc.values.map(jsonEncode).toSet();
    final identical = unique.length <= 1;

    final diffByField = identical
        ? const <String, List<dynamic>>{}
        : _buildDiffByField(docsInGroup);

    duplicates.add(
      DuplicateIssue(
        matchNumber: matchNumber,
        entryType: ScoutAuditEntryType.match,
        pos: pos,
        alliance: null,
        teamNumber: TeamScoutingBundle.teamNumber(first),
        entries: docsInGroup,
        identical: identical,
        diffByField: diffByField,
      ),
    );
  }

  for (final entry in byStratMatchAndAlliance.entries) {
    final docsInGroup = entry.value;
    if (docsInGroup.length < 2) continue;

    docsInGroup.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final first = docsInGroup.first;
    final matchNumber = _matchNumberFromMeta(first) ?? 0;
    final alliance = _allianceFromDoc(first);

    final canonicalByDoc = {
      for (final doc in docsInGroup) doc.id: _canonicalComparableData(doc),
    };

    final unique = canonicalByDoc.values.map(jsonEncode).toSet();
    final identical = unique.length <= 1;

    final diffByField = identical
        ? const <String, List<dynamic>>{}
        : _buildDiffByField(docsInGroup);

    duplicates.add(
      DuplicateIssue(
        matchNumber: matchNumber,
        entryType: ScoutAuditEntryType.strat,
        pos: null,
        alliance: alliance,
        teamNumber: null,
        entries: docsInGroup,
        identical: identical,
        diffByField: diffByField,
      ),
    );
  }

  duplicates.sort((a, b) {
    final byMatch = a.matchNumber.compareTo(b.matchNumber);
    if (byMatch != 0) return byMatch;
    final byType = a.entryType.index.compareTo(b.entryType.index);
    if (byType != 0) return byType;
    if (a.entryType == ScoutAuditEntryType.match) {
      return (a.pos ?? -1).compareTo(b.pos ?? -1);
    }
    return (a.alliance ?? '').compareTo(b.alliance ?? '');
  });

  final allMetrics = <AllianceMetric>[];
  for (final truth in schedule.values) {
    final matchEntries =
        byMatch[truth.matchNumber] ?? const <ScoutingDocument>[];

    final red = _buildAllianceMetric(
      matchNumber: truth.matchNumber,
      alliance: 'red',
      tbaScore: truth.redScore,
      teamNumbers: truth.redTeams,
      slotsByPos: truth.teamsByPos,
      docs: matchEntries,
      threshold: incorrectThreshold,
    );
    if (red != null) allMetrics.add(red);

    final blue = _buildAllianceMetric(
      matchNumber: truth.matchNumber,
      alliance: 'blue',
      tbaScore: truth.blueScore,
      teamNumbers: truth.blueTeams,
      slotsByPos: truth.teamsByPos,
      docs: matchEntries,
      threshold: incorrectThreshold,
    );
    if (blue != null) allMetrics.add(blue);
  }

  allMetrics.sort((a, b) {
    final byMatch = a.matchNumber.compareTo(b.matchNumber);
    if (byMatch != 0) return byMatch;
    return a.alliance.compareTo(b.alliance);
  });

  final incorrect = allMetrics.where((m) => m.flagged).toList(growable: false);

  return ScoutAuditSnapshot(
    incompleteMatches: incomplete,
    notInTba: notInTba,
    duplicates: duplicates,
    incorrect: incorrect,
    allianceMetrics: allMetrics,
  );
}

Map<int, _TbaMatchGroundTruth> _buildGroundTruthByMatch(
  List<Map<String, dynamic>> matches,
  String eventKey,
) {
  final result = <int, _TbaMatchGroundTruth>{};

  for (final match in matches) {
    if (!_isQualificationMatch(match)) {
      continue;
    }

    final matchEvent =
        match['event_key']?.toString() ?? match['eventKey']?.toString();
    if (matchEvent != null && matchEvent.isNotEmpty && matchEvent != eventKey) {
      continue;
    }

    final matchNumber = _toInt(match['match_number'] ?? match['matchNumber']);
    if (matchNumber == null || matchNumber <= 0) continue;

    final alliances = _map(match['alliances']);
    if (alliances == null) continue;

    final redMap = _map(alliances['red']) ?? const <String, dynamic>{};
    final blueMap = _map(alliances['blue']) ?? const <String, dynamic>{};

    final redTeams = _parseTeamKeys(redMap['team_keys']);
    final blueTeams = _parseTeamKeys(blueMap['team_keys']);

    if (redTeams.length < 3 || blueTeams.length < 3) {
      continue;
    }

    final redScore = _toInt(redMap['score']) ?? 0;
    final blueScore = _toInt(blueMap['score']) ?? 0;

    final teamsByPos = <int, int>{
      0: redTeams[0],
      1: redTeams[1],
      2: redTeams[2],
      3: blueTeams[0],
      4: blueTeams[1],
      5: blueTeams[2],
    };

    result[matchNumber] = _TbaMatchGroundTruth(
      matchNumber: matchNumber,
      teamsByPos: teamsByPos,
      redTeams: redTeams,
      blueTeams: blueTeams,
      redScore: redScore,
      blueScore: blueScore,
    );
  }

  return result;
}

bool _isQualificationMatch(Map<String, dynamic> match) {
  final compLevel =
      match['comp_level']?.toString() ?? match['compLevel']?.toString() ?? '';
  return compLevel == 'qm';
}

AllianceMetric? _buildAllianceMetric({
  required int matchNumber,
  required String alliance,
  required int tbaScore,
  required List<int> teamNumbers,
  required Map<int, int> slotsByPos,
  required List<ScoutingDocument> docs,
  required double threshold,
}) {
  final isRed = alliance == 'red';
  final minPos = isRed ? 0 : 3;
  final maxPos = isRed ? 2 : 5;

  var scoutedSum = 0;
  var entryCount = 0;

  for (final doc in docs) {
    final pos = _posOf(doc);
    if (pos == null || pos < minPos || pos > maxPos) continue;

    final auto =
        _toInt(
          TeamScoutingBundle.getMatchField(doc, kSectionAuto, kAutoFuelScored),
        ) ??
        0;
    final tele =
        _toInt(
          TeamScoutingBundle.getMatchField(doc, kSectionTele, kTeleFuelScored),
        ) ??
        0;

    scoutedSum += auto + tele;
    entryCount++;
  }

  if (entryCount < 3 || tbaScore <= 0) {
    return null;
  }

  final deviation = (scoutedSum - tbaScore).abs() / tbaScore;

  final slots = <AuditSlot>[];
  for (var pos = minPos; pos <= maxPos; pos++) {
    final team = slotsByPos[pos];
    if (team == null) continue;
    slots.add(
      AuditSlot(
        pos: pos,
        label: _posLabel(pos),
        teamNumber: team,
        alliance: alliance,
      ),
    );
  }

  return AllianceMetric(
    matchNumber: matchNumber,
    alliance: alliance,
    scoutedSum: scoutedSum,
    tbaScore: tbaScore,
    deviation: deviation,
    teams: teamNumbers,
    slots: slots,
    flagged: deviation > threshold,
  );
}

Map<String, List<dynamic>> _buildDiffByField(List<ScoutingDocument> docs) {
  final flattened = <String, Map<String, dynamic>>{
    for (final doc in docs)
      doc.id: _flattenComparableData(_canonicalComparableData(doc)),
  };

  final fieldNames = <String>{};
  for (final map in flattened.values) {
    fieldNames.addAll(map.keys);
  }

  final out = <String, List<dynamic>>{};
  final docIds = docs.map((d) => d.id).toList(growable: false);

  for (final field in fieldNames.toList()..sort()) {
    final values = <dynamic>[];
    for (final docId in docIds) {
      values.add(flattened[docId]?[field]);
    }

    final unique = values.map((v) => jsonEncode(v)).toSet();
    if (unique.length > 1) {
      out[field] = values;
    }
  }

  return out;
}

Map<String, dynamic> _flattenComparableData(Map<String, dynamic> source) {
  final out = <String, dynamic>{};

  void walk(String prefix, dynamic value) {
    if (value is Map<String, dynamic>) {
      for (final entry in value.entries) {
        final next = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
        walk(next, entry.value);
      }
      return;
    }

    if (value is List) {
      out[prefix] = value;
      return;
    }

    out[prefix] = value;
  }

  for (final entry in source.entries) {
    walk(entry.key, entry.value);
  }

  return out;
}

Map<String, dynamic> _canonicalComparableData(ScoutingDocument doc) {
  final raw = doc.data;
  final map = _sortAndNormalizeMap(_map(raw) ?? const <String, dynamic>{});
  final meta = _map(map['meta']);
  if (meta != null) {
    final cleanedMeta = Map<String, dynamic>.from(meta)
      ..remove('scoutedBy')
      ..remove('deviceId')
      ..remove('syncSource')
      ..remove('existingId')
      ..remove('userId');
    map['meta'] = _sortAndNormalizeMap(cleanedMeta);
  }
  return map;
}

Map<String, dynamic> _sortAndNormalizeMap(Map<String, dynamic> input) {
  final keys = input.keys.toList()..sort();
  final out = <String, dynamic>{};
  for (final key in keys) {
    final value = input[key];
    if (value is Map) {
      out[key] = _sortAndNormalizeMap(_map(value) ?? const <String, dynamic>{});
    } else if (value is List) {
      out[key] = value.map(_normalizeDynamic).toList(growable: false);
    } else {
      out[key] = value;
    }
  }
  return out;
}

dynamic _normalizeDynamic(dynamic value) {
  if (value is Map) {
    return _sortAndNormalizeMap(_map(value) ?? const <String, dynamic>{});
  }
  if (value is List) {
    return value.map(_normalizeDynamic).toList(growable: false);
  }
  return value;
}

Map<String, dynamic>? _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return null;
}

List<int> _parseTeamKeys(dynamic value) {
  if (value is! List) return const [];
  final teams = <int>[];
  for (final key in value) {
    final raw = key?.toString() ?? '';
    if (raw.isEmpty) continue;
    final normalized = raw.startsWith('frc') ? raw.substring(3) : raw;
    final team = int.tryParse(normalized);
    if (team != null) teams.add(team);
  }
  return teams;
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

ScoutAuditEntryType _entryTypeFromDoc(ScoutingDocument doc) {
  if (doc.meta?['type']?.toString() == 'strat') {
    return ScoutAuditEntryType.strat;
  }
  return ScoutAuditEntryType.match;
}

int? _auditMatchNumber(ScoutingDocument doc) {
  final entryType = _entryTypeFromDoc(doc);
  if (entryType == ScoutAuditEntryType.strat) {
    return _matchNumberFromMeta(doc);
  }
  return TeamScoutingBundle.matchNumber(doc);
}

int? _matchNumberFromMeta(ScoutingDocument doc) {
  final value = doc.meta?['matchNumber'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String? _allianceFromDoc(ScoutingDocument doc) {
  final raw = doc.meta?['alliance']?.toString().trim().toLowerCase();
  if (raw == 'red' || raw == 'blue') return raw;
  return null;
}

String _allianceLabel(String? alliance) {
  return switch (alliance) {
    'red' => 'Red Alliance',
    'blue' => 'Blue Alliance',
    _ => 'Unknown Alliance',
  };
}

int? _posOf(ScoutingDocument doc) {
  final value = doc.data['pos'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _posLabel(int? pos) {
  final parsed = ScoutPosition.fromPosIndex(pos);
  if (parsed != null) return parsed.displayName;
  return 'Unknown Position';
}
