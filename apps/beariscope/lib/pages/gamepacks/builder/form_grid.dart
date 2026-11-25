import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

GamePackControl controlWithPlacement(
  GamePackControl control,
  GamePackPlacement? placement,
) => GamePackControl(
  field: control.field,
  type: control.type,
  appearance: control.appearance,
  visibleWhen: control.visibleWhen,
  placement: placement,
);

bool canPlaceGridControl(
  GamePackFormPage page,
  GamePackPlacement placement, {
  GamePackControl? excluding,
}) =>
    placement.fits(page.columns!, page.rows!) &&
    !page.gridControls.any(
      (control) =>
          control != excluding && placement.overlaps(control.placement!),
    );

GamePackPlacement? findGridPlacement(
  int columns,
  int rows,
  List<GamePackControl> controls,
) {
  for (final (width, height) in {
    (math.min(3, columns), math.min(2, rows)),
    (1, 1),
  }) {
    for (var y = 0; y + height <= rows; y++) {
      for (var x = 0; x + width <= columns; x++) {
        final candidate = GamePackPlacement(x, y, width, height);
        if (!controls.any(
          (control) => candidate.overlaps(control.placement!),
        )) {
          return candidate;
        }
      }
    }
  }
  return null;
}

class GamePackGridEditor extends StatefulWidget {
  const GamePackGridEditor({
    super.key,
    required this.page,
    required this.fields,
    required this.selected,
    required this.selectedAnchor,
    required this.selectionActions,
    required this.onSelect,
    required this.onEdit,
    required this.onPlace,
  });

  final GamePackFormPage page;
  final Map<String, GamePackField> fields;
  final String? selected;
  final Key? selectedAnchor;
  final Widget? selectionActions;
  final ValueChanged<String?> onSelect;
  final ValueChanged<GamePackControl> onEdit;
  final void Function(GamePackControl, GamePackPlacement) onPlace;

  @override
  State<GamePackGridEditor> createState() => _GamePackGridEditorState();
}

class _GamePackGridEditorState extends State<GamePackGridEditor> {
  int? _pointer;
  Offset _origin = Offset.zero;
  GamePackControl? _moving;
  GamePackPlacement? _candidate;
  bool _resizing = false;

  void _start(PointerDownEvent event, GamePackControl control, Size tile) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _moving = control;
    _resizing =
        control.field == widget.selected &&
        event.localPosition.dx >= tile.width - math.min(28, tile.width / 2) &&
        event.localPosition.dy >= tile.height - math.min(28, tile.height / 2);
    widget.onSelect(control.field);
  }

  void _move(PointerMoveEvent event, Size cell) {
    if (event.pointer != _pointer) return;
    final delta = event.position - _origin;
    final dx = (delta.dx / cell.width).round();
    final dy = (delta.dy / cell.height).round();
    final bounds = widget.page;
    final start = _moving!.placement!;
    setState(
      () => _candidate = _resizing
          ? GamePackPlacement(
              start.x,
              start.y,
              (start.width + dx).clamp(1, bounds.columns! - start.x),
              (start.height + dy).clamp(1, bounds.rows! - start.y),
            )
          : GamePackPlacement(
              (start.x + dx).clamp(0, bounds.columns! - start.width),
              (start.y + dy).clamp(0, bounds.rows! - start.height),
              start.width,
              start.height,
            ),
    );
  }

  void _finish(PointerEvent event, {required bool commit}) {
    if (event.pointer != _pointer) return;
    final moving = _moving!;
    final candidate = _candidate;
    setState(() {
      _pointer = null;
      _candidate = null;
      _moving = null;
    });
    if (commit &&
        candidate != null &&
        canPlaceGridControl(widget.page, candidate, excluding: moving)) {
      widget.onPlace(moving, candidate);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = widget.page.columns!;
      final rows = widget.page.rows!;
      final bounds = constraints.biggest;
      if (bounds.isEmpty) return const SizedBox.expand();

      final cell = Size(bounds.width / columns, bounds.height / rows);
      final colors = Theme.of(context).colorScheme;
      final candidate = _candidate;
      final legal =
          candidate != null &&
          canPlaceGridControl(widget.page, candidate, excluding: _moving);
      Rect rect(GamePackPlacement placement) => Rect.fromLTWH(
        placement.x * cell.width,
        placement.y * cell.height,
        placement.width * cell.width,
        placement.height * cell.height,
      );
      final selection = widget.page.gridControls
          .where((control) => control.field == widget.selected)
          .firstOrNull;
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => widget.onSelect(null),
            child: ColoredBox(
              color: colors.surfaceContainerLow,
              child: CustomPaint(
                painter: _GridLines(columns, rows, colors.outlineVariant),
              ),
            ),
          ),
          for (final control in widget.page.gridControls)
            Positioned.fromRect(
              rect: rect(control.placement!),
              child: Listener(
                key: ValueKey(control.field),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) =>
                    _start(event, control, rect(control.placement!).size),
                onPointerMove: (event) => _move(event, cell),
                onPointerUp: (event) => _finish(event, commit: true),
                onPointerCancel: (event) => _finish(event, commit: false),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: InkWell(
                    onTap: () => widget.onSelect(control.field),
                    onDoubleTap: () => widget.onEdit(control),
                    child: Card.filled(
                      margin: const EdgeInsets.all(2),
                      color: widget.selected == control.field
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            key: control == selection
                                ? widget.selectedAnchor
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: Text(
                                widget.fields[control.field]?.label ??
                                    control.field,
                                textAlign: TextAlign.center,
                                maxLines: control.placement!.width == 1 ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (widget.selected == control.field)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeDownRight,
                                child: Tooltip(
                                  message:
                                      'Drag to resize ${widget.fields[control.field]!.label}',
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      LucideIcons.moveDiagonal2,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (selection != null &&
              widget.selectionActions != null &&
              candidate == null)
            _selectionToolbar(rect(selection.placement!), bounds),
          if (candidate != null)
            Positioned.fromRect(
              rect: rect(candidate),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: (legal ? colors.primary : colors.error).withValues(
                      alpha: .20,
                    ),
                    border: Border.all(
                      color: legal ? colors.primary : colors.error,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _selectionToolbar(Rect tile, Size bounds) {
    const width = 96.0;
    const height = 48.0;
    const gap = 4.0;
    if (bounds.width < width || bounds.height < height) {
      return const SizedBox.shrink();
    }
    final above = tile.top - height - gap;
    final below = tile.bottom + gap;
    final top = above >= 0
        ? above
        : below + height <= bounds.height
        ? below
        : tile.top + gap;
    return Positioned(
      left: (tile.center.dx - width / 2).clamp(0.0, bounds.width - width),
      top: top.clamp(0.0, bounds.height - height),
      width: width,
      child: Center(child: widget.selectionActions),
    );
  }
}

class _GridLines extends CustomPainter {
  const _GridLines(this.columns, this.rows, this.color);
  final int columns;
  final int rows;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawRect(Offset.zero & size, paint..style = PaintingStyle.stroke);
    for (var column = 1; column < columns; column++) {
      final x = column * size.width / columns;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var row = 1; row < rows; row++) {
      final y = row * size.height / rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridLines oldDelegate) =>
      columns != oldDelegate.columns ||
      rows != oldDelegate.rows ||
      color != oldDelegate.color;
}
