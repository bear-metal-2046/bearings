import 'package:core/core.dart' show CompetitionEvent, Scout, ScoutPosition;

export 'package:core/core.dart' show Scout, ScoutPosition;

/// Local-only event key used to isolate practice records from real events.
const trainingEventKey = 'training';

/// The selected event is kept in preferences for offline startup.
class ScoutingEventSelection {
  const ScoutingEventSelection({
    required this.key,
    required this.name,
    required this.year,
  });

  factory ScoutingEventSelection.fromCompetition(CompetitionEvent event) =>
      ScoutingEventSelection(
        key: event.id,
        name: event.name,
        year: event.season,
      );

  factory ScoutingEventSelection.fromJson(Map<String, dynamic> json) {
    final year = json['year'];
    return ScoutingEventSelection(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      year: year is num ? year.toInt() : int.tryParse('$year') ?? 0,
    );
  }

  final String key;
  final String name;
  final int year;

  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'year': year};
}

class ScoutingSession {
  final ScoutingEventSelection? event;
  final ScoutPosition? position;
  final Scout? scout;
  final int? matchNumber;

  const ScoutingSession({
    this.event,
    this.position,
    this.scout,
    this.matchNumber,
  });

  bool get isConfigured =>
      event != null && position != null && scout != null && matchNumber != null;

  ScoutingSession copyWith({
    ScoutingEventSelection? event,
    ScoutPosition? position,
    Scout? scout,
    int? matchNumber,
  }) {
    return ScoutingSession(
      event: event ?? this.event,
      position: position ?? this.position,
      scout: scout ?? this.scout,
      matchNumber: matchNumber ?? this.matchNumber,
    );
  }
}
