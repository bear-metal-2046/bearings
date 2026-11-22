import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:riverpod/riverpod.dart';
import 'package:services/providers/grove_provider.dart';

class PermissionKey {
  static const externalRead = competitionReadPermission;
  static const scoutsRead = 'scouting.scout.read';
  static const scoutsManage = 'scouting.scout.mutate';
  static const usersRead = 'identity.user.read';
  static const usersManage = 'identity.user.mutate';
  static const rolesRead = 'authorization.role.read';
  static const rolesManage = 'authorization.role.mutate';
  static const picklistsRead = 'strategy.picklist.read';
  static const picklistsManage = 'strategy.picklist.mutate';
  static const deviceProvision = deviceProvisionPermission;
}

class PermissionMetadata {
  const PermissionMetadata({
    required this.key,
    required this.name,
    required this.description,
    required this.group,
  });

  final String key;
  final String name;
  final String description;
  final String group;
}

const _permissionLabels = <String, (String, String, String)>{
  competitionReadPermission: (
    'Competition',
    'View competition data',
    'View event schedules, teams, rankings, match status, and pit maps.',
  ),
  gamePackReadPermission: (
    'GamePacks',
    'View published GamePacks',
    'Load the published forms and graphs assigned to an event.',
  ),
  gamePackPublishPermission: (
    'GamePacks',
    'Publish GamePacks',
    'Publish validated GamePacks and assign them to events.',
  ),
  gamePackObservationReadPermission: (
    'GamePacks',
    'View GamePack submissions',
    'Read collected observations and their calculated results.',
  ),
  gamePackSubmitPermission: (
    'GamePacks',
    'Submit GamePack observations',
    'Collect and upload match observations from assigned GamePack forms.',
  ),
  gamePackCorrectPermission: (
    'GamePacks',
    'Correct GamePack observations',
    'Append a correction or retraction to an existing observation.',
  ),
  'scouting.scout.read': (
    'Scouting',
    'View the scout roster',
    'See the scouts available for reports and assignments.',
  ),
  'scouting.scout.mutate': (
    'Scouting',
    'Manage the scout roster',
    'Add, update, or remove scouts from the roster.',
  ),
  'strategy.picklist.read': (
    'Picklists',
    'View shared picklists',
    'Browse event picklists shared with the team.',
  ),
  'strategy.picklist.mutate': (
    'Picklists',
    'Edit shared picklists',
    'Create, edit, or delete shared picklists.',
  ),
  PermissionKey.usersRead: (
    'Users & Roles',
    'View users',
    'View user profiles and their assigned roles.',
  ),
  PermissionKey.usersManage: (
    'Users & Roles',
    'Manage users',
    'Edit shared profiles and assign roles you can delegate.',
  ),
  PermissionKey.rolesRead: (
    'Users & Roles',
    'View roles',
    'See role names and their permissions.',
  ),
  PermissionKey.rolesManage: (
    'Users & Roles',
    'Manage roles',
    'Create, edit, and remove roles you can delegate.',
  ),
  deviceProvisionPermission: (
    'Device Setup',
    'Set up scouting devices',
    'Generate a provisioning QR code for Bearimetric.',
  ),
};

List<PermissionMetadata> permissionMetadataFor(EntityRegistry registry) {
  final keys = bearingsPermissions(registry).toSet();
  return [
    for (final MapEntry(key: key, value: (group, name, description))
        in _permissionLabels.entries)
      if (keys.remove(key))
        PermissionMetadata(
          key: key,
          name: name,
          description: description,
          group: group,
        ),
    for (final key in keys)
      PermissionMetadata(
        key: key,
        name: key,
        description: 'Permission details are unavailable.',
        group: 'Other',
      ),
  ];
}

class PermissionChecker {
  const PermissionChecker({required this.permissions});
  final Set<String> permissions;

  bool hasPermission(String permission) => permissions.contains(permission);
  bool hasAnyPermission(Iterable<String> values) => values.any(hasPermission);
  bool hasAllPermissions(Iterable<String> values) =>
      values.every(hasPermission);
  bool get canReadGamePackAnalysis => hasAllPermissions([
    gamePackReadPermission,
    gamePackObservationReadPermission,
  ]);
  bool get canOpenUsersAndRoles => hasAnyPermission([
    PermissionKey.usersRead,
    PermissionKey.rolesRead,
    PermissionKey.rolesManage,
  ]);
}

final groveAccessProvider = Provider<AsyncValue<QueryResult<GroveAccess>?>>((
  ref,
) {
  final subject = ref.watch(groveSubjectProvider);
  return subject.flatMap((id) {
    if (id == null) return const AsyncData(null);
    final grove = ref.watch(bearingsGroveProvider);
    return ref.watch(groveQueryProvider(grove.query<GroveAccess>().byId(id)));
  });
});

final permissionCheckerProvider = Provider<PermissionChecker?>((ref) {
  final result = ref.watch(groveAccessProvider).asData?.value;
  if (result == null || result.updateRequired || !result.hasSnapshot)
    return null;
  final access = result.items.singleOrNull;
  return access == null
      ? null
      : PermissionChecker(permissions: access.permissions);
});
