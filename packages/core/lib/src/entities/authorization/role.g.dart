// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _GroveRoleToGroveJson(GroveRole value) => {
  "id": value.id,
  "name": value.name,
  "description": value.description,
  "permissions": value.permissions.map((item) => item).toList(),
};
GroveRole _GroveRoleFromGroveJson(Json json) => GroveRole(
  id: json["id"] as String,
  name: json["name"] as String,
  description: json["description"] as String?,
  permissions: (json["permissions"] as List)
      .map((item) => item as String)
      .toList(),
);

final groveRoleEntity = EntityDescriptor<GroveRole>(
  type: "authorization.role",
  version: 1,
  offlineMutable: false,

  encode: _GroveRoleToGroveJson,
  decode: _GroveRoleFromGroveJson,
);

abstract final class GroveRoleFields {
  static const id = EntityField<GroveRole, String>("id");
  static const name = EntityField<GroveRole, String>("name");
  static const description = EntityField<GroveRole, String?>("description");
}
