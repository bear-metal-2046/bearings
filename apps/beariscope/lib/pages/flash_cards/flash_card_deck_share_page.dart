import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_qr.dart';
import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/flash_cards/flash_card_sheet.dart';
import 'package:beariscope/pages/picklists/picklist_emoji_colors.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

class FlashCardDeckSharePage extends ConsumerStatefulWidget {
  const FlashCardDeckSharePage({
    super.key,
    required this.deckId,
    this.asSheet = false,
  });
  final bool asSheet;
  final String deckId;
  @override
  ConsumerState<FlashCardDeckSharePage> createState() =>
      _FlashCardDeckSharePageState();
}

class _FlashCardDeckSharePageState
    extends ConsumerState<FlashCardDeckSharePage> {
  bool _saving = false;
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _copy(String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
      _message('Deck code copied.');
    } catch (_) {
      _message('Could not copy the deck code.');
    }
  }

  Future<void> _download(String code, String name) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await renderFlashCardQr(code);
      if (!mounted) return;
      final slug = name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save deck QR code',
        fileName: '${slug.isEmpty ? 'flashcard-deck' : slug}.png',
        bytes: bytes,
        mimeType: 'image/png',
      );
      if (saved != null) _message('QR code saved.');
    } catch (_) {
      _message('Could not save the QR code. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deck = findFlashCardDeck(
      ref.watch(flashCardLibraryProvider),
      widget.deckId,
    );
    return FlashCardSheet(
      title: 'Share deck',
      asSheet: widget.asSheet,
      footer: deck == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => _copy(deck.shareCode),
                  icon: const Icon(LucideIcons.copy),
                  label: const Text('Copy code'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _download(deck.shareCode, deck.name),
                  icon: const Icon(LucideIcons.download),
                  label: Text(_saving ? 'Saving…' : 'Download QR code'),
                ),
              ],
            ),
      child: deck == null
          ? const Text('Deck not found')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: picklistThumbnailColor(
                          deck.emoji,
                          Theme.of(context).colorScheme,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: PicklistEmoji(deck.emoji, size: 32),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        deck.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, bounds) => Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: RepaintBoundary(
                        key: const ValueKey('deck-share-qr'),
                        child: QrImageView(
                          data: deck.shareCode,
                          size: bounds.maxWidth.clamp(0, 300),
                          padding: const EdgeInsets.all(20),
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          gapless: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
