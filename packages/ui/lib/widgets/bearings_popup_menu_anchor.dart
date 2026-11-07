part of 'bearings_popup_menu.dart';

const _menuPadding = EdgeInsets.symmetric(vertical: 12);

const _defaultMenuAnimation = AnimationStyle(
  duration: Duration(milliseconds: 150),
  reverseDuration: Duration(milliseconds: 150),
  curve: Curves.easeOutCubic,
  reverseCurve: Curves.easeInCubic,
);

class _BearingsMenuScope extends InheritedWidget {
  const _BearingsMenuScope({
    required this.controller,
    required this.root,
    required this.animationStyle,
    required this.isActive,
    required this.cascadeLeft,
    required super.child,
  });

  final MenuController controller;
  final MenuController root;
  final AnimationStyle animationStyle;
  final bool Function() isActive;
  final bool Function() cascadeLeft;

  static _BearingsMenuScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BearingsMenuScope>();

  @override
  bool updateShouldNotify(_BearingsMenuScope oldWidget) =>
      controller != oldWidget.controller ||
      root != oldWidget.root ||
      animationStyle != oldWidget.animationStyle ||
      cascadeLeft != oldWidget.cascadeLeft;
}

class _BearingsMenuAnchor extends StatefulWidget {
  const _BearingsMenuAnchor({
    required this.background,
    required this.childFocusNode,
    required this.menuChildren,
    required this.builder,
    this.animationStyle,
    this.controller,
    this.alignmentOffset = Offset.zero,
  });

  final Color background;
  final FocusNode childFocusNode;
  final List<Widget> menuChildren;
  final RawMenuAnchorChildBuilder builder;
  final AnimationStyle? animationStyle;
  final MenuController? controller;
  final Offset alignmentOffset;

  @override
  State<_BearingsMenuAnchor> createState() => _BearingsMenuAnchorState();
}

