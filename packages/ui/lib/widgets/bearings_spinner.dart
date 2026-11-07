import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:material_ui/material_ui.dart';

/// Indicates indeterminate progress with a steadily rotating arc.
class BearingsSpinner extends StatefulWidget {
  const BearingsSpinner({
    super.key,
    this.size = 28,
    this.strokeWidth = 3,
    this.color,
    this.useForegroundColor = false,
    this.semanticsLabel = 'Loading',
  }) : assert(size > 0),
       assert(strokeWidth > 0);

  final double size;
  final double strokeWidth;
  final Color? color;

  /// Uses the surrounding icon color, for example inside a filled button.
  final bool useForegroundColor;
  final String semanticsLabel;

  @override
  State<BearingsSpinner> createState() => _BearingsSpinnerState();
}

class _BearingsSpinnerState extends State<BearingsSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotation.stop();
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.useForegroundColor
        ? IconTheme.of(context).color
        : null;
    final color =
        widget.color ?? foreground ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: widget.semanticsLabel,
      role: SemanticsRole.loadingSpinner,
      child: RotationTransition(
        turns: _rotation,
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _SpinnerArc(color: color, strokeWidth: widget.strokeWidth),
          ),
        ),
      ),
    );
  }
}

class _SpinnerArc extends CustomPainter {
  const _SpinnerArc({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    if (radius <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      -math.pi / 2,
      1.4 * math.pi,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpinnerArc oldDelegate) =>
      color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
}
