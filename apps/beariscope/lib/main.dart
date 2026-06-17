import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:beariscope/pages/auth/post_sign_in_onboarding_page.dart';
import 'package:beariscope/pages/auth/splash_screen.dart';
import 'package:beariscope/pages/auth/welcome_page.dart';
import 'package:beariscope/pages/corrections/corrections_page.dart';
import 'package:beariscope/pages/device_provisioning/device_provisioning_page.dart';
import 'package:beariscope/pages/export/export_page.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/picklists/picklists_create_page.dart';
import 'package:beariscope/pages/picklists/picklists_page.dart';
import 'package:beariscope/pages/pits_scouting/pits_scouting_home_page.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_page.dart';
import 'package:beariscope/pages/settings/about_settings_page.dart';
import 'package:beariscope/pages/settings/account_settings_page.dart';
import 'package:beariscope/pages/settings/advanced_settings_page.dart';
import 'package:beariscope/pages/settings/appearance_settings_page.dart';
import 'package:beariscope/pages/settings/notifications_settings_page.dart';
import 'package:beariscope/pages/settings/scout_selection_page.dart';
import 'package:beariscope/pages/settings/settings_page.dart';
import 'package:beariscope/pages/settings/team_role_settings_page.dart';
import 'package:beariscope/pages/team_lookup/team_lookup_page.dart';
import 'package:beariscope/pages/up_next/match_preview_page.dart';
import 'package:beariscope/pages/up_next/up_next_page.dart';
import 'package:beariscope/pages/utilities/utilities_page.dart';
import 'package:beariscope/providers/app_boot_provider.dart';
import 'package:beariscope/providers/post_sign_in_flow_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:beariscope/utils/platform_utils_stub.dart'
    if (dart.library.io) 'package:beariscope/utils/platform_utils.dart';
import 'package:beariscope/utils/window_size_stub.dart'
    if (dart.library.io) 'package:window_size/window_size.dart';
import 'package:core/providers/device_info_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/release/release_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beariscope/pages/match_lookup/match_lookup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();
  setUrlStrategy(PathUrlStrategy());

  await Hive.initFlutter();
  await Hive.openBox('api_cache');
  await Hive.openBox<String>('scouting_data');

  // happy easter
  if (Random().nextInt(500) == 0) {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/jingle.wav'), volume: 1000);
  }

  if (PlatformUtils.isDesktop()) {
    setWindowMinSize(const Size(500, 600));
    setWindowMaxSize(Size.infinite);
    setWindowTitle('Beariscope');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        auth0ConfigProvider.overrideWith((ref) {
          return const Auth0Config(
            domain: 'bearmetal2046.us.auth0.com',
            clientId: 'ORLhqJbHiTfgdF3Q8hqIbmdwT1wTkkP7',
            audience: 'ORLhqJbHiTfgdF3Q8hqIbmdwT1wTkkP7',
            redirectUris: {
              DeviceOS.ios: 'org.tahomarobotics.beariscope://callback',
              DeviceOS.macos: 'org.tahomarobotics.beariscope://callback',
              DeviceOS.android: 'org.tahomarobotics.beariscope://callback',
              DeviceOS.web: 'https://scout.bearmet.al/auth.html',
              DeviceOS.windows: 'http://localhost:4000/auth',
              DeviceOS.linux: 'http://localhost:4000/auth',
            },
            storageKeyPrefix: 'beariscope_',
          );
        }),
      ],
      child: const Beariscope(),
    ),
  );
}

