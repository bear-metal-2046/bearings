/// FRC's 8-alliance double-elimination playoff bracket (TBA playoff type 10).
/// TBA keys playoff match N as `sfNm1` and the finals as `f1mN`.
library;

/// TBA's `playoff_type` for the 8-alliance double-elimination bracket.
const doubleElimination8PlayoffType = 10;

enum PlayoffBracket { upper, lower }

/// Where an alliance goes next: a playoff match, or the finals when [match]
/// is null.
class PlayoffSlot {
  const PlayoffSlot(this.match, {required this.red});

  const PlayoffSlot.finals({required this.red}) : match = null;

  final int? match;
  final bool red;

  bool get isFinals => match == null;
}

class DoubleEliminationMatch {
  const DoubleEliminationMatch({
    required this.number,
    required this.round,
    required this.bracket,
    required this.winnerTo,
    this.loserTo,
    this.loserPlace,
  });

  final int number;
  final int round;
  final PlayoffBracket bracket;
  final PlayoffSlot winnerTo;

  /// The lower-bracket match the loser drops to, for upper-bracket matches.
  final PlayoffSlot? loserTo;

  /// The final placement of the loser, for lower-bracket matches.
  final String? loserPlace;
}

const _upper = PlayoffBracket.upper;
const _lower = PlayoffBracket.lower;

const _bracket = <int, DoubleEliminationMatch>{
  1: DoubleEliminationMatch(
    number: 1,
    round: 1,
    bracket: _upper,
    winnerTo: PlayoffSlot(7, red: true),
    loserTo: PlayoffSlot(5, red: true),
  ),
  2: DoubleEliminationMatch(
    number: 2,
    round: 1,
    bracket: _upper,
    winnerTo: PlayoffSlot(7, red: false),
    loserTo: PlayoffSlot(5, red: false),
  ),
  3: DoubleEliminationMatch(
    number: 3,
    round: 1,
    bracket: _upper,
    winnerTo: PlayoffSlot(8, red: true),
    loserTo: PlayoffSlot(6, red: true),
  ),
  4: DoubleEliminationMatch(
    number: 4,
    round: 1,
    bracket: _upper,
    winnerTo: PlayoffSlot(8, red: false),
    loserTo: PlayoffSlot(6, red: false),
  ),
  5: DoubleEliminationMatch(
    number: 5,
    round: 2,
    bracket: _lower,
    winnerTo: PlayoffSlot(10, red: false),
    loserPlace: 'T-7th',
  ),
  6: DoubleEliminationMatch(
    number: 6,
    round: 2,
    bracket: _lower,
    winnerTo: PlayoffSlot(9, red: false),
    loserPlace: 'T-7th',
  ),
  7: DoubleEliminationMatch(
    number: 7,
    round: 2,
    bracket: _upper,
    winnerTo: PlayoffSlot(11, red: true),
    loserTo: PlayoffSlot(9, red: true),
  ),
  8: DoubleEliminationMatch(
    number: 8,
    round: 2,
    bracket: _upper,
    winnerTo: PlayoffSlot(11, red: false),
    loserTo: PlayoffSlot(10, red: true),
  ),
  9: DoubleEliminationMatch(
    number: 9,
    round: 3,
    bracket: _lower,
    winnerTo: PlayoffSlot(12, red: false),
    loserPlace: 'T-5th',
  ),
  10: DoubleEliminationMatch(
    number: 10,
    round: 3,
    bracket: _lower,
    winnerTo: PlayoffSlot(12, red: true),
    loserPlace: 'T-5th',
  ),
  11: DoubleEliminationMatch(
    number: 11,
    round: 4,
    bracket: _upper,
    winnerTo: PlayoffSlot.finals(red: true),
    loserTo: PlayoffSlot(13, red: true),
  ),
  12: DoubleEliminationMatch(
    number: 12,
    round: 4,
    bracket: _lower,
    winnerTo: PlayoffSlot(13, red: false),
    loserPlace: '4th',
  ),
  13: DoubleEliminationMatch(
    number: 13,
    round: 5,
    bracket: _lower,
    winnerTo: PlayoffSlot.finals(red: false),
    loserPlace: '3rd',
  ),
};

/// Bracket details for playoff match [number] (1 to 13), or null.
DoubleEliminationMatch? doubleEliminationMatch(int number) => _bracket[number];

/// The alliance numbers (red, blue) that play each first-round match.
const doubleEliminationFirstRound = <int, (int, int)>{
  1: (1, 8),
  2: (4, 5),
  3: (2, 7),
  4: (3, 6),
};
