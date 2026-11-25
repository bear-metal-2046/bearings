import 'package:material_ui/material_ui.dart';

import 'package:ui/ui.dart';

class GamePackOutputView extends StatelessWidget {
  const GamePackOutputView({
    super.key,
    required this.title,
    required this.compact,
    required this.stackActions,
    this.picker,
    this.modeSwitcher,
    this.tools = const [],
    this.actions = const [],
    this.actionTools = const [],
    this.search,
    required this.child,
  });

  final String title;
  final bool compact;
  final bool stackActions;
  final Widget? picker;
  final Widget? modeSwitcher;
  final List<Widget> tools;
  final List<Widget> actions;
  final List<Widget> actionTools;
  final Widget? search;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gutter = compact ? 16.0 : 24.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 48 : 40),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Row(
                    spacing: 8,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (picker case final control?) Flexible(child: control),
                      ...tools,
                    ],
                  ),
                ),
                ?modeSwitcher,
                if (!stackActions) ...actions,
              ],
            ),
          ),
          if (search case final field?)
            field
          else if (stackActions &&
              (actions.isNotEmpty || actionTools.isNotEmpty))
            Row(
              spacing: 8,
              children: [
                for (final action in actions) Flexible(child: action),
                ...actionTools,
              ],
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class GamePackEditPreviewSwitcher extends StatelessWidget {
  const GamePackEditPreviewSwitcher({
    super.key,
    required this.previewing,
    required this.onChanged,
  });

  final bool previewing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: BearingsCapsuleBar<bool>(
      key: const ValueKey('gamepack-edit-preview-capsule'),
      selected: previewing,
      destinations: const [
        BearingsCapsuleDestination(value: false, label: 'Edit'),
        BearingsCapsuleDestination(value: true, label: 'Preview'),
      ],
      onActivated: (next) {
        if (next != previewing) onChanged(next);
      },
    ),
  );
}

class GamePackOutputEmpty extends StatelessWidget {
  const GamePackOutputEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      primary: false,
      padding: const EdgeInsets.only(top: 44, bottom: 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              spacing: 10,
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  child: Icon(icon, size: 22),
                ),
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
