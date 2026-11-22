import 'package:material_ui/material_ui.dart';

/// A responsive grid that uses the surrounding scaffold's scroll padding.
class LibraryGrid extends StatelessWidget {
  const LibraryGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.padding,
    this.physics,
    this.header,
    this.footer,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollPhysics? physics;
  final EdgeInsets padding;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final gutter = (bounds.maxWidth - 1080) / 2;
      final contentPadding = padding.copyWith(
        left: gutter > padding.left ? gutter : padding.left,
        right: gutter > padding.right ? gutter : padding.right,
      );
      final width = bounds.maxWidth - contentPadding.horizontal;
      final scaler = MediaQuery.textScalerOf(context);
      final largeText = scaler.scale(14) > 20;
      final columns = ((width + 16) / (largeText ? 296 : 172)).floor().clamp(
        1,
        4,
      );
      // Budget for two title and two metadata lines as text grows, keeping
      // the thumbnail visible instead of squeezing it into the remaining space.
      final extraHeight =
          (scaler.scale(16) - 16).clamp(0.0, double.infinity) * 3 +
          (scaler.scale(12) - 12).clamp(0.0, double.infinity) * 3;
      final gridPadding = contentPadding.copyWith(
        top: header == null ? contentPadding.top : 0,
      );
      return CustomScrollView(
        physics: physics,
        slivers: [
          if (header case final header?)
            SliverPadding(
              padding: contentPadding,
              sliver: SliverToBoxAdapter(child: header),
            ),
          SliverPadding(
            padding: gridPadding,
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: 228 + extraHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                itemBuilder,
                childCount: itemCount,
              ),
            ),
          ),
          if (footer case final footer?)
            SliverPadding(
              padding: contentPadding.copyWith(top: 0),
              sliver: SliverToBoxAdapter(child: footer),
            ),
        ],
      );
    },
  );
}

/// Emoji or icon first, then a readable title and feature-specific metadata.
class LibraryTile extends StatelessWidget {
  const LibraryTile({
    super.key,
    required this.title,
    required this.caption,
    required this.color,
    required this.thumbnail,
    required this.onTap,
    this.options,
    this.footer,
  });

  final String title;
  final String caption;
  final Color color;
  final Widget thumbnail;
  final VoidCallback onTap;
  final Widget? options;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: color,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: MediaQuery.withNoTextScaling(child: thumbnail),
                    ),
                    if (options != null)
                      Positioned(top: 4, right: 4, child: options!),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (footer != null) ...[const SizedBox(height: 10), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
