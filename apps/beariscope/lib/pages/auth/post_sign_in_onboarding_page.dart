import 'package:beariscope/providers/post_sign_in_flow_provider.dart';
import 'package:beariscope/widgets/step_flow.dart';
import 'package:beariscope/widgets/step_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/user_profile_provider.dart';

/// Steps the user through post-sign-in onboarding tasks (set real name, verify
/// email) using the same step-flow shell as [SignUpFlowPage].
///
/// Steps are only shown if the user's profile indicates they are needed (e.g.
/// no real name set, email not yet verified).  The flow can be dismissed at any
/// time via the explicit "Skip for now" action.
class PostSignInOnboardingPage extends ConsumerStatefulWidget {
  const PostSignInOnboardingPage({super.key});

  @override
  ConsumerState<PostSignInOnboardingPage> createState() =>
      _PostSignInOnboardingPageState();
}

// =============================================================================
// Parent state — owns the StepFlow shell and coordinates step routing.
// =============================================================================

class _PostSignInOnboardingPageState
    extends ConsumerState<PostSignInOnboardingPage> {
  final GlobalKey<NavigatorState> _nestedNavKey = GlobalKey<NavigatorState>();
  bool _isFinishingFlow = false;

  /// 1-indexed current step (matches [StepFlow] convention so the progress bar
  /// stays in sync with the nested navigator).
  int _currentStep = 1;

  /// Ordered list of route names for the required steps.  Populated once from
  /// [userInfoProvider] — never recomputed reactively, because the nested
  /// [Navigator] owns its own stack.
  List<String> _stepRoutes = const [];

  /// Whether [_stepRoutes] has been initialised from [userInfoProvider].
  bool _routesInitialized = false;

  /// Cached user info so step builders can reference it.
  UserInfo? _userInfo;

  // ---------------------------------------------------------------------------
  // Flow lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _finishFlow() async {
    if (_isFinishingFlow) return;
    _isFinishingFlow = true;

    ref.read(postSignInFlowPendingProvider.notifier).clearPending();
    if (mounted) {
      context.go('/up_next');
    }
  }

  // ---------------------------------------------------------------------------
  // Step routing
  // ---------------------------------------------------------------------------

  /// Determines which onboarding steps are needed for [userInfo].
  static List<String> _computeStepRoutes(UserInfo userInfo) {
    final email = userInfo.email?.trim();
    final normalizedName = userInfo.name?.trim().toLowerCase();
    final normalizedEmail = email?.toLowerCase();

    final needsRealName =
        normalizedName == null ||
        normalizedName.isEmpty ||
        (normalizedEmail != null && normalizedName == normalizedEmail);

    final needsEmailVerification = userInfo.emailVerified != true;

    final routes = <String>[];
    if (needsRealName) routes.add('real_name');
    if (needsEmailVerification) routes.add('email_verification');
    return routes;
  }

  Widget _buildStep(RouteSettings settings) {
    switch (settings.name) {
      case 'real_name':
        return _buildRealNameStep();
      case 'email_verification':
        return _buildEmailVerificationStep();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Called by a step widget when it has been completed successfully.
  void _advanceToNextStep() {
    final nextIndex = _currentStep; // 1-indexed = index of next route
    if (nextIndex < _stepRoutes.length) {
      setState(() => _currentStep++);
      _nestedNavKey.currentState?.pushNamed(_stepRoutes[nextIndex]);
    } else {
      _finishFlow();
    }
  }

  // ---------------------------------------------------------------------------
  // Step builders
  // ---------------------------------------------------------------------------

  Widget _buildRealNameStep() {
    final userInfo = _userInfo;
    if (userInfo == null) return const SizedBox.shrink();
    return _RealNameStep(userInfo: userInfo, onComplete: _advanceToNextStep);
  }

  Widget _buildEmailVerificationStep() {
    final userInfo = _userInfo;
    if (userInfo == null) return const SizedBox.shrink();

    return StepLayout(
      title: 'Verify your email',
      buttonText: 'Refresh verification status',
      buttonIcon: LucideIcons.refreshCcw,
      onButtonPressed: () {
        ref.invalidate(userInfoProvider);
      },
      secondaryButtonText: 'Skip for now',
      onSecondaryButtonPressed: _finishFlow,
      body: Text(
        'Please check ${userInfo.email ?? 'your inbox'} for a verification email. If you can\'t find it, skip for now.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final userInfoAsync = ref.watch(userInfoProvider);

    return userInfoAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                const Text('Unable to load your account info right now.'),
                FilledButton(
                  onPressed: () => ref.invalidate(userInfoProvider),
                  child: const Text('Try again'),
                ),
                TextButton(
                  onPressed: _finishFlow,
                  child: const Text('Continue to app'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (userInfo) {
        if (userInfo == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _finishFlow());
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        _userInfo = userInfo;

        if (!_routesInitialized) {
          _stepRoutes = _computeStepRoutes(userInfo);
          _routesInitialized = true;
        }

        if (_stepRoutes.contains('email_verification') &&
            userInfo.emailVerified == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _finishFlow());
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_stepRoutes.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _finishFlow());
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return StepFlow(
          totalSteps: _stepRoutes.length,
          currentStep: _currentStep,
          title: 'Onboarding',
          navigatorKey: _nestedNavKey,
          initialRoute: _stepRoutes.first,
          stepBuilder: _buildStep,
          onBack: () => setState(() => _currentStep--),
          onExitRequested: null,
        );
      },
    );
  }
}

// =============================================================================
// Self-contained real-name step  (StatefulWidget so validation is reactive
// inside the nested Navigator's page — the parent's setState can't reach in).
// =============================================================================

class _RealNameStep extends ConsumerStatefulWidget {
  const _RealNameStep({required this.userInfo, required this.onComplete});

  final UserInfo userInfo;
  final VoidCallback onComplete;

  @override
  ConsumerState<_RealNameStep> createState() => _RealNameStepState();
}

class _RealNameStepState extends ConsumerState<_RealNameStep> {
  final TextEditingController _controller = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rawName = _controller.text;
    if (_nameValidationError(rawName, widget.userInfo.email) != null) return;

    setState(() => _isSaving = true);
    try {
      await ref
          .read(userProfileServiceProvider)
          .updateProfile(name: rawName.trim());

      if (mounted) {
        widget.onComplete();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update name: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nameError = _nameValidationError(
      _controller.text,
      widget.userInfo.email,
    );
    final isNameEmpty = _controller.text.trim().isEmpty;
    final canSubmit = !_isSaving && !isNameEmpty && nameError == null;

    return StepLayout(
      title: 'Set your real name',
      isLoading: _isSaving,
      onButtonPressed: canSubmit ? _save : null,
      buttonText: 'Continue',
      buttonIcon: LucideIcons.arrowRight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Using your real name helps teammates know who you are.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_isSaving,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canSubmit) _save();
            },
            decoration: InputDecoration(
              labelText: 'Real name',
              hintText: 'First and last name',
              errorText: nameError,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Name validation helpers (top-level so they're accessible from both the
// parent and the self-contained step widget).
// =============================================================================

String? _nameValidationError(String name, String? email) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) return 'Enter your first and last name.';

  final parts = trimmedName
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) return 'Please include both first and last name.';

  if (trimmedName.toLowerCase() == email) {
    return 'Name cannot be the same as your email.';
  }

  final hasProperCapitalization = parts.asMap().entries.every(
    (entry) => _isProperlyCapitalizedNamePart(
      entry.value,
      isFirstPart: entry.key == 0,
    ),
  );
  if (!hasProperCapitalization) {
    return 'Use proper capitalization (for example: John Scout).';
  }

  if (trimmedName == 'John Scout') {
    return 'Nice try, but you aren\'t the real John Scout.';
  }

  return null;
}

bool _isProperlyCapitalizedNamePart(String part, {required bool isFirstPart}) {
  const lowercaseParticles = {
    'de',
    'del',
    'da',
    'di',
    'du',
    'la',
    'le',
    'van',
    'von',
    'der',
    'den',
    'bin',
    'al',
    'ibn',
  };

  if (!isFirstPart && lowercaseParticles.contains(part.toLowerCase())) {
    return true;
  }

  final segments = part.split(RegExp(r"[-']"));
  for (final segment in segments) {
    if (segment.isEmpty) return false;
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(segment)) return false;
    if (!RegExp(r'^[A-Z]').hasMatch(segment)) return false;
  }

  return true;
}
