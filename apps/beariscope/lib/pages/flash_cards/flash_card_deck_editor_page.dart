import 'package:beariscope/widgets/beariscope_alert_dialog.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_share_page.dart';
import 'package:beariscope/pages/flash_cards/flash_card_event_picker.dart';
import 'package:beariscope/pages/flash_cards/flash_card_sheet.dart';
import 'package:beariscope/widgets/library_identity_fields.dart';
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
    final events = await BeariscopeModal.show<Set<String>>(
      context,

      builder: (_) => FlashCardEventPicker(selected: _events),
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
    final confirmed = await BeariscopeAlertDialog.show<bool>(
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
        setState(() => _saving = false);
        await BeariscopeModal.show<void>(
          context,

          builder: (_) =>
              FlashCardDeckSharePage(deckId: deck.id, asSheet: true),
        );
      } else {
        BeariscopeModal.complete(context, deck);
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
          BeariscopeModalAction(
            label: 'Share deck',
            icon: LucideIcons.share,
            onPressed: _saving ? null : () => _save(share: true),
          ),
        if (_original != null)
          BeariscopeModalAction(
            label: 'Delete deck',
            icon: LucideIcons.trash2,
            onPressed: _saving ? null : _delete,
          ),
      ],
      canDismiss: !_saving,
      primaryAction: missing
          ? null
          : BeariscopeModalPrimaryAction(
              label: widget.deckId == null ? 'Create deck' : 'Save changes',
              icon: LucideIcons.check,
              loading: _saving,
              onPressed: _save,
            ),
      child: missing
          ? const Text('Deck not found')
          : Form(
              key: _form,
              child: LibraryIdentityFields(
                nameController: _name,
                nameLabel: 'Deck name',
                emoji: _emoji,
                maxLength: 64,
                enabled: !_saving,
                onEmojiChanged: (emoji) => setState(() => _emoji = emoji),
                details: [
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
                ],
              ),
            ),
    );
  }
}