class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(this.ref) {
    ref.listen(appBootProvider, (_, _) => notifyListeners());
    ref.listen(authStatusProvider, (_, _) => notifyListeners());
    ref.listen(postSignInFlowPendingProvider, (_, _) => notifyListeners());
    ref.listen(authMeProvider, (_, _) => notifyListeners());
  }

  final Ref ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomePage()),
      GoRoute(
        path: '/post_sign_in_onboarding',
        builder: (_, _) => const PostSignInOnboardingPage(),
      ),
      ShellRoute(
        builder: (_, _, child) => MainView(child: child),
        routes: [
          GoRoute(
            path: '/up_next',
            pageBuilder: (_, _) => const NoTransitionPage(child: UpNextPage()),
            routes: [
              GoRoute(
                path: ':matchKey',
                builder: (context, state) {
                  final matchKey = state.pathParameters['matchKey'] ?? '1';
                  return DriveTeamMatchPreviewPage(matchKey: matchKey);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/team_lookup',
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: TeamLookupPage()),
          ),
          GoRoute(
            path: '/match_lookup',
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: MatchLookupPage()),
          ),
          GoRoute(
            path: '/export',
            pageBuilder: (_, _) => const NoTransitionPage(child: ExportPage()),
          ),
          GoRoute(
            path: '/picklists',
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: PicklistsPage()),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, _) => const PicklistsCreatePage(),
              ),
            ],
          ),
          GoRoute(
            path: '/corrections',
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: CorrectionsPage()),
          ),
          GoRoute(
            path: '/scout_audit',
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: ScoutAuditPage()),
          ),
          GoRoute(
            path: '/pits_scouting',
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: PitsScoutingHomePage()),
          ),
          GoRoute(
            path: '/utilities',
            pageBuilder: (_, _) =>
                const NoTransitionPage(child: UtilitiesPage()),
          ),
        ],
      ),
      GoRoute(
        path: '/device_provisioning',
        builder: (_, _) => const DeviceProvisioningPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsPage(),
        routes: [
          GoRoute(
            path: 'account',
            builder: (_, _) => const AccountSettingsPage(),
          ),
          GoRoute(
            path: 'notifications',
            builder: (_, _) => const NotificationsSettingsPage(),
          ),
          GoRoute(
            path: 'appearance',
            builder: (_, _) => const AppearanceSettingsPage(),
          ),
          GoRoute(
            path: 'advanced',
            builder: (_, _) => const AdvancedSettingsPage(),
          ),
          GoRoute(
            path: 'user_selection',
            builder: (_, _) => const ScoutSelectionPage(),
          ),
          GoRoute(
            path: 'roles',
            builder: (_, _) => const TeamRoleSettingsPage(),
          ),
          GoRoute(path: 'about', builder: (_, _) => const AboutSettingsPage()),
          GoRoute(
            path: 'licenses',
            builder: (_, _) {
              return FutureBuilder<(PackageInfo, String)>(
                future:
                    Future.wait([
                      PackageInfo.fromPlatform(),
                      loadReleaseCodename(),
                    ]).then(
                      (results) => (
                        results[0] as PackageInfo,
                        (results[1] as String).trim(),
                      ),
                    ),
                builder: (context, snapshot) {
                  final version = snapshot.data?.$1.version ?? '...';
                  final codename = snapshot.data?.$2 ?? '';
                  final displayVersion =
                      codename.isNotEmpty && codename != 'Unknown'
                      ? '$version \u2014 $codename'
                      : version;
                  return LicensePage(
                    applicationName: 'Beariscope',
                    applicationVersion: displayVersion,
                  );
                },
              );
            },
          ),
        ],
      ),
    ],
    redirect: (_, state) {
      final auth = ref.read(authStatusProvider);
      final location = state.matchedLocation;
      final bootReady = ref.read(appBootProvider).isReady;

      // splash while booting
      if (!bootReady) {
        return location == '/splash' ? null : '/splash';
      }

      // go to welcome if not authed
      if (auth == AuthStatus.unauthenticated) {
        return location == '/welcome' ? null : '/welcome';
      }

      // if on welcome and authed then leave
      if (auth == AuthStatus.authenticated) {
        final pendingPostSignInFlow = ref.read(postSignInFlowPendingProvider);

        if (pendingPostSignInFlow) {
          if (location != '/post_sign_in_onboarding') {
            return '/post_sign_in_onboarding';
          }
          return null;
        }

        final isRoleManagementRoute = location == '/settings/roles';
        final isScoutManagementRoute = location == '/settings/user_selection';
        final isPicklistCreateRoute = location == '/picklists/create';
        final isDeviceProvisioningRoute = location == '/device_provisioning';
        final needsPermissions =
            isRoleManagementRoute ||
            isScoutManagementRoute ||
            isPicklistCreateRoute ||
            isDeviceProvisioningRoute;

        if (needsPermissions) {
          final authMe = ref.read(authMeProvider);

          if (authMe.isLoading) {
            return null;
          }

          final checker = ref.read(permissionCheckerProvider);

          if (isRoleManagementRoute) {
            final canManageRoles =
                checker?.hasPermission(PermissionKey.usersRolesManage) ?? false;
            if (!canManageRoles) return '/settings';
          }

          if (isScoutManagementRoute) {
            final canViewScouts =
                checker?.hasAnyPermission([
                  PermissionKey.scoutsRead,
                  PermissionKey.scoutsManage,
                ]) ??
                false;
            if (!canViewScouts) return '/settings';
          }

          if (isPicklistCreateRoute) {
            final canManagePicklists =
                checker?.hasPermission(PermissionKey.picklistsManage) ?? false;
            if (!canManagePicklists) return '/picklists';
          }

          if (isDeviceProvisioningRoute) {
            final canProvision =
                checker?.hasPermission(PermissionKey.deviceProvision) ?? false;
            if (!canProvision) return '/up_next';
          }
        }

        if (location == '/welcome' ||
            location == '/splash' ||
            location == '/post_sign_in_onboarding') {
          return '/up_next';
        }
      }

      return null;
    },
  );
});

