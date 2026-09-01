import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/pages/settings/appearance_settings_page.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/providers/user_profile_provider.dart';
import 'package:services/widgets/profile_picture.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';

import '../providers/pits_scouting_provider.dart';

class _NavItem {
  final String route;
  final IconData icon;
  final String label;
  final String group;

  const _NavItem({
    required this.route,
    required this.icon,
    required this.label,
    required this.group,
  });
}

class MainViewController extends InheritedWidget {
  final VoidCallback openDrawer;
  final bool isDesktop;

  const MainViewController({
    super.key,
    required this.openDrawer,
    required this.isDesktop,
    required super.child,
  });

  static MainViewController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainViewController>()!;

  @override
  bool updateShouldNotify(MainViewController oldWidget) =>
      isDesktop != oldWidget.isDesktop;
}

class MainView extends ConsumerStatefulWidget {
  final Widget child;

  const MainView({super.key, required this.child});

  @override
  ConsumerState<MainView> createState() => _MainViewState();
}

class _MainViewState extends ConsumerState<MainView> {
  bool _isRefreshing = false;
  static const double _drawerWidth = 280;
  static const _animationDuration = Duration(milliseconds: 100);

  static const List<_NavItem> _navItems = [
    _NavItem(
      route: '/up_next',
      icon: Symbols.event_rounded,
      label: 'Up Next',
      group: 'General',
    ),
    _NavItem(
      route: '/team_lookup',
      icon: Symbols.smart_toy_rounded,
      label: 'Team Lookup',
      group: 'Insights',
    ),
    _NavItem(
      route: '/match_lookup',
      icon: Symbols.leaderboard,
      label: 'Match Lookup',
      group: 'Insights',
    ),
    _NavItem(
      route: '/export',
      icon: Symbols.table_chart_rounded,
      label: 'Export Data',
      group: 'Insights',
    ),
    // _NavItem(
    //   route: '/picklists',
    //   icon: Symbols.list_alt_rounded,
    //   label: 'Picklists',
    //   group: 'Insights',
    // ),
    // _NavItem(
    //   route: '/corrections',
    //   icon: Symbols.table_edit_rounded,
    //   label: 'Data Corrections',
    //   group: 'Scouting',
    // ),
    _NavItem(
      route: '/scout_audit',
      icon: Symbols.assignment_rounded,
      label: 'Scout Audit',
      group: 'Scouting',
    ),
    _NavItem(
      route: '/pits_scouting',
      icon: Symbols.build_rounded,
      label: 'Pits Scouting',
      group: 'Scouting',
    ),
  ];

  List<_NavItem> _visibleNavItems(PermissionChecker? permissionChecker) {
    return [
      for (final item in _navItems)
        if (_canShowNavItem(item, permissionChecker)) item,
    ];
  }

