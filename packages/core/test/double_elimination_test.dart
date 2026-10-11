import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final matches = [for (var n = 1; n <= 13; n++) doubleEliminationMatch(n)!];

  test('matches the Nexus card for Playoff 5', () {
    final match = doubleEliminationMatch(5)!;
    expect(match.round, 2);
    expect(match.bracket, PlayoffBracket.lower);
    expect(match.winnerTo.match, 10);
    expect(match.winnerTo.red, isFalse);
    expect(match.loserPlace, 'T-7th');
  });

  test('every result moves to a later match', () {
    for (final match in matches) {
      for (final slot in [match.winnerTo, ?match.loserTo]) {
        if (!slot.isFinals) expect(slot.match, greaterThan(match.number));
      }
    }
  });

  test('every later match and the finals get one red and one blue', () {
    final sources = <int?, List<bool>>{};
    for (final match in matches) {
      for (final slot in [match.winnerTo, ?match.loserTo]) {
        sources.putIfAbsent(slot.match, () => []).add(slot.red);
      }
    }

    expect(sources.keys.toSet(), {for (var n = 5; n <= 13; n++) n, null});
    for (final sides in sources.values) {
      expect(sides..sort((a, b) => a ? -1 : 1), [true, false]);
    }
  });

  test('upper bracket losers drop down, lower bracket losers are out', () {
    for (final match in matches) {
      final upper = match.bracket == PlayoffBracket.upper;
      expect(match.loserTo != null, upper, reason: 'Playoff ${match.number}');
      expect(
        match.loserPlace != null,
        !upper,
        reason: 'Playoff ${match.number}',
      );
    }
  });

  test('the first round covers all 8 alliances', () {
    expect(
      doubleEliminationFirstRound.values.expand((pair) => [pair.$1, pair.$2]),
      unorderedEquals([1, 2, 3, 4, 5, 6, 7, 8]),
    );
  });
}
