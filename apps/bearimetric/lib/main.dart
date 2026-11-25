import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:bearimetric/data/local_data.dart';
import 'package:bearimetric/data/scouting_store.dart';
import 'package:core/core.dart' show ScoutPosition;
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
        persistGroveOnWebProvider.overrideWithValue(true),
        groveSubjectProvider.overrideWith((ref) async {
          if (ref.watch(authStatusProvider) != AuthStatus.authenticated) {
            return null;
          }
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
        redirect: (_, state) =>
            state.extra is ScoutingUploadTarget ||
                ref.read(scoutingSessionProvider).isConfigured
            ? null
            : '/config',
        builder: (context, state) {
          final target = state.extra;
          if (target is ScoutingUploadTarget) {
            return GamePackScoutPage(
              key: ValueKey(target.match),
              event: target.event,
              position: ScoutPosition.fromPosIndex(target.station)!,
              scoutId: target.scout,
              initialMatchId: target.match,
              onChooseMatch: () => context.go('/config'),
              onBack: () => context.go('/config'),
            );
          }
          final session = ref.read(scoutingSessionProvider);
          return GamePackScoutPage(
            event: session.event!.key,
            position: session.position!,
            scoutId: session.scout!.uuid,
            initialMatchId: session.matchId!,
            onChooseMatch: () => context.go('/match-select'),
            onMatchSelected: ref
                .read(scoutingSessionProvider.notifier)
                .selectMatch,
            onBack: () {
              ref.read(scoutingSessionProvider.notifier).exitToScoutSelect();
              context.go('/scout');
            },
          );
        },
      ),
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
    if (ref.watch(authStatusProvider) == AuthStatus.authenticated) {
      ref.watch(scoutingStoreProvider);
    }
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
