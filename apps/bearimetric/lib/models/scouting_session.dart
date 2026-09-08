import 'package:core/core.dart' show Scout, ScoutPosition, ScoutingEvent;

export 'package:core/core.dart'
    show MatchAlliance, Scout, ScoutPosition, ScoutingEvent, ScoutingMatch;

class ScoutingSession {
  final ScoutingEvent? event;
  final ScoutPosition? position;
  final Scout? scout;
  final int? matchNumber;
  final bool isTrainingMode;

  const ScoutingSession({
    this.event,
    this.position,
    this.scout,
    this.matchNumber,
    this.isTrainingMode = false,
  });

  bool get isConfigured =>
      event != null && position != null && scout != null && matchNumber != null;

  ScoutingSession copyWith({
    ScoutingEvent? event,
    ScoutPosition? position,
    Scout? scout,
    int? matchNumber,
    bool? isTrainingMode,
  }) {
    return ScoutingSession(
      event: event ?? this.event,
      position: position ?? this.position,
      scout: scout ?? this.scout,
      matchNumber: matchNumber ?? this.matchNumber,
      isTrainingMode: isTrainingMode ?? this.isTrainingMode,
    );
  }
}
