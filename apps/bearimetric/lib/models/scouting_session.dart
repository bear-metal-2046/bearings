import 'package:core/core.dart' show Scout, ScoutPosition, ScoutingEvent;

export 'package:core/core.dart'
    show MatchAlliance, Scout, ScoutPosition, ScoutingEvent, ScoutingMatch;

class ScoutingSession {
  final ScoutingEvent? event;
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
    ScoutingEvent? event,
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
