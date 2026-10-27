import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:material_ui/material_ui.dart';

/// Uses the same modal chrome when a flash card view is opened as a page.
class FlashCardSheet extends StatelessWidget {
  const FlashCardSheet({
    super.key,
    required this.title,
    required this.child,
    this.primaryAction,
    this.actions = const [],
    this.asSheet = true,
    this.scrollable = true,
    this.canDismiss = true,
  });

  final String title;
  final Widget child;
  final BeariscopeModalPrimaryAction? primaryAction;
  final List<BeariscopeModalAction> actions;
  final bool asSheet;
  final bool scrollable;
  final bool canDismiss;

  @override
  Widget build(BuildContext context) {
    final content = BeariscopeModal(
      title: title,
      actions: actions,
      size: BeariscopeModalSize.tall,
      scrolling: scrollable
          ? BeariscopeModalScrolling.managed
          : BeariscopeModalScrolling.content,
      primaryAction: primaryAction,
      canDismiss: canDismiss,
      content: child,
    );
    if (asSheet) return content;
    return Scaffold(
      body: SafeArea(child: Center(child: content)),
    );
  }
}
