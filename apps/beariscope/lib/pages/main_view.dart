import 'package:ui/widgets/bearings_alert_dialog.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_provider.dart';
import 'package:beariscope/providers/appearance_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/widgets/server_connection_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/providers/user_profile_provider.dart';
import 'package:services/widgets/profile_picture.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/pits_scouting_provider.dart';
import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:ui/widgets/bearings_spinner.dart';

class _NavItem {
  final String route;
  final IconData icon;
  final String label;
  final String group;
  final List<String> requiredPermissions;
  final int? badgeCount;

  const _NavItem({
    required this.route,
    required this.icon,
    required this.label,
    required this.group,
    this.requiredPermissions = const [],
    this.badgeCount,
  });

  bool canAccess(PermissionChecker? checker) {
    if (requiredPermissions.isEmpty) return true;

    return checker != null && requiredPermissions.any(checker.hasPermission);
  }

  _NavItem copyWith({int? badgeCount}) {
    return _NavItem(
      route: route,
      icon: icon,
      label: label,
      group: group,
      requiredPermissions: requiredPermissions,
      badgeCount: badgeCount,
    );
  }
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

  static MainViewController of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MainViewController>()!;
  }

  @override
  bool updateShouldNotify(MainViewController oldWidget) {
    return isDesktop != oldWidget.isDesktop;
  }
}

class MainView extends ConsumerStatefulWidget {
  final Widget child;

  const MainView({super.key, required this.child});

  @override
  ConsumerState<MainView> createState() => _MainViewState();
}

class _MainViewState extends ConsumerState<MainView> {
  static const _desktopBreakpoint = 700.0;

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static final List<_NavItem> _navItems = [
    const _NavItem(
      route: '/up_next',
      icon: LucideIcons.calendar,
      label: 'Up Next',
      group: 'General',
    ),
    const _NavItem(
      route: '/team_lookup',
      icon: LucideIcons.bot,
      label: 'Teams',
      group: 'General',
    ),
    const _NavItem(
      route: '/pits_scouting',
      icon: LucideIcons.wrench,
      label: 'Pits',
      group: 'General',
      requiredPermissions: [PermissionKey.pitsUpload, PermissionKey.pitsRead],
    ),
    const _NavItem(
      route: '/picklists',
      icon: LucideIcons.notebookText,
      label: 'Picklists',
      group: 'General',
    ),
    const _NavItem(
      route: '/scout_audit',
      icon: LucideIcons.clipboardCheck,
      label: 'Scout Audit',
      group: 'Data',
      requiredPermissions: [PermissionKey.matchCorrect],
    ),
    const _NavItem(
      route: '/export',
      icon: LucideIcons.sheet,
      label: 'Export Data',
      group: 'Data',
    ),
    const _NavItem(
      route: '/match_lookup',
      icon: LucideIcons.scale,
      label: 'Match Compare',
      group: 'Utilities',
    ),
    const _NavItem(
      route: '/flash_cards',
      icon: LucideIcons.layers,
      label: 'Flash Cards',
      group: 'Utilities',
    ),
  ];

  List<_NavItem> _buildNavItems({
    required int scoutAuditIssueCount,
    required PermissionChecker? permissionChecker,
  }) {
    return _navItems
        .map((item) {
          if (item.route == '/scout_audit') {
            return item.copyWith(
              badgeCount: scoutAuditIssueCount > 0
                  ? scoutAuditIssueCount
                  : null,
            );
          }

          return item;
        })
        .where((item) => item.canAccess(permissionChecker))
        .toList();
  }

  String get _location {
    return GoRouterState.of(context).uri.toString();
  }

  int _selectedIndexFor(List<_NavItem> items) {
    return items.indexWhere((item) => _location.startsWith(item.route));
  }

  bool _isAtTopLevelFor(List<_NavItem> items) {
    return items.any((item) => item.route == _location);
  }