class _BearingsMenuAnchorState extends State<_BearingsMenuAnchor>
    with SingleTickerProviderStateMixin {
  final _internalController = MenuController();
  final _menuFocus = FocusScopeNode();
  late final _animation = AnimationController(vsync: this);
  late final _progress = CurvedAnimation(
    parent: _animation,
    curve: Curves.linear,
  );
  Offset? _position;
  bool? _cascadeLeft;

  MenuController get _controller => widget.controller ?? _internalController;
  bool get _isActive => _animation.isForwardOrCompleted;

  @override
  void dispose() {
    _menuFocus.dispose();
    _progress.dispose();
    _animation.dispose();
    super.dispose();
  }

  void _open(Offset? position, VoidCallback showOverlay) {
    if (_BearingsMenuScope.maybeOf(context)?.isActive() == false) return;
    if (!_controller.isOpen || position != _position) {
      _position = position;
      showOverlay();
    }
    _animation.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isActive) {
        final first = _menuFocus.traversalDescendants.firstOrNull;
        (first ?? _menuFocus).requestFocus();
      }
    });
  }

  void _close(VoidCallback hideOverlay) {
    if (!_isActive) return;
    if (_menuFocus.hasFocus &&
        _BearingsMenuScope.maybeOf(context)?.isActive() != false) {
      widget.childFocusNode.requestFocus();
    }
    _animation.reverse().whenComplete(hideOverlay);
  }

  @override
  Widget build(BuildContext context) {
    final parent = _BearingsMenuScope.maybeOf(context);
    final motion = _defaultMenuAnimation.merge(
      widget.animationStyle ?? parent?.animationStyle,
    );
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _animation
      ..duration = reducedMotion ? Duration.zero : motion.duration
      ..reverseDuration = reducedMotion
          ? Duration.zero
          : motion.reverseDuration;
    _progress
      ..curve = motion.curve!
      ..reverseCurve = motion.reverseCurve;

    return RawMenuAnchor(
      controller: _controller,
      childFocusNode: widget.childFocusNode,
      onOpenRequested: _open,
      onCloseRequested: _close,
      builder: widget.builder,
      overlayBuilder: (context, info) {
        final root = parent?.root ?? _controller;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final media = MediaQuery.of(context);
        final safeArea =
            (media.padding + media.viewInsets + const EdgeInsets.all(8))
                .deflateRect(Offset.zero & info.overlaySize);
        final bounds =
            DisplayFeatureSubScreen.subScreensInBounds(
              safeArea,
              media.displayFeatures.map((feature) => feature.bounds),
            ).reduce((nearest, candidate) {
              final center = info.anchorRect.center;
              return (candidate.center - center).distanceSquared <
                      (nearest.center - center).distanceSquared
                  ? candidate
                  : nearest;
            });

        final placement = _MenuPlacement(
          bounds: bounds,
          anchor: info.anchorRect,
          offset: widget.alignmentOffset,
          position: info.position,
          nested: parent != null,
          rtl: rtl,
          preferredLeft: parent?.cascadeLeft ?? () => rtl,
          onCascadeDirection: (left) => _cascadeLeft = left,
        );

        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final progress = _progress.value.clamp(0.0, 1.0);
            return _MenuLayout(
              delegate: placement,
              child: _MenuScale(
                scale: 0.94 + 0.06 * _progress.value,
                child: ExcludeSemantics(
                  excluding: !_isActive,
                  child: ExcludeFocus(
                    excluding: !_isActive,
                    child: IgnorePointer(
                      ignoring: !_isActive,
                      child: Opacity(opacity: progress, child: child),
                    ),
                  ),
                ),
              ),
            );
          },
          child: TapRegion(
            groupId: info.tapRegionGroupId,
            onTapOutside: (_) => root.close(),
            child: _BearingsMenuScope(
              controller: _controller,
              root: root,
              animationStyle: motion,
              isActive: () => _isActive,
              cascadeLeft: () => _cascadeLeft ?? rtl,
              child: Semantics(
                role: SemanticsRole.menu,
                container: true,
                explicitChildNodes: true,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        root.close,
                    const SingleActivator(LogicalKeyboardKey.arrowDown):
                        _menuFocus.nextFocus,
                    const SingleActivator(LogicalKeyboardKey.arrowUp):
                        _menuFocus.previousFocus,
                    if (parent != null)
                      SingleActivator(
                        rtl
                            ? LogicalKeyboardKey.arrowRight
                            : LogicalKeyboardKey.arrowLeft,
                      ): _controller.close,
                  },
                  child: FocusScope(
                    node: _menuFocus,
                    child: Material(
                      elevation: 8,
                      color: widget.background,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicWidth(
                        child: SingleChildScrollView(
                          primary: false,
                          padding: _menuPadding,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: widget.menuChildren,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuScale extends Transform {
  _MenuScale({required double scale, super.child}) : super.scale(scale: scale);

  @override
  void updateRenderObject(BuildContext context, RenderTransform renderObject) {
    // Layout owns the pivot. Animation frames only update the scale.
    renderObject.transform = transform;
  }
}

class _MenuLayout extends CustomSingleChildLayout {
  const _MenuLayout({required _MenuPlacement super.delegate, super.child});

  @override
  RenderCustomSingleChildLayoutBox createRenderObject(BuildContext context) =>
      _RenderMenuLayout(delegate: delegate);
}

class _RenderMenuLayout extends RenderCustomSingleChildLayoutBox {
  _RenderMenuLayout({required super.delegate});

  @override
  void performLayout() {
    super.performLayout();
    final panel = child as RenderTransform?;
    if (panel == null) return;

    final placement = delegate as _MenuPlacement;
    final panelData = panel.parentData! as BoxParentData;
    if (placement.nested && placement.position == null) {
      placement.onCascadeDirection(placement.cascade(panel.size.width).left);
    }
    panel.alignment = placement.scaleAlignment(panelData.offset & panel.size);
  }
}

class _MenuPlacement extends SingleChildLayoutDelegate {
  const _MenuPlacement({
    required this.bounds,
    required this.anchor,
    required this.offset,
    required this.position,
    required this.nested,
    required this.rtl,
    required this.preferredLeft,
    required this.onCascadeDirection,
  });

  final Rect bounds;
  final Rect anchor;
  final Offset offset;
  final Offset? position;
  final bool nested;
  final bool rtl;
  final bool Function() preferredLeft;
  final ValueChanged<bool> onCascadeDirection;

  Alignment scaleAlignment(Rect panel) {
    if (panel.isEmpty) return Alignment.center;
    final origin = position;
    final source = origin == null ? anchor.center : anchor.topLeft + origin;
    final fromCenter = source - panel.center;
    // Pull toward the trigger, leaving the pivot inside the panel's edges.
    const bias = 0.75;
    return Alignment(
      (2 * fromCenter.dx / panel.width).clamp(-1.0, 1.0) * bias,
      (2 * fromCenter.dy / panel.height).clamp(-1.0, 1.0) * bias,
    );
  }

  ({double x, bool left}) cascade(double width) {
    final left = anchor.left - width;
    final right = anchor.right;
    final preferLeft = preferredLeft();
    final preferred = preferLeft ? left : right;
    final alternate = preferLeft ? right : left;
    final maxX = bounds.right - width;
    if (preferred >= bounds.left && preferred <= maxX) {
      return (x: preferred, left: preferLeft);
    }
    if (alternate >= bounds.left && alternate <= maxX) {
      return (x: alternate, left: !preferLeft);
    }
    // When both sides are too narrow, overlap toward the side with more room.
    // Keep the row's vertical attachment and the full viewport height available.
    final availableWidth = bounds.width.clamp(0.0, double.infinity);
    final leftSpace = (anchor.left - bounds.left).clamp(0.0, availableWidth);
    final rightSpace = (bounds.right - anchor.right).clamp(0.0, availableWidth);
    final useLeft = leftSpace == rightSpace
        ? preferLeft
        : leftSpace > rightSpace;
    return (x: useLeft ? left : right, left: useLeft);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          bounds.width.clamp(0, constraints.maxWidth),
          bounds.height.clamp(0, constraints.maxHeight),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX =
        bounds.left + (bounds.width - childSize.width).clamp(0, size.width);
    final maxY =
        bounds.top + (bounds.height - childSize.height).clamp(0, size.height);
    final origin = position;
    var x = rtl
        ? anchor.right - childSize.width - offset.dx
        : anchor.left + offset.dx;
    var y = anchor.bottom + offset.dy;

    if (origin != null) {
      x = anchor.left + origin.dx;
      y = anchor.top + origin.dy;
    } else if (nested) {
      x = cascade(childSize.width).x;
      y = anchor.top - _menuPadding.top;
    } else if (y > maxY && anchor.top - childSize.height >= bounds.top) {
      y = anchor.top - childSize.height - offset.dy;
    }
    return Offset(x.clamp(bounds.left, maxX), y.clamp(bounds.top, maxY));
  }

  @override
  bool shouldRelayout(_MenuPlacement oldDelegate) =>
      bounds != oldDelegate.bounds ||
      anchor != oldDelegate.anchor ||
      offset != oldDelegate.offset ||
      position != oldDelegate.position ||
      nested != oldDelegate.nested ||
      rtl != oldDelegate.rtl ||
      preferredLeft != oldDelegate.preferredLeft;
}
