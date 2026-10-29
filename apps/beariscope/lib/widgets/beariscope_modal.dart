import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart'
    show
        CupertinoDynamicColor,
        CupertinoUserInterfaceLevel,
        CupertinoUserInterfaceLevelData;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';
import 'package:ui/ui.dart' show FlutterMaterialScope;

part 'beariscope_modal/android_header.dart';

part 'beariscope_modal/desktop_header.dart';

part 'beariscope_modal/ios_header.dart';

part 'beariscope_modal/ios_transitions.dart';

enum _ModalPresentation { desktop, ios, android }

/// The space available to a modal's content.
enum BeariscopeModalSize { compact, tall, expansive }

/// How outside taps and sheet gestures interact with the modal.
enum BeariscopeModalDismissal {
  /// Outside taps and dragging may dismiss the modal.
  standard,

  /// Outside taps cannot dismiss; dragging moves the sheet and snaps it back.
  explicit,

  /// Outside taps cannot dismiss and the sheet does not recognize drags.
  fixed,
}

/// Whether the modal or its content owns the vertical scroll view.
enum BeariscopeModalScrolling { managed, content }

/// A secondary icon action. [label] is also its accessibility label.
class BeariscopeModalAction {
  const BeariscopeModalAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
}

/// A primary action, rendered appropriately for the active presentation.
class BeariscopeModalPrimaryAction {
  const BeariscopeModalPrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool loading;
}

/// Adaptive modal chrome. Its content owns its own state and results.
class BeariscopeModal extends StatefulWidget {
  const BeariscopeModal({
    super.key,
    required this.title,
    required this.actions,
    required this.content,
    this.primaryAction,
    this.size = BeariscopeModalSize.compact,
    this.scrolling = BeariscopeModalScrolling.managed,
    this.dismissal = BeariscopeModalDismissal.standard,
    this.canDismiss = true,
    this.onDismissRequested,
  });

  final String title;
  final List<BeariscopeModalAction> actions;

  /// Content with its own internal spacing. The modal provides outer padding.
  final Widget content;
  final BeariscopeModalPrimaryAction? primaryAction;
  final BeariscopeModalSize size;
  final BeariscopeModalScrolling scrolling;
  final BeariscopeModalDismissal dismissal;
  final bool canDismiss;

  /// Asks whether an attempted dismissal may proceed, e.g. for unsaved work.
  /// Drag dismissal is disabled while a guard is present because the sheet
  /// package cannot restore a dragged sheet after an asynchronous veto.
  final Future<bool> Function()? onDismissRequested;

  /// Pushes a modal and returns its typed result. The builder should return a
  /// [BeariscopeModal] or a stateful widget that builds one.
  /// Uses the root navigator by default so the entire main view participates
  /// in the iOS sheet's background transition, including navigation chrome.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool useRootNavigator = true,
  }) {
    final presentation = kIsWeb
        ? _ModalPresentation.desktop
        : switch (Theme.of(context).platform) {
            TargetPlatform.iOS => _ModalPresentation.ios,
            TargetPlatform.android => _ModalPresentation.android,
            TargetPlatform.fuchsia ||
            TargetPlatform.linux ||
            TargetPlatform.macOS ||
            TargetPlatform.windows => _ModalPresentation.desktop,
          };

    // final presentation = _ModalPresentation.ios;

    final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
    final policy = _ModalPolicy();
    final contentKey = GlobalKey();

    Widget body(BuildContext context) => KeyedSubtree(
      key: contentKey,
      child: _ModalScope(
        policy: policy,
        presentation: presentation,
        child: _ModalBody(presentation: presentation, builder: builder),
      ),
    );

    switch (presentation) {
      case _ModalPresentation.desktop:
        final route = _DesktopModalRoute<T>(
          context: context,
          builder: body,
          barrierColor:
              DialogTheme.of(context).barrierColor ??
              Theme.of(context).dialogTheme.barrierColor ??
              Colors.black54,
          themes: InheritedTheme.capture(from: context, to: navigator.context),
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          policy: policy,
        );
        policy.refresh = route.refreshPolicy;
        return navigator.push<T>(route);
      case _ModalPresentation.ios:
        final route = _CupertinoModalRoute<T>(
          policy: policy,
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: Builder(builder: body),
        );
        policy.refresh = route.refreshPolicy;
        return navigator.push<T>(route);
      case _ModalPresentation.android:
        final route = _MaterialModalRoute<T>(
          policy: policy,
          barrierLabel: MaterialLocalizations.of(context)
              .modalBarrierDismissLabel,
          child: Builder(builder: body),
        );
        policy.refresh = route.refreshPolicy;
        return navigator.push<T>(route);
    }
  }

  /// Completes a modal without running its user-dismissal guard.
  /// Use this after a successful action, especially while [canDismiss] is
  /// false or [onDismissRequested] is configured.
  static void complete<T>(BuildContext context, [T? result]) {
    final route = ModalRoute.of(context);
    if (route is _GuardedRoute) (route as _GuardedRoute).allowNextPop();
    Navigator.of(context).pop<T>(result);
  }

  /// Whether this widget is inside a Beariscope modal route.
  static bool contains(BuildContext context) =>
      _ModalScope.maybeOf(context) != null;

  @override
  State<BeariscopeModal> createState() => _BeariscopeModalState();
}

