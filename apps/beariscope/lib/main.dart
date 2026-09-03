import 'package:beariscope/pages/auth/post_sign_in_onboarding_page.dart';
import 'package:beariscope/pages/auth/sign_up_flow_page.dart';
import 'package:beariscope/pages/auth/splash_screen.dart';
import 'package:beariscope/pages/auth/welcome_page.dart';
import 'package:beariscope/pages/device_provisioning/device_provisioning_page.dart';
import 'package:beariscope/pages/export/export_page.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/match_lookup/match_lookup_page.dart';
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
import 'package:beariscope/providers/app_phase_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:beariscope/utils/platform_utils_stub.dart'
    if (dart.library.io) 'package:beariscope/utils/platform_utils.dart';
import 'package:beariscope/utils/hive_storage.dart';
import 'package:beariscope/utils/window_size_stub.dart'
    if (dart.library.io) 'package:window_size/window_size.dart';
import 'package:core/providers/device_info_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/release/release_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();
  setUrlStrategy(PathUrlStrategy());

  await initializeHiveStorage();
  await Hive.openBox('api_cache');
  await Hive.openBox<String>('scouting_data');

  if (PlatformUtils.isDesktop()) {
    setWindowMinSize(const Size(400, 600));
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
    ref.listen(appPhaseProvider, (_, _) => notifyListeners());
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
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const WelcomePage(),
        routes: [
          GoRoute(path: 'sign_up', builder: (_, _) => const SignUpFlowPage()),
        ],
      ),
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
      final location = state.matchedLocation;
      final phase = ref.read(appPhaseProvider);

      // 1. Route based on app phase
      final phaseRedirect = switch (phase) {
        AppPhase.splashing => location == '/splash' ? null : '/splash',
        AppPhase.loginRequired =>
          location == '/welcome' || location.startsWith('/welcome/')
              ? null
              : '/welcome',
        AppPhase.onboarding =>
          location == '/post_sign_in_onboarding'
              ? null
              : '/post_sign_in_onboarding',
        AppPhase.ready => null,
      };

      if (phaseRedirect != null) return phaseRedirect;

      // 2. AppPhase.ready — permission guards for protected routes
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

      // 3. If ready and still on a phase-based route, go to main
      if (phase == AppPhase.ready &&
          (location == '/splash' ||
              location == '/welcome' ||
              location == '/post_sign_in_onboarding')) {
        return '/up_next';
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
          builder: (context, child) =>
              FlutterMaterialScope(child: child ?? const SizedBox.shrink()),
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
    splashFactory: NoSplash.splashFactory,
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (BuildContext context) =>
          const Icon(LucideIcons.chevronLeft),
      closeButtonIconBuilder: (BuildContext context) =>
          const Icon(LucideIcons.x),
      drawerButtonIconBuilder: (BuildContext context) =>
          const Icon(LucideIcons.menu),
      endDrawerButtonIconBuilder: (BuildContext context) =>
          const Icon(LucideIcons.ellipsisVertical),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(iconSize: 20),
    ),
    popupMenuTheme: const PopupMenuThemeData(iconSize: 22),
    iconTheme: IconThemeData(
      weight: 600,
      size: 22,
      color: colorScheme.onSurface,
    ),
    textTheme: _outfitTextTheme(
      ThemeData(brightness: brightness, colorScheme: colorScheme).textTheme,
    ),
  );

  return baseTheme.copyWith(
    appBarTheme: baseTheme.appBarTheme.copyWith(
      centerTitle: false,
      actionsPadding: EdgeInsets.symmetric(horizontal: 8),
      scrolledUnderElevation: 1,
      //   titleTextStyle: baseTheme.textTheme.titleLarge!.copyWith(
      //     fontFamily: 'Xolonium',
      //     fontSize: 20,
      //   ),
      // ),
      // dialogTheme: baseTheme.dialogTheme.copyWith(
      //   titleTextStyle: baseTheme.textTheme.headlineSmall!.copyWith(
      //     fontFamily: 'Xolonium',
      //     fontSize: 20,
      //   ),
    ),
  );
}

// TEMP STUFF UNTIL GOOGLE_FONTS UPDATES TO BE COMPATIBLE WITH MATERIAL_UI
TextTheme _outfitTextTheme(TextTheme textTheme) {
  return TextTheme(
    displayLarge: GoogleFonts.outfit(textStyle: textTheme.displayLarge),
    displayMedium: GoogleFonts.outfit(textStyle: textTheme.displayMedium),
    displaySmall: GoogleFonts.outfit(textStyle: textTheme.displaySmall),
    headlineLarge: GoogleFonts.outfit(textStyle: textTheme.headlineLarge),
    headlineMedium: GoogleFonts.outfit(textStyle: textTheme.headlineMedium),
    headlineSmall: GoogleFonts.outfit(textStyle: textTheme.headlineSmall),
    titleLarge: GoogleFonts.outfit(textStyle: textTheme.titleLarge),
    titleMedium: GoogleFonts.outfit(textStyle: textTheme.titleMedium),
    titleSmall: GoogleFonts.outfit(textStyle: textTheme.titleSmall),
    bodyLarge: GoogleFonts.outfit(textStyle: textTheme.bodyLarge),
    bodyMedium: GoogleFonts.outfit(textStyle: textTheme.bodyMedium),
    bodySmall: GoogleFonts.outfit(textStyle: textTheme.bodySmall),
    labelLarge: GoogleFonts.outfit(textStyle: textTheme.labelLarge),
    labelMedium: GoogleFonts.outfit(textStyle: textTheme.labelMedium),
    labelSmall: GoogleFonts.outfit(textStyle: textTheme.labelSmall),
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
