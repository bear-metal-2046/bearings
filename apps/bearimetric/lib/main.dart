import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bearimetric/data/local_data.dart';
import 'package:bearimetric/pages/flow/config_page.dart';
import 'package:bearimetric/pages/flow/match_select_page.dart';
import 'package:bearimetric/pages/flow/scout_page.dart';
import 'package:bearimetric/pages/flow/gamepack_scout_page.dart';
import 'package:bearimetric/pages/flow/settings_page.dart';
import 'package:bearimetric/pages/provisioning_page.dart';
import 'package:bearimetric/pages/splash_screen.dart';
import 'package:bearimetric/providers/app_provider.dart';
import 'package:bearimetric/services/device_auth_service.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:ui/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadStorage();
  runApp(
    ProviderScope(
      overrides: [
        groveSubjectProvider.overrideWith((ref) async {
          if (ref.watch(authStatusProvider) != AuthStatus.authenticated)
            return null;
          final auth = await ref.watch(deviceAuthServiceProvider.future);
          return auth.groveSubject();
        }),
        groveAccessTokenProvider.overrideWith(
          (ref) => ({required forceRefresh}) async {
            final auth = await ref.read(deviceAuthServiceProvider.future);
            return auth.getAccessToken(forceRefresh: forceRefresh);
          },
        ),
      ],
      child: const MyApp(),
    ),
  );
}

final _deviceBootProvider = FutureProvider<void>((ref) async {
  try {
    await ref.read(honeycombEndpointPreferenceProvider.notifier).initialize();
    final service = await ref.read(deviceAuthServiceProvider.future);
    await service.initialize();
    if (ref.mounted &&
        ref.read(authStatusProvider) == AuthStatus.authenticated) {
      await ref.read(connectHoneycombProvider)();
    }
  } catch (error) {
    debugPrint('Could not finish Bearimetric startup: $error');
    if (ref.mounted &&
        ref.read(authStatusProvider) == AuthStatus.authenticating) {
      ref
          .read(authStatusProvider.notifier)
          .setStatus(AuthStatus.unauthenticated);
    }
  }
});

final routerProvider = Provider<GoRouter>((ref) {
  final authStatus = ref.watch(authStatusProvider.notifier);
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authStatus,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/provision',
        builder: (context, state) => const ProvisioningPage(),
      ),
      GoRoute(
        path: '/config',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: ConfigPage()),
        routes: [
          GoRoute(
            path: 'settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
      GoRoute(
        path: '/scout',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: ScoutPage()),
      ),
      GoRoute(
        path: '/match-select',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: MatchSelectPage()),
      ),
      GoRoute(
        path: '/gamepack-match',
        redirect: (_, _) =>
            ref.read(scoutingSessionProvider).isConfigured ? null : '/config',
        builder: (context, state) {
          final session = ref.read(scoutingSessionProvider);
          return GamePackScoutPage(
            event: session.event!.key,
            position: session.position!,
            scoutId: session.scout!.uuid,
            initialMatchNumber: session.matchNumber,
            onMatchChanged: ref
                .read(scoutingSessionProvider.notifier)
                .setMatchNumber,
            onBack: () => context.go('/match-select'),
          );
        },
      ),
      for (final path in ['/match/auto', '/match/tele', '/match/end', '/strat'])
        GoRoute(path: path, redirect: (_, _) => '/gamepack-match'),
    ],
    redirect: (context, state) {
      final auth = ref.read(authStatusProvider);
      final location = state.matchedLocation;

      if (ref.read(_deviceBootProvider).isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      // go to provision page if device is not provisioned
      if (auth == AuthStatus.unauthenticated) {
        return location == '/provision' ? null : '/provision';
      }

      // if on provision/splash and authed then go to config
      if (auth == AuthStatus.authenticated) {
        if (location == '/provision' || location == '/splash') {
          return '/config';
        }
      }

      return null;
    },
  );
  ref.listen(_deviceBootProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(honeycombSessionProvider);
    final router = ref.watch(routerProvider);
    final usePapyrusFont = ref.watch(papyrusFontProvider);
    final colorScheme = ref.watch(colorSchemeNotifierProvider);
    final brightness = ref.watch(brightnessNotifierProvider);

    return MaterialApp.router(
      title: 'Bearimetric',
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          FlutterMaterialScope(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        fontFamily: usePapyrusFont
            ? 'Papyrus'
            : GoogleFonts.googleSansFlex().fontFamily,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: colorScheme.seedColor,
          brightness: brightness,
        ),
      ),
    );
  }
}
