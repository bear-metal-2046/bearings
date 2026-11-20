enum ScoutPosition {
  red1('Red 1', true, false),
  red2('Red 2', true, false),
  red3('Red 3', true, false),
  redStrat('Red Strat', true, true),
  blue1('Blue 1', false, false),
  blue2('Blue 2', false, false),
  blue3('Blue 3', false, false),
  blueStrat('Blue Strat', false, true);

  const ScoutPosition(this.displayName, this.isRed, this.isStrategy);

  final String displayName;
  final bool isRed;
  final bool isStrategy;

  int get allianceIndex {
    switch (this) {
      case ScoutPosition.red1:
      case ScoutPosition.blue1:
        return 0;
      case ScoutPosition.red2:
      case ScoutPosition.blue2:
        return 1;
      case ScoutPosition.red3:
      case ScoutPosition.blue3:
        return 2;
      case ScoutPosition.redStrat:
      case ScoutPosition.blueStrat:
        return -1;
    }
  }

  String get allianceKey => isRed ? 'red' : 'blue';

  int get posIndex {
    switch (this) {
      case ScoutPosition.red1:
        return 0;
      case ScoutPosition.red2:
        return 1;
      case ScoutPosition.red3:
        return 2;
      case ScoutPosition.blue1:
        return 3;
      case ScoutPosition.blue2:
        return 4;
      case ScoutPosition.blue3:
        return 5;
      case ScoutPosition.redStrat:
        return 6;
      case ScoutPosition.blueStrat:
        return 7;
    }
  }

  static ScoutPosition? fromPosIndex(int? value) {
    if (value == null) return null;
    for (final position in ScoutPosition.values) {
      if (position.posIndex == value) return position;
    }
    return null;
  }
}
