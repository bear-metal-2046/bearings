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

class ScoutingEvent {
  const ScoutingEvent({
    required this.key,
    required this.name,
    required this.year,
    this.startDate,
    this.endDate,
  });

  final String key;
  final String name;
  final int year;
  final DateTime? startDate;
  final DateTime? endDate;

  factory ScoutingEvent.fromJson(Map<String, dynamic> json) {
    return ScoutingEvent(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      year: _asInt(json['year']) ?? 0,
      startDate: _asDateTime(json['startDate']),
      endDate: _asDateTime(json['endDate']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'year': year,
      'startDate': startDate?.toUtc().toIso8601String(),
      'endDate': endDate?.toUtc().toIso8601String(),
    };
  }
}

class MatchAlliance {
  const MatchAlliance({this.score, this.teamKeys = const []});

  final int? score;
  final List<String> teamKeys;

  factory MatchAlliance.fromJson(Map<String, dynamic> json) {
    return MatchAlliance(
      score: _asInt(json['score']),
      teamKeys: (json['team_keys'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {'score': score, 'team_keys': teamKeys};
  }
}

class ScoutingMatch {
  const ScoutingMatch({
    required this.key,
    required this.compLevel,
    required this.matchNumber,
    this.setNumber = 1,
    this.eventKey,
    this.redAlliance,
    this.blueAlliance,
    this.predictedTime,
    this.actualTime,
    this.nexus,
  });

  final String key;
  final String compLevel;
  final int matchNumber;
  final int setNumber;
  final String? eventKey;
  final MatchAlliance? redAlliance;
  final MatchAlliance? blueAlliance;
  final int? predictedTime;
  final int? actualTime;
  final Map<String, dynamic>? nexus;

  factory ScoutingMatch.fromJson(Map<String, dynamic> json) {
    final alliances = _asStringMap(json['alliances']);
    final red = _asStringMap(alliances?['red']);
    final blue = _asStringMap(alliances?['blue']);

    return ScoutingMatch(
      key: json['key']?.toString() ?? '',
      compLevel: json['comp_level']?.toString() ?? '',
      matchNumber: _asInt(json['match_number']) ?? 0,
      setNumber: _asInt(json['set_number']) ?? 1,
      eventKey: json['event_key']?.toString(),
      redAlliance: red != null ? MatchAlliance.fromJson(red) : null,
      blueAlliance: blue != null ? MatchAlliance.fromJson(blue) : null,
      predictedTime: _asInt(json['predicted_time']),
      actualTime: _asInt(json['actual_time']),
      nexus: _asStringMap(json['nexus']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'comp_level': compLevel,
      'match_number': matchNumber,
      'set_number': setNumber,
      'event_key': eventKey,
      'alliances': {
        'red': redAlliance?.toJson(),
        'blue': blueAlliance?.toJson(),
      },
      'predicted_time': predictedTime,
      'actual_time': actualTime,
      if (nexus != null) 'nexus': nexus,
    };
  }

  String get displayLabel {
    switch (compLevel) {
      case 'qm':
        return 'Qual $matchNumber';
      case 'sf':
        return 'SF $setNumber-$matchNumber';
      case 'f':
        return 'Final $matchNumber';
      default:
        return '$compLevel $matchNumber';
    }
  }

  String? teamKeyAt(ScoutPosition position) {
    final alliance = position.isRed ? redAlliance : blueAlliance;
    if (alliance == null) return null;

    final index = position.allianceIndex;
    if (index < 0 || index >= alliance.teamKeys.length) return null;
    return alliance.teamKeys[index];
  }

  String teamNumberAt(ScoutPosition position) {
    final key = teamKeyAt(position);
    if (key == null) return '???';
    return key.replaceFirst('frc', '');
  }
}

class Scout {
  const Scout({required this.name, required this.uuid});

  final String name;
  final String uuid;

  factory Scout.fromJson(Map<String, dynamic> json) {
    return Scout(
      name: json['name']?.toString() ?? '',
      uuid: json['uuid']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'uuid': uuid};
  }
}

Map<String, dynamic>? _asStringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}
