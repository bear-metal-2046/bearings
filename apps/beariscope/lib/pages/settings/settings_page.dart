import 'package:core/core.dart'
    show gamePackReadPermission, gamePackManagePermission;

import 'package:ui/widgets/bearings_setting_group.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
    final canOpenUsersAndRoles =
        permissionChecker?.canOpenUsersAndRoles ?? false;

    final canManagePractice =
        permissionChecker?.hasPermission(gamePackReadPermission) == true &&
        permissionChecker?.hasPermission(gamePackManagePermission) == true;
    final showTeamSettings =
        canViewScouts ||
        canEditScouts ||
        canOpenUsersAndRoles ||
        canManagePractice;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          BearingsSettingGroup(
            title: 'General',
            children: [
              ListTile(
                leading: const Icon(LucideIcons.circleUser),
                title: const Text('Account'),
                subtitle: const Text('Your Profile, Picture, Details'),
                onTap: () => context.push('/settings/account'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.palette),
                title: const Text('Appearance'),
                subtitle: const Text('Theme, Accent Color'),
                onTap: () => context.push('/settings/appearance'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.wrench),
                title: const Text('Advanced'),
                subtitle: const Text('Tweaks, Overrides'),
                onTap: () => context.push('/settings/advanced'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (showTeamSettings)
            BearingsSettingGroup(
              title: 'Team',
              children: [
                if (canManagePractice)
                  ListTile(
                    leading: const Icon(LucideIcons.flaskConical),
                    title: const Text('Bearimetric Practice'),
                    subtitle: const Text('Practice event and GamePack'),
                    onTap: () => context.push('/settings/practice'),
                  ),
                if (canViewScouts || canEditScouts)
                  ListTile(
                    leading: const Icon(LucideIcons.userPen),
                    title: const Text('Scouts'),
                    subtitle: Text(
                      canEditScouts ? 'Add, Remove Scouts' : 'View Scouts',
                    ),
                    onTap: () => context.push('/settings/user_selection'),
                  ),
                if (canOpenUsersAndRoles)
                  ListTile(
                    leading: const Icon(LucideIcons.users),
                    title: const Text('Users & Roles'),
                    subtitle: const Text(
                      'User profiles, role assignments, and permissions',
                    ),
                    onTap: () => context.push('/settings/roles'),
                  ),
              ],
            ),

          if (showTeamSettings) const SizedBox(height: 16),

          // About Section
          BearingsSettingGroup(
            title: 'About',
            children: [
              ListTile(
                leading: const Icon(LucideIcons.info),
                title: const Text('About'),
                subtitle: const Text('Version, Acknowledgements'),
                onTap: () => context.push('/settings/about'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.scroll),
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
