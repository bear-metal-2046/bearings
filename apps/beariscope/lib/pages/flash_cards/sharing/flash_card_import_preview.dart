import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_provider.dart';
import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/picklists/picklist_emoji_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardImportPreview extends ConsumerWidget {
  const FlashCardImportPreview({super.key, required this.deck});
  final FlashCardDeckDefinition deck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final years = deck.eventKeys
        .map((key) => int.parse(key.substring(0, 4)))
        .toSet();
    final catalogs = {
      for (final year in years)
        year: ref.watch(flashCardEventCatalogProvider(year)),
    };
    final names = {
      for (final catalog in catalogs.values)
        for (final event in catalog.asData?.value ?? [])
          event.key: event.shortName,
    };
    final rosters = {
      for (final key in deck.eventKeys)
        key: ref.watch(flashCardEventRosterProvider(key)),
    };
    final failed = rosters.values.any((roster) => roster.hasError);
    final ready = rosters.values.every((roster) => roster.asData != null);
    final teamCount = ready
        ? flashCardTeamsForDeck(deck, {
            for (final entry in rosters.entries)
              entry.key: entry.value.requireValue,
          }).length
        : null;
    final eventsLabel =
        '${deck.eventKeys.length} ${deck.eventKeys.length == 1 ? 'event' : 'events'}';
    final countLabel = teamCount != null
        ? '$teamCount ${teamCount == 1 ? 'team' : 'teams'} · $eventsLabel'
        : failed
        ? 'Team count unavailable'
        : 'Counting teams…';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: picklistThumbnailColor(deck.emoji, colors),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: PicklistEmoji(deck.emoji, size: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        countLabel,
                        key: const ValueKey('deck-import-team-count'),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (failed)
                  IconButton(
                    tooltip: 'Retry team count',
                    icon: const Icon(LucideIcons.refreshCw, size: 18),
                    onPressed: () {
                      for (final entry in rosters.entries) {
                        if (entry.value.hasError) {
                          ref.invalidate(
                            flashCardEventRosterProvider(entry.key),
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final key in deck.eventKeys)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  names[key] == null
                      ? key
                      : '${names[key]} · ${key.substring(0, 4)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            if (catalogs.values.any((catalog) => catalog.hasError))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    for (final entry in catalogs.entries) {
                      if (entry.value.hasError) {
                        ref.invalidate(
                          flashCardEventCatalogProvider(entry.key),
                        );
                      }
                    }
                  },
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Retry event names'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
