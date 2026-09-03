import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class TileableCardView extends StatelessWidget {
  final List<Widget> children;
  final double horizontalSpacing;
  final double verticalSpacing;
  final double maxColumnWidth;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  final Widget? emptyState;

  /// A masonry grid for tileable cards.
  const TileableCardView({
    super.key,
    required this.children,
    this.horizontalSpacing = 16,
    this.verticalSpacing = 16,
    this.maxColumnWidth = 300,
    this.padding = const EdgeInsets.all(16.0),
    this.controller,
    this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty && emptyState != null) {
      return Center(child: emptyState);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = max(
          1,
          (constraints.maxWidth / maxColumnWidth).floor(),
        );
        return MasonryGridView.count(
          controller: controller,
          crossAxisCount: crossAxisCount,
          padding: padding,
          crossAxisSpacing: horizontalSpacing,
          mainAxisSpacing: verticalSpacing,
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}
