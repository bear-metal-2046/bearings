import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: const CircularProgressIndicator()
            .animate()
            .fadeIn(duration: 600.ms)
            .scale(delay: 300.ms, duration: 400.ms),
      ),
    );
  }
}
