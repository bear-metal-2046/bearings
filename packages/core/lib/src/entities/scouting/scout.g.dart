// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scout.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _ScoutToGroveJson(Scout value) => {"name": value.name, "id": value.uuid};
Scout _ScoutFromGroveJson(Json json) =>
    Scout(name: json["name"] as String, uuid: json["id"] as String);

final scoutEntity = EntityDescriptor<Scout>(
  type: "scouting.scout",
  version: 1,
  offlineMutable: false,

  encode: _ScoutToGroveJson,
  decode: _ScoutFromGroveJson,
);

abstract final class ScoutFields {
  static const name = EntityField<Scout, String>("name");
  static const uuid = EntityField<Scout, String>("id");
}
