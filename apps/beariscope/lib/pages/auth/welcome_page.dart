import 'package:beariscope/providers/post_sign_in_flow_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 16,
              children: [
                SvgPicture.asset(
                  'assets/beariscope_head.svg',
                  height: 128,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).colorScheme.primary,
                    BlendMode.srcATop,
                  ),
                ),
                const Text(
                  'Welcome to Beariscope!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                IntrinsicWidth(
                  child: Column(
                    spacing: 16,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          ref
                              .read(postSignInFlowPendingProvider.notifier)
                              .setPending();

                          try {
                            final auth = await ref.read(authProvider.future);
                            await auth.login([
                              'openid',
                              'profile',
                              'email',
                              'offline_access',
                              'ORLhqJbHiTfgdF3Q8hqIbmdwT1wTkkP7',
                            ]);
                          } on OfflineAuthException {
                            ref
                                .read(postSignInFlowPendingProvider.notifier)
                                .clearPending();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No internet connection'),
                                ),
                              );
                            }
                          } catch (e) {
                            ref
                                .read(postSignInFlowPendingProvider.notifier)
                                .clearPending();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Sign in failed: $e'),
                                  duration: const Duration(seconds: 8),
                                ),
                              );
                            }
                          }
                        },
                        label: const Text('Sign In'),
                        icon: const Icon(Symbols.open_in_new_rounded),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final uri = Uri.parse(
                      'https://bear-metal-2046.github.io/bearings/privacy-policy',
                    );
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Text(
                    'Privacy Policy',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final info = snapshot.data!;
                  return Text(
                    'v${info.version} (${info.buildNumber})',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
