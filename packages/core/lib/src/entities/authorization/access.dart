import 'package:grove/grove.dart';

part 'access.g.dart';

/// The effective permissions for the current authenticated subject. Honeycomb
/// computes this read-only projection from its user and role records.
@GroveEntity('authorization.access', version: 1)
class GroveAccess {
  GroveAccess(this.id, Iterable<String> permissions)
    : permissions = Set.unmodifiable(permissions);
  final String id;
  final Set<String> permissions;
  Json toJson() => _GroveAccessToGroveJson(this);
  factory GroveAccess.fromJson(Json json) => _GroveAccessFromGroveJson(json);
}
