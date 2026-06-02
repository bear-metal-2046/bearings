import 'dart:async';

import 'package:beariscope/providers/post_sign_in_flow_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/providers/user_profile_provider.dart';

enum AppBootStage { initializing, restoringSession, loadingPermissions, ready }

extension AppBootStageExtention on AppBootStage {
  String get label => switch (this) {
    AppBootStage.initializing => 'Starting up...',
    AppBootStage.restoringSession => 'Authenticating...',
    AppBootStage.loadingPermissions => 'Authorizing...',
    AppBootStage.ready => 'Crescendo!',
  };

  double get progress => switch (this) {
    AppBootStage.initializing => 0.1,
    AppBootStage.restoringSession => 0.3,
    AppBootStage.loadingPermissions => 0.7,
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
  Completer<void>? _startCompleter;

  @override
  AppBootState build() => AppBootState.initial();

  Future<void> start() {
    if (state.isReady) {
      return Future.value();
    }

    final completer = _startCompleter;
    if (completer != null) {
      return completer.future;
    }

    final nextCompleter = Completer<void>();
    _startCompleter = nextCompleter;
    unawaited(_runBoot(nextCompleter));
    return nextCompleter.future;
  }

  Future<void> _runBoot(Completer<void> completer) async {
    try {
      state = AppBootState.stage(AppBootStage.initializing);
      await Future<void>.delayed(Duration.zero);

      state = AppBootState.stage(AppBootStage.restoringSession);
      final auth = await ref.read(authProvider.future);
      await auth.trySilentLogin();

      if (ref.read(authStatusProvider) == AuthStatus.authenticated) {
        ref.invalidate(userInfoProvider);
        final userInfo = await ref.read(userInfoProvider.future);
        if (userInfo != null && checkNeedsOnboarding(userInfo)) {
          ref.read(postSignInFlowPendingProvider.notifier).setPending();
        }
      }

      state = AppBootState.stage(AppBootStage.loadingPermissions);
      await ref.read(authMeProvider.future);

      state = AppBootState.stage(AppBootStage.ready);
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      if (identical(_startCompleter, completer)) {
        _startCompleter = null;
      }
    }
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
