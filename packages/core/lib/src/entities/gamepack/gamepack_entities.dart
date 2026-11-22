import 'dart:convert';

import 'package:gamepack/gamepack.dart';
import 'package:grove/grove.dart';

import '../competition/competition_entities.dart';
import '../scouting/scout.dart';

part 'gamepack_entities.g.dart';

const gamePackReadPermission = 'gamepack.read';
const gamePackPublishPermission = 'gamepack.publish';
const gamePackObservationReadPermission = 'scouting.observation.read';
const gamePackSubmitPermission = 'scouting.observation.submit';
const gamePackCorrectPermission = 'scouting.observation.correct';

/// In-progress editor data may contain incomplete forms or graphs.
@GroveEntity('gamepack.draft', version: 1)
class GamePackDraft {
  GamePackDraft({
    required this.id,
    required this.name,
    required this.documentJson,
    required this.updatedAt,
  }) {
    validateGamePackLabel(name);
    if (documentJson.length > 1024 * 1024 ||
        jsonDecode(documentJson) is! Json) {
      throw const FormatException(
        'A draft must be a JSON document up to 1 MB.',
      );
    }
  }

  final String id;
  final String name;

  /// Treat the collaborative editor document as an atomic value.
  final String documentJson;
  final DateTime updatedAt;

  Json get document => jsonDecode(documentJson) as Json;
}

@GroveEntity('gamepack.release', version: 1)
class GamePackRelease {
  GamePackRelease({required String id, required Json document})
    : this._(id, GamePackDefinition.fromJson(document));

  GamePackRelease._(this.id, this.definition)
    : document = _freeze(definition.toJson()) as Json;

  final String id;
  final GamePackDefinition definition;
  final Json document;
}

@GroveEntity('gamepack.binding', version: 1)
class EventGamePack {
  const EventGamePack({
    required this.id,
    required this.release,
    this.analysisRelease,
  });

  /// The competition event key. An event can have one collection release.
  final String id;
  final EntityRef<GamePackRelease> release;
  final EntityRef<GamePackRelease>? analysisRelease;

  EntityRef<GamePackRelease> get effectiveAnalysisRelease =>
      analysisRelease ?? release;
}

@GroveEntity('scouting.observation', version: 2, offlineMutable: true)
class GamePackObservation {
  GamePackObservation({
    required this.id,
    required this.event,
    this.match,
    this.team,
    required this.release,
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
  final EntityRef<GamePackRelease> release;
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
  };

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
      release.id == other.release.id &&
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
  Json map => Map<String, dynamic>.unmodifiable(
    map.map((key, item) => MapEntry(key, _freeze(item))),
  ),
  List<dynamic> list => List.unmodifiable(list.map(_freeze)),
  _ => value,
};
