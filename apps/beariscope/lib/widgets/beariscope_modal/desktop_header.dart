part of '../beariscope_modal.dart';

class _DesktopModalHeader extends StatelessWidget {
  const _DesktopModalHeader({
    required this.title,
    required this.actions,
    required this.onClose,
  });

  // Desktop dialog toolbar. The title shares the content's leading gutter.
  static const _padding = EdgeInsets.fromLTRB(16, 8, 8, 8);
  static const _titleGap = 12.0;

  final String title;
  final List<BeariscopeModalAction> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
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
  );
}
