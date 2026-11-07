import 'package:ui/widgets/bearings_alert_dialog.dart';
import 'package:ui/widgets/bearings_modal.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_scaffold.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/api_provider.dart';
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
  List<ManagedRole>? _optimisticRoles;
  List<ManagedUser>? _optimisticUsers;

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

  Future<void> _refreshRbacData() async {
    final client = ref.read(honeycombClientProvider);
    client.invalidateCache('/rbac/roles');
    client.invalidateCache('/rbac/users');
    client.invalidateCache('/rbac/metadata');

    ref.invalidate(rbacRolesProvider);
    ref.invalidate(rbacUsersProvider);
    ref.invalidate(rbacMetadataProvider);

    try {
      await Future.wait([
        ref.read(rbacRolesProvider.future),
        ref.read(rbacUsersProvider.future),
        ref.read(rbacMetadataProvider.future),
      ]);

      if (mounted) {
        setState(() {
          _optimisticRoles = null;
          _optimisticUsers = null;
        });
      }
    } catch (_) {
      // Keep current optimistic/cached state visible if refresh fails.
    }
  }

  Future<void> _showRoleDialog({
    ManagedRole? role,
    required List<RbacPermissionMetadata> permissions,
    required List<ManagedRole> currentRoles,
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
                final previousRoles = List<ManagedRole>.from(
                  _optimisticRoles ?? currentRoles,
                );

                final nextRole = ManagedRole(
                  id: currentId,
                  name: currentName,
                  description: currentDescription.isEmpty
                      ? null
                      : currentDescription,
                  permissions: permissionList,
                );

                final nextRoles = isEdit
                    ? previousRoles
                          .map(
                            (entry) => entry.id == currentId ? nextRole : entry,
                          )
                          .toList()
                    : <ManagedRole>[...previousRoles, nextRole];

                setState(() {
                  _optimisticRoles = nextRoles;
                });

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
                  await _refreshRbacData();
                  if (dialogContext.mounted) {
                    BearingsModal.complete<_RoleEditorAction>(dialogContext);
                  }
                } catch (error) {
                  if (!mounted) return;
                  setState(() {
                    _optimisticRoles = previousRoles;
                  });
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
                  ...permissions.map(
                    (permission) => CheckboxListTile(
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
                  ),
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
        currentRoles: currentRoles,
        duplicate: true,
      );
    }
  }

  Future<bool> _deleteRole(ManagedRole role, int assignedUsers) async {
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

    final previousRoles = List<ManagedRole>.from(
      _optimisticRoles ??
          ref.read(rbacRolesProvider).asData?.value ??
          const <ManagedRole>[],
    );
    final previousUsers = List<ManagedUser>.from(
      _optimisticUsers ??
          ref.read(rbacUsersProvider).asData?.value ??
          const <ManagedUser>[],
    );

    try {
      setState(() {
        _optimisticRoles = previousRoles
            .where((entry) => entry.id != role.id)
            .toList();
      });

      await ref.read(rbacManagementServiceProvider).deleteRole(role.id);
      await _refreshRbacData();
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _optimisticRoles = previousRoles;
        _optimisticUsers = previousUsers;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete role: $error')));
      return false;
    }
  }

  Future<void> _showUserDialog({
    required ManagedUser user,
    required List<ManagedRole> roles,
    required List<ManagedUser> currentUsers,
  }) async {
    final initialName = user.name ?? '';
    final initialRoles = <String>{...user.roles};

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
                !_sameStringListAsSet(user.roles, selectedRoles);

            final canSave = hasChanges;

            Future<void> handleSave() async {
              if (saving) return;
              setDialogState(() => saving = true);
              final messenger = ScaffoldMessenger.of(context);

              final previousUsers = List<ManagedUser>.from(
                _optimisticUsers ?? currentUsers,
              );
              final nextUser = ManagedUser(
                id: user.id,
                name: currentName.isEmpty ? null : currentName,
                avatarUrl: user.avatarUrl,
                roles: selectedRoles.toList()..sort(),
              );

              setState(() {
                _optimisticUsers = previousUsers
                    .map((entry) => entry.id == user.id ? nextUser : entry)
                    .toList();
              });

              try {
                await ref
                    .read(rbacManagementServiceProvider)
                    .updateUserRoles(
                      userId: user.id,
                      name: currentName.isEmpty ? null : currentName,
                      roles: selectedRoles.toList()..sort(),
                    );
                if (!mounted) return;
                await _refreshRbacData();
                if (dialogContext.mounted) {
                  BearingsModal.complete<void>(dialogContext);
                }
              } catch (error) {
                if (!mounted) return;
                setState(() {
                  _optimisticUsers = previousUsers;
                });
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
    final metadataAsync = ref.watch(rbacMetadataProvider);
    final rolesAsync = ref.watch(rbacRolesProvider);
    final usersAsync = ref.watch(rbacUsersProvider);
    final searchQuery = _searchQuery;
    final newRoleAction = metadataAsync.when(
      loading: () => null,
      error: (_, _) => null,
      data: (metadata) => BearingsAction(
        icon: const Icon(LucideIcons.plus),
        label: 'New Role',
        onPressed: () => _showRoleDialog(
          permissions: metadata.permissions,
          currentRoles:
              _optimisticRoles ??
              rolesAsync.asData?.value ??
              const <ManagedRole>[],
        ),
      ),
    );

    Widget withMetadata(Widget Function(RbacMetadata) builder) =>
        metadataAsync.when(
          loading: () => const Center(child: BearingsSpinner()),
          error: (error, _) => BearingsStatusView(
            icon: LucideIcons.circleAlert,
            iconColor: Theme.of(context).colorScheme.error,
            title: 'RBAC metadata unavailable',
            subtitle: 'Failed to load metadata: $error',
          ),
          data: builder,
        );

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
                bodyBuilder: (context, layout) => withMetadata(
                  (_) => usersAsync.when(
                    loading: () => const Center(child: BearingsSpinner()),
                    error: (error, _) => BearingsStatusView(
                      icon: LucideIcons.circleAlert,
                      iconColor: Theme.of(context).colorScheme.error,
                      title: 'Users unavailable',
                      subtitle: 'Failed to load users: $error',
                    ),
                    data: (users) {
                      final effectiveUsers = _optimisticUsers ?? users;
                      final effectiveRolesForUsers =
                          _optimisticRoles ??
                          rolesAsync.asData?.value ??
                          const <ManagedRole>[];
                      final roleMap = {
                        for (final role in effectiveRolesForUsers)
                          role.id: role,
                      };

                      final filteredUsers = effectiveUsers.where((user) {
                        if (searchQuery.isEmpty) return true;
                        final roleNames = user.roles
                            .map((roleId) => roleMap[roleId]?.name ?? '')
                            .join(' ');
                        final userText = '${user.name ?? ''} $roleNames'
                            .toLowerCase();
                        return userText.contains(searchQuery);
                      }).toList();

                      if (filteredUsers.isEmpty) {
                        return RefreshIndicator(
                          onRefresh: _refreshRbacData,
                          child: ListView(
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
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _refreshRbacData,
                        child: BearingsCardList(
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundImage:
                                                  (user.avatarUrl ?? '')
                                                      .isNotEmpty
                                                  ? NetworkImage(
                                                      user.avatarUrl!,
                                                    )
                                                  : null,
                                              child:
                                                  (user.avatarUrl ?? '').isEmpty
                                                  ? const Icon(LucideIcons.user)
                                                  : null,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                user.name?.isNotEmpty == true
                                                    ? user.name!
                                                    : 'Unknown User',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () => _showUserDialog(
                                                user: user,
                                                roles: effectiveRolesForUsers,
                                                currentUsers: effectiveUsers,
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
                                                  roleMap[roleId]?.name ??
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
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            BearingsTab(
              id: 'roles',
              label: const Text('Roles'),
              page: BearingsPage(
                search: _buildSearch('Search roles'),
                primaryAction: newRoleAction,
                bodyBuilder: (context, layout) => withMetadata((metadata) {
                  final permissionMap = {
                    for (final permission in metadata.permissions)
                      permission.key: permission,
                  };
                  return rolesAsync.when(
                    loading: () => const Center(child: BearingsSpinner()),
                    error: (error, _) => BearingsStatusView(
                      icon: LucideIcons.circleAlert,
                      iconColor: Theme.of(context).colorScheme.error,
                      title: 'Roles unavailable',
                      subtitle: 'Failed to load roles: $error',
                    ),
                    data: (roles) {
                      final effectiveRoles = _optimisticRoles ?? roles;
                      final users =
                          _optimisticUsers ??
                          usersAsync.asData?.value ??
                          const <ManagedUser>[];
                      final roleUserCounts = <String, int>{};
                      for (final user in users) {
                        for (final roleId in user.roles) {
                          roleUserCounts.update(
                            roleId,
                            (value) => value + 1,
                            ifAbsent: () => 1,
                          );
                        }
                      }

                      final filteredRoles = effectiveRoles.where((role) {
                        if (searchQuery.isEmpty) return true;
                        final roleText =
                            '${role.name} ${role.description ?? ''} ${role.permissions.join(' ')}'
                                .toLowerCase();
                        return roleText.contains(searchQuery);
                      }).toList();

                      if (filteredRoles.isEmpty) {
                        return RefreshIndicator(
                          onRefresh: _refreshRbacData,
                          child: ListView(
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
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _refreshRbacData,
                        child: BearingsCardList(
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                              onPressed: () => _showRoleDialog(
                                                role: role,
                                                permissions:
                                                    metadata.permissions,
                                                currentRoles: effectiveRoles,
                                                assignedUsers:
                                                    roleUserCounts[role.id] ??
                                                    0,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if ((role.description ?? '').isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
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
                                                  metadataEntry?.description ??
                                                  '',
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
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
