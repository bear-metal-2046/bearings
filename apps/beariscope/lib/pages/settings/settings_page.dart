import 'package:beariscope/widgets/settings_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:services/providers/permissions_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final permissionChecker = ref.watch(permissionCheckerProvider);
    final canViewScouts =
        permissionChecker?.hasAnyPermission([PermissionKey.scoutsRead]) ??
        false;
    final canEditScouts =
        permissionChecker?.hasPermission(PermissionKey.scoutsManage) ?? false;
    final canManageUsersRoles =
        permissionChecker?.hasPermission(PermissionKey.usersRolesManage) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          SettingsGroup(
            title: 'General',
            children: [
              ListTile(
                leading: const Icon(Symbols.person_rounded),
                title: const Text('Account'),
                subtitle: const Text('Your Profile, Picture, Details'),
                onTap: () => context.push('/settings/account'),
              ),
              ListTile(
                leading: const Icon(Symbols.palette_rounded),
                title: const Text('Appearance'),
                subtitle: const Text('Theme, Accent Color'),
                onTap: () => context.push('/settings/appearance'),
              ),
              ListTile(
                leading: const Icon(Symbols.tune_rounded),
                title: const Text('Advanced'),
                subtitle: const Text('Tweaks, Overrides'),
                onTap: () => context.push('/settings/advanced'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (canViewScouts || canEditScouts || canManageUsersRoles)
            SettingsGroup(
              title: 'Team',
              children: [
                if (canViewScouts || canEditScouts)
                  ListTile(
                    leading: const Icon(Symbols.group_rounded),
                    title: const Text('Scouts'),
                    subtitle: Text(
                      canEditScouts ? 'Add, Remove Scouts' : 'View Scouts',
                    ),
                    onTap: () => context.push('/settings/user_selection'),
                  ),
                if (canManageUsersRoles)
                  ListTile(
                    leading: const Icon(Symbols.groups_rounded),
                    title: const Text('Beariscope Users, Roles'),
                    subtitle: const Text('Edit Roles, Permissions, Users'),
                    onTap: () => context.push('/settings/roles'),
                  ),
              ],
            ),

          if (canViewScouts || canEditScouts || canManageUsersRoles)
            const SizedBox(height: 16),

          // About Section
          SettingsGroup(
            title: 'About',
            children: [
              ListTile(
                leading: const Icon(Symbols.info_rounded),
                title: const Text('About'),
                subtitle: const Text('Version, Acknowledgements'),
                onTap: () => context.push('/settings/about'),
              ),
              ListTile(
                leading: const Icon(Symbols.license_rounded),
                title: const Text('Licenses'),
                subtitle: const Text('Licenses, Open Source'),
                onTap: () => context.push('/settings/licenses'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
