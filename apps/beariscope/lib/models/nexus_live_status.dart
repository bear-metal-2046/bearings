class NexusLiveStatus {
  final String eventKey;
  final DateTime dataAsOfTime;
  final String? nowQueuing;
  final List<NexusMatch> matches;
  final List<NexusAnnouncement> announcements;

  const NexusLiveStatus({
    required this.eventKey,
    required this.dataAsOfTime,
    this.nowQueuing,
    required this.matches,
    required this.announcements,
  });

  factory NexusLiveStatus.fromJson(Map<String, dynamic> json) {
    return NexusLiveStatus(
      eventKey: json['eventKey']?.toString() ?? '',
      dataAsOfTime: _parseTimestamp(json['dataAsOfTime']),
      nowQueuing: json['nowQueuing']?.toString(),
      matches: (json['matches'] as List? ?? const [])
          .whereType<Map>()
          .map((raw) => NexusMatch.fromJson(Map<String, dynamic>.from(raw)))
          .toList(),
      announcements: (json['announcements'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (raw) => NexusAnnouncement.fromJson(Map<String, dynamic>.from(raw)),
          )
          .toList(),
    );
  }
}

class NexusMatch {
  final String label;
  final String? status;
  final List<String> redTeams;
  final List<String> blueTeams;
  final NexusMatchTimes times;

  const NexusMatch({
    required this.label,
    this.status,
    required this.redTeams,
    required this.blueTeams,
    required this.times,
  });

  bool includesTeam(int teamNumber) {
    final team = teamNumber.toString();
    return redTeams.contains(team) || blueTeams.contains(team);
  }

  factory NexusMatch.fromJson(Map<String, dynamic> json) {
    return NexusMatch(
      label: json['label']?.toString() ?? 'Unknown match',
      status: json['status']?.toString(),
      redTeams: _parseTeamList(json['redTeams']),
      blueTeams: _parseTeamList(json['blueTeams']),
      times: NexusMatchTimes.fromJson(
        Map<String, dynamic>.from(json['times'] as Map? ?? const {}),
      ),
    );
  }
}

class NexusMatchTimes {
  final DateTime? estimatedQueueTime;
  final DateTime? estimatedOnDeckTime;
  final DateTime? estimatedOnFieldTime;
  final DateTime? estimatedStartTime;
  final DateTime? actualQueueTime;

  const NexusMatchTimes({
    this.estimatedQueueTime,
    this.estimatedOnDeckTime,
    this.estimatedOnFieldTime,
    this.estimatedStartTime,
    this.actualQueueTime,
  });

  DateTime? get displayTime =>
      estimatedQueueTime ?? actualQueueTime ?? estimatedStartTime;

  factory NexusMatchTimes.fromJson(Map<String, dynamic> json) {
    return NexusMatchTimes(
      estimatedQueueTime: _parseOptionalTimestamp(json['estimatedQueueTime']),
      estimatedOnDeckTime: _parseOptionalTimestamp(json['estimatedOnDeckTime']),
      estimatedOnFieldTime: _parseOptionalTimestamp(
        json['estimatedOnFieldTime'],
      ),
      estimatedStartTime: _parseOptionalTimestamp(json['estimatedStartTime']),
      actualQueueTime: _parseOptionalTimestamp(json['actualQueueTime']),
    );
  }
}

class NexusAnnouncement {
  final String message;

  const NexusAnnouncement({required this.message});

  factory NexusAnnouncement.fromJson(Map<String, dynamic> json) {
    return NexusAnnouncement(
      message: json['message']?.toString() ?? json['text']?.toString() ?? '',
    );
  }
}

List<String> _parseTeamList(Object? value) {
  if (value is! List) return const [];
  return value.map((team) => team.toString()).toList();
}

DateTime _parseTimestamp(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _parseOptionalTimestamp(Object? value) {
  if (value == null) return null;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
