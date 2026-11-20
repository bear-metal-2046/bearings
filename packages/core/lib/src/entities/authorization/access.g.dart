// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'access.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _GroveAccessToGroveJson(GroveAccess value) => {
  "id": value.id,
  "permissions": (value.permissions.toList()..sort()),
};
GroveAccess _GroveAccessFromGroveJson(Json json) => GroveAccess(
  json["id"] as String,
  (json["permissions"] as List).cast<String>().toSet(),
);

final groveAccessEntity = EntityDescriptor<GroveAccess>(
  type: "authorization.access",
  version: 1,
  offlineMutable: false,

  encode: _GroveAccessToGroveJson,
  decode: _GroveAccessFromGroveJson,
);

abstract final class GroveAccessFields {
  static const id = EntityField<GroveAccess, String>("id");
}
