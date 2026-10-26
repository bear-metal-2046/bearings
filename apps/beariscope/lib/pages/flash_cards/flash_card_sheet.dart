import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

Future<T?> showFlashCardSheet<T>(BuildContext context, Widget child) =>
    Navigator.of(context).push<T>(
      StupidSimpleSheetRoute(originateAboveBottomViewInset: true, child: child),
    );

/// The same compact, scrollable sheet structure used by picklist options.
class FlashCardSheet extends StatelessWidget {
  const FlashCardSheet({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.actions = const [],
    this.asSheet = true,
    this.scrollable = true,
  });

  final String title;
  final Widget child;
  final Widget? footer;
  final List<Widget> actions;
  final bool asSheet;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (asSheet) ...[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ...actions,
              IconButton(
                tooltip: 'Close options',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: scrollable ? SingleChildScrollView(child: child) : child,
          ),
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ],
      ),
    );
    final panel = SafeArea(
      child: Center(
        heightFactor: asSheet ? 1 : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
          child: Material(
            color: colors.surface,
            borderRadius: asSheet
                ? const BorderRadius.vertical(top: Radius.circular(28))
                : BorderRadius.zero,
            clipBehavior: Clip.antiAlias,
            child: content,
          ),
        ),
      ),
    );
    return asSheet ? panel : Scaffold(body: panel);
  }
}