  bool _canShowNavItem(_NavItem item, PermissionChecker? permissionChecker) {
    return switch (item.route) {
      '/scout_audit' =>
        permissionChecker?.hasPermission(PermissionKey.matchCorrect) ?? false,
      '/pits_scouting' =>
        (permissionChecker?.hasPermission(PermissionKey.pitsUpload) ?? false) ||
            (permissionChecker?.hasPermission(PermissionKey.pitsRead) ?? false),
      _ => true,
    };
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _selectedIndexFor(List<_NavItem> items) {
    final location = GoRouterState.of(context).uri.toString();
    final idx = items.indexWhere((n) => location.startsWith(n.route));
    return idx;
  }

  bool _isAtTopLevelFor(List<_NavItem> items) {
    final location = GoRouterState.of(context).uri.toString();
    // just checks if we're at a top level nav item (not a nested route)
    return items.any((n) => n.route == location);
  }

  void _onDestinationSelected(int index, bool isDesktop, List<_NavItem> items) {
    if (index < 0 || index >= items.length) return;
    if (index == _selectedIndexFor(items)) {
      if (!isDesktop) Navigator.pop(context);
      return;
    }
    context.go(items[index].route);
    if (!isDesktop) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final searchFocusNode = ref.watch(searchFocusNodeProvider);
    final searchController = ref.watch(searchControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 700;
        final permissionChecker = ref.watch(permissionCheckerProvider);
        final visibleNavItems = _visibleNavItems(permissionChecker);
        final selectedIndex = _selectedIndexFor(visibleNavItems);
        final isAtTopLevel = _isAtTopLevelFor(visibleNavItems);
        final allowDrawerGesture =
            !isDesktop &&
            isAtTopLevel &&
            ModalRoute.of(context)?.isCurrent == true;

        final isOnline = switch (ref.watch(connectivityProvider)) {
          AsyncData(:final value) => value,
          _ => true,
        };

        final navigationSidebarContent = Column(
          children: [
            Expanded(
              child: NavigationDrawer(
                selectedIndex: selectedIndex == -1 ? null : selectedIndex,
                onDestinationSelected: (i) =>
                    _onDestinationSelected(i, isDesktop, visibleNavItems),
                children: _buildNavChildren(),
              ),
            ),
            const Divider(height: 2),
            _buildBottomComponents(isOnline: isOnline),
          ],
        );

        final navigationDrawer = SizedBox(
          width: _drawerWidth,
          child: isDesktop
              ? Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: navigationSidebarContent,
                )
              : Drawer(child: navigationSidebarContent),
        );

        final childContent = isDesktop
            ? Row(
                children: [
                  navigationDrawer,
                  Expanded(child: widget.child),
                ],
              )
            : widget.child;

        // checks for showing no perms banner
        final authMeLoaded = ref.watch(authMeProvider).hasValue;
        final hasNoPermissions =
            authMeLoaded &&
            permissionChecker != null &&
            permissionChecker.permissions.isEmpty;

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            final location = GoRouterState.of(context).uri.toString();

            final isTeamLookup = location.startsWith('/team_lookup');
            final isPitsScouting = location.startsWith('/pits_scouting');

            if (isTeamLookup || isPitsScouting) {
              final focusNode = ref.read(
                isTeamLookup
                    ? searchFocusNodeProvider
                    : pitsSearchFocusNodeProvider,
              );
              final controller = ref.read(
                isTeamLookup
                    ? searchControllerProvider
                    : pitsSearchControllerProvider,
              );

              if (event is KeyDownEvent &&
                  event.character != null &&
                  !focusNode.hasFocus) {
                focusNode.requestFocus();

                Future.microtask(() {
                  controller.text += event.character!;
                  controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: controller.text.length),
                  );
                });
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(
            key: _scaffoldKey,
            // Only enable drawer when at top level and on mobile
            drawer: isDesktop ? null : (isAtTopLevel ? navigationDrawer : null),
            drawerEnableOpenDragGesture: !isDesktop && isAtTopLevel,
            drawerBarrierDismissible: !isDesktop,
            body: MainViewController(
              isDesktop: isDesktop,
              openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasNoPermissions) const _NoPermissionsBanner(),
                  Expanded(child: childContent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _doRefresh() async {
    setState(() => _isRefreshing = true);
    try {
      await ref.read(scoutingDataProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  List<Widget> _buildNavChildren() {
    final children = <Widget>[];
    final permissionChecker = ref.watch(permissionCheckerProvider);
    final visibleNavItems = _visibleNavItems(permissionChecker);

    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 24, 10),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/beariscope_head.svg',
                    width: 24,
                    colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.primary,
                      BlendMode.srcATop,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Beariscope',
                    style: TextStyle(fontFamily: 'Xolonium', fontSize: 20),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Settings',
              child: InkWell(
                onTap: () => context.push('/settings'),
                borderRadius: BorderRadius.circular(24),
                child: ProfilePicture(size: 16),
              ),
            ),
          ],
        ),
      ),
    );

    children.add(
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Divider(),
      ),
    );

    String? currentGroup;
    for (final entry in visibleNavItems.indexed) {
      final index = entry.$1;
      final item = entry.$2;
      if (item.group != currentGroup) {
        if (currentGroup != null) {
          children.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Divider(),
            ),
          );
        }
        currentGroup = item.group;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 10, 16, 16),
            child: Text(
              currentGroup,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
      }
      children.add(
        NavigationDrawerDestination(
          icon: TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: _selectedIndexFor(visibleNavItems) == index ? 0.0 : 1.0,
              end: _selectedIndexFor(visibleNavItems) == index ? 1.0 : 0.0,
            ),
            duration: _animationDuration,
            curve: Curves.fastOutSlowIn,
            builder: (context, value, _) =>
                Icon(item.icon, weight: 600, fill: value),
          ),
          label: Text(item.label),
        ),
      );
    }

    return children;
  }

  Widget _buildBottomComponents({required bool isOnline}) {
    final userInfoAsync = ref.watch(userInfoProvider);
    final userName = userInfoAsync.value?.name ?? 'Loading...';
    final themeMode = ref.watch(themeModeProvider);

    final permissionChecker = ref.watch(permissionCheckerProvider);
    final canSelectEvent =
        permissionChecker != null && permissionChecker.permissions.isNotEmpty;
    final canProvision =
        permissionChecker?.hasPermission(PermissionKey.deviceProvision) ??
        false;
    final eventsAsync = canSelectEvent ? ref.watch(teamEventsProvider) : null;
    final currentEventKey = ref.watch(currentEventProvider);
    final availableEvents = eventsAsync?.value ?? const <EventOption>[];
    final eventOptions = canSelectEvent
        ? eventPickerOptions(availableEvents, currentEventKey)
        : const <EventOption>[];
    final selectedEvent = canSelectEvent
        ? eventOptions.firstWhere(
            (event) => event.key == currentEventKey,
            orElse: () => EventOption.current(currentEventKey),
          )
        : EventOption.current(currentEventKey);

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subtitleText = canSelectEvent
        ? 'At ${selectedEvent.displayShortName}'
        : 'No event selected';

    return SafeArea(
      top: false,
      child: MenuTheme(
        data: MenuThemeData(
          style: MenuStyle(
            elevation: const WidgetStatePropertyAll(8.0),
            backgroundColor: WidgetStatePropertyAll(
              colorScheme.surfaceContainerHigh,
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        child: MenuAnchor(
          // animated: true,
          alignmentOffset: const Offset(12, 0),
          builder: (context, controller, child) {
            final isOpen = controller.isOpen;

            return Material(
              color: isOpen
                  ? colorScheme.surfaceContainerHighest
                  : Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const ProfilePicture(size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              userName,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              layoutBuilder:
                                  (
                                    Widget? currentChild,
                                    List<Widget> previousChildren,
                                  ) {
                                    return Stack(
                                      alignment: Alignment.centerLeft,
                                      children: <Widget>[
                                        ...previousChildren,
                                        ?currentChild,
                                      ],
                                    );
                                  },
                              child: Text(
                                _isRefreshing ? 'Syncing...' : subtitleText,
                                key: ValueKey('$_isRefreshing-$subtitleText'),
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isOpen
                            ? Symbols.unfold_less_rounded
                            : Symbols.unfold_more_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          menuChildren: [
            if (canSelectEvent && eventsAsync != null)
              eventsAsync.when(
                data: (events) {
                  final pickerEvents = eventPickerOptions(
                    events,
                    currentEventKey,
                  );
                  final currentEvent = pickerEvents.firstWhere(
                    (e) => e.key == currentEventKey,
                    orElse: () => EventOption.current(currentEventKey),
                  );
                  return SubmenuButton(
                    // animated: true,
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                    menuStyle: MenuStyle(
                      elevation: const WidgetStatePropertyAll(8.0),
                      backgroundColor: WidgetStatePropertyAll(
                        colorScheme.surfaceContainerHighest,
                      ),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    submenuIcon: WidgetStatePropertyAll(
                      const Icon(Symbols.chevron_right_rounded, size: 16),
                    ),
                    leadingIcon: const Icon(
                      Symbols.edit_calendar_rounded,
                      size: 20,
                    ),
                    menuChildren: pickerEvents
                        .map(
                          (e) => MenuItemButton(
                            style: const ButtonStyle(
                              padding: WidgetStatePropertyAll(
                                EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),
                            leadingIcon: Icon(e.leadingIcon, size: 20),
                            trailingIcon: e.key == currentEventKey
                                ? Icon(
                                    Symbols.check_rounded,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  )
                                : const SizedBox(width: 20),
                            onPressed: () {
                              ref
                                  .read(currentEventProvider.notifier)
                                  .setEventKey(e.key);
                            },
                            child: Text(e.displayName),
                          ),
                        )
                        .toList(),
                    child: Text('At ${currentEvent.displayShortName}'),
                  );
                },
                loading: () => const MenuItemButton(
                  onPressed: null,
                  style: ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                  leadingIcon: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  child: Text('Loading events...'),
                ),
                error: (e, s) => MenuItemButton(
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                  onPressed: () => ref.invalidate(teamEventsProvider),
                  leadingIcon: const Icon(Symbols.error_rounded, size: 20),
                  child: const Text('Failed to load events. Retry?'),
                ),
              ),

            if (canSelectEvent && eventsAsync != null)
              const Divider(height: 16),

            MenuItemButton(
              closeOnActivate: false,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              leadingIcon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isRefreshing
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isOnline
                            ? Symbols.sync_rounded
                            : Symbols.cloud_off_rounded,
                        key: const ValueKey('icon'),
                        size: 20,
                      ),
              ),
              onPressed: isOnline && !_isRefreshing ? _doRefresh : null,
              child: Text(
                _isRefreshing
                    ? 'Syncing...'
                    : isOnline
                    ? 'Sync Scouting Data'
                    : 'Sync Unavailable (Offline)',
              ),
            ),

            if (canProvision)
              MenuItemButton(
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
                leadingIcon: const Icon(Symbols.qr_code_rounded, size: 20),
                onPressed: () => context.push('/device_provisioning'),
                child: const Text('Provision Device'),
              ),

            const Divider(height: 16),

            MenuItemButton(
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              leadingIcon: const Icon(Symbols.settings_rounded, size: 20),
              onPressed: () => context.push('/settings'),
              child: const Text('Settings'),
            ),

            SubmenuButton(
              // TODO: make this animated again once this param is added to flutter stable
              // animated: true,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              menuStyle: MenuStyle(
                elevation: const WidgetStatePropertyAll(8.0),
                backgroundColor: WidgetStatePropertyAll(
                  colorScheme.surfaceContainerHighest,
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              submenuIcon: const WidgetStatePropertyAll(
                Icon(Symbols.chevron_right_rounded, size: 16),
              ),
              leadingIcon: const Icon(Symbols.dark_mode_rounded, size: 20),
              menuChildren: [
                for (final mode in ThemeMode.values)
                  MenuItemButton(
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                    trailingIcon: mode == themeMode
                        ? Icon(
                            Symbols.check_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : const SizedBox(width: 20),
                    onPressed: () async {
                      await ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(mode);
                    },
                    leadingIcon: Icon(switch (mode) {
                      ThemeMode.light => Symbols.light_mode_rounded,
                      ThemeMode.dark => Symbols.dark_mode_rounded,
                      ThemeMode.system => Symbols.routine_rounded,
                    }, size: 20),
                    child: Text(switch (mode) {
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                      ThemeMode.system => 'System',
                    }),
                  ),
              ],
              child: const Text('Theme'),
            ),

            const Divider(height: 16),

            MenuItemButton(
              closeOnActivate: false,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                foregroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.error,
                ),
              ),
              leadingIcon: Icon(
                Symbols.logout_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                final confirmed =
                    await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sign Out'),
                        content: const Text(
                          'Are you sure you want to sign out?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .error,
                            ),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    ) ??
                    false;

                if (confirmed && context.mounted) {
                  final auth = await ref.read(authProvider.future);
                  await auth.logout(federated: true);
                }
              },
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPermissionsBanner extends StatelessWidget {
  const _NoPermissionsBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Symbols.warning_rounded,
                color: colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You don\'t have any permissions yet and won\'t be able to use the app. Ask an Apps lead or Executive to give you access.',
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
