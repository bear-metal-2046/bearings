import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:services/providers/auth_provider.dart';

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 16,
            children: [
              const Text(
                    'Pawfinder',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .slideY(
                    begin: -0.3,
                    end: 0,
                    duration: 600.ms,
                    curve: Curves.easeOutCubic,
                  ),
              IntrinsicWidth(
                child: Column(
                  spacing: 16,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                          onPressed: () async {
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
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('No internet connection'),
                                  ),
                                );
                              }
                            }
                          },
                          label: const Text('Sign In'),
                          icon: const Icon(Symbols.open_in_new_rounded),
                        )
                        .animate()
                        .fadeIn(delay: 300.ms, duration: 600.ms)
                        .slideY(
                          begin: 0.3,
                          end: 0,
                          delay: 300.ms,
                          duration: 600.ms,
                          curve: Curves.easeOutCubic,
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
