import 'package:beariscope/widgets/grove_load_message.dart';
import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_alert_dialog.dart';
import 'package:ui/widgets/bearings_modal.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_scaffold.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/rbac_management_provider.dart';
import 'package:ui/widgets/bearings_spinner.dart';

enum _RoleEditorAction { duplicate }

class TeamRoleSettingsPage extends ConsumerStatefulWidget {
  const TeamRoleSettingsPage({super.key});

  @override
  ConsumerState<TeamRoleSettingsPage> createState() =>
      _TeamRoleSettingsPageState();
}

class _TeamRoleSettingsPageState extends ConsumerState<TeamRoleSettingsPage> {
  final FocusNode _pageFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageFocusNode.requestFocus();
    });
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text.trim().toLowerCase();
    if (nextQuery == _searchQuery) {
      return;
    }

    if (!mounted) {
      _searchQuery = nextQuery;
      return;
    }

    setState(() => _searchQuery = nextQuery);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageFocusNode.dispose();
    super.dispose();
  }

  InputDecoration _outlinedInput({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    );
  }

  bool _sameStringSet(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  bool _sameStringListAsSet(List<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  Future<void> _showRoleDialog({
    GroveRole? role,
    required List<PermissionMetadata> permissions,
    bool duplicate = false,
    int assignedUsers = 0,
  }) async {
    final isEdit = role != null && !duplicate;

    final initialId = duplicate ? '${role?.id ?? ''}_copy' : (role?.id ?? '');
    final initialName = duplicate
        ? '${role?.name ?? ''} Copy'
        : (role?.name ?? '');
    final initialDescription = role?.description ?? '';
    final initialPermissions = <String>{...?role?.permissions};

    final idController = TextEditingController(text: initialId);
    final nameController = TextEditingController(text: initialName);
    final descriptionController = TextEditingController(
      text: initialDescription,
    );
    final selectedPermissions = <String>{...initialPermissions};
    var saving = false;
    var deleting = false;

    Future<_RoleEditorAction?> showDialogBody() async {
      return BearingsModal.show<_RoleEditorAction>(
        context,
        useRootNavigator: true,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final busy = saving || deleting;
              final currentId = idController.text.trim();
              final currentName = nameController.text.trim();
              final currentDescription = descriptionController.text.trim();

              final hasChanges =
                  currentId != initialId ||
                  currentName != initialName ||
                  currentDescription != initialDescription ||
                  !_sameStringSet(selectedPermissions, initialPermissions);

              final canSave =
                  hasChanges &&
                  currentId.isNotEmpty &&
                  currentName.isNotEmpty &&
                  selectedPermissions.isNotEmpty;

              final titleText = isEdit
                  ? 'Edit Role'
                  : duplicate
                  ? 'Duplicate Role'
                  : 'Create Role';

              Future<void> handleSave() async {
                if (busy) return;
                setDialogState(() => saving = true);
                final messenger = ScaffoldMessenger.of(context);

                final permissionList = selectedPermissions.toList()..sort();
                try {
                  final service = ref.read(rbacManagementServiceProvider);
                  if (isEdit) {
                    await service.updateRole(
                      id: currentId,
                      name: currentName,
                      description: currentDescription.isEmpty
                          ? ''
                          : currentDescription,
                      permissions: permissionList,
                      basedOn: role,
                    );
                  } else {
                    await service.createRole(
                      id: currentId,
                      name: currentName,
                      description: currentDescription.isEmpty
                          ? null
                          : currentDescription,
                      permissions: permissionList,
                    );
                  }

                  if (!mounted) return;
                  if (dialogContext.mounted) {
                    BearingsModal.complete<_RoleEditorAction>(dialogContext);
                  }
                } catch (error) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to save role: $error')),
                  );
                } finally {
                  if (dialogContext.mounted) {
                    setDialogState(() => saving = false);
                  }
                }
              }

              final formBody = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: idController,
                    enabled: !isEdit,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: _outlinedInput(label: 'Role ID'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: _outlinedInput(label: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: _outlinedInput(label: 'Description'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Permissions',
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final group
                      in permissions
                          .map((permission) => permission.group)
                          .toSet()) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        group,
                        style: Theme.of(dialogContext).textTheme.titleSmall,
                      ),
                    ),
                    for (final permission in permissions.where(
                      (permission) => permission.group == group,
                    ))
                      CheckboxListTile(
                        value: selectedPermissions.contains(permission.key),
                        title: Text(permission.name),
                        subtitle: Text(permission.description),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              selectedPermissions.add(permission.key);
                            } else {
                              selectedPermissions.remove(permission.key);
                            }
                          });
                        },
                      ),
                  ],
                ],
              );

              return BearingsModal(
                title: titleText,
                size: BearingsModalSize.tall,
                content: formBody,
                actions: [
                  if (isEdit) ...[
                    BearingsModalAction(
                      label: 'Duplicate role',
                      icon: LucideIcons.copy,
                      enabled: !busy,
                      onPressed: () => BearingsModal.complete(
                        dialogContext,
                        _RoleEditorAction.duplicate,
                      ),
                    ),
                    BearingsModalAction(
                      label: assignedUsers == 0
                          ? 'Delete role'
                          : 'Delete (assigned to $assignedUsers users)',
                      icon: LucideIcons.trash2,
                      enabled: !busy && assignedUsers == 0,
                      onPressed: () async {
                        if (busy) return;
                        setDialogState(() => deleting = true);
                        try {
                          final deleted = await _deleteRole(
                            role,
                            assignedUsers,
                          );
                          if (deleted && dialogContext.mounted) {
                            BearingsModal.complete<_RoleEditorAction>(
                              dialogContext,
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => deleting = false);
                          }
                        }
                      },
                    ),
                  ],
                ],
                canDismiss: !busy,
                primaryAction: BearingsModalPrimaryAction(
                  label: 'Save',
                  icon: LucideIcons.check,
                  enabled: canSave && !deleting,
                  loading: saving,
                  onPressed: handleSave,
                ),
              );
            },
          );
        },
      );
    }

    final action = await showDialogBody();
    if (action == _RoleEditorAction.duplicate && mounted) {
      await _showRoleDialog(
        role: role,
        permissions: permissions,
        duplicate: true,
      );
    }
  }

  Future<bool> _deleteRole(GroveRole role, int assignedUsers) async {
    if (assignedUsers > 0) {
      await BearingsAlertDialog.show<void>(
        context: context,
        title: 'Cannot delete role',
        message:
            'This role is assigned to $assignedUsers users. Please reassign them before deleting.',
        actions: const [
          BearingsAlertAction(
            label: 'OK',
            role: BearingsAlertActionRole.primary,
          ),
        ],
      );
      return false;
    }

    final confirmed = await BearingsAlertDialog.show<bool>(
      context: context,
      title: 'Delete Role',
      message: 'Delete ${role.name}?',
      actions: const [
        BearingsAlertAction(label: 'Cancel', result: false),
        BearingsAlertAction(
          label: 'Delete',
          result: true,
          role: BearingsAlertActionRole.destructive,
        ),
      ],
    );

    if (confirmed != true || !mounted) return false;

    try {
      await ref.read(rbacManagementServiceProvider).deleteRole(role.id);
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete role: $error')));
      return false;
    }
  }

  Future<void> _showUserDialog({
    required GroveUser user,
    required List<GroveRole> roles,
  }) async {
    final initialName = user.name ?? '';
    final roleIds = user.roles.map((role) => role.id).toList();
    final initialRoles = roleIds.toSet();

    final nameController = TextEditingController(text: initialName);
    final selectedRoles = <String>{...initialRoles};
    var saving = false;

    await BearingsModal.show<void>(
      context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final currentName = nameController.text.trim();

            final hasChanges =
                currentName != initialName ||
                !_sameStringListAsSet(roleIds, selectedRoles);

            final canSave = hasChanges;

            Future<void> handleSave() async {
              if (saving) return;
              setDialogState(() => saving = true);
              final messenger = ScaffoldMessenger.of(context);

              try {
                await ref
                    .read(rbacManagementServiceProvider)
                    .updateUserRoles(
                      userId: user.id,
                      name: currentName == initialName ? null : currentName,
                      roles: _sameStringListAsSet(roleIds, selectedRoles)
                          ? null
                          : (selectedRoles.toList()..sort()),
                    );
                if (!mounted) return;
                if (dialogContext.mounted) {
                  BearingsModal.complete<void>(dialogContext);
                }
              } catch (error) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Failed to update user: $error')),
                );
              } finally {
                if (dialogContext.mounted) setDialogState(() => saving = false);
              }
            }

            final formBody = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: _outlinedInput(label: 'Name'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Roles',
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (roles.isEmpty)
                  const Text('No roles available.')
                else
                  ...roles.map(
                    (role) => CheckboxListTile(
                      value: selectedRoles.contains(role.id),
                      title: Text(role.name),
                      subtitle: (role.description ?? '').isNotEmpty
                          ? Text(role.description!)
                          : null,
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            selectedRoles.add(role.id);
                          } else {
                            selectedRoles.remove(role.id);
                          }
                        });
                      },
                    ),
                  ),
              ],
            );

            return BearingsModal(
              title: 'Edit User',
              size: BearingsModalSize.tall,
              content: formBody,
              actions: const [],
              canDismiss: !saving,
              primaryAction: BearingsModalPrimaryAction(
                label: 'Save',
                icon: LucideIcons.check,
                enabled: canSave,
                loading: saving,
                onPressed: handleSave,
              ),
            );
          },
        );
      },
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return BearingsStatusView(icon: icon, title: title, subtitle: subtitle);
  }

  BearingsSearch _buildSearch(String hintText) {
    return BearingsSearch(
      id: 'people-search',
      controller: _searchController,
      focusNode: _searchFocusNode,
      hintText: hintText,
    );
  }

  KeyEventResult _handleTypeToSearch(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.character == null ||
        _searchFocusNode.hasFocus) {
      return KeyEventResult.ignored;
    }

    final character = event.character!;
    _searchFocusNode.requestFocus();
    Future.microtask(() {
      if (!mounted) return;
      _searchController.text += character;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final grove = ref.watch(bearingsGroveProvider);
    final permissions = permissionMetadataFor(grove.registry);
    final permissionMap = {
      for (final permission in permissions) permission.key: permission,
    };
    final rolesAsync = ref
        .watch(groveQueryProvider(grove.query<GroveRole>()))
        .whenData((result) => result.requireAvailable());
    final usersAsync = ref
        .watch(groveQueryProvider(grove.query<GroveUser>()))
        .whenData((result) => result.requireAvailable());
    final searchQuery = _searchQuery;
    final checker = ref.watch(permissionCheckerProvider);
    final canCreateRole =
        ref.watch(honeycombConnectionProvider).value ==
            GroveConnectionState.connected &&
        (checker?.hasPermission(PermissionKey.rolesManage) ?? false);
    final canManageRoles = rolesAsync.value?.complete == true && canCreateRole;
    final canManageUsers =
        usersAsync.value?.complete == true &&
        rolesAsync.value?.complete == true &&
        (checker?.hasPermission(PermissionKey.usersManage) ?? false);
    final newRoleAction = canCreateRole
        ? BearingsAction(
            icon: const Icon(LucideIcons.plus),
            label: 'New Role',
            onPressed: () => _showRoleDialog(permissions: permissions),
          )
        : null;

    return Focus(
      focusNode: _pageFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleTypeToSearch(event),
      child: BearingsScaffold(
        title: const Text('Users & Roles'),
        titleSpacing: 8,
        content: BearingsTabs(
          tabs: [
            BearingsTab(
              id: 'users',
              label: const Text('Users'),
              page: BearingsPage(
                search: _buildSearch('Search users'),
                bodyBuilder: (context, layout) => usersAsync.when(
                  loading: () => const Center(child: BearingsSpinner()),
                  error: (error, _) => BearingsStatusView(
                    icon: LucideIcons.circleAlert,
                    iconColor: Theme.of(context).colorScheme.error,
                    title: 'Users unavailable',
                    subtitle: groveLoadMessage(error),
                  ),
                  data: (users) {
                    final effectiveUsers = users.items;
                    final effectiveRolesForUsers =
                        rolesAsync.value?.items ?? const <GroveRole>[];
                    final roleMap = {
                      for (final role in effectiveRolesForUsers) role.id: role,
                    };

                    final filteredUsers = effectiveUsers.where((user) {
                      if (searchQuery.isEmpty) return true;
                      final roleNames = user.roles
                          .map((roleId) => roleMap[roleId.id]?.name ?? '')
                          .join(' ');
                      final userText =
                          '${user.name ?? ''} ${user.email ?? ''} $roleNames'
                              .toLowerCase();
                      return userText.contains(searchQuery);
                    }).toList();

                    if (filteredUsers.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: layout.scrollPadding,
                        children: [
                          SizedBox(
                            height: 320,
                            child: _emptyState(
                              icon: LucideIcons.users,
                              title: 'No users found',
                              subtitle: _searchQuery.isEmpty
                                  ? 'No users have been added yet.'
                                  : 'Try adjusting your search.',
                            ),
                          ),
                        ],
                      );
                    }

                    return BearingsCardList(
                      padding: layout.scrollPadding,
                      children: filteredUsers
                          .map(
                            (user) => Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              margin: EdgeInsets.zero,
                              clipBehavior: Clip.antiAlias,
                              elevation: 0,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundImage:
                                              (user.avatarUrl ?? '').isNotEmpty
                                              ? NetworkImage(user.avatarUrl!)
                                              : null,
                                          child: (user.avatarUrl ?? '').isEmpty
                                              ? const Icon(LucideIcons.user)
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            user.name?.isNotEmpty == true
                                                ? user.name!
                                                : user.email ?? user.id,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: !canManageUsers
                                              ? null
                                              : () => _showUserDialog(
                                                  user: user,
                                                  roles: effectiveRolesForUsers,
                                                ),
                                          icon: Icon(LucideIcons.pencil),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (user.roles.isEmpty)
                                      const Text('No roles assigned')
                                    else
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: user.roles.map((roleId) {
                                          final roleName =
                                              roleMap[roleId.id]?.name ??
                                              'Unknown Role';
                                          return Chip(
                                            label: Text(
                                              roleName,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            padding: EdgeInsets.zero,
                                            labelPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: -2,
                                                ),
                                            visualDensity:
                                                VisualDensity.standard,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          );
                                        }).toList(),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ),
            ),
            BearingsTab(
              id: 'roles',
              label: const Text('Roles'),
              page: BearingsPage(
                search: _buildSearch('Search roles'),
                primaryAction: newRoleAction,
                bodyBuilder: (context, layout) => rolesAsync.when(
                  loading: () => const Center(child: BearingsSpinner()),
                  error: (error, _) => BearingsStatusView(
                    icon: LucideIcons.circleAlert,
                    iconColor: Theme.of(context).colorScheme.error,
                    title: 'Roles unavailable',
                    subtitle: groveLoadMessage(error),
                  ),
                  data: (roles) {
                    final effectiveRoles = roles.items;
                    final users =
                        usersAsync.value?.items ?? const <GroveUser>[];
                    final roleUserCounts = <String, int>{};
                    for (final user in users) {
                      for (final roleId in user.roles) {
                        roleUserCounts.update(
                          roleId.id,
                          (value) => value + 1,
                          ifAbsent: () => 1,
                        );
                      }
                    }

                    final filteredRoles = effectiveRoles.where((role) {
                      if (searchQuery.isEmpty) return true;
                      final roleText =
                          '${role.name} ${role.description ?? ''} ${role.permissions.map((key) => permissionMap[key]?.name ?? key).join(' ')}'
                              .toLowerCase();
                      return roleText.contains(searchQuery);
                    }).toList();

                    if (filteredRoles.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: layout.scrollPadding,
                        children: [
                          SizedBox(
                            height: 320,
                            child: _emptyState(
                              icon: LucideIcons.shield,
                              title: 'No roles defined',
                              subtitle: _searchQuery.isEmpty
                                  ? 'Create a role to control team access.'
                                  : 'Try adjusting your search.',
                            ),
                          ),
                        ],
                      );
                    }

                    return BearingsCardList(
                      padding: layout.scrollPadding,
                      children: filteredRoles
                          .map(
                            (role) => Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              margin: EdgeInsets.zero,
                              clipBehavior: Clip.antiAlias,
                              elevation: 0,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            role.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Edit role',
                                          icon: const Icon(
                                            LucideIcons.ellipsis,
                                          ),
                                          onPressed: !canManageRoles
                                              ? null
                                              : () => _showRoleDialog(
                                                  role: role,
                                                  permissions: permissions,

                                                  assignedUsers:
                                                      roleUserCounts[role.id] ??
                                                      0,
                                                ),
                                        ),
                                      ],
                                    ),
                                    if ((role.description ?? '').isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(role.description!),
                                      ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: role.permissions.map((
                                        permissionKey,
                                      ) {
                                        final metadataEntry =
                                            permissionMap[permissionKey];
                                        return Tooltip(
                                          message:
                                              metadataEntry?.description ?? '',
                                          child: Chip(
                                            label: Text(
                                              metadataEntry?.name ??
                                                  'Unknown Permission',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            padding: EdgeInsets.zero,
                                            labelPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: -2,
                                                ),
                                            visualDensity:
                                                VisualDensity.standard,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
