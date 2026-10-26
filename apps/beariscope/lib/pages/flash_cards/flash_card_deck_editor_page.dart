import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_share_page.dart';
import 'package:beariscope/pages/flash_cards/flash_card_event_picker.dart';
import 'package:beariscope/pages/flash_cards/flash_card_sheet.dart';
import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/picklists/picklist_emoji_colors.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardDeckEditorPage extends ConsumerStatefulWidget {
  const FlashCardDeckEditorPage({super.key, this.deckId, this.asSheet = false});
  final String? deckId;
  final bool asSheet;
  @override
  ConsumerState<FlashCardDeckEditorPage> createState() =>
      _FlashCardDeckEditorPageState();
}

class _FlashCardDeckEditorPageState
    extends ConsumerState<FlashCardDeckEditorPage> {
  final _form = GlobalKey<FormState>();
  late final FlashCardDeckDefinition? _original;
  late final TextEditingController _name;
  late String _emoji;
  late Set<String> _events;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _original = findFlashCardDeck(
      ref.read(flashCardLibraryProvider),
      widget.deckId,
    );
    _name = TextEditingController(text: _original?.name ?? '');
    _emoji = _original?.emoji ?? randomPicklistEmoji();
    _events = {...?_original?.eventKeys};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _chooseEvents() async {
    FocusScope.of(context).unfocus();
    final events = await showFlashCardSheet<Set<String>>(
      context,
      FlashCardEventPicker(selected: _events),
    );
    if (mounted && events != null) {
      setState(() {
        _events = events;
        _error = null;
      });
    }
  }

  Future<void> _delete() async {
    final deck = _original;
    if (deck == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete deck?'),
        content: Text(
          '“${deck.name}” and its progress will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(flashCardLibraryProvider.notifier).delete(deck);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not delete the deck.';
        });
      }
    }
  }

  Future<void> _save({bool share = false}) async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final deck = FlashCardDeckDefinition.create(
        id: _original?.id,
        name: _name.text,
        emoji: _emoji,
        eventKeys: _events,
        createdAt: _original?.createdAt,
      );
      await ref.read(flashCardLibraryProvider.notifier).save(deck);
      if (!mounted) return;
      if (share) {
        await showFlashCardSheet<void>(
          context,
          FlashCardDeckSharePage(deckId: deck.id, asSheet: true),
        );
      } else {
        Navigator.pop(context, deck);
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the deck. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final missing = widget.deckId != null && _original == null;
    return FlashCardSheet(
      asSheet: widget.asSheet,
      title: widget.deckId == null ? 'New deck' : 'Deck options',
      actions: [
        if (_original != null)
          IconButton(
            tooltip: 'Share deck',
            onPressed: _saving ? null : () => _save(share: true),
            icon: const Icon(LucideIcons.share),
          ),
        if (_original != null)
          IconButton(
            tooltip: 'Delete deck',
            onPressed: _saving ? null : _delete,
            icon: Icon(LucideIcons.trash2, color: colors.error),
          ),
      ],
      footer: missing
          ? null
          : FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : widget.deckId == null
                    ? 'Create deck'
                    : 'Save changes',
              ),
            ),
      child: missing
          ? const Text('Deck not found')
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: picklistThumbnailColor(_emoji, colors),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: PicklistEmoji(_emoji, size: 56),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    maxLength: 64,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Deck name',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: const Icon(LucideIcons.calendarDays),
                      title: const Text('Events'),
                      subtitle: Text(
                        _events.isEmpty
                            ? 'Choose events'
                            : '${_events.length} selected',
                      ),
                      trailing: const Icon(LucideIcons.chevronRight, size: 20),
                      onTap: _saving ? null : _chooseEvents,
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
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
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _emoji = randomPicklistEmoji(),
                              ),
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
                      for (final emoji in picklistEmojis)
                        Semantics(
                          button: true,
                          selected: _emoji == emoji,
                          label: 'Use $emoji as thumbnail',
                          excludeSemantics: true,
                          onTap: _saving
                              ? null
                              : () => setState(() => _emoji = emoji),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Material(
                              color: _emoji == emoji
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: _emoji == emoji
                                      ? colors.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _saving
                                    ? null
                                    : () => setState(() => _emoji = emoji),
                                child: Center(
                                  child: PicklistEmoji(emoji, size: 28),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
