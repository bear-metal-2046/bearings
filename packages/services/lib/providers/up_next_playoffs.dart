import 'package:core/core.dart';

/// Which result would send a team to a possible playoff match.
enum PlayoffOutcome { win, lose }

/// Whether the event uses FRC's 8-alliance double-elimination bracket. Uses
/// TBA's [playoffType] when known, otherwise looks for playoff matches past
/// the first two rounds, which only that bracket has.
bool isDoubleElimination(int? playoffType, Iterable<ScoutingMatch> matches) {
  if (playoffType != null) return playoffType == doubleElimination8PlayoffType;
  return matches.any((match) => match.compLevel == 'sf' && match.setNumber > 8);
}

/// The double-elimination bracket entry for a match, or null for qualifications
/// and finals.
DoubleEliminationMatch? bracketFor(ScoutingMatch match) {
  if (match.compLevel != 'sf') return null;
  return doubleEliminationMatch(match.setNumber);
}

/// Alliance number for each team key, read from the first-round matches, where
/// the bracket fixes which alliances play.
Map<String, int> playoffAllianceNumbers(Iterable<ScoutingMatch> matches) {
  final alliances = <String, int>{};
  for (final match in matches) {
    if (match.compLevel != 'sf') continue;
    final firstRound = doubleEliminationFirstRound[match.setNumber];
    if (firstRound == null) continue;
    final (red, blue) = firstRound;
    for (final team in match.redAlliance?.teamKeys ?? const <String>[]) {
      alliances[team] = red;
    }
    for (final team in match.blueAlliance?.teamKeys ?? const <String>[]) {
      alliances[team] = blue;
    }
  }
  return alliances;
}

/// The alliance most of [teamKeys] belong to. Backup robots can be missing
/// from [alliances], so this goes by majority.
int? allianceNumberFor(List<String> teamKeys, Map<String, int> alliances) {
  final counts = <int, int>{};
  for (final team in teamKeys) {
    final alliance = alliances[team];
    if (alliance != null) counts[alliance] = (counts[alliance] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Upcoming playoff matches [teamKey] could play next, keyed by match key, for
/// the side of each match that has no teams yet. Only looks one result ahead,
/// from the team's latest playoff match that is still in [upcoming].
Map<String, PlayoffOutcome> possiblePlayoffMatches({
  required Iterable<ScoutingMatch> allMatches,
  required List<ScoutingMatch> upcoming,
  required String teamKey,
}) {
  bool plays(ScoutingMatch match) =>
      (match.redAlliance?.teamKeys.contains(teamKey) ?? false) ||
      (match.blueAlliance?.teamKeys.contains(teamKey) ?? false);

  final latest = allMatches
      .where((match) => match.compLevel == 'sf' && plays(match))
      .fold<ScoutingMatch?>(
        null,
        (latest, match) => latest == null || match.setNumber > latest.setNumber
            ? match
            : latest,
      );
  if (latest == null || !upcoming.any((match) => match.key == latest.key)) {
    return const {};
  }
  final bracket = bracketFor(latest);
  if (bracket == null) return const {};

  final possible = <String, PlayoffOutcome>{};
  void mark(PlayoffSlot? slot, PlayoffOutcome outcome) {
    if (slot == null) return;
    for (final match in upcoming) {
      final isSlot = slot.isFinals
          ? match.compLevel == 'f'
          : match.compLevel == 'sf' && match.setNumber == slot.match;
      if (!isSlot) continue;
      final side = slot.red ? match.redAlliance : match.blueAlliance;
      if (side?.teamKeys.isEmpty ?? true) possible[match.key] = outcome;
    }
  }

  mark(bracket.winnerTo, PlayoffOutcome.win);
  mark(bracket.loserTo, PlayoffOutcome.lose);
  return possible;
}
