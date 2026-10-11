import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services/services.dart';

ScoutingMatch playoff(
  int number, {
  List<String> red = const [],
  List<String> blue = const [],
  String level = 'sf',
}) {
  return ScoutingMatch(
    key: level == 'sf' ? '2026wabel_sf${number}m1' : '2026wabel_f1m$number',
    compLevel: level,
    setNumber: level == 'sf' ? number : 1,
    matchNumber: level == 'sf' ? 1 : number,
    redAlliance: MatchAlliance(teamKeys: red),
    blueAlliance: MatchAlliance(teamKeys: blue),
  );
}

void main() {
  test('reads alliance numbers from the first round', () {
    final alliances = playoffAllianceNumbers([
      playoff(1, red: ['frc1', 'frc2', 'frc3'], blue: ['frc80', 'frc81']),
      playoff(2, red: ['frc40'], blue: ['frc50']),
      playoff(5, red: ['frc999']),
    ]);

    expect(alliances, {
      'frc1': 1,
      'frc2': 1,
      'frc3': 1,
      'frc80': 8,
      'frc81': 8,
      'frc40': 4,
      'frc50': 5,
    });
    expect(
      allianceNumberFor(['frc80', 'frc81', 'frc7777'], alliances),
      8,
      reason: 'a backup robot is not in the first round',
    );
    expect(allianceNumberFor(['frc7777'], alliances), isNull);
  });

  test('finds the playoff matches a team could reach next', () {
    final p1 = playoff(1, red: ['frc2046', 'frc2', 'frc3'], blue: ['frc80']);
    final p5 = playoff(5);
    final p7 = playoff(7, blue: ['frc40']);
    final upcoming = [p1, playoff(2), p5, playoff(6), p7];

    expect(
      possiblePlayoffMatches(
        allMatches: upcoming,
        upcoming: upcoming,
        teamKey: 'frc2046',
      ),
      {p7.key: PlayoffOutcome.win, p5.key: PlayoffOutcome.lose},
    );
  });

  test('does not guess once the side is filled or the match is played', () {
    final p1 = playoff(1, red: ['frc2046'], blue: ['frc80']);
    final p7 = playoff(7, red: ['frc1', 'frc2', 'frc3']);

    expect(
      possiblePlayoffMatches(
        allMatches: [p1, p7],
        upcoming: [p1, p7],
        teamKey: 'frc2046',
      ),
      isEmpty,
      reason: 'Playoff 7 red is already decided',
    );
    expect(
      possiblePlayoffMatches(
        allMatches: [p1, playoff(5)],
        upcoming: [playoff(5)],
        teamKey: 'frc2046',
      ),
      isEmpty,
      reason: 'Playoff 1 is already played',
    );
  });

  test('marks every finals match after the last upper-bracket match', () {
    final p11 = playoff(11, red: ['frc2046'], blue: ['frc80']);
    final finals = [playoff(1, level: 'f'), playoff(2, level: 'f')];

    expect(
      possiblePlayoffMatches(
        allMatches: [p11, ...finals],
        upcoming: [p11, ...finals],
        teamKey: 'frc2046',
      ).keys,
      [finals[0].key, finals[1].key],
    );
  });

  test('detects the double-elimination bracket', () {
    expect(isDoubleElimination(10, const []), isTrue);
    expect(isDoubleElimination(0, [playoff(13)]), isFalse);
    expect(isDoubleElimination(null, [playoff(9)]), isTrue);
    expect(isDoubleElimination(null, [playoff(2)]), isFalse);
  });
}
