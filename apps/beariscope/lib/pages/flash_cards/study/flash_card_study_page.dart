import 'package:beariscope/widgets/beariscope_modal.dart';

import 'dart:async';

import 'package:beariscope/pages/flash_cards/study/flash_card_deck.dart';
import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/study/flash_card_options.dart';
import 'package:beariscope/pages/flash_cards/study/flash_card_options_sheet.dart';
import 'package:beariscope/pages/flash_cards/study/flash_card_progress.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardStudyPage extends ConsumerStatefulWidget {
  const FlashCardStudyPage({super.key, this.deckId});

  final String? deckId;

  @override
  ConsumerState<FlashCardStudyPage> createState() => _FlashCardStudyPageState();
}

class _FlashCardStudyPageState extends ConsumerState<FlashCardStudyPage> {
  late final FlashCardStore _store;
  late FlashCardOptions _options;
  int _resetGeneration = 0;
  bool _refreshingCustom = false;

  @override
  void initState() {
    super.initState();
    _store = FlashCardStore(ref.read(sharedPreferencesProvider));
    _options = _store.readOptions();
    final id = widget.deckId;
    if (id != null) {
      _refreshingCustom = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final deck = findFlashCardDeck(ref.read(flashCardLibraryProvider), id);
        for (final event in deck?.eventKeys ?? <String>[]) {
          ref.invalidate(eventTeamsProvider(event));
          ref.invalidate(flashCardEventRosterProvider(event));
          ref.invalidate(flashCardEventMediaProvider(event));
        }
        ref.invalidate(flashCardCustomTeamsProvider(id));
        ref.invalidate(flashCardCustomMediaProvider(id));
        setState(() => _refreshingCustom = false);
      });
    }
  }

  final _studyFocus = FocusNode(debugLabel: 'Flash cards');

  @override
  void dispose() {
    _studyFocus.dispose();
    super.dispose();
  }

  Future<void> _showOptions() async {
    await BeariscopeModal.show<void>(
      context,
      builder: (_) => FlashCardOptionsSheet(
        options: _options,
        onReset: () {
          final event = widget.deckId == null
              ? ref.read(currentEventProvider)
              : flashCardDeckProgressScope(widget.deckId!);
          unawaited(_store.saveProgress(event, const FlashCardProgress()));
          setState(() => _resetGeneration++);
        },
        onChanged: (options) {
          if (mounted) setState(() => _options = options);
          unawaited(_store.saveOptions(options));
        },
      ),
    );
    if (mounted && _studyFocus.context != null) _studyFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.deckId;
    final deck = id == null
        ? null
        : findFlashCardDeck(ref.watch(flashCardLibraryProvider), id);
    final eventKey = id == null
        ? ref.watch(currentEventProvider)
        : flashCardDeckProgressScope(id);
    final teamsAsync = id == null
        ? normalizeCurrentFlashCardRoster(ref.watch(teamsProvider))
        : ref.watch(flashCardCustomTeamsProvider(id));
    final controller = MainViewController.of(context);

    return Scaffold(
      appBar: AppBar(
        title: deck == null
            ? const Text('Flash Cards')
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PicklistEmoji(deck.emoji, size: 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: 'Flash card options',
            onPressed: _showOptions,
            icon: const Icon(LucideIcons.slidersHorizontal),
          ),
        ],
        leading: Navigator.of(context).canPop()
            ? const BackButton()
            : controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                tooltip: 'Open navigation',
                onPressed: controller.openDrawer,
              ),
      ),
      body: _refreshingCustom
          ? const Center(child: CircularProgressIndicator())
          : id != null && deck == null
          ? const BeariscopeStatusView(
              icon: LucideIcons.layers,
              title: 'Deck not found',
              subtitle: 'This deck may have been deleted.',
            )
          : teamsAsync.when(
              skipLoadingOnRefresh: false,
              skipLoadingOnReload: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => BeariscopeStatusView(
                icon: LucideIcons.circleAlert,
                title: 'Teams unavailable',
                subtitle: id == null
                    ? 'Could not load teams for $eventKey.'
                    : error is StateError
                    ? error.message
                    : 'Could not load all events in this deck.',
                action: FilledButton(
                  onPressed: () {
                    if (id == null) {
                      ref.invalidate(eventTeamsProvider(eventKey));
                      ref.invalidate(teamsProvider);
                    } else {
                      for (final event in deck?.eventKeys ?? <String>[]) {
                        ref.invalidate(eventTeamsProvider(event));
                        ref.invalidate(flashCardEventRosterProvider(event));
                      }
                      ref.invalidate(flashCardCustomTeamsProvider(id));
                    }
                  },
                  child: const Text('Retry'),
                ),
              ),
              data: (teams) {
                if (teams.isEmpty) {
                  return BeariscopeStatusView(
                    icon: LucideIcons.layers,
                    title: id == null
                        ? 'No teams in this event'
                        : 'No teams in this deck',
                    subtitle: id == null
                        ? 'Try another event.'
                        : 'Edit the deck’s events or team overrides.',
                  );
                }

                // Media is optional: slow or unavailable photos never block studying.
                final media =
                    (id == null
                            ? ref.watch(eventTeamMediaProvider)
                            : ref.watch(flashCardCustomMediaProvider(id)))
                        .asData
                        ?.value ??
                    const <TeamMediaRecord>[];
                return FlashCardDeck(
                  key: ValueKey(eventKey),
                  eventKey: eventKey,
                  resetGeneration: _resetGeneration,
                  store: _store,
                  teams: teams,
                  media: media,
                  options: _options,
                  focusNode: _studyFocus,
                );
              },
            ),
    );
  }
}
