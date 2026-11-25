import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

import 'bearings_navigation_motion.dart';

class BearingsCapsuleSegment {
  const BearingsCapsuleSegment(this.child, {this.expanded});

  final Widget child;
  final bool? expanded;
}

class BearingsCapsuleSelector extends StatefulWidget {
  const BearingsCapsuleSelector({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.height = 40,
    this.inset = 4,
    this.elevated = false,
    this.minimumSegmentWidth = 0,
  }) : assert(segments.length > 0),
       assert(selected >= 0 && selected < segments.length);

  final List<BearingsCapsuleSegment> segments;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool enabled;
  final double height;
  final double inset;
  final bool elevated;

  /// Below this width, segments scroll instead of shrinking further.
  final double minimumSegmentWidth;

  @override
  State<BearingsCapsuleSelector> createState() =>
      _BearingsCapsuleSelectorState();
}

class _BearingsCapsuleSelectorState extends State<BearingsCapsuleSelector>
    with SingleTickerProviderStateMixin {
  late final _indicator = SingleMotionController(
    vsync: this,
    motion: navigationSpring,
    initialValue: widget.selected.toDouble(),
  );
  final _scroll = ScrollController();
  double? _dragOffset;
  ({double viewport, double width, int index, int count})? _reveal;

  @override
  void didUpdateWidget(BearingsCapsuleSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected ||
        widget.segments.length != oldWidget.segments.length ||
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
    _scroll.dispose();
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
    _settle();
    if (!canceled && index != widget.selected) _activate(index);
  }

  void _revealSelection(double viewport, double width) {
    final target = (
      viewport: viewport,
      width: width,
      index: widget.selected,
      count: widget.segments.length,
    );
    if (_reveal == target) return;
    _reveal = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reveal != target || !_scroll.hasClients) return;
      final step = (width - 2 * widget.inset) / target.count;
      final center = widget.inset + step * (target.index + .5);
      final offset = (center - viewport / 2).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(offset);
      } else {
        _scroll.animateTo(
          offset,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minimum =
          widget.minimumSegmentWidth * widget.segments.length +
          2 * widget.inset;
      if (!constraints.hasBoundedWidth) {
        return SizedBox(
          width: widget.minimumSegmentWidth > 0
              ? minimum
              : 56 * widget.segments.length + 2 * widget.inset,
          child: _capsule(dragEnabled: widget.enabled),
        );
      }
      final viewport = constraints.maxWidth;
      if (minimum <= viewport) {
        _reveal = null;
        return _capsule(dragEnabled: widget.enabled);
      }

      _revealSelection(viewport, minimum);
      final behavior = ScrollConfiguration.of(context);
      return ScrollConfiguration(
        behavior: behavior.copyWith(
          dragDevices: {...behavior.dragDevices, PointerDeviceKind.mouse},
        ),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          primary: false,
          child: SizedBox(width: minimum, child: _capsule(dragEnabled: false)),
        ),
      );
    },
  );

  Widget _capsule({required bool dragEnabled}) {
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
        key: const ValueKey('bearings-capsule-clip'),
        clipper: const ShapeBorderClipper(shape: StadiumBorder()),
        child: Padding(
          padding: EdgeInsets.all(widget.inset),
          child: SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final step = constraints.maxWidth / widget.segments.length;
                double logicalX(double x) =>
                    Directionality.of(context) == TextDirection.rtl
                    ? constraints.maxWidth - x
                    : x;
                return Listener(
                  // An accepted drag can report onEnd after a pointer cancel.
                  onPointerCancel: (_) => _finishDrag(canceled: true),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: dragEnabled && step > 0
                        ? (details) => _startDrag(
                            logicalX(details.localPosition.dx),
                            step,
                          )
                        : null,
                    onHorizontalDragUpdate: dragEnabled && step > 0
                        ? (details) => _updateDrag(
                            logicalX(details.localPosition.dx),
                            step,
                          )
                        : null,
                    onHorizontalDragEnd: dragEnabled
                        ? (_) => _finishDrag(canceled: false)
                        : null,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedBuilder(
                          animation: _indicator,
                          builder: (_, child) => PositionedDirectional(
                            start: _indicator.value * step,
                            top: 0,
                            bottom: 0,
                            width: step,
                            child: child!,
                          ),
                          child: DecoratedBox(
                            key: const ValueKey('bearings-capsule-indicator'),
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
                                child: BearingsCapsuleTarget(
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

class BearingsCapsuleTarget extends StatelessWidget {
  const BearingsCapsuleTarget({
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
      enabled: onTap != null,
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
