import 'package:beariscope/providers/post_sign_in_flow_provider.dart';
import 'package:beariscope/widgets/step_flow.dart';
import 'package:beariscope/widgets/step_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Simple local state object to carry user inputs across internal steps
class SignupData {
  String teamNumber = '';
  bool teamExists = false;
  String joinCode = '';
  bool createTeam = false;
}

class SignUpFlowPage extends ConsumerStatefulWidget {
  const SignUpFlowPage({super.key});

  @override
  ConsumerState<SignUpFlowPage> createState() => _SignUpFlowPageState();
}

class _SignUpFlowPageState extends ConsumerState<SignUpFlowPage> {
  // GlobalKey to target and control our internal Navigator instance
  final GlobalKey<NavigatorState> _nestedNavKey = GlobalKey<NavigatorState>();

  // The master data payload gathered throughout the steps
  final SignupData _signupData = SignupData();

  // Animation configuration for our custom app bar progress indicator
  int _currentStep = 1;
  final int _totalSteps = 3;

  // Form keys for quick frontend validation
  final _teamFormKey = GlobalKey<FormState>();
  final _joinFormKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return StepFlow(
      totalSteps: _totalSteps,
      currentStep: _currentStep,
      navigatorKey: _nestedNavKey,
      initialRoute: 'team_number',
      stepBuilder: _buildStep,
      onBack: () => setState(() => _currentStep--),
      onExitRequested: () {
        if (context.canPop()) context.pop();
      },
    );
  }

  Widget _buildStep(RouteSettings settings) {
    switch (settings.name) {
      case 'team_number':
        return _buildTeamNumberStep();
      case 'join_team':
        return _buildJoinTeamStep();
      case 'confirm_team':
        return _buildConfirmTeamStep();
      case 'auth_gateway':
        return _buildAuthGatewayStep();
      default:
        return _buildTeamNumberStep();
    }
  }

  Widget _buildTeamNumberStep() {
    return StepLayout(
      title: 'Enter your team number',
      buttonText: 'Continue',
      buttonIcon: LucideIcons.arrowRight,
      onButtonPressed: () async {
        if (_teamFormKey.currentState?.validate() ?? false) {
          // TODO: Replace with your actual database/API check
          bool dummyTeamExists =
              _signupData.teamNumber == '254' ||
              _signupData.teamNumber == '1114';
          _signupData.teamExists = dummyTeamExists;

          setState(() => _currentStep = 2);

          if (dummyTeamExists) {
            _nestedNavKey.currentState?.pushNamed('join_team');
          } else {
            _nestedNavKey.currentState?.pushNamed('confirm_team');
          }
        }
      },
      body: Form(
        key: _teamFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will be used to find your team\'s workspace or create a new one if it doesn\'t exist.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Team Number',
                hintText: 'e.g. 2910',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a team number';
                }
                if (int.tryParse(value) == null) return 'Enter a valid number';
                return null;
              },
              onChanged: (val) => _signupData.teamNumber = val,
            ),
          ],
        ),
      ),
    );
  }

  // --- STEP 2A: Join Team with Code ---
  Widget _buildJoinTeamStep() {
    final String subject = Uri.encodeComponent(
      'Beariscope Workspace Recovery Request',
    );
    final String body = Uri.encodeComponent(
      'Hi Beariscope Team,\n\nOur team (${_signupData.teamNumber}) needs help recovering or accessing our workspace.',
    );

    final Uri emailLaunchUri = Uri.parse(
      'mailto:scouting-app@bearmet.al?subject=$subject&body=$body',
    );

    return StepLayout(
      title: 'Join Team ${_signupData.teamNumber}\'s Workspace',
      buttonText: 'Verify Access',
      buttonIcon: LucideIcons.lockKeyhole,
      onButtonPressed: () {
        _signupData.createTeam = false;
        if (_joinFormKey.currentState?.validate() ?? false) {
          setState(() => _currentStep = 3);
          _nestedNavKey.currentState?.pushNamed('auth_gateway');
        }
      },
      body: Form(
        key: _joinFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To protect your team\'s data, enter the join code provided by your team\'s admin or scan their QR code.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Team Join Code',
                hintText: 'XXXXXX',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Join code required'
                  : null,
              onChanged: (val) => _signupData.joinCode = val,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                // TODO: Wire up a scanner library like mobile_scanner
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Camera/Scanner UI pops up here'),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.scanQrCode),
              label: const Text('Scan QR Code instead'),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              margin: EdgeInsets.all(0),
              color: Theme.of(context).colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(LucideIcons.shieldQuestionMark),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text:
                                  'Locked out or think this workspace was created in error? Contact us at ',
                            ),
                            TextSpan(
                              text: 'scouting-app@bearmet.al',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () async {
                                  if (await canLaunchUrl(emailLaunchUri)) {
                                    await launchUrl(emailLaunchUri);
                                  } else {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not open mail app.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                            ),
                            const TextSpan(
                              text: ' and we\'ll help you sort it out.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmTeamStep() {
    return StepLayout(
      title: 'Create Team ${_signupData.teamNumber}\'s Workspace?',
      buttonText: 'Create Workspace',
      buttonIcon: LucideIcons.squarePlus,
      onButtonPressed: () {
        _signupData.createTeam = true;
        setState(() => _currentStep = 3);
        _nestedNavKey.currentState?.pushNamed('auth_gateway');
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'It looks like you\'re the first person on Team ${_signupData.teamNumber} to sign up for Beariscope. Continuing will create a workspace for this team. Only continue if you are authorized to do so on behalf of Team ${_signupData.teamNumber}.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            margin: EdgeInsets.all(0),
            color: Theme.of(context).colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(LucideIcons.userStar),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The workspace will be created with you as the administrator. You can change this later.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 3: Auth0 Secure Account Creation ---
  Widget _buildAuthGatewayStep() {
    return StepLayout(
      title: 'Final Step',
      buttonText: 'Create Account',
      buttonIcon: LucideIcons.externalLink,
      onButtonPressed: () async {
        ref.read(postSignInFlowPendingProvider.notifier).setPending();

        try {
          final auth = await ref.read(authProvider.future);
          await auth.login([
            'openid',
            'profile',
            'email',
            'offline_access',
            'ORLhqJbHiTfgdF3Q8hqIbmdwT1wTkkP7',
          ], isSignup: true);
        } on OfflineAuthException {
          ref.read(postSignInFlowPendingProvider.notifier).clearPending();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No internet connection')),
          );
        } catch (e) {
          ref.read(postSignInFlowPendingProvider.notifier).clearPending();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sign in failed: $e'),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      },

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To finish setup, we need to create your account. This will be used to securely store your team data and sync across devices.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
