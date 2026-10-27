import 'package:beariscope/widgets/beariscope_alert_dialog.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
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
    final confirmed = await BeariscopeAlertDialog.show<bool>(
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
    return BeariscopeModal(
      title: 'Study Options',
      actions: const [],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Show first', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('Number')),
              ButtonSegment(value: true, label: Text('Name')),
            ],
            selected: {_options.nameFirst},
            onSelectionChanged: (value) =>
                _update(_options.copyWith(nameFirst: value.single)),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(LucideIcons.shuffle),
            title: const Text('Shuffle'),
            value: _options.shuffled,
            onChanged: (value) => _update(_options.copyWith(shuffled: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(LucideIcons.image),
            title: const Text('Robot photos'),
            value: _options.showPhotos,
            onChanged: (value) => _update(_options.copyWith(showPhotos: value)),
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
    );
  }
}
