// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gamepack_entities.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _GamePackToGroveJson(GamePack value) => {
  "id": value.id,
  "document": value.document,
};
GamePack _GamePackFromGroveJson(Json json) =>
    GamePack(id: json["id"] as String, document: json["document"]);

final gamePackEntity = EntityDescriptor<GamePack>(
  type: "gamepack",
  version: 1,
  offlineMutable: false,

  encode: _GamePackToGroveJson,
  decode: _GamePackFromGroveJson,
);

abstract final class GamePackFields {
  static const id = EntityField<GamePack, String>("id");
}

Json _EventGamePackToGroveJson(EventGamePack value) => {
  "id": value.id,
  "gamePack": value.gamePack == null ? null : value.gamePack!.id,
};
EventGamePack _EventGamePackFromGroveJson(Json json) => EventGamePack(
  id: json["id"] as String,
  gamePack: json["gamePack"] == null
      ? null
      : EntityRef<GamePack>(json["gamePack"] as String),
);

final eventGamePackEntity = EntityDescriptor<EventGamePack>(
  type: "gamepack.binding",
  version: 2,
  offlineMutable: false,

  encode: _EventGamePackToGroveJson,
  decode: _EventGamePackFromGroveJson,

  fieldVersions: EventGamePack.groveFieldVersions,
);

abstract final class EventGamePackFields {
  static const id = EntityField<EventGamePack, String>("id");
  static const gamePack = EntityField<EventGamePack, EntityRef<GamePack>?>(
    "gamePack",
  );
}

Json _GamePackObservationToGroveJson(GamePackObservation value) => {
  "id": value.id,
  "event": value.event.id,
  "match": value.match == null ? null : value.match!.id,
  "team": value.team == null ? null : value.team!.id,
  "gamePack": value.gamePack.id,
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
      gamePack: EntityRef<GamePack>(json["gamePack"] as String),
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
  version: 3,
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
  static const gamePack = EntityField<GamePackObservation, EntityRef<GamePack>>(
    "gamePack",
  );
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
