import 'package:beariscope/utils/platform_utils_stub.dart'
    if (dart.library.io) 'package:beariscope/utils/platform_utils.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:beariscope/widgets/beariscope_search_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/rbac_management_provider.dart';

class TeamRoleSettingsPage extends ConsumerStatefulWidget {
  const TeamRoleSettingsPage({super.key});

  @override
  ConsumerState<TeamRoleSettingsPage> createState() =>
      _TeamRoleSettingsPageState();
}

class _TeamRoleSettingsPageState extends ConsumerState<TeamRoleSettingsPage>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  late final TabController _tabController;
  final FocusNode _pageFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<ManagedRole>? _optimisticRoles;
  List<ManagedUser>? _optimisticUsers;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _selectedTab,
    )..addListener(_handleTabChanged);
    _searchController.addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageFocusNode.requestFocus();
    });
  }

  void _handleTabChanged() {
    final nextIndex = _tabController.index;
    if (nextIndex == _selectedTab || !mounted) {
      return;
    }

    setState(() => _selectedTab = nextIndex);
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
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageFocusNode.dispose();
    super.dispose();
  }

  bool _isMobileDialog(BuildContext context) =>
      MediaQuery.of(context).size.width < 700;

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

    Future<void> showDialogBody() async {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
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
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);

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
                  navigator.pop();
                } catch (error) {
                  if (!mounted) return;
                  setState(() {
                    _optimisticRoles = previousRoles;
                  });
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to save role: $error')),
                  );
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

              if (_isMobileDialog(dialogContext)) {
                return Dialog.fullscreen(
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(titleText),
                      leading: IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(LucideIcons.x),
                      ),
                      actions: [
                        TextButton(
                          onPressed: canSave ? handleSave : null,
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: formBody,
                      ),
                    ),
                  ),
                );
              }

              return AlertDialog(
                title: Text(titleText),
                content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(child: formBody),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: canSave ? handleSave : null,
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

    await showDialogBody();
  }

  Future<void> _deleteRole(ManagedRole role, int assignedUsers) async {
    if (assignedUsers > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cannot delete role'),
          content: Text(
            'This role is assigned to $assignedUsers users. Please reassign them before deleting.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Delete ${role.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _optimisticRoles = previousRoles;
        _optimisticUsers = previousUsers;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete role: $error')));
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

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final currentName = nameController.text.trim();

            final hasChanges =
                currentName != initialName ||
                !_sameStringListAsSet(user.roles, selectedRoles);

            final canSave = hasChanges;

            Future<void> handleSave() async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

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
                navigator.pop();
              } catch (error) {
                if (!mounted) return;
                setState(() {
                  _optimisticUsers = previousUsers;
                });
                messenger.showSnackBar(
                  SnackBar(content: Text('Failed to update user: $error')),
                );
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

            if (_isMobileDialog(dialogContext)) {
              return Dialog.fullscreen(
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Edit User'),
                    leading: IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(LucideIcons.x),
                    ),
                    actions: [
                      TextButton(
                        onPressed: canSave ? handleSave : null,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: formBody,
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              title: const Text('Edit User'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(child: formBody),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: canSave ? handleSave : null,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _emptyState({required String text}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }

  Widget _buildSearchBar() {
    return BeariscopeSearchBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      hintText: _selectedTab == 0 ? 'Search users' : 'Search roles',
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

  Widget _buildRoleFabTransition(
    Widget fab, {
    required bool includeBottomSpacing,
  }) {
    final tabAnimation = _tabController.animation;
    final child = includeBottomSpacing
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [fab, const SizedBox(height: 8)],
          )
        : fab;

    if (tabAnimation == null) return child;

    return AnimatedBuilder(
      animation: tabAnimation,
      child: child,
      builder: (context, child) {
        final opacity = tabAnimation.value.clamp(0.0, 1.0).toDouble();
        return IgnorePointer(
          ignoring: opacity < 1.0,
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: opacity,
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metadataAsync = ref.watch(rbacMetadataProvider);
        final rolesAsync = ref.watch(rbacRolesProvider);
        final usersAsync = ref.watch(rbacUsersProvider);
        final searchQuery = _searchQuery;
        final isMobile = PlatformUtils.isMobile();
        final searchInAppBar = !isMobile && constraints.maxWidth > 900;
        final searchAtTop = !isMobile && !searchInAppBar;
        final safeAreaBottom = MediaQuery.of(context).padding.bottom;
        final listPadding = searchInAppBar
            ? const EdgeInsets.all(16)
            : searchAtTop
            ? const EdgeInsets.fromLTRB(16, 72, 16, 16)
            : EdgeInsets.fromLTRB(16, 16, 16, 128 + safeAreaBottom);
        final newRoleFab = metadataAsync.when(
          loading: () => null,
          error: (_, _) => null,
          data: (metadata) {
            return FloatingActionButton.extended(
              onPressed: () {
                _showRoleDialog(
                  permissions: metadata.permissions,
                  currentRoles:
                      _optimisticRoles ??
                      rolesAsync.asData?.value ??
                      const <ManagedRole>[],
                );
              },
              icon: Icon(LucideIcons.plus),
              label: const Text('New Role'),
            );
          },
        );

        return Focus(
          focusNode: _pageFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) => _handleTypeToSearch(event),
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 8,
              title: const Text('Users & Roles'),
              flexibleSpace: searchInAppBar
                  ? BeariscopeCenteredAppBarSearch(searchBar: _buildSearchBar())
                  : null,
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Users'),
                  Tab(text: 'Roles'),
                ],
              ),
              actions: const [SizedBox(width: 48)],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: metadataAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) =>
                        Center(child: Text('Failed to load metadata: $error')),
                    data: (metadata) {
                      final permissionMap = {
                        for (final permission in metadata.permissions)
                          permission.key: permission,
                      };

                      return TabBarView(
                        controller: _tabController,
                        children: [
                          usersAsync.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, _) => Center(
                              child: Text('Failed to load users: $error'),
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

                              final filteredUsers = effectiveUsers.where((
                                user,
                              ) {
                                if (searchQuery.isEmpty) return true;
                                final roleNames = user.roles
                                    .map(
                                      (roleId) => roleMap[roleId]?.name ?? '',
                                    )
                                    .join(' ');
                                final userText = '${user.name ?? ''} $roleNames'
                                    .toLowerCase();
                                return userText.contains(searchQuery);
                              }).toList();

                              if (filteredUsers.isEmpty) {
                                return RefreshIndicator(
                                  onRefresh: _refreshRbacData,
                                  child: ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: listPadding,
                                    children: [
                                      SizedBox(
                                        height: 320,
                                        child: _emptyState(
                                          text: 'No users found',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return RefreshIndicator(
                                onRefresh: _refreshRbacData,
                                child: BeariscopeCardList(
                                  padding: listPadding,
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
                                                          (user.avatarUrl ?? '')
                                                              .isEmpty
                                                          ? const Icon(
                                                              LucideIcons.user,
                                                            )
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        user.name?.isNotEmpty ==
                                                                true
                                                            ? user.name!
                                                            : 'Unknown User',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      onPressed: () =>
                                                          _showUserDialog(
                                                            user: user,
                                                            roles:
                                                                effectiveRolesForUsers,
                                                            currentUsers:
                                                                effectiveUsers,
                                                          ),
                                                      icon: Icon(
                                                        LucideIcons.pencil,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                if (user.roles.isEmpty)
                                                  const Text(
                                                    'No roles assigned',
                                                  )
                                                else
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    children: user.roles.map((
                                                      roleId,
                                                    ) {
                                                      final roleName =
                                                          roleMap[roleId]
                                                              ?.name ??
                                                          'Unknown Role';
                                                      return Chip(
                                                        label: Text(
                                                          roleName,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                        padding:
                                                            EdgeInsets.zero,
                                                        labelPadding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: -2,
                                                            ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .standard,
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
                          rolesAsync.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, _) => Center(
                              child: Text('Failed to load roles: $error'),
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

                              final filteredRoles = effectiveRoles.where((
                                role,
                              ) {
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
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: listPadding,
                                    children: [
                                      SizedBox(
                                        height: 320,
                                        child: _emptyState(
                                          text: 'No roles defined',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return RefreshIndicator(
                                onRefresh: _refreshRbacData,
                                child: BeariscopeCardList(
                                  padding: listPadding,
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
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuButton<String>(
                                                      onSelected: (action) {
                                                        final assignedUsers =
                                                            roleUserCounts[role
                                                                .id] ??
                                                            0;
                                                        if (action == 'edit') {
                                                          _showRoleDialog(
                                                            role: role,
                                                            permissions: metadata
                                                                .permissions,
                                                            currentRoles:
                                                                effectiveRoles,
                                                          );
                                                        } else if (action ==
                                                            'duplicate') {
                                                          _showRoleDialog(
                                                            role: role,
                                                            permissions: metadata
                                                                .permissions,
                                                            currentRoles:
                                                                effectiveRoles,
                                                            duplicate: true,
                                                          );
                                                        } else if (action ==
                                                            'delete') {
                                                          _deleteRole(
                                                            role,
                                                            assignedUsers,
                                                          );
                                                        }
                                                      },
                                                      itemBuilder: (context) {
                                                        final assignedUsers =
                                                            roleUserCounts[role
                                                                .id] ??
                                                            0;
                                                        return [
                                                          const PopupMenuItem(
                                                            value: 'edit',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  LucideIcons
                                                                      .pencil,
                                                                ),
                                                                SizedBox(
                                                                  width: 8,
                                                                ),
                                                                Text('Edit'),
                                                              ],
                                                            ),
                                                          ),
                                                          const PopupMenuItem(
                                                            value: 'duplicate',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  LucideIcons
                                                                      .copy,
                                                                ),
                                                                SizedBox(
                                                                  width: 8,
                                                                ),
                                                                Text(
                                                                  'Duplicate',
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          PopupMenuItem(
                                                            value: 'delete',
                                                            enabled:
                                                                assignedUsers ==
                                                                0,
                                                            child: Row(
                                                              children: [
                                                                const Icon(
                                                                  LucideIcons
                                                                      .trash2,
                                                                ),
                                                                const SizedBox(
                                                                  width: 8,
                                                                ),
                                                                Text(
                                                                  assignedUsers ==
                                                                          0
                                                                      ? 'Delete'
                                                                      : 'Delete (assigned to $assignedUsers users)',
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ];
                                                      },
                                                    ),
                                                  ],
                                                ),
                                                if ((role.description ?? '')
                                                    .isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Text(
                                                      role.description!,
                                                    ),
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
                                                          metadataEntry
                                                              ?.description ??
                                                          '',
                                                      child: Chip(
                                                        label: Text(
                                                          metadataEntry?.name ?? 'Unknown Permission',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                        padding:
                                                            EdgeInsets.zero,
                                                        labelPadding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: -2,
                                                            ),
                                                        visualDensity:
                                                            VisualDensity
                                                                .standard,
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
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (!searchInAppBar && searchAtTop)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: _buildSearchBar(),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!searchInAppBar && !searchAtTop)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (newRoleFab != null)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _buildRoleFabTransition(
                                  newRoleFab,
                                  includeBottomSpacing: true,
                                ),
                              ],
                            ),
                          _buildSearchBar(),
                        ],
                      ),
                    ),
                  ),
                if ((searchAtTop || searchInAppBar) && newRoleFab != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: SafeArea(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildRoleFabTransition(
                            newRoleFab,
                            includeBottomSpacing: false,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
