part of 'competition_entities.dart';

/// Timing estimates for a match. Every field can be missing.
@GroveValue()
class QueueMatchTimes {
  const QueueMatchTimes({
    this.scheduledStartTime,
    this.estimatedQueueTime,
    this.estimatedOnDeckTime,
    this.estimatedOnFieldTime,
    this.estimatedStartTime,
    this.actualQueueTime,
    this.actualOnDeckTime,
    this.actualOnFieldTime,
    this.actualStartTime,
    this.actualCommitTime,
  });

  final DateTime? scheduledStartTime;
  final DateTime? estimatedQueueTime;
  final DateTime? estimatedOnDeckTime;
  final DateTime? estimatedOnFieldTime;
  final DateTime? estimatedStartTime;
  final DateTime? actualQueueTime;
  final DateTime? actualOnDeckTime;
  final DateTime? actualOnFieldTime;
  final DateTime? actualStartTime;
  final DateTime? actualCommitTime;

  factory QueueMatchTimes.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const QueueMatchTimes();
    return QueueMatchTimes(
      scheduledStartTime: _asTimestamp(json['scheduledStartTime']),
      estimatedQueueTime: _asTimestamp(json['estimatedQueueTime']),
      estimatedOnDeckTime: _asTimestamp(json['estimatedOnDeckTime']),
      estimatedOnFieldTime: _asTimestamp(json['estimatedOnFieldTime']),
      estimatedStartTime: _asTimestamp(json['estimatedStartTime']),
      actualQueueTime: _asTimestamp(json['actualQueueTime']),
      actualOnDeckTime: _asTimestamp(json['actualOnDeckTime']),
      actualOnFieldTime: _asTimestamp(json['actualOnFieldTime']),
      actualStartTime: _asTimestamp(json['actualStartTime']),
      actualCommitTime: _asTimestamp(json['actualCommitTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scheduledStartTime': scheduledStartTime?.millisecondsSinceEpoch,
      'estimatedQueueTime': estimatedQueueTime?.millisecondsSinceEpoch,
      'estimatedOnDeckTime': estimatedOnDeckTime?.millisecondsSinceEpoch,
      'estimatedOnFieldTime': estimatedOnFieldTime?.millisecondsSinceEpoch,
      'estimatedStartTime': estimatedStartTime?.millisecondsSinceEpoch,
      'actualQueueTime': actualQueueTime?.millisecondsSinceEpoch,
      'actualOnDeckTime': actualOnDeckTime?.millisecondsSinceEpoch,
      'actualOnFieldTime': actualOnFieldTime?.millisecondsSinceEpoch,
      'actualStartTime': actualStartTime?.millisecondsSinceEpoch,
      'actualCommitTime': actualCommitTime?.millisecondsSinceEpoch,
    };
  }
}

/// A match in the event queue. Team lists are in station order; a null entry is an
/// empty station and a null list is an undecided playoff alliance.
@GroveValue()
class QueueMatch {
  const QueueMatch({
    required this.label,
    this.status,
    this.redTeams,
    this.blueTeams,
    this.times = const QueueMatchTimes(),
    this.replayOf,
    this.breakAfter,
  });

  final String label;
  final String? status;
  final List<String?>? redTeams;
  final List<String?>? blueTeams;
  final QueueMatchTimes times;
  final String? replayOf;
  final String? breakAfter;

  factory QueueMatch.fromJson(Map<String, dynamic> json) {
    final label = _asString(json['label']);
    if (label == null) {
      throw const FormatException('match is missing a label');
    }

    return QueueMatch(
      label: label,
      status: _asString(json['status']),
      redTeams: _asTeams(json['redTeams']),
      blueTeams: _asTeams(json['blueTeams']),
      times: QueueMatchTimes.fromJson(_asStringMap(json['times'])),
      replayOf: _asString(json['replayOf']),
      breakAfter: _asString(json['breakAfter']),
    );
  }

  NexusMatchRef? get ref => parseNexusMatchLabel(label);

  bool get isPractice => ref?.isPractice ?? false;

  List<String> get redTeamKeys => _teamKeys(redTeams);
  List<String> get blueTeamKeys => _teamKeys(blueTeams);

  String? matchKey(String eventKey) {
    final parsed = ref;
    if (parsed == null) return null;
    return matchKeyForNexusRef(eventKey, parsed);
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'status': status,
      'redTeams': redTeams,
      'blueTeams': blueTeams,
      'times': times.toJson(),
      'replayOf': replayOf,
      'breakAfter': breakAfter,
    };
  }
}

/// Live queue status, announcements, and parts requests for an event.
@GroveEntity('event_status', version: 1, serverManaged: true)
class EventStatusSnapshot {
  const EventStatusSnapshot({
    required this.id,
    required this.dataAsOfTime,
    this.nowQueuing,
    this.matches = const [],
    this.announcements = const [],
    this.partsRequests = const [],
  });

  final String id;
  final DateTime dataAsOfTime;
  final String? nowQueuing;
  final List<QueueMatch> matches;
  final List<EventAnnouncement> announcements;
  final List<EventPartsRequest> partsRequests;

  bool get hasData =>
      matches.isNotEmpty || nowQueuing != null || announcements.isNotEmpty;
}

@GroveValue()
class EventAnnouncement {
  const EventAnnouncement({this.id, required this.text, this.postedAt});

  final String? id;
  final String text;
  final DateTime? postedAt;
}

@GroveValue()
class EventPartsRequest {
  const EventPartsRequest({
    this.id,
    required this.parts,
    required this.requestedByTeam,
    this.postedAt,
  });

  final String? id;
  final String parts;
  final String requestedByTeam;
  final DateTime? postedAt;
}

List<String> _teamKeys(List<String?>? teams) {
  if (teams == null) return const [];
  return teams
      .whereType<String>()
      .map((team) => team.startsWith('frc') ? team : 'frc$team')
      .toList(growable: false);
}

List<String?>? _asTeams(dynamic value) {
  if (value is! List) return null;
  return value.map(_asString).toList(growable: false);
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _asTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    final number = value.toInt();
    return DateTime.fromMillisecondsSinceEpoch(
      number < 1e12 ? number * 1000 : number,
    );
  }
  final text = value.toString().trim();
  final asNumber = num.tryParse(text);
  if (asNumber != null) return _asTimestamp(asNumber);
  return DateTime.tryParse(text);
}

Map<String, dynamic>? _asStringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return null;
}