  void _onDestinationSelected(int index, bool isDesktop, List<_NavItem> items) {
    if (index < 0 || index >= items.length) return;

    final selectedItem = items[index];
    final isDrawerOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;

    if (_location.startsWith(selectedItem.route)) {
      if (!isDesktop && isDrawerOpen) {
        Navigator.pop(context);
      }
      return;
    }

    if (!isDesktop && isDrawerOpen) {
      Navigator.pop(context);
    }

    context.go(selectedItem.route);
  }

  int _scoutAuditIssueCount() {
    final audit = ref.watch(scoutAuditSnapshotProvider).value;
    return audit == null
        ? 0
        : audit.incompleteMatches.length +
              audit.notInTba.length +
              audit.duplicates.length +
              audit.incorrect.length;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;

        final permissionChecker = ref.watch(permissionCheckerProvider);

        final visibleNavItems = _buildNavItems(
          scoutAuditIssueCount: _scoutAuditIssueCount(),
          permissionChecker: permissionChecker,
        );

        final selectedIndex = _selectedIndexFor(visibleNavItems);

        final isAtTopLevel = _isAtTopLevelFor(visibleNavItems);

        final allowDrawerGesture =
            !isDesktop &&
            isAtTopLevel &&
            ModalRoute.of(context)?.isCurrent == true;

        final drawerContent = _buildSidebar(
          visibleNavItems: visibleNavItems,
          selectedIndex: selectedIndex,
          isDesktop: isDesktop,
        );

        final childContent = isDesktop
            ? Row(
                children: [
                  drawerContent,
                  Expanded(child: widget.child),
                ],
              )
            : widget.child;

        final access = ref.watch(groveAccessProvider);
        final result = access.value;
        final hasNoPermissions =
            result?.complete == true &&
            permissionChecker?.permissions.isEmpty == true;
        final accessError = access.asError?.error;
        final accessMessage = result?.updateRequired == true
            ? 'Update Beariscope to load permissions.'
            : accessError is GroveException && accessError.code == 'forbidden'
            ? 'The server denied access. Contact a team administrator.'
            : null;

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
            drawer: isDesktop ? null : drawerContent,
            drawerEnableOpenDragGesture: allowDrawerGesture,
            drawerBarrierDismissible: !isDesktop,
            body: MainViewController(
              isDesktop: isDesktop,
              openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasNoPermissions) const _NoPermissionsBanner(),
                  if (accessMessage != null)
                    _NoPermissionsBanner(message: accessMessage),
                  Expanded(child: childContent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar({
    required List<_NavItem> visibleNavItems,
    required int selectedIndex,
    required bool isDesktop,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 280,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 12, 0),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/beariscope_head.svg',
                      width: 24,
                      colorFilter: ColorFilter.mode(
                        colorScheme.primary,
                        BlendMode.srcATop,
                      ),
                    ),

                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Beariscope',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const ServerConnectionButton(),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                  children: _buildNavChildren(
                    visibleNavItems,
                    selectedIndex: selectedIndex,
                    isDesktop: isDesktop,
                  ),
                ),
              ),
              const Divider(height: 2),
              _buildBottomComponents(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNavChildren(
    List<_NavItem> visibleNavItems, {
    required int selectedIndex,
    required bool isDesktop,
  }) {
    final children = <Widget>[];
    String? currentGroup;

    for (final entry in visibleNavItems.indexed) {
      final index = entry.$1;
      final item = entry.$2;
      if (item.group != currentGroup) {
        if (currentGroup != null) {
          children.add(const Divider(height: 20, indent: 12, endIndent: 12));
        }
        currentGroup = item.group;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(12, children.isEmpty ? 12 : 0, 12, 6),
            child: Text(
              currentGroup,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        );
      }

      children.add(
        _buildNavDestination(
          item: item,
          selected: index == selectedIndex,
          onTap: () =>
              _onDestinationSelected(index, isDesktop, visibleNavItems),
        ),
      );
    }

    return children;
  }

  Widget _buildNavDestination({
    required _NavItem item,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? colorScheme.surfaceContainerHighest
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 18,
                    weight: 600,
                    color: selected ? colorScheme.primary : foregroundColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected ? colorScheme.primary : foregroundColor,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (item.badgeCount case final badgeCount?)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        badgeCount.toString(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomComponents() {
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
        ? 'At ${selectedEvent.shortName}'
        : 'No event selected';

    return SafeArea(
      top: false,
      child: BearingsPopupMenu(
        alignmentOffset: const Offset(12, 0),
        triggerBuilder: (context, controller, focusNode) {
          final isOpen = controller.isOpen;

          return Material(
            color: isOpen
                ? colorScheme.surfaceContainerHighest
                : Colors.transparent,
            child: InkWell(
              focusNode: focusNode,
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
                              subtitleText,
                              key: ValueKey(subtitleText),
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
                          ? LucideIcons.chevronsDownUp
                          : LucideIcons.chevronsUpDown,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
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
                return BearingsSubmenu(
                  leadingIcon: const Icon(LucideIcons.calendarCog, size: 20),
                  menuChildren: pickerEvents
                      .map(
                        (e) => BearingsMenuItem(
                          leadingIcon: Icon(e.leadingIcon, size: 20),
                          selected: e.key == currentEventKey,
                          onPressed: () {
                            ref
                                .read(currentEventProvider.notifier)
                                .setEventKey(e.key);
                          },
                          child: Text(e.shortName),
                        ),
                      )
                      .toList(),
                  child: Text('At ${currentEvent.shortName}'),
                );
              },
              loading: () => const BearingsMenuItem(
                onPressed: null,
                leadingIcon: SizedBox(
                  width: 20,
                  height: 20,
                  child: BearingsSpinner(strokeWidth: 2),
                ),
                child: Text('Loading events...'),
              ),
              error: (e, s) => BearingsMenuItem(
                onPressed: () => retryCompetitionEvents(
                  ProviderScope.containerOf(context, listen: false),
                  (year: DateTime.now().year, team: 'frc2046'),
                ),
                leadingIcon: const Icon(LucideIcons.circleAlert, size: 20),
                child: const Text('Failed to load events. Retry?'),
              ),
            ),

          if (canSelectEvent && eventsAsync != null) const Divider(height: 16),

          if (canProvision)
            BearingsMenuItem(
              leadingIcon: const Icon(LucideIcons.qrCode, size: 20),
              onPressed: () => context.push('/device_provisioning'),
              child: const Text('Provision Device'),
            ),

          const Divider(height: 16),

          BearingsMenuItem(
            leadingIcon: const Icon(LucideIcons.settings, size: 20),
            onPressed: () => context.push('/settings'),
            child: const Text('Settings'),
          ),

          BearingsSubmenu(
            leadingIcon: const Icon(LucideIcons.sunMoon, size: 20),
            menuChildren: [
              for (final mode in ThemeMode.values)
                BearingsMenuItem(
                  selected: mode == themeMode,
                  onPressed: () async {
                    await ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(mode);
                  },
                  leadingIcon: Icon(switch (mode) {
                    ThemeMode.light => LucideIcons.sun,
                    ThemeMode.dark => LucideIcons.moon,
                    ThemeMode.system => LucideIcons.eclipse,
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

          BearingsMenuItem(
            closeOnActivate: false,
            destructive: true,
            leadingIcon: const Icon(LucideIcons.logOut, size: 20),
            onPressed: () async {
              final confirmed =
                  await BearingsAlertDialog.show<bool>(
                    context: context,
                    title: 'Sign Out',
                    message: 'Are you sure you want to sign out?',
                    actions: const [
                      BearingsAlertAction(label: 'Cancel', result: false),
                      BearingsAlertAction(
                        label: 'Sign Out',
                        result: true,
                        role: BearingsAlertActionRole.primary,
                      ),
                    ],
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
    );
  }
}

class _NoPermissionsBanner extends StatelessWidget {
  const _NoPermissionsBanner({
    this.message =
        'No permissions assigned. Ask a team administrator for access.',
  });

  final String message;

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
                LucideIcons.circleAlert,
                color: colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
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
