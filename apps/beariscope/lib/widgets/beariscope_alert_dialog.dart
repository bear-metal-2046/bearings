import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

enum BeariscopeAlertActionRole {
  /// Cancels, dismisses, or offers an alternative to the main action.
  secondary,

  /// Confirms or acknowledges without deleting or discarding data.
  primary,

  /// Deletes, clears, resets, or otherwise discards data or progress.
  destructive,
}

/// A button that closes the alert and returns [result] from [BeariscopeAlertDialog.show].
/// Perform any follow-up work after awaiting the dialog's result.
class BeariscopeAlertAction<T> {
  const BeariscopeAlertAction({
    required this.label,
    this.result,
    this.role = BeariscopeAlertActionRole.secondary,
    this.enabled = true,
  });

  final String label;
  final T? result;
  final BeariscopeAlertActionRole role;
  final bool enabled;
}

/// Shared alert layout, actions, and presentation.
class BeariscopeAlertDialog {
  BeariscopeAlertDialog._();

  /// Shows an alert with buttons in the supplied order. Choosing a button
  /// returns its result; dismissing the alert returns null.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required String message,
    required List<BeariscopeAlertAction<T>> actions,
    bool useRootNavigator = true,
    bool barrierDismissible = true,
    Color? barrierColor,
    RouteSettings? routeSettings,
    Offset? anchorPoint,
  }) {
    assert(actions.isNotEmpty, 'An alert needs at least one action.');
    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);

    return navigator.push<T>(
      _BeariscopeAlertDialogRoute<T>(
        context: context,
        builder: (_) => _DesktopAlertDialogTransition(
          child: _AlertContent<T>(
            title: title,
            message: message,
            actions: actions,
          ),
        ),
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

class _AlertContent<T> extends StatelessWidget {
  const _AlertContent({
    required this.title,
    required this.message,
    required this.actions,
  });

  final String title;
  final String message;
  final List<BeariscopeAlertAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        for (final action in actions)
          if (action.role == BeariscopeAlertActionRole.secondary)
            TextButton(
              onPressed: action.enabled
                  ? () => Navigator.of(context).pop<T>(action.result)
                  : null,
              child: Text(action.label),
            )
          else
            FilledButton(
              onPressed: action.enabled
                  ? () => Navigator.of(context).pop<T>(action.result)
                  : null,
              style: action.role == BeariscopeAlertActionRole.destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    )
                  : null,
              child: Text(action.label),
            ),
      ],
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
