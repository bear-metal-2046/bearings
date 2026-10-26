import 'package:beariscope/pages/flash_cards/flash_card_options.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardOptionsSheet extends StatefulWidget {
  const FlashCardOptionsSheet({
    super.key,
    required this.options,
    required this.onChanged,
    required this.onReset,
  });

  final FlashCardOptions options;
  final ValueChanged<FlashCardOptions> onChanged;
  final VoidCallback onReset;

  @override
  State<FlashCardOptionsSheet> createState() => _FlashCardOptionsSheetState();
}

class _FlashCardOptionsSheetState extends State<FlashCardOptionsSheet> {
  late FlashCardOptions _options = widget.options;

  void _update(FlashCardOptions options) {
    HapticFeedback.selectionClick();
    setState(() => _options = options);
    widget.onChanged(options);
  }

  Future<void> _confirmReset() async {
    HapticFeedback.selectionClick();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text(
          'All teams in this deck will move back to Still learning. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset progress'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onReset();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Options',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close options',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(LucideIcons.x),
                      ),
                    ],
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Text('Show first', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 8),
                          SegmentedButton<bool>(
                            expandedInsets: EdgeInsets.zero,
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Number'),
                              ),
                              ButtonSegment(value: true, label: Text('Name')),
                            ],
                            selected: {_options.nameFirst},
                            onSelectionChanged: (value) => _update(
                              _options.copyWith(nameFirst: value.single),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(LucideIcons.shuffle),
                            title: const Text('Shuffle'),
                            value: _options.shuffled,
                            onChanged: (value) =>
                                _update(_options.copyWith(shuffled: value)),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(LucideIcons.image),
                            title: const Text('Robot photos'),
                            value: _options.showPhotos,
                            onChanged: (value) =>
                                _update(_options.copyWith(showPhotos: value)),
                          ),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(LucideIcons.rotateCcw),
                            title: const Text('Reset progress'),
                            onTap: _confirmReset,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
