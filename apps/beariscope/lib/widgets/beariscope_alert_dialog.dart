import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

class BeariscopeAlertDialog {
  BeariscopeAlertDialog._();

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool useRootNavigator = true,
    bool barrierDismissible = true,
    Color? barrierColor,
    RouteSettings? routeSettings,
    Offset? anchorPoint,
  }) {
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);

    return navigator.push<T>(
      _BeariscopeAlertDialogRoute<T>(
        context: context,
        builder: (_) =>
            _DesktopAlertDialogTransition(child: Builder(builder: builder)),
        barrierColor:
            barrierColor ??
            DialogTheme.of(context).barrierColor ??
            Theme.of(context).dialogTheme.barrierColor ??
            Colors.black54,
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
        barrierDismissible: barrierDismissible,
        themes: themes,
        settings: routeSettings,
        anchorPoint: anchorPoint,
        reduceMotion: reduceMotion,
      ),
    );
  }
}

class _BeariscopeAlertDialogRoute<T> extends DialogRoute<T> {
  _BeariscopeAlertDialogRoute({
    required super.context,
    required super.builder,
    required super.barrierColor,
    required super.barrierLabel,
    required super.barrierDismissible,
    required super.themes,
    required this.reduceMotion,
    super.settings,
    super.anchorPoint,
  }) : super(
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
         animationStyle: reduceMotion
             ? AnimationStyle.noAnimation
             : const AnimationStyle(
                 duration: Duration(milliseconds: 350),
                 curve: Curves.easeOutCubic,
                 reverseCurve: Curves.easeInCubic,
               ),
       );

  final bool reduceMotion;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) {
    if (previousRoute is StupidSimpleCupertinoSheetRoute) return false;
    return super.canTransitionFrom(previousRoute);
  }

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 140);
}

class _DesktopAlertDialogTransition extends StatelessWidget {
  const _DesktopAlertDialogTransition({required this.child});

  final Widget child;

  static final _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 0.62),
    0,
    1,
    0,
  );

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final value = animation.value;
        final progress = animation.status == AnimationStatus.reverse
            ? Curves.easeInCubic.transform(value)
            : value == 1
            ? 1.0
            : _spring.x(value * 0.45);
        return Transform.scale(
          key: const ValueKey('beariscope-alert-dialog-scale'),
          scale: 0.8 + 0.2 * progress,
          child: child,
        );
      },
    );
  }
}
