// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _GroveUserToGroveJson(GroveUser value) => {
  "id": value.id,
  "name": value.name,
  "avatarUrl": value.avatarUrl,
  "email": value.email,
  "emailVerified": value.emailVerified,
  "roles": value.roles.map((item) => item.id).toList(),
};
GroveUser _GroveUserFromGroveJson(Json json) => GroveUser(
  id: json["id"] as String,
  name: json["name"] as String?,
  avatarUrl: json["avatarUrl"] as String?,
  email: json["email"] as String?,
  emailVerified: json["emailVerified"] as bool?,
  roles: (json["roles"] as List)
      .map((item) => EntityRef<GroveRole>(item as String))
      .toList(),
);

final groveUserEntity = EntityDescriptor<GroveUser>(
  type: "identity.user",
  version: 1,
  offlineMutable: false,

  encode: _GroveUserToGroveJson,
  decode: _GroveUserFromGroveJson,
);

abstract final class GroveUserFields {
  static const id = EntityField<GroveUser, String>("id");
  static const name = EntityField<GroveUser, String?>("name");
  static const avatarUrl = EntityField<GroveUser, String?>("avatarUrl");
  static const email = EntityField<GroveUser, String?>("email");
  static const emailVerified = EntityField<GroveUser, bool?>("emailVerified");
}
