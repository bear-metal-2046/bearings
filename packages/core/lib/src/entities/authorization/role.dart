import 'package:grove/grove.dart';

part 'role.g.dart';

@GroveEntity('authorization.role', version: 1)
class GroveRole {
  GroveRole({
    required this.id,
    required this.name,
    this.description,
    required Iterable<String> permissions,
  }) : permissions = List.unmodifiable(permissions) {
    if (id.isEmpty || name.trim().isEmpty)
      throw ArgumentError('Role ID and name required');
  }
  final String id;
  final String name;
  final String? description;
  final List<String> permissions;
  GroveRole copyWith({
    String? name,
    String? description,
    List<String>? permissions,
  }) => GroveRole(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    permissions: permissions ?? this.permissions,
  );
  Json toJson() => _GroveRoleToGroveJson(this);
  factory GroveRole.fromJson(Json json) => _GroveRoleFromGroveJson(json);
}
