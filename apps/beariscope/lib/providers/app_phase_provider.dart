import 'package:beariscope/providers/app_boot_provider.dart';
import 'package:beariscope/providers/post_sign_in_flow_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/auth_provider.dart';

/// Top-level navigation phase of the app.
///
/// This is the single source of truth that drives GoRouter's redirect,
/// replacing the previous chain of individual provider checks.
enum AppPhase {
  /// Boot sequence still running, or user is actively authenticating
  /// (login/signup in progress).  Shows the splash screen.
  splashing,

  /// Boot is complete and user is not authenticated.
  /// Shows the welcome / sign-up screen.
  loginRequired,

  /// User is authenticated but still needs post-sign-in onboarding
  /// (set real name, verify email, etc.).
  onboarding,

  /// Normal operation — user is authenticated and onboarding is done.
  ready,
}

/// Computes the current [AppPhase] from the underlying auth/boot/onboarding
/// state providers.
final appPhaseProvider = Provider<AppPhase>((ref) {
  final bootReady = ref.watch(appBootProvider).isReady;
  final authStatus = ref.watch(authStatusProvider);
  final pendingOnboarding = ref.watch(postSignInFlowPendingProvider);

  return switch ((bootReady, authStatus, pendingOnboarding)) {
    // Still booting or mid-authentication → splash
    (false, _, _) || (_, AuthStatus.authenticating, _) => AppPhase.splashing,
    // Boot done, not authenticated → welcome
    (true, AuthStatus.unauthenticated, _) => AppPhase.loginRequired,
    // Authenticated with pending onboarding
    (true, AuthStatus.authenticated, true) => AppPhase.onboarding,
    // Authenticated, no onboarding needed
    (true, AuthStatus.authenticated, false) => AppPhase.ready,
  };
});
