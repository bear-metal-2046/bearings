import 'package:grove/grove.dart';

import '../authorization/role.dart';

part 'user.g.dart';

@GroveEntity('identity.user', version: 1)
class GroveUser {
  GroveUser({
    required this.id,
    this.name,
    this.avatarUrl,
    this.email,
    this.emailVerified,
    Iterable<EntityRef<GroveRole>> roles = const [],
  }) : roles = List.unmodifiable(roles) {
    if (id.isEmpty) throw ArgumentError('User ID required');
  }
  final String id;
  final String? name;
  final String? avatarUrl;
  final String? email;
  final bool? emailVerified;
  final List<EntityRef<GroveRole>> roles;
  GroveUser copyWith({
    String? name,
    String? avatarUrl,
    String? email,
    bool? emailVerified,
    List<EntityRef<GroveRole>>? roles,
  }) => GroveUser(
    id: id,
    name: name ?? this.name,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    email: email ?? this.email,
    emailVerified: emailVerified ?? this.emailVerified,
    roles: roles ?? this.roles,
  );
  Json toJson() => _GroveUserToGroveJson(this);
  factory GroveUser.fromJson(Json json) => _GroveUserFromGroveJson(json);
}
