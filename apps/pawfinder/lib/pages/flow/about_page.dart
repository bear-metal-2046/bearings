import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pawfinder/providers/app_provider.dart';
import 'package:services/release/release_info.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  int _tapCount = 0;
  static const int _tapsRequired = 7;
  int _animationTrigger = 0;

  void _handlePawTap() {
    final isPapyrusEnabled = ref.read(papyrusFontProvider);
    setState(() {
      _tapCount++;
      _animationTrigger++;
    });

    final remaining = _tapsRequired - _tapCount;

    if (remaining > 0) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remaining == _tapsRequired - 1
                ? '...'
                : remaining == 1
                ? 'one more...'
                : '$remaining more',
            textAlign: TextAlign.center,
          ),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
          width: 160,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );
    } else {
      _tapCount = 0;
      ref.read(papyrusFontProvider.notifier).toggle();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPapyrusEnabled ? 'brainrot cured' : 'son im crine 😭',
            textAlign: TextAlign.center,
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 200,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _tapCount / _tapsRequired;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),

                  GestureDetector(
                    onTap: _handlePawTap,
                    child: Animate(
                      // new key on every tap so the effect re-fires
                      key: ValueKey(_animationTrigger),
                      effects: _animationTrigger == 0
                          ? [
                              FadeEffect(duration: 500.ms),
                              ScaleEffect(
                                begin: const Offset(0.8, 0.8),
                                end: const Offset(1.0, 1.0),
                                duration: 500.ms,
                              ),
                            ]
                          // tap feedback: shake + pop bounce
                          : [
                              ShakeEffect(
                                hz: 8,
                                offset: const Offset(4, 0),
                                duration: 300.ms,
                              ),
                              ScaleEffect(
                                begin: const Offset(1.0, 1.0),
                                end: const Offset(1.2, 1.2),
                                duration: 80.ms,
                                curve: Curves.easeOut,
                              ),
                              ScaleEffect(
                                begin: const Offset(1.2, 1.2),
                                end: const Offset(1.0, 1.0),
                                delay: 80.ms,
                                duration: 200.ms,
                                curve: Curves.elasticOut,
                              ),
                            ],
                      child: Icon(
                        Icons.pets,
                        size: 100,
                        color: Color.lerp(
                          Theme.of(context).colorScheme.primary,
                          Colors.amberAccent,
                          progress,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // App Name
                  Text(
                        'Pawfinder',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      )
                      .animate()
                      .fadeIn(delay: 100.ms, duration: 500.ms)
                      .slideY(
                        begin: 0.2,
                        end: 0,
                        delay: 100.ms,
                        duration: 500.ms,
                      ),

                  const SizedBox(height: 8),

                  FutureBuilder<(PackageInfo, String)>(
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
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Text(
                          'Loading',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(delay: 200.ms, duration: 500.ms);
                      } else if (snapshot.hasError) {
                        return Text(
                          'Error',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(delay: 200.ms, duration: 500.ms);
                      } else {
                        final (info, codename) = snapshot.data!;
                        final version = info.version;
                        if (codename.isEmpty || codename == 'Unknown') {
                          return Text(
                            'Version $version',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(delay: 200.ms, duration: 500.ms);
                        }
                        return Text(
                          'Version $version - $codename',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(delay: 200.ms, duration: 500.ms);
                      }
                    },
                  ),

                  const SizedBox(height: 40),

                  // Description Card
                  Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'About This App',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Pawfinder is a comprehensive FRC scouting application designed to help teams collect, analyze, and utilize match data efficiently.\n\n'
                                'Built with Flutter for a seamless cross-platform experience.',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 300.ms, duration: 500.ms)
                      .slideX(
                        begin: -0.2,
                        end: 0,
                        delay: 300.ms,
                        duration: 500.ms,
                      ),

                  const SizedBox(height: 16),

                  // Credits Card
                  Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Credits',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              RichText(
                                text: TextSpan(
                                  style: Theme.of(context).textTheme.bodyLarge,
                                  children: [
                                    TextSpan(text: 'JackGPT\n'),
                                    TextSpan(text: 'Ben the Ginger\n'),
                                    TextSpan(text: 'The big Aurav G\n'),
                                    TextSpan(text: 'Ryan Essay\n'),
                                    TextSpan(
                                      text: 'Meghnaa\'s broken computer\n',
                                    ),
                                    TextSpan(text: 'Ash Balatro\n'),
                                    TextSpan(text: 'Zaydenyahu Palantir\n'),
                                    TextSpan(text: 'Tiny and Sen\n'),
                                    TextSpan(
                                      text:
                                          'And Nived i guess (emotional support)',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 400.ms, duration: 500.ms)
                      .slideX(
                        begin: -0.2,
                        end: 0,
                        delay: 400.ms,
                        duration: 500.ms,
                      ),

                  const SizedBox(height: 16),

                  // Footer Card
                  Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Made with ❤️ by Bear Metal Apps',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Get back to scouting you lazy bum.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 500.ms)
                      .slideX(
                        begin: -0.2,
                        end: 0,
                        delay: 500.ms,
                        duration: 500.ms,
                      ),

                  const SizedBox(height: 24),

                  OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => Theme(
                                data: Theme.of(context),
                                child: const LicensePage(
                                  applicationName: 'Pawfinder',
                                  applicationVersion: '1.0.0',
                                  applicationIcon: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Icon(Icons.pets, size: 48),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.article_outlined),
                        label: const Text('View Licenses & Credits'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 500.ms)
                      .slideY(
                        begin: 0.2,
                        end: 0,
                        delay: 600.ms,
                        duration: 500.ms,
                      ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
