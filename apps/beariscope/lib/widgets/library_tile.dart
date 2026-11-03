import 'package:material_ui/material_ui.dart';

/// Shared library spacing, including room for the floating create action.
class LibraryGrid extends StatelessWidget {
  const LibraryGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.physics,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final padding = ((bounds.maxWidth - 1080) / 2).clamp(
        16.0,
        double.infinity,
      );
      final width = bounds.maxWidth - padding * 2;
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
      return GridView.builder(
        physics: physics,
        padding: EdgeInsets.fromLTRB(padding, 16, padding, 104),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 228 + extraHeight,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
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
