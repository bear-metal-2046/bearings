// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'picklist.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _GrovePicklistToGroveJson(GrovePicklist value) => {
  "id": value.id,
  "eventKey": value.eventKey,
  "title": value.title,
  "emoji": value.emoji,
  "createdAt": value.createdAt.toUtc().toIso8601String(),
  "updatedAt": value.updatedAt.toUtc().toIso8601String(),
  "teamChanges": value.teamChanges.map((key, item) => MapEntry(key, item)),
};
GrovePicklist _GrovePicklistFromGroveJson(Json json) => GrovePicklist(
  id: json["id"] as String,
  eventKey: json["eventKey"] as String,
  title: json["title"] as String,
  emoji: json["emoji"] as String,
  createdAt: DateTime.parse(json["createdAt"] as String),
  updatedAt: DateTime.parse(json["updatedAt"] as String),
  teamChanges: (json["teamChanges"] as Map).map(
    (key, item) => MapEntry(key as String, item as String),
  ),
);

final grovePicklistEntity = EntityDescriptor<GrovePicklist>(
  type: "strategy.picklist",
  version: 1,
  offlineMutable: false,

  encode: _GrovePicklistToGroveJson,
  decode: _GrovePicklistFromGroveJson,
);

abstract final class GrovePicklistFields {
  static const id = EntityField<GrovePicklist, String>("id");
  static const eventKey = EntityField<GrovePicklist, String>("eventKey");
  static const title = EntityField<GrovePicklist, String>("title");
  static const emoji = EntityField<GrovePicklist, String>("emoji");
}
