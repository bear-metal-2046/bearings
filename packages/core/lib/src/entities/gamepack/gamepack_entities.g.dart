// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gamepack_entities.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _GamePackDraftToGroveJson(GamePackDraft value) => {
  "id": value.id,
  "name": value.name,
  "documentJson": value.documentJson,
  "updatedAt": value.updatedAt.toUtc().toIso8601String(),
};
GamePackDraft _GamePackDraftFromGroveJson(Json json) => GamePackDraft(
  id: json["id"] as String,
  name: json["name"] as String,
  documentJson: json["documentJson"] as String,
  updatedAt: DateTime.parse(json["updatedAt"] as String),
);

final gamePackDraftEntity = EntityDescriptor<GamePackDraft>(
  type: "gamepack.draft",
  version: 1,
  offlineMutable: false,

  encode: _GamePackDraftToGroveJson,
  decode: _GamePackDraftFromGroveJson,
);

abstract final class GamePackDraftFields {
  static const id = EntityField<GamePackDraft, String>("id");
  static const name = EntityField<GamePackDraft, String>("name");
  static const documentJson = EntityField<GamePackDraft, String>(
    "documentJson",
  );
}

Json _GamePackReleaseToGroveJson(GamePackRelease value) => {
  "id": value.id,
  "document": value.document.map((key, item) => MapEntry(key, item)),
};
GamePackRelease _GamePackReleaseFromGroveJson(Json json) => GamePackRelease(
  id: json["id"] as String,
  document: (json["document"] as Map).map(
    (key, item) => MapEntry(key as String, item),
  ),
);

final gamePackReleaseEntity = EntityDescriptor<GamePackRelease>(
  type: "gamepack.release",
  version: 1,
  offlineMutable: false,

  encode: _GamePackReleaseToGroveJson,
  decode: _GamePackReleaseFromGroveJson,
);

abstract final class GamePackReleaseFields {
  static const id = EntityField<GamePackRelease, String>("id");
}

Json _EventGamePackToGroveJson(EventGamePack value) => {
  "id": value.id,
  "release": value.release.id,
  "analysisRelease": value.analysisRelease == null
      ? null
      : value.analysisRelease!.id,
};
EventGamePack _EventGamePackFromGroveJson(Json json) => EventGamePack(
  id: json["id"] as String,
  release: EntityRef<GamePackRelease>(json["release"] as String),
  analysisRelease: json["analysisRelease"] == null
      ? null
      : EntityRef<GamePackRelease>(json["analysisRelease"] as String),
);

final eventGamePackEntity = EntityDescriptor<EventGamePack>(
  type: "gamepack.binding",
  version: 1,
  offlineMutable: false,

  encode: _EventGamePackToGroveJson,
  decode: _EventGamePackFromGroveJson,
);

abstract final class EventGamePackFields {
  static const id = EntityField<EventGamePack, String>("id");
  static const release = EntityField<EventGamePack, EntityRef<GamePackRelease>>(
    "release",
  );
  static const analysisRelease =
      EntityField<EventGamePack, EntityRef<GamePackRelease>?>(
        "analysisRelease",
      );
}

