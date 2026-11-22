import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'calculation_preview.dart';
import 'design.dart';
import 'editor_action_bar.dart';

/// A port's visible role. Variable inputs get stable names within the calculation.
Map<String, String> calculationPorts(GamePackStepNode node) {
  final required = switch (node.operation) {
    GamePackRecipe.constant => const <String, String>{},
    GamePackRecipe.scale => {
      'scouted': 'Scouted team value',
      'official': 'Official alliance total',
      if (node.inputs.containsKey('extra'))
        'extra': 'Extra alliance contribution',
    },
    GamePackRecipe.compare => const {
      'scouted': 'Scouted team value',
      'official': 'Official alliance total',
    },
    GamePackRecipe.subtract || GamePackRecipe.divide || GamePackRecipe.less =>
      const {'left': 'First value', 'right': 'Second value'},
    GamePackRecipe.choose => const {
      'condition': 'Condition',
      'then': 'When yes',
      'else': 'When no',
    },
    GamePackRecipe.fallback => const {
      'value': 'Primary value',
      'fallback': 'Fallback value',
    },
    GamePackRecipe.rows ||
    GamePackRecipe.latestNote ||
    GamePackRecipe.add ||
    GamePackRecipe.multiply ||
    GamePackRecipe.any ||
    GamePackRecipe.all ||
    GamePackRecipe.meanOf =>
      node.inputs.isEmpty
          ? const {'value': 'First value'}
          : const <String, String>{},
    _ => const {'value': 'Input value'},
  };
  final custom = switch (node.operation) {
    GamePackRecipe.compare => const {'scouted_other': 'Second scouting value'},
    _ => const <String, String>{},
  };
  return {
    ...required,
    if (node.operation != GamePackRecipe.scale)
      for (final key in node.inputs.keys)
        if (!required.containsKey(key))
          key: custom[key] ?? gamePackKeyLabel(key),
  };
}

bool calculationHasMorePorts(GamePackStepNode node) => switch (node.operation) {
  GamePackRecipe.scale => !node.inputs.containsKey('extra'),
  GamePackRecipe.rows ||
  GamePackRecipe.latestNote ||
  GamePackRecipe.add ||
  GamePackRecipe.multiply ||
  GamePackRecipe.any ||
  GamePackRecipe.all ||
  GamePackRecipe.meanOf ||
  GamePackRecipe.compare => true,
  _ => false,
};

String calculationStepTitle(GamePackStepNode node) => switch (node.operation) {
  GamePackRecipe.average when node.grain == GamePackGrain.team =>
    'Average across team matches',
  GamePackRecipe.average when node.grain == GamePackGrain.allianceMatch =>
    'Average across alliance teams',
  GamePackRecipe.average when node.grain == GamePackGrain.match =>
    'Average across the match',
  GamePackRecipe.rate when node.grain == GamePackGrain.team =>
    'Rate across team matches',
  GamePackRecipe.rows when node.grain == GamePackGrain.team =>
    'Build a match trend',
  _ => node.operation.label,
};

typedef CalculationCanvasPreview = ({
  GamePackValue? value,
  String? explanation,
  String? issue,
});

class GamePackCalculationCanvas extends StatefulWidget {
  const GamePackCalculationCanvas({
    super.key,
    required this.calculation,
    required this.catalog,
    required this.previews,
    required this.readOnly,
    required this.connecting,
    required this.selected,
    required this.selectionActions,
    required this.onSelect,
    required this.onInput,
    required this.onOutput,
    required this.onAddInput,
    required this.onDrill,
  });

  final GamePackCalculation calculation;
  final GamePackAnalysis catalog;
  final Map<String, CalculationCanvasPreview> previews;
  final bool readOnly;
  final String? connecting;
  final String? selected;
  final List<Widget> selectionActions;
  final ValueChanged<String?> onSelect;
  final void Function(GamePackStepNode step, String port, String label) onInput;
  final ValueChanged<String> onOutput;
  final ValueChanged<GamePackStepNode> onAddInput;
  final ValueChanged<String> onDrill;

  @override
  State<GamePackCalculationCanvas> createState() =>
      GamePackCalculationCanvasState();
}

const _cardWidth = 244.0;
const _columnSpace = 78.0;
const _rowSpace = 24.0;
const _headingHeight = 67.0;
const _portHeight = 34.0;
const _valueHeight = 70.0;
const _moreHeight = 30.0;

class GamePackCalculationCanvasState extends State<GamePackCalculationCanvas> {
  final _camera = TransformationController();
  Size _view = Size.zero;
  Size _world = Size.zero;
  late Map<String, Rect> _rects = _arrange();
  bool _fitPending = true;