class _ModalPolicy {
  BeariscopeModalDismissal dismissal = BeariscopeModalDismissal.standard;
  bool canDismiss = true;
  Future<bool> Function()? onDismissRequested;
  void Function({required bool rebuildPage})? refresh;

  bool get barrierDismissible =>
      dismissal == BeariscopeModalDismissal.standard && canDismiss;

  // A temporary dismissal lock must not remove the grabber and move the header.
  bool get showGrabber =>
      dismissal == BeariscopeModalDismissal.standard &&
      onDismissRequested == null;

  bool get dragDismissible => showGrabber && canDismiss;
}

abstract interface class _GuardedRoute {
  void allowNextPop();
}

mixin _DismissalGuard<T> on ModalRoute<T> implements _GuardedRoute {
  _ModalPolicy get policy;

  bool _allowPop = false;
  bool _asking = false;

  @override
  void allowNextPop() => _allowPop = true;

  void refreshPolicy({required bool rebuildPage}) {
    changedInternalState();
    // Changing dismissal mode can replace the page's gesture wrapper.
    if (rebuildPage) changedExternalState();
  }

  @override
  bool didPop(T? result) {
    if (_allowPop) {
      _allowPop = false;
      return super.didPop(result);
    }
    if (!policy.canDismiss) return false;
    final request = policy.onDismissRequested;
    if (request == null) return super.didPop(result);
    if (!_asking) {
      _asking = true;
      unawaited(
        Future<void>(() async {
          try {
            final allowed = await request();
            if (allowed &&
                policy.canDismiss &&
                isCurrent &&
                navigator != null) {
              _allowPop = true;
              navigator!.pop<T>(result);
            }
          } catch (error, stack) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'BeariscopeModal',
              ),
            );
          } finally {
            _asking = false;
          }
        }),
      );
    }
    return false;
  }
}

class _DesktopModalRoute<T> extends DialogRoute<T> with _DismissalGuard<T> {
  _DesktopModalRoute({
    required super.context,
    required super.builder,
    required super.barrierColor,
    required super.themes,
    required this.reduceMotion,
    required this.policy,
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

  @override
  final _ModalPolicy policy;
  final bool reduceMotion;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is RawDialogRoute<dynamic>;

  @override
  bool get barrierDismissible => policy.barrierDismissible;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 140);
}

// The package's `draggable: false` still recognizes drags and springs back.
// Skip its gesture wrapper when the content needs exclusive drag ownership.
mixin _SheetDragControl<T>
    on ModalRoute<T>, StupidSimpleSheetTransitionMixin<T> {
  _ModalPolicy get policy;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    if (policy.dismissal != BeariscopeModalDismissal.fixed) {
      return super.buildPage(context, animation, secondaryAnimation);
    }
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: originateAboveBottomViewInset,
      child: buildContent(context),
    );
  }
}

