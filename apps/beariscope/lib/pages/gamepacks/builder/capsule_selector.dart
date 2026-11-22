import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

final gamePackNavigationSpring = SpringMotion(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: .72),
  snapToEnd: true,
);

class GamePackCapsuleSegment {
  const GamePackCapsuleSegment(this.child, {this.expanded});

  final Widget child;
  final bool? expanded;
}

class GamePackCapsuleSelector extends StatefulWidget {
  const GamePackCapsuleSelector({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.height = 40,
    this.inset = 4,
    this.elevated = false,
    this.capsuleKey,
    this.indicatorKey,
  });

  final List<GamePackCapsuleSegment> segments;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool enabled;
  final double height;
  final double inset;
  final bool elevated;
  final Key? capsuleKey;
  final Key? indicatorKey;

  @override
  State<GamePackCapsuleSelector> createState() =>
      _GamePackCapsuleSelectorState();
}

class _GamePackCapsuleSelectorState extends State<GamePackCapsuleSelector>
    with SingleTickerProviderStateMixin {
  late final _indicator = SingleMotionController(
    vsync: this,
    motion: gamePackNavigationSpring,
    initialValue: widget.selected.toDouble(),
  );
  double? _dragOffset;

  @override
  void didUpdateWidget(GamePackCapsuleSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected ||
        (!widget.enabled && _dragOffset != null)) {
      _dragOffset = null;
      _settle();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _indicator.isAnimating) {
      _indicator.value = widget.selected.toDouble();
    }
  }

  @override
  void dispose() {
    _indicator.dispose();
    super.dispose();
  }

  void _settle() {
    final target = widget.selected.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _indicator.value = target;
    } else {
      _indicator.animateTo(target);
    }
  }

  void _activate(int index) {
    HapticFeedback.selectionClick();
    widget.onSelected(index);
  }

  void _startDrag(double x, double step) {
    _indicator.stop(canceled: true);
    final offset = _indicator.value - (x / step - .5);
    _dragOffset = offset.abs() <= .5 ? offset : 0;
  }

  void _updateDrag(double x, double step) {
    if (_dragOffset case final offset?) {
      final last = widget.segments.length - 1;
      _indicator.value = (x / step - .5 + offset).clamp(-.2, last + .2);
    }
  }

  void _finishDrag({required bool canceled}) {
    if (_dragOffset == null) return;
    _dragOffset = null;
    final index = _indicator.value.round().clamp(0, widget.segments.length - 1);
    if (canceled || index == widget.selected) {
      _settle();
    } else {
      _activate(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.surfaceContainerHigh,
        shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
        shadows: [
          if (widget.elevated)
            BoxShadow(
              color: colors.shadow.withValues(alpha: .14),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: ClipPath(
        key: widget.capsuleKey,
        clipper: const ShapeBorderClipper(shape: StadiumBorder()),
        child: Padding(
          padding: EdgeInsets.all(widget.inset),
          child: SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final step = constraints.maxWidth / widget.segments.length;
                return Listener(
                  // An accepted drag can report onEnd after a pointer cancel.
                  onPointerCancel: (_) => _finishDrag(canceled: true),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: widget.enabled && step > 0
                        ? (details) =>
                              _startDrag(details.localPosition.dx, step)
                        : null,
                    onHorizontalDragUpdate: widget.enabled && step > 0
                        ? (details) =>
                              _updateDrag(details.localPosition.dx, step)
                        : null,
                    onHorizontalDragEnd: widget.enabled
                        ? (_) => _finishDrag(canceled: false)
                        : null,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedBuilder(
                          animation: _indicator,
                          builder: (_, child) => Positioned(
                            left: _indicator.value * step,
                            top: 0,
                            bottom: 0,
                            width: step,
                            child: child!,
                          ),
                          child: DecoratedBox(
                            key: widget.indicatorKey,
                            decoration: ShapeDecoration(
                              color: colors.primaryContainer,
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: colors.primary.withValues(alpha: .28),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (final (index, segment)
                                in widget.segments.indexed)
                              Expanded(
                                child: GamePackCapsuleTarget(
                                  selected: index == widget.selected,
                                  expanded: segment.expanded,
                                  shape: const StadiumBorder(),
                                  onTap: widget.enabled
                                      ? () => _activate(index)
                                      : null,
                                  child: segment.child,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class GamePackCapsuleTarget extends StatelessWidget {
  const GamePackCapsuleTarget({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.expanded,
    this.shape,
  });

  final bool selected;
  final ShapeBorder? shape;
  final bool? expanded;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = selected ? colors.onPrimaryContainer : colors.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      expanded: expanded,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder:
              shape ??
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          splashFactory: NoSplash.splashFactory,
          highlightColor: colors.primary.withValues(alpha: .12),
          focusColor: colors.primary.withValues(alpha: .18),
          onTap: onTap,
          child: DefaultTextStyle(
            style: (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: IconTheme(
              data: IconThemeData(color: color),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
