part of '../beariscope_modal.dart';

class _AndroidModalHeader extends StatelessWidget {
  const _AndroidModalHeader({
    required this.title,
    required this.actions,
    required this.onClose,
    required this.showGrabber,
  });

  // Android sheet toolbar. The title shares the content's leading gutter.
  static const _padding = EdgeInsets.fromLTRB(16, 4, 8, 8);
  static const _titleGap = 8.0;
  static const _grabberWidth = 36.0;
  static const _grabberHeight = 4.0;
  static const _grabberPadding = EdgeInsets.only(top: 8, bottom: 4);

  final String title;
  final List<BeariscopeModalAction> actions;
  final VoidCallback? onClose;
  final bool showGrabber;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showGrabber)
        Padding(
          padding: _grabberPadding,
          child: Container(
            key: const ValueKey('beariscope-modal-grabber'),
            width: _grabberWidth,
            height: _grabberHeight,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(_grabberHeight / 2),
            ),
          ),
        ),
      Padding(
        padding: _padding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: _titleGap),
            for (final action in actions)
              IconButton(
                tooltip: action.label,
                onPressed: action.enabled ? action.onPressed : null,
                icon: Icon(action.icon),
              ),

            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(LucideIcons.x),
            ),
          ],
        ),
      ),
    ],
  );
}