  @override
  void didUpdateWidget(GamePackCalculationCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.calculation.nodes, widget.calculation.nodes) ||
        oldWidget.readOnly != widget.readOnly) {
      final next = _arrange();
      if (next.length != _rects.length ||
          next.entries.any((entry) => _rects[entry.key] != entry.value)) {
        _rects = next;
        _fitPending = true;
      }
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  double _height(GamePackCalculationNode node) =>
      _headingHeight +
      _valueHeight +
      (node is GamePackStepNode
          ? calculationPorts(node).length * _portHeight +
                (!widget.readOnly && calculationHasMorePorts(node)
                    ? _moreHeight
                    : 0)
          : 0);

  Map<String, Rect> _arrange() {
    final graph = widget.calculation;
    final depths = <String, int>{};
    final visiting = <String>{};
    int depth(String id) {
      if (depths[id] case final known?) return known;
      final node = graph.nodesById[id];
      if (node == null || !visiting.add(id)) return 0;
      final level = node.inputs.values.fold<int>(
        0,
        (deepest, next) => math.max(deepest, depth(next) + 1),
      );
      visiting.remove(id);
      return depths[id] = level;
    }

    final columns = <int, List<GamePackCalculationNode>>{};
    for (final node in graph.nodes) {
      columns.putIfAbsent(depth(node.id), () => []).add(node);
    }
    // Keep each preceding lane in the order its inputs are read.
    final order = <String, int>{};
    for (final column
        in columns.keys.toList()..sort((a, b) => b.compareTo(a))) {
      final nodes = columns[column]!;
      final original = {for (final (i, node) in nodes.indexed) node.id: i};
      nodes.sort(
        (a, b) => (order[a.id] ?? original[a.id]!).compareTo(
          order[b.id] ?? original[b.id]!,
        ),
      );
      var index = 0;
      for (final node in nodes) {
        for (final id in node.inputs.values) {
          order.putIfAbsent(id, () => index++);
        }
      }
    }

    final heights = columns.map(
      (column, nodes) => MapEntry(
        column,
        nodes.fold<double>(0, (sum, node) => sum + _height(node) + _rowSpace) -
            _rowSpace,
      ),
    );
    final maxHeight = heights.values.fold<double>(0, math.max);
    final rects = <String, Rect>{};
    for (final entry in columns.entries) {
      var top = 34 + (maxHeight - heights[entry.key]!) / 2;
      for (final node in entry.value) {
        final height = _height(node);
        rects[node.id] = Rect.fromLTWH(
          32 + entry.key * (_cardWidth + _columnSpace),
          top,
          _cardWidth,
          height,
        );
        top += height + _rowSpace;
      }
    }
    return rects;
  }

  void fit({bool preserveReadability = false}) {
    if (!mounted || _view.isEmpty || _world.isEmpty) return;
    final target = math
        .min(_view.width / _world.width, _view.height / _world.height)
        .clamp(.20, 1.0);
    if (preserveReadability && target < .62 && _rects.isNotEmpty) {
      const readable = .8;
      final anchor =
          _rects[widget.selected] ??
          _rects[widget.calculation.result] ??
          _rects.values.first;
      _move(readable, _view.center(Offset.zero) - anchor.center * readable);
      return;
    }
    _move(
      target,
      (_view.center(Offset.zero) - _world.center(Offset.zero) * target),
    );
  }

  void zoom(double factor) {
    final prior = _camera.value.getMaxScaleOnAxis();
    final next = (prior * factor).clamp(.20, 2.3);
    final anchor = _view.center(Offset.zero);
    _move(next, anchor - _camera.toScene(anchor) * next);
  }

  void _move(double scale, Offset offset) {
    _camera.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(offset.dx, offset.dy, 0);
  }

  Widget _selectionToolbar(Rect node) {
    const extent = 48.0;
    const gap = 6.0;
    final width = extent * widget.selectionActions.length;
    return AnimatedBuilder(
      animation: _camera,
      child: GamePackEditorActionBar(
        children: [
          for (final action in widget.selectionActions)
            SizedBox.square(dimension: extent, child: action),
        ],
      ),
      builder: (context, child) {
        if (_view.width < width + 2 * gap || _view.height < extent + 2 * gap) {
          return const SizedBox.shrink();
        }
        final viewport = Offset.zero & _view;
        final visible = MatrixUtils.transformRect(
          _camera.value,
          node,
        ).intersect(viewport);
        if (visible.isEmpty) return const SizedBox.shrink();

        final maxLeft = viewport.right - width - gap;
        final maxTop = viewport.bottom - extent - gap;
        final centered = (visible.center.dx - width / 2).clamp(gap, maxLeft);
        final above = visible.top - extent - gap;
        final below = visible.bottom + gap;
        final right = visible.right + gap;
        final left = visible.left - width - gap;
        final sideTop = visible.top.clamp(gap, maxTop);
        final position = switch ((above, below, right, left)) {
          (final y, _, _, _) when y >= gap => Offset(centered, y),
          (_, final y, _, _) when y <= maxTop => Offset(centered, y),
          (_, _, final x, _) when x <= maxLeft => Offset(x, sideTop),
          (_, _, _, final x) when x >= gap => Offset(x, sideTop),
          _ => Offset(centered, (visible.top + gap).clamp(gap, maxTop)),
        };
        return Positioned(left: position.dx, top: position.dy, child: child!);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final nodes = widget.calculation.nodes;
    final paths = <(Offset, Offset)>[];
    for (final step in nodes.whereType<GamePackStepNode>()) {
      final rect = _rects[step.id]!;
      for (final (index, port) in calculationPorts(step).keys.indexed) {
        if (_rects[step.inputs[port]] case final from?) {
          paths.add((
            Offset(from.right, from.top + 34),
            Offset(
              rect.left,
              rect.top + _headingHeight + _portHeight * (index + .5),
            ),
          ));
        }
      }
    }
    _world = Size(
      _rects.values.fold<double>(0, (x, rect) => math.max(x, rect.right)) + 32,
      _rects.values.fold<double>(0, (y, rect) => math.max(y, rect.bottom)) + 34,
    );
    var visibleCards = <String, Widget>{};
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final shouldFit = _fitPending || _view.width != size.width;
        _view = size;
        if (shouldFit) {
          _fitPending = false;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => fit(preserveReadability: true),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.surfaceContainerLow),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _Dots(colors.outlineVariant)),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.readOnly ? null : () => widget.onSelect(null),
                  excludeFromSemantics: true,
                  child: InteractiveViewer.builder(
                    transformationController: _camera,
                    minScale: .20,
                    maxScale: 2.3,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    builder: (context, quad) {
                      final viewport = Rect.fromLTRB(
                        quad.point0.x,
                        quad.point0.y,
                        quad.point2.x,
                        quad.point2.y,
                      ).inflate(80);
                      visibleCards = {
                        for (final node in nodes)
                          if (_rects[node.id]!.overlaps(viewport))
                            node.id:
                                visibleCards[node.id] ??
                                Positioned.fromRect(
                                  key: ValueKey(node.id),
                                  rect: _rects[node.id]!,
                                  child: RepaintBoundary(
                                    child: _card(node, theme),
                                  ),
                                ),
                      };
                      return SizedBox(
                        width: _world.width,
                        height: _world.height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _Wires(
                                    paths,
                                    colors.primary.withValues(alpha: .68),
                                  ),
                                ),
                              ),
                            ),
                            ...visibleCards.values,
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (_rects[widget.selected] case final selection?
                    when widget.selectionActions.isNotEmpty)
                  _selectionToolbar(selection),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card(GamePackCalculationNode node, ThemeData theme) {
    final colors = theme.colorScheme;
    final ref = node is GamePackInputNode && node.field != null
        ? gamePackFieldRef(node.field!)
        : null;
    final field = ref == null ? null : widget.catalog.tryInfo(ref);
    final isResult = widget.calculation.result == node.id;
    final selected = widget.selected == node.id;
    final wiring = widget.connecting == node.id;
    final preview = widget.previews[node.id];
    final digest = preview?.value;
    final isSource = node is GamePackInputNode;
    final linked = field?.origin == GamePackResultOrigin.calculated
        ? ref?.output
        : null;
    final title = node is GamePackStepNode
        ? calculationStepTitle(node)
        : field?.label.split(' · ').first ?? 'Choose a field';
    final grain = node is GamePackStepNode ? node.grain : field?.grain;
    final source =
        field?.origin == GamePackResultOrigin.scouting &&
            (field?.label.contains(' · ') ?? false)
        ? field!.label.split(' · ').last
        : field?.origin.label;
    final subtitle = [
      if (isResult) 'Result' else if (source != null) source,
      if (grain != null) grain.label,
    ].join(' · ');
    final tone = isResult || selected || wiring
        ? colors.primary
        : colors.outlineVariant;
    final icon = switch (field?.origin) {
      GamePackResultOrigin.scouting => LucideIcons.clipboardList,
      GamePackResultOrigin.official => LucideIcons.database,
      GamePackResultOrigin.schedule => LucideIcons.calendar,
      GamePackResultOrigin.calculated => LucideIcons.workflow,
      _ => isSource ? LucideIcons.logIn : LucideIcons.calculator,
    };
    return Material(
      color: colors.surface,
      elevation: isResult ? 2 : 1,
      shadowColor: colors.primary.withValues(alpha: .20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: tone,
          width: selected || isResult || wiring ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _headingHeight,
            child: InkWell(
              onTap: !widget.readOnly ? () => widget.onSelect(node.id) : null,
              child: ColoredBox(
                color: isResult
                    ? colors.primaryContainer.withValues(alpha: .40)
                    : colors.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Row(
                    children: [
                      Icon(icon, color: colors.primary, size: 17),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Tooltip(
                              message: title,
                              child: Text(
                                title,
                                style: theme.textTheme.titleSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall,
                              ),
                          ],
                        ),
                      ),
                      if (widget.readOnly && linked != null)
                        IconButton(
                          tooltip: 'Open $title calculation',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 30,
                            height: 36,
                          ),
                          icon: const Icon(LucideIcons.arrowUpRight, size: 15),
                          onPressed: () => widget.onDrill(linked),
                        ),
                      if (!widget.readOnly)
                        IconButton(
                          tooltip: 'Connect from $title',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 36,
                          ),
                          icon: Icon(
                            LucideIcons.circleDot,
                            size: 15,
                            color: wiring ? colors.tertiary : colors.primary,
                          ),
                          onPressed: () => widget.onOutput(node.id),
                        )
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (node is GamePackStepNode) ...[
            for (final port in calculationPorts(node).entries)
              SizedBox(
                height: _portHeight,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 120),
                  tween: Tween(
                    begin: 0,
                    end: widget.connecting != null && !wiring ? 1 : 0,
                  ),
                  builder: (context, highlight, child) => ColoredBox(
                    color: colors.primaryContainer.withValues(
                      alpha: highlight * .45,
                    ),
                    child: child,
                  ),
                  child: InkWell(
                    onTap: widget.readOnly
                        ? null
                        : () => widget.onInput(node, port.key, port.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Row(
                        children: [
                          Icon(
                            node.inputs.containsKey(port.key)
                                ? LucideIcons.circleDot
                                : LucideIcons.circle,
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              node.inputs.containsKey(port.key)
                                  ? port.value
                                  : 'Choose ${port.value.toLowerCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!widget.readOnly && calculationHasMorePorts(node))
              SizedBox(
                height: _moreHeight,
                child: InkWell(
                  onTap: () => widget.onAddInput(node),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Row(
                      spacing: 7,
                      children: [
                        Icon(LucideIcons.plus, size: 14, color: colors.primary),
                        Text(
                          'Add input',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          Expanded(
            child: InkWell(
              onTap: widget.readOnly ? null : () => widget.onSelect(node.id),
              child: ColoredBox(
                color: isResult
                    ? colors.primaryContainer.withValues(alpha: .28)
                    : colors.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 6, 10, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        digest == null
                            ? (preview?.issue == null
                                  ? 'Test value'
                                  : 'Needs input')
                            : summarizeCalculationValue(digest),
                        key: ValueKey(('calculation-value', node.id)),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: preview?.issue != null ? colors.error : null,
                          fontWeight: digest?.isKnown == true
                              ? FontWeight.w700
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      if ((preview?.explanation ?? preview?.issue)
                          case final detail?)
                        Tooltip(
                          message: detail,
                          child: Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        )
                      else if (digest?.isKnown == true)
                        Text(
                          'Test value',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends CustomPainter {
  const _Dots(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .65);
    for (double x = 15; x < size.width; x += 23) {
      for (double y = 15; y < size.height; y += 23) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots oldDelegate) => oldDelegate.color != color;
}

class _Wires extends CustomPainter {
  const _Wires(this.paths, this.color);
  final List<(Offset, Offset)> paths;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final (from, to) in paths) {
      final control = (to.dx - from.dx).abs() * .46;
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(
            from.dx + control,
            from.dy,
            to.dx - control,
            to.dy,
            to.dx,
            to.dy,
          ),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(to.dx - 6, to.dy - 3.5)
          ..lineTo(to.dx, to.dy)
          ..lineTo(to.dx - 6, to.dy + 3.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Wires oldDelegate) =>
      oldDelegate.paths != paths || oldDelegate.color != color;
}
