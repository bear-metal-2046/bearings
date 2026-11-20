import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:riverpod/riverpod.dart';
import 'package:services/providers/grove_provider.dart';

class RbacManagementService {
  const RbacManagementService(this.grove);
  final Grove grove;

  Future<GroveRole> createRole({
    required String id,
    required String name,
    String? description,
    required List<String> permissions,
  }) => grove.create(
    GroveRole(
      id: id,
      name: name,
      description: description,
      permissions: permissions,
    ),
  );
  Future<GroveRole> updateRole({
    required String id,
    String? name,
    String? description,
    List<String>? permissions,
    GroveRole? basedOn,
  }) => grove.update<GroveRole>(
    id,
    (role) => role.copyWith(
      name: name,
      description: description,
      permissions: permissions,
    ),
    basedOn: basedOn,
  );
  Future<void> deleteRole(String id) => grove.delete<GroveRole>(id);
  Future<void> updateUserRoles({
    required String userId,
    String? name,
    List<String>? roles,
  }) async {
    await grove.update<GroveUser>(
      userId,
      (user) => user.copyWith(
        name: name,
        roles: roles?.map(EntityRef<GroveRole>.new).toList(),
      ),
    );
  }
}

final rbacManagementServiceProvider = Provider<RbacManagementService>(
  (ref) => RbacManagementService(ref.watch(bearingsGroveProvider)),
);
