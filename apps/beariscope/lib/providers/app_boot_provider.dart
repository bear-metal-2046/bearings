import 'package:flutter/foundation.dart';

import 'package:beariscope/providers/post_sign_in_flow_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/user_profile_provider.dart';

enum AppBootStage { initializing, restoringSession, connecting, ready }

extension AppBootStageExtention on AppBootStage {
  String get label => switch (this) {
    AppBootStage.initializing => 'Starting up...',
    AppBootStage.restoringSession => 'Authenticating...',
    AppBootStage.connecting => 'Establishing connection...',
    AppBootStage.ready => 'Crescendo!',
  };

  double get progress => switch (this) {
    AppBootStage.initializing => 0.1,
    AppBootStage.restoringSession => 0.3,
    AppBootStage.connecting => 0.7,
    AppBootStage.ready => 1.0,
  };
}

class AppBootState {
  final AppBootStage stage;
  final String message;
  final double progress;

  const AppBootState({
    required this.stage,
    required this.message,
    required this.progress,
  });

  factory AppBootState.initial() {
    return AppBootState(
      stage: AppBootStage.initializing,
      message: AppBootStage.initializing.label,
      progress: 0.0,
    );
  }

  factory AppBootState.stage(AppBootStage stage) {
    return AppBootState(
      stage: stage,
      message: stage.label,
      progress: stage.progress,
    );
  }

  bool get isReady => stage == AppBootStage.ready;
}

class AppBootNotifier extends Notifier<AppBootState> {
  Future<void>? _boot;

  @override
  AppBootState build() => AppBootState.initial();

  Future<void> start() => _boot ??= _start();

  Future<void> _start() async {
    Auth? restored;
    try {
      state = AppBootState.stage(AppBootStage.restoringSession);
      final auth = await ref.read(authProvider.future);
      await auth.trySilentLogin();
      if (!ref.mounted) return;

      if (ref.read(authStatusProvider) == AuthStatus.authenticated) {
        restored = auth;
        state = AppBootState.stage(AppBootStage.connecting);
        await ref.read(connectHoneycombProvider)();
      }
    } catch (error) {
      debugPrint('Could not finish Beariscope startup: $error');
    }
    if (!ref.mounted) return;

    state = AppBootState.stage(AppBootStage.ready);
    if (restored != null &&
        ref.read(authStatusProvider) == AuthStatus.authenticated) {
      _resumeOnboarding(restored);
    }
  }

  void _resumeOnboarding(Auth session) {
    final subject = session.user?.subject;
    if (subject == null) return;
    late final ProviderSubscription<AsyncValue<UserInfo?>> profile;
    late final ProviderSubscription<AuthStatus> auth;
    void stop() {
      profile.close();
      auth.close();
    }

    auth = ref.listen(authStatusProvider, (_, status) {
      if (status != AuthStatus.authenticated) stop();
    });
    void check(AsyncValue<UserInfo?> value) {
      final user = value.value;
      if (user == null) return;
      stop();
      if (session.user?.subject == subject && checkNeedsOnboarding(user)) {
        ref.read(postSignInFlowPendingProvider.notifier).setPending();
      }
    }

    profile = ref.listen(userInfoProvider, (_, next) => check(next));
    check(profile.read());
  }
}

/// Returns `true` when [userInfo] still needs post-sign-in onboarding
/// (e.g. the user hasn't set their real name or verified their email yet).
bool checkNeedsOnboarding(UserInfo userInfo) {
  final email = userInfo.email?.trim();
  final normalizedName = userInfo.name?.trim().toLowerCase();
  final normalizedEmail = email?.toLowerCase();

  final needsRealName =
      normalizedName == null ||
      normalizedName.isEmpty ||
      (normalizedEmail != null && normalizedName == normalizedEmail);

  final needsEmailVerification = userInfo.emailVerified != true;

  return needsRealName || needsEmailVerification;
}

final appBootProvider = NotifierProvider<AppBootNotifier, AppBootState>(
  AppBootNotifier.new,
);
