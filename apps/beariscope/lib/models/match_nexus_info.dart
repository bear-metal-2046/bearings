class MatchNexusInfo {
  final String? label;
  final String? status;
  final List<String> redTeams;
  final List<String> blueTeams;
  final DateTime? estimatedQueueTime;
  final DateTime? estimatedOnDeckTime;
  final DateTime? estimatedOnFieldTime;
  final DateTime? estimatedStartTime;
  final DateTime? actualQueueTime;

  const MatchNexusInfo({
    this.label,
    this.status,
    this.redTeams = const [],
    this.blueTeams = const [],
    this.estimatedQueueTime,
    this.estimatedOnDeckTime,
    this.estimatedOnFieldTime,
    this.estimatedStartTime,
    this.actualQueueTime,
  });

  DateTime? get displayTime {
    return estimatedQueueTime ??
        actualQueueTime ??
        estimatedStartTime ??
        estimatedOnDeckTime;
  }

  static MatchNexusInfo? fromMatchJson(Map<String, dynamic> match) {
    final nested = match['nexus'];
    if (nested is Map) {
      return fromNexusMap(Map<String, dynamic>.from(nested));
    }

    final status = _string(match['nexusStatus'] ?? match['nexus_status']);
    final times = match['nexusTimes'] ?? match['nexus_times'] ?? match['times'];
    if (status == null && times is! Map) return null;

    return fromNexusMap({
      'label': match['nexusLabel'] ?? match['nexus_label'],
      'status': status,
      'times': times is Map ? times : const {},
    });
  }

  static MatchNexusInfo? fromNexusMap(Map<String, dynamic> json) {
    final status = _string(json['status']);
    final label = _string(json['label']);
    final timesRaw = json['times'];
    final times = timesRaw is Map
        ? Map<String, dynamic>.from(timesRaw)
        : const <String, dynamic>{};

    if (status == null &&
        label == null &&
        times.isEmpty &&
        json['estimatedQueueTime'] == null &&
        json['estimated_queue_time'] == null) {
      return null;
    }

    return MatchNexusInfo(
      label: label,
      status: status,
      redTeams: _parseTeamList(json['redTeams'] ?? json['red_teams']),
      blueTeams: _parseTeamList(json['blueTeams'] ?? json['blue_teams']),
      estimatedQueueTime: _parseTimestamp(
        times['estimatedQueueTime'] ?? times['estimated_queue_time'],
      ),
      estimatedOnDeckTime: _parseTimestamp(
        times['estimatedOnDeckTime'] ?? times['estimated_on_deck_time'],
      ),
      estimatedOnFieldTime: _parseTimestamp(
        times['estimatedOnFieldTime'] ?? times['estimated_on_field_time'],
      ),
      estimatedStartTime: _parseTimestamp(
        times['estimatedStartTime'] ?? times['estimated_start_time'],
      ),
      actualQueueTime: _parseTimestamp(
        times['actualQueueTime'] ?? times['actual_queue_time'],
      ),
    );
  }
}

class UpNextEventContext {
  final String? nowQueuing;
  final List<String> announcements;
  final DateTime? dataAsOfTime;

  const UpNextEventContext({
    this.nowQueuing,
    this.announcements = const [],
    this.dataAsOfTime,
  });

  static UpNextEventContext? fromEventJson(Map<String, dynamic> json) {
    final nested = json['nexus'];
    final source = nested is Map ? Map<String, dynamic>.from(nested) : json;

    final nowQueuing = _string(
      source['nowQueuing'] ??
          source['now_queuing'] ??
          json['nowQueuing'] ??
          json['now_queuing'],
    );

    final announcements = _parseAnnouncements(
      source['announcements'] ?? json['announcements'],
    );

    final dataAsOfTime = _parseTimestamp(
      source['dataAsOfTime'] ??
          source['data_as_of_time'] ??
          json['dataAsOfTime'] ??
          json['data_as_of_time'] ??
          json['nexusDataAsOfTime'],
    );

    if (nowQueuing == null && announcements.isEmpty && dataAsOfTime == null) {
      return null;
    }

    return UpNextEventContext(
      nowQueuing: nowQueuing,
      announcements: announcements,
      dataAsOfTime: dataAsOfTime,
    );
  }
}

const activeNexusQueueStatuses = {
  'Queuing soon',
  'Now queuing',
  'On deck',
  'On field',
};

bool isActiveQueueStatus(String? status) {
  if (status == null) return false;
  return activeNexusQueueStatuses.contains(status);
}

List<String> _parseAnnouncements(Object? value) {
  if (value is! List) return const [];
  return value
      .map((entry) {
        if (entry is String) return entry;
        if (entry is Map) {
          return entry['announcement']?.toString() ??
              entry['message']?.toString() ??
              entry['text']?.toString() ??
              '';
        }
        return entry?.toString() ?? '';
      })
      .where((message) => message.isNotEmpty)
      .toList();
}

List<String> _parseTeamList(Object? value) {
  if (value is! List) return const [];
  return value.map((team) => team.toString()).toList();
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

DateTime? _parseTimestamp(Object? value) {
  if (value == null) return null;
  if (value is num) {
    final ms = value.toInt();
    if (ms < 1e12) {
      return DateTime.fromMillisecondsSinceEpoch(ms * 1000);
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
