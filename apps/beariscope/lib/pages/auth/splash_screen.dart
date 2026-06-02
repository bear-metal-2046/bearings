import 'package:beariscope/providers/app_boot_provider.dart';
import 'package:beariscope/providers/app_phase_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootState = ref.watch(appBootProvider);
    final phase = ref.watch(appPhaseProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // When boot is done and we're in the splashing phase (e.g. during
    // login after initial boot), show "Authorizing…" instead of the
    // boot-ready message.
    final message = switch (phase) {
      AppPhase.splashing when !bootState.isReady => bootState.message,
      AppPhase.splashing => 'Authorizing…',
      _ => '',
    };

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Animate(
                    onPlay: (controller) => controller.repeat(),
                    effects: [
                      ShimmerEffect(
                        color: Colors.white.withValues(
                          alpha: isDark ? 0.6 : 0.2,
                        ),
                        duration: 1200.ms,
                      ),
                    ],
                    child: SvgPicture.asset(
                      'assets/beariscope_head.svg',
                      height: 128,
                      colorFilter: ColorFilter.mode(
                        Theme.of(context).colorScheme.primary,
                        BlendMode.srcATop,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                        message,
                        key: ValueKey(message),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                      .animate(key: ValueKey(message))
                      .fadeIn(duration: 250.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.35,
                        end: 0,
                        duration: 250.ms,
                        curve: Curves.easeOut,
                      ),
                ],
              ),
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
