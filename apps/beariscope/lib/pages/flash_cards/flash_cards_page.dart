import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_editor_page.dart';
import 'package:beariscope/pages/flash_cards/sharing/flash_card_deck_import_page.dart';
import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/study/flash_card_progress.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:beariscope/widgets/library_tile.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/picklists/picklist_emoji_colors.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardsPage extends ConsumerStatefulWidget {
  const FlashCardsPage({super.key});
  @override
  ConsumerState<FlashCardsPage> createState() => _FlashCardsPageState();
}

class _FlashCardsPageState extends ConsumerState<FlashCardsPage> {
  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) setState(() {});
  }

  Future<void> _create({bool importing = false}) async {
    final deck = await BeariscopeModal.show<FlashCardDeckDefinition>(
      context,

      builder: (_) => importing
          ? const FlashCardDeckImportPage(asSheet: true)
          : const FlashCardDeckEditorPage(asSheet: true),
    );
    if (mounted && deck != null) await _open('/flash_cards/${deck.id}');
  }

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final decks = ref.watch(flashCardLibraryProvider);
    final event = ref.watch(currentEventProvider);
    final eventName =
        ref
            .watch(teamEventsProvider)
            .asData
            ?.value
            .where((option) => option.key == event)
            .firstOrNull
            ?.shortName ??
        event;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flash Cards'),
        leading: controller.isDesktop
            ? null
            : IconButton(
                tooltip: 'Open navigation',
                icon: const Icon(LucideIcons.menu),
                onPressed: controller.openDrawer,
              ),
        actions: [
          IconButton(
            tooltip: 'Import deck',
            icon: const Icon(LucideIcons.import),
            onPressed: () => _create(importing: true),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LibraryGrid(
          itemCount: decks.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _DeckTile(
                key: const ValueKey('flash-card-current-event'),
                title: eventName,
                caption: 'Current event',
                progressScope: event,
                color: colors.primaryContainer,
                thumbnail: Icon(
                  LucideIcons.calendarDays,
                  size: 48,
                  color: colors.onPrimaryContainer,
                ),
                onTap: () => _open('/flash_cards/current'),
              );
            }
            final deck = decks[index - 1];
            return _DeckTile(
              key: ValueKey('deck-${deck.id}'),
              title: deck.name,
              caption:
                  '${deck.eventKeys.length} ${deck.eventKeys.length == 1 ? 'event' : 'events'}',
              progressScope: deck.progressScope,
              deckId: deck.id,
              color: picklistThumbnailColor(deck.emoji, colors),
              thumbnail: PicklistEmoji(deck.emoji, size: 56),
              onTap: () => _open('/flash_cards/${deck.id}'),
              options: IconButton(
                tooltip: 'Deck options for ${deck.name}',
                icon: const Icon(LucideIcons.ellipsis, size: 20),
                onPressed: () => BeariscopeModal.show<FlashCardDeckDefinition>(
                  context,

                  builder: (_) =>
                      FlashCardDeckEditorPage(deckId: deck.id, asSheet: true),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(LucideIcons.plus),
        label: const Text('New deck'),
      ),
    );
  }
}

class _DeckTile extends ConsumerWidget {
  const _DeckTile({
    super.key,
    required this.title,
    required this.caption,
    required this.progressScope,
    this.deckId,
    required this.color,
    required this.thumbnail,
    required this.onTap,
    this.options,
  });
  final String title;
  final String caption;
  final String progressScope;
  final String? deckId;
  final Color color;
  final Widget thumbnail;
  final VoidCallback onTap;
  final Widget? options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = deckId == null
        ? normalizeCurrentFlashCardRoster(ref.watch(teamsProvider))
        : ref.watch(flashCardCustomTeamsProvider(deckId!));
    final teams = roster.asData?.value
        .where((team) => team.number > 0)
        .map((team) => 'frc${team.number}')
        .toSet();
    final ratings = FlashCardStore(ref.watch(sharedPreferencesProvider))
        .readProgress(progressScope)
        .ratings;
    final learned = teams == null
        ? null
        : teams.isEmpty
        ? 0.0
        : teams.where((key) => ratings[key] == true).length / teams.length;
    return LibraryTile(
      title: title,
      caption: caption,
      color: color,
      thumbnail: thumbnail,
      onTap: onTap,
      options: options,
      footer: _LearnedProgress(
        fraction: learned,
        label: title,
        failed: roster.hasError,
      ),
    );
  }
}

class _LearnedProgress extends StatelessWidget {
  const _LearnedProgress({
    required this.fraction,
    required this.label,
    required this.failed,
  });
  final double? fraction;
  final String label;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final percentage = fraction == null ? null : (fraction! * 100).round();
    final status = percentage == null
        ? failed
              ? 'Progress unavailable'
              : 'Loading progress'
        : '$percentage% learned';
    return Semantics(
      label: percentage == null ? '$label: $status' : null,
      child: Tooltip(
        message: status,
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                excluding: percentage == null,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: fraction ?? 0),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: colors.outlineVariant.withValues(
                      alpha: .5,
                    ),
                    color: colors.primary,
                    stopIndicatorRadius: 0,
                    trackGap: 0,
                    semanticsLabel: '$label learned',
                    semanticsValue: percentage == null ? null : '$percentage%',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Text(
                percentage == null ? '—' : '$percentage%',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