class _MaterialModalRoute<T> extends StupidSimpleSheetRoute<T>
    with _SheetDragControl<T>, _DismissalGuard<T> {
  _MaterialModalRoute({
    required this.policy,
    required super.barrierLabel,
    required super.child,
  }) : super(
         motion: const MaterialSpringMotion.standardSpatialDefault(
           snapToEnd: true,
         ),
         originateAboveBottomViewInset: true,
       );
  @override
  final _ModalPolicy policy;

  @override
  bool get barrierDismissible => policy.barrierDismissible;

  @override
  bool get draggable => policy.dragDismissible;
}

class _CupertinoModalRoute<T> extends StupidSimpleCupertinoSheetRoute<T>
    with _SheetDragControl<T>, _DismissalGuard<T> {
  _CupertinoModalRoute({
    required this.policy,
    required super.backgroundColor,
    required super.child,
  }) : super(
         shape: const RoundedRectangleBorder(
           borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
         ),
       );
  @override
  final _ModalPolicy policy;

  @override
  bool get draggable => policy.dragDismissible;

  StupidSimpleSheetTransitionMixin<dynamic>? _nextSheet;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    _nextSheet = nextRoute is StupidSimpleSheetTransitionMixin
        ? nextRoute
        : null;
    super.didChangeNext(nextRoute);
  }

  @override
  void didPopNext(Route<dynamic> nextRoute) {
    _nextSheet = null;
    super.didPopNext(nextRoute);
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      (context, animation, secondaryAnimation, canSnapshot, child) {
        final snapping =
            _nextSheet?.effectiveSnappingConfig ?? effectiveSnappingConfig;
        return _IosModalTransitions.secondarySlideDownTransition(
          context,
          animation: animation.clamped,
          secondaryAnimation: secondaryAnimation.clamped,
          opacityRange: snapping.bottomTwoPoints,
          slideBackRange: snapping.topTwoPoints,
          primaryShape: shape,
          child: SnapshotWidget(
            controller: backgroundSnapshotController,
            mode: SnapshotMode.permissive,
            autoresize: true,
            child: child,
          ),
        );
      };

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => CupertinoUserInterfaceLevel(
    data: CupertinoUserInterfaceLevelData.elevated,
    child: Builder(
      builder: (context) => _IosModalTransitions.fullTransition(
        context,
        animation: controller!.view,
        secondaryAnimation: secondaryAnimation.clamped,
        opacityRange: effectiveSnappingConfig.bottomTwoPoints,
        slideBackRange: effectiveSnappingConfig.topTwoPoints,
        backgroundColor: backgroundColor,
        shape: shape,
        child: maybeSnapshotChild(child),
      ),
    ),
  );

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      // Menus and dialogs float over the sheet; other sheets still stack.
      nextRoute is! PopupRoute || nextRoute is StupidSimpleSheetTransitionMixin;
}

class _ModalScope extends InheritedWidget {
  const _ModalScope({
    required this.policy,
    required this.presentation,
    required super.child,
  });

  final _ModalPolicy policy;
  final _ModalPresentation presentation;

  static _ModalScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ModalScope>();

  @override
  bool updateShouldNotify(_ModalScope oldWidget) => false;
}

class _ModalBody extends StatelessWidget {
  const _ModalBody({required this.presentation, required this.builder});

  final _ModalPresentation presentation;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final child = FlutterMaterialScope(
      child: Material(
        color: Colors.transparent,
        child: Builder(builder: builder),
      ),
    );
    return switch (presentation) {
      _ModalPresentation.desktop => _DesktopModalTransition(
        child: Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          child: child,
        ),
      ),
      // Include the blank sheet surface in the ancestor's drag hit testing.
      _ModalPresentation.ios => ColoredBox(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Align(alignment: Alignment.topCenter, child: child),
          ),
        ),
      ),
      _ModalPresentation.android => SafeArea(
        top: true,
        bottom: false,
        child: SheetBackground(
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: SafeArea(top: false, child: child),
        ),
      ),
    };
  }
}

class _BeariscopeModalState extends State<BeariscopeModal> {
  static const _contentPadding = EdgeInsets.symmetric(horizontal: 16);
  static const _outerPadding = EdgeInsets.only(bottom: 12);

  _ModalScope? _scope;