Json _GamePackObservationToGroveJson(GamePackObservation value) => {
  "id": value.id,
  "event": value.event.id,
  "match": value.match == null ? null : value.match!.id,
  "team": value.team == null ? null : value.team!.id,
  "release": value.release.id,
  "station": value.station,
  "capturedAt": value.capturedAt.toUtc().toIso8601String(),
  "answers": value.answers.map((key, item) => MapEntry(key, item)),
  "author": value.author,
  "form": value.form,
  "scout": value.scout == null ? null : value.scout!.id,
  "supersedes": value.supersedes == null ? null : value.supersedes!.id,
  "retracted": value.retracted,
  "reason": value.reason,
};
GamePackObservation _GamePackObservationFromGroveJson(Json json) =>
    GamePackObservation(
      id: json["id"] as String,
      event: EntityRef<CompetitionEvent>(json["event"] as String),
      match: json["match"] == null
          ? null
          : EntityRef<CompetitionMatch>(json["match"] as String),
      team: json["team"] == null
          ? null
          : EntityRef<CompetitionTeam>(json["team"] as String),
      release: EntityRef<GamePackRelease>(json["release"] as String),
      station: json["station"] as int?,
      capturedAt: DateTime.parse(json["capturedAt"] as String),
      answers: (json["answers"] as Map).map(
        (key, item) => MapEntry(key as String, item),
      ),
      author: json["author"] as String?,
      form: json["form"] as String?,
      scout: json["scout"] == null
          ? null
          : EntityRef<Scout>(json["scout"] as String),
      supersedes: json["supersedes"] == null
          ? null
          : EntityRef<GamePackObservation>(json["supersedes"] as String),
      retracted: json["retracted"] as bool?,
      reason: json["reason"] as String?,
    );

final gamePackObservationEntity = EntityDescriptor<GamePackObservation>(
  type: "scouting.observation",
  version: 2,
  offlineMutable: true,

  encode: _GamePackObservationToGroveJson,
  decode: _GamePackObservationFromGroveJson,
  migrations: GamePackObservation.groveMigrations,
  fieldVersions: GamePackObservation.groveFieldVersions,
);

abstract final class GamePackObservationFields {
  static const id = EntityField<GamePackObservation, String>("id");
  static const event =
      EntityField<GamePackObservation, EntityRef<CompetitionEvent>>("event");
  static const match =
      EntityField<GamePackObservation, EntityRef<CompetitionMatch>?>("match");
  static const team =
      EntityField<GamePackObservation, EntityRef<CompetitionTeam>?>("team");
  static const release =
      EntityField<GamePackObservation, EntityRef<GamePackRelease>>("release");
  static const station = EntityField<GamePackObservation, int?>("station");
  static const author = EntityField<GamePackObservation, String?>("author");
  static const form = EntityField<GamePackObservation, String?>("form");
  static const scout = EntityField<GamePackObservation, EntityRef<Scout>?>(
    "scout",
  );
  static const supersedes =
      EntityField<GamePackObservation, EntityRef<GamePackObservation>?>(
        "supersedes",
      );
  static const retracted = EntityField<GamePackObservation, bool?>("retracted");
  static const reason = EntityField<GamePackObservation, String?>("reason");
}

Json _TbaMatchRevisionToGroveJson(TbaMatchRevision value) => {
  "id": value.id,
  "event": value.event.id,
  "match": value.match.id,
  "observedAt": value.observedAt.toUtc().toIso8601String(),
  "sequence": value.sequence,
  "payload": value.payload.map((key, item) => MapEntry(key, item)),
};
TbaMatchRevision _TbaMatchRevisionFromGroveJson(Json json) => TbaMatchRevision(
  id: json["id"] as String,
  event: EntityRef<CompetitionEvent>(json["event"] as String),
  match: EntityRef<CompetitionMatch>(json["match"] as String),
  observedAt: DateTime.parse(json["observedAt"] as String),
  sequence: json["sequence"] as int,
  payload: (json["payload"] as Map).map(
    (key, item) => MapEntry(key as String, item),
  ),
);

final tbaMatchRevisionEntity = EntityDescriptor<TbaMatchRevision>(
  type: "tba_match_revision",
  version: 1,
  offlineMutable: false,
  serverManaged: true,
  encode: _TbaMatchRevisionToGroveJson,
  decode: _TbaMatchRevisionFromGroveJson,
);

abstract final class TbaMatchRevisionFields {
  static const id = EntityField<TbaMatchRevision, String>("id");
  static const event =
      EntityField<TbaMatchRevision, EntityRef<CompetitionEvent>>("event");
  static const match =
      EntityField<TbaMatchRevision, EntityRef<CompetitionMatch>>("match");
  static const sequence = EntityField<TbaMatchRevision, int>("sequence");
}
