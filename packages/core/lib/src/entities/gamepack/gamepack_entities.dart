import 'package:gamepack/gamepack.dart';
import 'package:grove/grove.dart';

import '../competition/competition_entities.dart';
import '../scouting/scout.dart';

part 'gamepack_entities.g.dart';

/// Reserved assignment key for Bearimetric's local-only practice mode.
const practiceGamePackKey = 'training';

const gamePackReadPermission = 'gamepack.read';
const gamePackManagePermission = 'gamepack.manage';
@Deprecated('Use gamePackManagePermission.')
const gamePackPublishPermission = gamePackManagePermission;
const gamePackObservationReadPermission = 'scouting.observation.read';
const gamePackSubmitPermission = 'scouting.observation.submit';
const gamePackCorrectPermission = 'scouting.observation.correct';

/// A library gamepack. Its document stays raw until a caller needs to use it,
/// so one unsupported or damaged document cannot prevent the library loading.
@GroveEntity('gamepack', version: 1)
class GamePack {
  GamePack({required this.id, required dynamic document})
    : document = _freeze(document);

  final String id;
  final dynamic document;

  String get name => document is Map && document['name'] is String
      ? document['name'] as String
      : 'Unnamed GamePack';

  GamePackDefinition get definition => GamePackDefinition.fromJson(document);
}

/// Source compatibility for callers that used the former release name.
@Deprecated('Use GamePack.')
typedef GamePackRelease = GamePack;

@GroveEntity('gamepack.binding', version: 3)
class EventGamePack {
  const EventGamePack({
    required this.id,
    required this.gamePack,
    this.practiceEvent,
  });

  /// The competition event key or [practiceGamePackKey].
  final String id;

  /// Null means the event has no GamePack assigned.
  final EntityRef<GamePack>? gamePack;

  /// Schedule source for the reserved practice assignment.
  final EntityRef<CompetitionEvent>? practiceEvent;

  static const groveMigrations = <int, Json Function(Json)>{
    2: _addPracticeEvent,
  };
  static const groveFieldVersions = {'gamePack': 2, 'practiceEvent': 3};

  static Json _addPracticeEvent(Json data) => {...data, 'practiceEvent': null};
}

@GroveEntity('scouting.observation', version: 3, offlineMutable: true)
class GamePackObservation {
  GamePackObservation({
    required this.id,
    required this.event,
    this.match,
    this.team,
    required this.gamePack,
    this.station,
    required this.capturedAt,
    required Json answers,
    this.author,
    this.form,
    this.scout,
    this.supersedes,
    this.retracted,
    this.reason,
  }) : answers = _freeze(answers) as Json;

  final String id;
  final EntityRef<CompetitionEvent> event;
  final EntityRef<CompetitionMatch>? match;
  final EntityRef<CompetitionTeam>? team;
  final EntityRef<GamePack> gamePack;
  final int? station;
  final DateTime capturedAt;
  final Json answers;
  final String? author;
  final String? form;
  final EntityRef<Scout>? scout;
  final EntityRef<GamePackObservation>? supersedes;
  final bool? retracted;
  final String? reason;

  String get formId => form ?? 'match';
  bool get isRetraction => retracted == true;

  static const groveFieldVersions = {
    'form': 2,
    'scout': 2,
    'supersedes': 2,
    'retracted': 2,
    'reason': 2,
    'gamePack': 3,
  };

  // Observation records predate the single-library GamePack shape. The server
  // cutover intentionally rejects those queued payloads instead of migrating
  // them into the new data model.
  static final groveMigrations = <int, Json Function(Json)>{
    1: (data) => {...data, 'form': 'match'},
  };

  CompetitionAlliance? allianceFor(CompetitionMatch match) => switch (station) {
    0 || 1 || 2 || 6 => match.red,
    3 || 4 || 5 || 7 => match.blue,
    _ => null,
  };

  bool hasSameSubject(GamePackObservation other) =>
      event.id == other.event.id &&
      match?.id == other.match?.id &&
      team?.id == other.team?.id &&
      station == other.station &&
      gamePack.id == other.gamePack.id &&
      formId == other.formId;
}

/// Resolve the current heads while retaining the original immutable rows
/// for audit and provenance. Pass the complete history for the selected event.
Iterable<GamePackObservation> activeGamePackObservations(
  Iterable<GamePackObservation> history,
) {
  final superseded = {
    for (final record in history)
      if (record.supersedes case final previous?) previous.id,
  };
  return history.where(
    (record) => !record.isRetraction && !superseded.contains(record.id),
  );
}

/// One immutable snapshot of the TBA payload used for match interpretation.
@GroveEntity('tba_match_revision', version: 1, serverManaged: true)
class TbaMatchRevision {
  TbaMatchRevision({
    required this.id,
    required this.event,
    required this.match,
    required this.observedAt,
    required this.sequence,
    required Json payload,
  }) : payload = _freeze(payload) as Json;

  final String id;
  final EntityRef<CompetitionEvent> event;
  final EntityRef<CompetitionMatch> match;
  final DateTime observedAt;
  final int sequence;
  final Json payload;
}

Object? _freeze(Object? value) => switch (value) {
  Map map => Map<String, dynamic>.unmodifiable(
    map.map((key, item) => MapEntry(key as String, _freeze(item))),
  ),
  List<dynamic> list => List.unmodifiable(list.map(_freeze)),
  _ => value,
};
