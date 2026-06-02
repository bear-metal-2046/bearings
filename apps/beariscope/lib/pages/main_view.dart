import 'package:beariscope/pages/scout_audit/scout_audit_provider.dart';
import 'package:beariscope/pages/settings/appearance_settings_page.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/providers/user_profile_provider.dart';
import 'package:services/widgets/profile_picture.dart';

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

  bool _isRefreshing = false;

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
      route: '/picklists',
      icon: LucideIcons.notebookText,
      label: 'Picklists',
      group: 'General',
      requiredPermissions: [
        PermissionKey.picklistsManage,
        PermissionKey.picklistsRead,
      ],
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
      route: '/pits_scouting',
      icon: LucideIcons.wrench,
      label: 'Pits Scouting',
      group: 'Scouting',
      requiredPermissions: [PermissionKey.pitsUpload, PermissionKey.pitsRead],
    ),
    const _NavItem(
      route: '/match_lookup',
      icon: LucideIcons.scale,
      label: 'Match Compare',
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
    return switch (ref.watch(scoutAuditSnapshotProvider)) {
      AsyncData(:final value) =>
        value.incompleteMatches.length +
            value.notInTba.length +
            value.duplicates.length +
            value.incorrect.length,
      _ => 0,
    };
  }

  bool _isOnline() {
    return switch (ref.watch(connectivityProvider)) {
      AsyncData(:final value) => value,
      _ => true,
    };
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

        final drawerContent = NavigationDrawer(
          selectedIndex: selectedIndex >= 0 ? selectedIndex : null,
          onDestinationSelected: (index) =>
              _onDestinationSelected(index, isDesktop, visibleNavItems),
          footer: Column(
            children: [
              const Divider(height: 2),
              _buildBottomComponents(isOnline: _isOnline()),
            ],
          ),
          children: _buildNavChildren(visibleNavItems),
        );

        final childContent = isDesktop
            ? Row(
                children: [
                  drawerContent,
                  Expanded(child: widget.child),
                ],
              )
            : widget.child;

        final authMeLoaded = ref.watch(authMeProvider).hasValue;

        final hasNoPermissions =
            authMeLoaded &&
            permissionChecker != null &&
            permissionChecker.permissions.isEmpty;

        return Scaffold(
          key: _scaffoldKey,
          drawer: isDesktop ? null : drawerContent,
          drawerEnableOpenDragGesture: allowDrawerGesture,
          drawerBarrierDismissible: !isDesktop,
          body: MainViewController(
            isDesktop: isDesktop,
            openDrawer: () {
              _scaffoldKey.currentState?.openDrawer();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasNoPermissions) const _NoPermissionsBanner(),
                Expanded(child: childContent),
              ],
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

  List<Widget> _buildNavChildren(List<_NavItem> visibleNavItems) {
    final children = <Widget>[];

    children.add(
      SizedBox(
        height: kToolbarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
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
                    Text(
                      'Beariscope',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    children.add(
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Divider(height: 2),
      ),
    );

    String? currentGroup;
    for (final entry in visibleNavItems.indexed) {
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
          icon: Badge(
            isLabelVisible: item.badgeCount != null && item.badgeCount! > 0,
            label: item.badgeCount != null
                ? Text(item.badgeCount.toString())
                : null,
            child: Icon(item.icon, weight: 600),
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
          animated: true,
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
                  return SubmenuButton(
                    animated: true,
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
                      const Icon(LucideIcons.chevronRight, size: 16),
                    ),
                    leadingIcon: const Icon(LucideIcons.calendarCog, size: 20),
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
                            leadingIcon: Icon(customIconFor(e), size: 20),
                            trailingIcon: e.key == currentEventKey
                                ? Icon(
                                    LucideIcons.check,
                                    size: 20,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  )
                                : const SizedBox(width: 20),
                            onPressed: () {
                              ref
                                  .read(currentEventProvider.notifier)
                                  .setEventKey(e.key);
                            },
                            child: Text(e.displayName.shortenEventName()),
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
                  leadingIcon: const Icon(LucideIcons.circleAlert, size: 20),
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
                        isOnline ? LucideIcons.cloud : LucideIcons.cloudOff,
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
                leadingIcon: const Icon(LucideIcons.qrCode, size: 20),
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
              leadingIcon: const Icon(LucideIcons.settings, size: 20),
              onPressed: () => context.push('/settings'),
              child: const Text('Settings'),
            ),

            SubmenuButton(
              animated: true,
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
                Icon(LucideIcons.chevronRight, size: 16),
              ),
              leadingIcon: const Icon(LucideIcons.sunMoon, size: 20),
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
                            LucideIcons.check,
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
                LucideIcons.logOut,
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
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
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
                LucideIcons.circleAlert,
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

const _eventNameReplacements = {
  'District Championship': 'DCMP',
  'State Championship': 'State CMP',
  'Provincial Championship': 'PCMP',

  'Pacific Northwest FIRST': 'PNW',
  'FIRST in Michigan': 'FIM',
  'FIRST in Texas': 'FIT',
  'FIRST Indiana': 'FIN',
  'FIRST Mid-Atlantic': 'FMA',
  'FIRST North Carolina': 'FNC',
  'FIRST South Carolina': 'FSC',
  'FIRST Wisconsin': 'WIN',
  'New England FIRST': 'NE',
  'Peachtree': 'PCH',
  'FIRST Ontario': 'ONT',
  'FIRST Israel': 'ISR',

  'PNW District': 'PNW',
  'FIM District': 'FIM',
  'FIT District': 'FIT',
  'FCH District': 'FCH',
  'FIN District': 'FIN',
  'FMA District': 'FMA',
  'FNC District': 'FNC',
  'FSC District': 'FSC',
  'WIN District': 'WIN',
  'NE District': 'NE',
  'PCH District': 'PCH',
  'ONT District': 'ONT',
  'ISR District': 'ISR',
};

extension EventNameShortener on String {
  String shortenEventName() {
    var text = replaceAll(RegExp(r'\s+presented.*$', caseSensitive: false), '');

    for (final entry in _eventNameReplacements.entries) {
      text = text.replaceAll(
        RegExp(RegExp.escape(entry.key), caseSensitive: false),
        entry.value,
      );
    }

    return text;
  }
}

IconData customIconFor(EventOption event) {
  final name = event.displayName.toLowerCase();

  // Worlds divisions
  if (name.contains('archimedes')) {
    return LucideIcons.pi;
  }

  if (name.contains('curie')) {
    return LucideIcons.radiation;
  }

  if (name.contains('daly')) {
    return LucideIcons.flaskConical;
  }

  if (name.contains('galileo')) {
    return LucideIcons.telescope;
  }

  if (name.contains('hopper')) {
    return LucideIcons.bug;
  }

  if (name.contains('johnson')) {
    return LucideIcons.rocket;
  }

  if (name.contains('milstein')) {
    return LucideIcons.biohazard;
  }

  if (name.contains('newton')) {
    return LucideIcons.apple;
  }

  // FIM
  if (name.contains('dte')) {
    return LucideIcons.solarPanel;
  }
  if (name.contains('consumers')) {
    return LucideIcons.zap;
  }
  if (name.contains('hemlock')) {
    return LucideIcons.microchip;
  }
  if (name.contains('aptiv')) {
    return LucideIcons.factory;
  }

  // FIT
  if (name.contains('mercury')) {
    return LucideIcons.globe;
  }
  if (name.contains('apollo')) {
    return LucideIcons.sparkles;
  }

  // NE
  if (name.contains('burns')) {
    return LucideIcons.bookMarked;
  }
  if (name.contains('newsom')) {
    return LucideIcons.amphora;
  }

  // ONT
  if (name.contains('technology')) {
    return LucideIcons.cpu;
  }

  if (name.contains('science')) {
    return LucideIcons.atom;
  }

  // Other
  if (name.contains('chezy')) {
    return LucideIcons.hamburger;
  }
  if (name.contains('bordie')) {
    return LucideIcons.bird;
  }
  if (name.contains('block party')) {
    return LucideIcons.cuboid;
  }
  if (name.contains('girl') && name.contains('generation')) {
    return LucideIcons.venus;
  }
  if (name.contains('stormsurge')) {
    return LucideIcons.cloudLightning;
  }

  return event.leadingIcon;
}
