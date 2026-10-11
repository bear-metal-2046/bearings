import '../utils/nexus_match_key.dart';
import 'scouting_domain.dart';

/// Nexus timing estimates for a match. Every field can be missing.
class NexusMatchTimes {
  const NexusMatchTimes({
    this.scheduledStartTime,
    this.estimatedQueueTime,
    this.estimatedOnDeckTime,
    this.estimatedOnFieldTime,
    this.estimatedStartTime,
    this.actualQueueTime,
    this.actualOnDeckTime,
    this.actualOnFieldTime,
  });

  final DateTime? scheduledStartTime;
  final DateTime? estimatedQueueTime;
  final DateTime? estimatedOnDeckTime;
  final DateTime? estimatedOnFieldTime;
  final DateTime? estimatedStartTime;
  final DateTime? actualQueueTime;
  final DateTime? actualOnDeckTime;
  final DateTime? actualOnFieldTime;

  factory NexusMatchTimes.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const NexusMatchTimes();
    return NexusMatchTimes(
      scheduledStartTime: _asTimestamp(json['scheduledStartTime']),
      estimatedQueueTime: _asTimestamp(json['estimatedQueueTime']),
      estimatedOnDeckTime: _asTimestamp(json['estimatedOnDeckTime']),
      estimatedOnFieldTime: _asTimestamp(json['estimatedOnFieldTime']),
      estimatedStartTime: _asTimestamp(json['estimatedStartTime']),
      actualQueueTime: _asTimestamp(json['actualQueueTime']),
      actualOnDeckTime: _asTimestamp(json['actualOnDeckTime']),
      actualOnFieldTime: _asTimestamp(json['actualOnFieldTime']),
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
    };
  }
}

/// A single Nexus match. Team lists are in station order; a null entry is an
/// empty station and a null list is an undecided playoff alliance.
class NexusMatch {
  const NexusMatch({
    required this.label,
    this.status,
    this.redTeams,
    this.blueTeams,
    this.times = const NexusMatchTimes(),
    this.replayOf,
    this.breakAfter,
  });

  final String label;
  final String? status;
  final List<String?>? redTeams;
  final List<String?>? blueTeams;
  final NexusMatchTimes times;
  final String? replayOf;
  final String? breakAfter;

  factory NexusMatch.fromJson(Map<String, dynamic> json) {
    final label = _asString(json['label']);
    if (label == null) {
      throw const FormatException('match is missing a label');
    }

    return NexusMatch(
      label: label,
      status: _asString(json['status']),
      redTeams: _asTeams(json['redTeams']),
      blueTeams: _asTeams(json['blueTeams']),
      times: NexusMatchTimes.fromJson(_asStringMap(json['times'])),
      replayOf: _asString(json['replayOf']),
      breakAfter: _asString(json['breakAfter']),
    );
  }

  NexusMatchRef? get ref => parseNexusMatchLabel(label);

  bool get isPractice => ref?.isPractice ?? false;

  String? matchKey(String eventKey) {
    final parsed = ref;
    if (parsed == null) return null;
    return matchKeyForNexusRef(eventKey, parsed);
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'status': status,
      'redTeams': redTeams?.whereType<String>().toList(growable: false),
      'blueTeams': blueTeams?.whereType<String>().toList(growable: false),
      'times': times.toJson(),
      'replayOf': replayOf,
      'breakAfter': breakAfter,
    };
  }

  /// Maps this match onto [ScoutingMatch] so the existing match helpers and
  /// match preview can use it. Returns null when there is no TBA match key.
  ScoutingMatch? toScoutingMatch(String eventKey) {
    final parsed = ref;
    if (parsed == null) return null;
    final key = matchKeyForNexusRef(eventKey, parsed);
    if (key == null) return null;

    final start = times.estimatedStartTime ?? times.scheduledStartTime;

    return ScoutingMatch(
      key: key,
      compLevel: parsed.compLevel,
      matchNumber: parsed.matchNumber,
      setNumber: parsed.setNumber,
      eventKey: eventKey,
      redAlliance: MatchAlliance(teamKeys: _teamKeys(redTeams)),
      blueAlliance: MatchAlliance(teamKeys: _teamKeys(blueTeams)),
      predictedTime: start == null
          ? null
          : start.millisecondsSinceEpoch ~/ 1000,
      nexus: toJson(),
    );
  }
}

/// The Nexus part of Honeycomb's `GET /events?event=...&enrich=true` response.
class NexusEventStatus {
  const NexusEventStatus({
    this.dataAsOfTime,
    this.nowQueuing,
    this.announcements = const [],
    this.matches = const [],
    this.parseWarnings = const [],
  });

  final DateTime? dataAsOfTime;
  final String? nowQueuing;
  final List<String> announcements;
  final List<NexusMatch> matches;

  /// Fields or matches that were skipped because they had an unexpected shape.
  final List<String> parseWarnings;

  bool get hasData =>
      matches.isNotEmpty || nowQueuing != null || announcements.isNotEmpty;

  /// Parses one Honeycomb event. Each field and match is read on its own so a
  /// single bad value cannot drop the whole snapshot.
  factory NexusEventStatus.fromHoneycombEvent(Map<String, dynamic> json) {
    final warnings = <String>[];
    final source = _asStringMap(json['nexus']) ?? json;

    final matches = <NexusMatch>[];
    final rawMatches = source['matches'];
    if (rawMatches is List) {
      for (final (index, raw) in rawMatches.indexed) {
        final map = _asStringMap(raw);
        if (map == null) {
          warnings.add('matches[$index] is not an object');
          continue;
        }
        try {
          matches.add(NexusMatch.fromJson(map));
        } catch (error) {
          warnings.add('matches[$index] skipped: $error');
        }
      }
    } else if (rawMatches != null) {
      warnings.add('matches is not a list');
    }

    final announcements = <String>[];
    final rawAnnouncements = source['announcements'];
    if (rawAnnouncements is List) {
      for (final (index, raw) in rawAnnouncements.indexed) {
        final text = raw is Map
            ? _asString(raw['announcement'])
            : _asString(raw);
        if (text == null) {
          warnings.add('announcements[$index] has no text');
          continue;
        }
        announcements.add(text);
      }
    } else if (rawAnnouncements != null) {
      warnings.add('announcements is not a list');
    }

    final rawNowQueuing = source['nowQueuing'];
    final nowQueuing = _asString(rawNowQueuing);
    if (rawNowQueuing != null && rawNowQueuing is! String) {
      warnings.add('nowQueuing is not a string');
    }

    return NexusEventStatus(
      dataAsOfTime: _asTimestamp(
        source['nexusDataAsOfTime'] ?? source['dataAsOfTime'],
      ),
      nowQueuing: nowQueuing,
      announcements: List.unmodifiable(announcements),
      matches: List.unmodifiable(matches),
      parseWarnings: List.unmodifiable(warnings),
    );
  }
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