  void _updatePolicy() {
    final policy = _scope?.policy;
    if (policy == null) return;
    final oldBarrier = policy.barrierDismissible;
    final oldDragDismissible = policy.dragDismissible;
    final oldDismissal = policy.dismissal;
    policy.dismissal = widget.dismissal;
    policy.canDismiss = widget.canDismiss;
    policy.onDismissRequested = widget.onDismissRequested;
    if (oldDismissal != policy.dismissal ||
        oldBarrier != policy.barrierDismissible ||
        oldDragDismissible != policy.dragDismissible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          policy.refresh?.call(
            rebuildPage:
                (oldDismissal == BeariscopeModalDismissal.fixed) !=
                (policy.dismissal == BeariscopeModalDismissal.fixed),
          );
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = _ModalScope.maybeOf(context);
    _updatePolicy();
  }

  @override
  void didUpdateWidget(BeariscopeModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePolicy();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final presentation = scope?.presentation ?? _ModalPresentation.android;
    final primary = widget.primaryAction;
    final canPressPrimary =
        primary != null &&
        primary.enabled &&
        !primary.loading &&
        primary.onPressed != null;
    final media = MediaQuery.of(context);
    final maxWidth = switch (widget.size) {
      BeariscopeModalSize.compact => 560.0,
      BeariscopeModalSize.tall => 640.0,
      BeariscopeModalSize.expansive => 960.0,
    };
    final maxHeight = math.max(
      100.0,
      media.size.height - media.viewInsets.bottom - media.padding.top - 32,
    );
    final primaryButton = primary == null
        ? const SizedBox.shrink()
        : FilledButton(
            onPressed: canPressPrimary ? primary.onPressed : null,
            child: primary.loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(primary.label),
          );
    final onClose = widget.canDismiss ? _close : null;
    final showGrabber = scope?.policy.showGrabber ?? false;
    final header = switch (presentation) {
      _ModalPresentation.desktop => _DesktopModalHeader(
        title: widget.title,
        actions: widget.actions,
        onClose: onClose,
      ),
      _ModalPresentation.ios => _IosModalHeader(
        title: widget.title,
        actions: widget.actions,
        primaryAction: primary,
        onClose: onClose,
        showGrabber: showGrabber,
      ),
      _ModalPresentation.android => _AndroidModalHeader(
        title: widget.title,
        actions: widget.actions,
        onClose: onClose,
        showGrabber: showGrabber,
      ),
    };
    final body = widget.scrolling == BeariscopeModalScrolling.managed
        ? SingleChildScrollView(child: widget.content)
        : widget.content;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Flexible(
          child: Padding(padding: _contentPadding, child: body),
        ),
        if (presentation != _ModalPresentation.ios && primary != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: _contentPadding,
            child: presentation == _ModalPresentation.desktop
                ? OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: widget.canDismiss ? _close : null,
                        child: const Text('Cancel'),
                      ),
                      primaryButton,
                    ],
                  )
                : SizedBox(width: double.infinity, child: primaryButton),
          ),
        ],
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: Padding(
        padding: _outerPadding,
        child: widget.size == BeariscopeModalSize.expansive
            ? SizedBox(width: maxWidth, height: maxHeight, child: column)
            : column,
      ),
    );
  }
}

class _DesktopModalTransition extends StatelessWidget {
  const _DesktopModalTransition({required this.child});

  final Widget child;
  static final _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 0.62),
    0,
    1,
    0,
  );

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    final secondaryAnimation = route?.secondaryAnimation;
    if (animation == null || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final value = animation.value;
        final progress = animation.status == AnimationStatus.reverse
            ? Curves.easeInCubic.transform(value)
            : value == 1
            ? 1.0
            : _spring.x(value * 0.45);
        // Shrink in the first 140 ms of the top dialog's 350 ms entrance,
        // settling before its spring. The 140 ms return also eases out.
        final coveredCurve =
            secondaryAnimation?.status == AnimationStatus.reverse
            ? Curves.easeOutCubic.flipped
            : const Interval(0, 0.4, curve: Curves.easeOutCubic);
        final coveredProgress = coveredCurve.transform(
          secondaryAnimation?.value ?? 0,
        );
        return Transform.scale(
          key: const ValueKey('beariscope-modal-scale'),
          // Give a covered dialog a little depth without changing its layout.
          scale: (0.8 + 0.2 * progress) * (1 - 0.05 * coveredProgress),
          child: child,
        );
      },
    );
  }
}
