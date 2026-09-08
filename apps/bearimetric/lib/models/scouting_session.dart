import 'package:core/core.dart' show Scout, ScoutPosition, ScoutingEvent;

export 'package:core/core.dart'
    show MatchAlliance, Scout, ScoutPosition, ScoutingEvent, ScoutingMatch;

/// Local-only event key used to isolate practice records from real events.
const trainingEventKey = 'training';

class ScoutingSession {
  final ScoutingEvent? event;
  final ScoutingEvent? scheduleEvent;
  final ScoutPosition? position;
  final Scout? scout;
  final int? matchNumber;
  final bool isTrainingMode;

  const ScoutingSession({
    this.event,
    this.scheduleEvent,
    this.position,
    this.scout,
    this.matchNumber,
    this.isTrainingMode = false,
  });

  bool get isConfigured =>
      event != null && position != null && scout != null && matchNumber != null;

  /// The real event used for schedules and team assignments.
  ScoutingEvent? get dataSourceEvent =>
      isTrainingMode ? scheduleEvent : event;

  ScoutingSession copyWith({
    ScoutingEvent? event,
    ScoutingEvent? scheduleEvent,
    ScoutPosition? position,
    Scout? scout,
    int? matchNumber,
    bool? isTrainingMode,
  }) {
    return ScoutingSession(
      event: event ?? this.event,
      scheduleEvent: scheduleEvent ?? this.scheduleEvent,
      position: position ?? this.position,
      scout: scout ?? this.scout,
      matchNumber: matchNumber ?? this.matchNumber,
      isTrainingMode: isTrainingMode ?? this.isTrainingMode,
    );
  }
}
