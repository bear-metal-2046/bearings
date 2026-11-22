import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Starts an editor drag immediately with a mouse or after a short touch hold.
class EditorDraggable<T extends Object> extends Draggable<T> {
  const EditorDraggable({
    super.key,
    required super.data,
    required this.canStart,
    required super.feedback,
    required super.childWhenDragging,
    required super.onDragStarted,
    super.onDragUpdate,
    super.dragAnchorStrategy,
    required super.onDragCompleted,
    required super.onDraggableCanceled,
    required super.child,
  }) : super(maxSimultaneousDrags: 1, hitTestBehavior: HitTestBehavior.opaque);

  final bool Function() canStart;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _EditorDragRecognizer(
    (position) => canStart() ? onStart(position) : null,
  );
}

class _EditorDragRecognizer extends DelayedMultiDragGestureRecognizer {
  _EditorDragRecognizer(GestureMultiDragStartCallback start)
    : super(delay: const Duration(milliseconds: 250)) {
    onStart = start;
    _mouse.onStart = start;
  }

  final _mouse = ImmediateMultiDragGestureRecognizer();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _mouse.gestureSettings = gestureSettings;
      _mouse.addPointer(event);
    } else {
      super.addAllowedPointer(event);
    }
  }

  @override
  void dispose() {
    _mouse.dispose();
    super.dispose();
  }
}
