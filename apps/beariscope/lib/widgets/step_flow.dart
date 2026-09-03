import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A reusable flow container that shows an animated progress bar, manages
/// page transitions between steps via a nested [Navigator], and handles system
/// back navigation.
///
/// Usage:
/// ```dart
/// StepFlow(
///   totalSteps: 3,
///   currentStep: _currentStep,     // 1-indexed
///   navigatorKey: _nestedNavKey,
///   initialRoute: 'first_step',
///   stepBuilder: (settings) { ... },
///   onBack: () => setState(() => _currentStep--),
///   onExitRequested: () => context.pop(),
/// )
/// ```
class StepFlow extends StatelessWidget {
  /// Total number of steps in the flow (used to compute the progress bar
  /// fraction: `(currentStep - 1) / totalSteps`).
  final int totalSteps;

  /// The current step the user is on (1-indexed).
  final int currentStep;

  /// Key to control the nested [Navigator] (push / pop).
  final GlobalKey<NavigatorState> navigatorKey;

  /// The initial route name pushed into the nested navigator.
  final String initialRoute;

  /// Optional title shown in the centre of the app bar.
  final String? title;

  /// Builds the [Widget] for each route in the nested navigator.
  ///
  /// The returned widget is automatically wrapped in a [PageRouteBuilder]
  /// with slide transitions.
  final Widget Function(RouteSettings settings) stepBuilder;

  /// Called when the user presses back and the nested navigator still has
  /// routes to pop.  The parent should decrement [currentStep] here.
  final VoidCallback? onBack;

  /// Called when the user presses back on the first step — typically used
  /// to pop the outer router or abort the flow.  When `null` the back
  /// button is hidden on the first step.
  final VoidCallback? onExitRequested;

  const StepFlow({
    super.key,
    required this.totalSteps,
    required this.currentStep,
    required this.navigatorKey,
    required this.initialRoute,
    required this.stepBuilder,
    this.title,
    this.onBack,
    this.onExitRequested,
  });

  @override
  Widget build(BuildContext context) {
    // 1-indexed → fraction so that step 1 shows 0% (clamped to 5%).
    final double progressPercent = totalSteps > 0
        ? (currentStep - 1) / totalSteps
        : 0.0;

    // Determine whether to render a leading back button.
    final bool canPop = navigatorKey.currentState?.canPop() == true;
    final bool canExit = onExitRequested != null;
    final Widget? leading = canPop || canExit
        ? IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () {
              if (navigatorKey.currentState?.canPop() == true) {
                navigatorKey.currentState?.pop();
                onBack?.call();
              } else {
                onExitRequested?.call();
              }
            },
          )
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (navigatorKey.currentState?.canPop() == true) {
          navigatorKey.currentState?.pop();
          onBack?.call();
        } else {
          onExitRequested?.call();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: title != null ? Text(title!) : null,
          leading: leading,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.centerLeft,
              height: 6.0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                tween: Tween<double>(
                  begin: 0.05,
                  end: progressPercent == 0.0 ? 0.05 : progressPercent,
                ),
                builder: (ctx, animatedProgress, _) {
                  return FractionallySizedBox(
                    widthFactor: animatedProgress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Navigator(
            key: navigatorKey,
            initialRoute: initialRoute,
            onGenerateRoute: (settings) {
              final child = stepBuilder(settings);
              return PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 300),
                reverseTransitionDuration: const Duration(milliseconds: 300),
                pageBuilder: (ctx, animation, secondaryAnimation) => child,
                transitionsBuilder:
                    (ctx, animation, secondaryAnimation, child) {
                      final forwardSlider =
                          Tween<Offset>(
                            begin: const Offset(1.0, 0.0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOutCubic,
                            ),
                          );

                      final forwardExiter =
                          Tween<Offset>(
                            begin: Offset.zero,
                            end: const Offset(-1.0, 0.0),
                          ).animate(
                            CurvedAnimation(
                              parent: secondaryAnimation,
                              curve: Curves.easeInOutCubic,
                            ),
                          );

                      return SlideTransition(
                        position: forwardSlider,
                        child: SlideTransition(
                          position: forwardExiter,
                          child: child,
                        ),
                      );
                    },
              );
            },
          ),
        ),
      ),
    );
  }
}
