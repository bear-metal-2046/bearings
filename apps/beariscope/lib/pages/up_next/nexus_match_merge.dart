import 'package:beariscope/models/match_nexus_info.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';

class ParsedNexusLabel {
  final String compLevel;
  final int number;

  const ParsedNexusLabel({required this.compLevel, required this.number});
}

ParsedNexusLabel? parseNexusMatchLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return null;

  final qualification = RegExp(
    r'^qualification\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (qualification != null) {
    return ParsedNexusLabel(
      compLevel: 'qm',
      number: int.parse(qualification.group(1)!),
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
    );
  }

  return null;
}

MatchNexusInfo? nexusMatchForTbaMatch(
  Map<String, dynamic> tbaMatch,
  List<MatchNexusInfo> nexusMatches,
) {
  if (nexusMatches.isEmpty) return null;

  final candidates = nexusMatches.where((nexusMatch) {
    final label = nexusMatch.label;
    if (label == null) return false;

    final parsed = parseNexusMatchLabel(label);
    if (parsed == null) return false;
    if (!_scheduleMatchMatchesLabel(tbaMatch, parsed)) return false;

    return _alliancesMatch(nexusMatch, tbaMatch);
  }).toList();

  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first;

  return candidates.firstWhere(
    (match) => isActiveQueueStatus(match.status),
    orElse: () => candidates.first,
  );
}

bool _scheduleMatchMatchesLabel(
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

bool _alliancesMatch(MatchNexusInfo nexusMatch, Map<String, dynamic> tbaMatch) {
  final nexusTeams = {
    ...nexusMatch.redTeams.map(_teamNumberFromKey),
    ...nexusMatch.blueTeams.map(_teamNumberFromKey),
  }.whereType<int>().toSet();
  final tbaTeams = _teamNumbersForTbaMatch(tbaMatch);

  if (nexusTeams.isEmpty || tbaTeams.isEmpty) return true;
  if (nexusTeams.length != tbaTeams.length) return false;
  return nexusTeams.containsAll(tbaTeams);
}

Set<int> _teamNumbersForTbaMatch(Map<String, dynamic> match) {
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

int? _teamNumberFromKey(String? key) {
  if (key == null || key.isEmpty) return null;
  final stripped = key.toLowerCase().replaceFirst(RegExp(r'^frc'), '');
  return int.tryParse(stripped);
}