class Beariscope extends ConsumerStatefulWidget {
  const Beariscope({super.key});

  @override
  ConsumerState<Beariscope> createState() => _BeariscopeState();
}

class _BeariscopeState extends ConsumerState<Beariscope> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize endpoint preference from SharedPreferences
      ref.read(honeycombEndpointPreferenceProvider.notifier).initialize();
      // Boot the app explicitly from splash before any route transitions.
      ref.read(appBootProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final accentColor = ref.watch(accentColorProvider);
    final deviceInfo = ref.read(deviceInfoProvider);

    // Wrap with builder to ensure HeroineController is available everywhere
    final app = Builder(
      builder: (context) {
        return MaterialApp.router(
          routerConfig: router,
          theme: _createTheme(Brightness.light, accentColor),
          darkTheme: _createTheme(Brightness.dark, accentColor),
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
        );
      },
    );

    if (deviceInfo.deviceOS == DeviceOS.macos) {
      return PlatformMenuBar(menus: _buildMacMenus(router), child: app);
    }

    return app;
  }
}

ThemeData _createTheme(Brightness brightness, Color accentColor) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: brightness,
  );

  final baseTheme = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: colorScheme,
    iconTheme: IconThemeData(
      fill: 0.0,
      weight: 600,
      color: colorScheme.onSurface,
    ),
    textTheme: GoogleFonts.nunitoSansTextTheme(
      ThemeData(brightness: brightness, colorScheme: colorScheme).textTheme,
    ),
  );

  return baseTheme.copyWith(
    appBarTheme: baseTheme.appBarTheme.copyWith(
      centerTitle: false,
      actionsPadding: EdgeInsets.symmetric(horizontal: 8),
      scrolledUnderElevation: 2,
      titleTextStyle: baseTheme.textTheme.titleLarge!.copyWith(
        fontFamily: 'Xolonium',
        fontSize: 20,
      ),
    ),
    dialogTheme: baseTheme.dialogTheme.copyWith(
      titleTextStyle: baseTheme.textTheme.headlineSmall!.copyWith(
        fontFamily: 'Xolonium',
        fontSize: 20,
      ),
    ),
  );
}

List<PlatformMenu> _buildMacMenus(GoRouter router) {
  return [
    PlatformMenu(
      label: 'Beariscope',
      menus: [
        PlatformMenuItem(
          label: 'About Beariscope',
          onSelected: () => router.push('/settings/about'),
        ),
        PlatformMenuItem(
          label: 'Settings',
          shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
          onSelected: () => router.push('/settings'),
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'View',
      menus: [
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.toggleFullScreen,
        ),
      ],
    ),
    PlatformMenu(
      label: 'Window',
      menus: [
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
        ),
      ],
    ),
  ];
}
