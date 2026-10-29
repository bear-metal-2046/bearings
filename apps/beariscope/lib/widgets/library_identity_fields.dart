import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/picklists/picklist_emoji_colors.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

/// The same name and thumbnail controls for creating and editing library items.
class LibraryIdentityFields extends StatelessWidget {
  const LibraryIdentityFields({
    super.key,
    required this.nameController,
    required this.nameLabel,
    required this.emoji,
    required this.onEmojiChanged,
    required this.maxLength,
    this.enabled = true,
    this.onSubmitted,
    this.details = const [],
  });

  final TextEditingController nameController;
  final String nameLabel;
  final String emoji;
  final ValueChanged<String> onEmojiChanged;
  final int maxLength;
  final bool enabled;
  final VoidCallback? onSubmitted;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: picklistThumbnailColor(emoji, colors),
              borderRadius: BorderRadius.circular(22),
            ),
            child: MediaQuery.withNoTextScaling(
              child: PicklistEmoji(emoji, size: 56),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: nameController,
          enabled: enabled,
          maxLength: maxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: onSubmitted == null ? null : TextInputAction.done,
          onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
          decoration: InputDecoration(
            labelText: nameLabel,
            counterText: '',
            border: const OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Enter a name' : null,
        ),
        ...details,
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Choose an emoji',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Surprise me',
              onPressed: enabled
                  ? () => onEmojiChanged(randomPicklistEmoji())
                  : null,
              icon: const Icon(LucideIcons.shuffle, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final option in picklistEmojis)
              Semantics(
                button: true,
                enabled: enabled,
                selected: emoji == option,
                label: 'Use $option as thumbnail',
                excludeSemantics: true,
                onTap: enabled ? () => onEmojiChanged(option) : null,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Material(
                    color: emoji == option
                        ? colors.primaryContainer
                        : colors.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: emoji == option
                            ? colors.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: enabled ? () => onEmojiChanged(option) : null,
                      child: Center(
                        child: MediaQuery.withNoTextScaling(
                          child: PicklistEmoji(option, size: 28),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
