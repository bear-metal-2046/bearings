import 'package:beariscope/models/nexus_live_status.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';

class ParsedNexusLabel {
  final String compLevel;
  final int number;
  final bool isReplay;

  const ParsedNexusLabel({
    required this.compLevel,
    required this.number,
    this.isReplay = false,
  });
}

const _activeNexusStatuses = {
  'Queuing soon',
  'Now queuing',
  'On deck',
  'On field',
};

bool isActiveNexusStatus(String? status) {
  if (status == null) return false;
  return _activeNexusStatuses.contains(status);
}

ParsedNexusLabel? parseNexusMatchLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return null;

  final isReplay = RegExp(
    r'\breplay\b',
    caseSensitive: false,
  ).hasMatch(trimmed);

  final qualification = RegExp(
    r'^qualification\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (qualification != null) {
    return ParsedNexusLabel(
      compLevel: 'qm',
      number: int.parse(qualification.group(1)!),
      isReplay: isReplay,
    );
  }

  final semifinal = RegExp(
    r'^(?:semifinal|playoff)\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (semifinal != null) {
    return ParsedNexusLabel(
      compLevel: 'sf',
      number: int.parse(semifinal.group(1)!),
      isReplay: isReplay,
    );
  }

  final finalMatch = RegExp(
    r'^final\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (finalMatch != null) {
    return ParsedNexusLabel(
      compLevel: 'f',
      number: int.parse(finalMatch.group(1)!),
      isReplay: isReplay,
    );
  }

  final practice = RegExp(
    r'^practice\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (practice != null) {
    return ParsedNexusLabel(
      compLevel: 'pm',
      number: int.parse(practice.group(1)!),
      isReplay: isReplay,
    );
  }

  return null;
}

Set<int> teamNumbersForTbaMatch(Map<String, dynamic> match) {
  final alliances = match['alliances'] as Map?;
  if (alliances == null) return const {};

  final numbers = <int>{};
  for (final alliance in alliances.values) {
    if (alliance is! Map) continue;
    final keys =
        (alliance['team_keys'] ?? alliance['teamKeys'] ?? alliance['teams'])
            as List?;
    if (keys == null) continue;

    for (final key in keys) {
      final parsed = _teamNumberFromKey(key?.toString());
      if (parsed != null) numbers.add(parsed);
    }
  }

  return numbers;
}

Set<int> teamNumbersForNexusMatch(NexusMatch match) {
  final numbers = <int>{};
  for (final team in [...match.redTeams, ...match.blueTeams]) {
    final parsed = int.tryParse(team);
    if (parsed != null) numbers.add(parsed);
  }
  return numbers;
}

bool alliancesMatch(NexusMatch nexusMatch, Map<String, dynamic> tbaMatch) {
  final nexusTeams = teamNumbersForNexusMatch(nexusMatch);
  final tbaTeams = teamNumbersForTbaMatch(tbaMatch);

  if (nexusTeams.isEmpty || tbaTeams.isEmpty) return true;
  if (nexusTeams.length != tbaTeams.length) return false;
  return nexusTeams.containsAll(tbaTeams);
}

bool scheduleMatchMatchesNexusLabel(
  Map<String, dynamic> tbaMatch,
  ParsedNexusLabel parsed,
) {
  if (compLevelForMatch(tbaMatch) != parsed.compLevel) return false;

  final number = switch (parsed.compLevel) {
    'sf' => setNumberForMatch(tbaMatch) ?? matchNumberForMatch(tbaMatch),
    _ => matchNumberForMatch(tbaMatch),
  };

  return number == parsed.number;
}

String? tbaMatchKeyForNexusMatch(
  NexusMatch nexusMatch,
  List<Map<String, dynamic>> scheduleMatches,
) {
  final parsed = parseNexusMatchLabel(nexusMatch.label);
  if (parsed == null) return null;

  final candidates = scheduleMatches
      .where((match) => scheduleMatchMatchesNexusLabel(match, parsed))
      .where((match) => alliancesMatch(nexusMatch, match))
      .toList();

  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first['key']?.toString();

  for (final match in candidates) {
    if (alliancesMatch(nexusMatch, match)) {
      return match['key']?.toString();
    }
  }

  return candidates.first['key']?.toString();
}

NexusMatch? nexusMatchForScheduleMatch(
  Map<String, dynamic> tbaMatch,
  NexusLiveStatus? liveStatus,
) {
  if (liveStatus == null) return null;

  final matches = liveStatus.matches.where((nexusMatch) {
    final parsed = parseNexusMatchLabel(nexusMatch.label);
    if (parsed == null) return false;
    if (!scheduleMatchMatchesNexusLabel(tbaMatch, parsed)) return false;
    return alliancesMatch(nexusMatch, tbaMatch);
  }).toList();

  if (matches.isEmpty) return null;
  if (matches.length == 1) return matches.first;

  return matches.firstWhere(
    (match) => isActiveNexusStatus(match.status),
    orElse: () => matches.first,
  );
}

DateTime? resolveScheduleMatchTime(
  Map<String, dynamic> tbaMatch,
  NexusMatch? nexusMatch,
) {
  if (nexusMatch != null &&
      isActiveNexusStatus(nexusMatch.status) &&
      nexusMatch.times.displayTime != null) {
    return nexusMatch.times.displayTime;
  }

  return _parseTbaMatchTime(tbaMatch) ?? nexusMatch?.times.displayTime;
}

int? _teamNumberFromKey(String? key) {
  if (key == null || key.isEmpty) return null;
  final stripped = key.toLowerCase().replaceFirst(RegExp(r'^frc'), '');
  return int.tryParse(stripped);
}

DateTime? _parseTbaMatchTime(Map<String, dynamic> match) {
  final value = match['predictedTime'] ?? match['predicted_time'];
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
  }
  return null;
}
