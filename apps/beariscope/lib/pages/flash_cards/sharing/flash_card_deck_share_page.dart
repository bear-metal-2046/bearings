import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/sharing/flash_card_share_card.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

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
  final _cardKey = GlobalKey();
  // Deal once per sheet, so copying or exporting never makes the card jump.
  late final double _angle =
      (math.Random().nextBool() ? 1 : -1) *
      (1.2 + math.Random().nextDouble() * 1.6) *
      math.pi /
      180;
  bool _saving = false;

  bool get _nativeSharing =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
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

  Future<Uint8List> _cardImage() async {
    final boundary =
        _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(
      pixelRatio: 1200 / boundary.size.width,
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('The card could not be rendered.');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  Future<void> _shareImage(FlashCardDeckDefinition deck) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _cardImage();
      if (!mounted) return;
      final slug = deck.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final filename = '${slug.isEmpty ? 'flashcard-deck' : slug}.png';
      if (_nativeSharing) {
        final box = _cardKey.currentContext!.findRenderObject() as RenderBox;
        await SharePlus.instance.share(
          ShareParams(
            text: 'Study my flashcards on Beariscope:\n\n${deck.shareCode}',
            files: [
              XFile.fromData(bytes, mimeType: 'image/png', name: filename),
            ],
            fileNameOverrides: [filename],
            subject: deck.name,
            sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      } else {
        final saved = await FilePicker.saveFile(
          dialogTitle: 'Save deck card',
          fileName: filename,
          bytes: bytes,
          mimeType: 'image/png',
        );
        if (saved != null) _message('Deck card saved.');
      }
    } catch (_) {
      _message('Could not share the deck card. Try again.');
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
    final modal = BeariscopeModal(
      size: BeariscopeModalSize.tall,
      title: 'Share deck',
      actions: [
        if (deck != null)
          BeariscopeModalAction(
            label: 'Copy code',
            icon: LucideIcons.copy,
            onPressed: () => _copy(deck.shareCode),
          ),
      ],
      primaryAction: deck == null
          ? null
          : BeariscopeModalPrimaryAction(
              label: _nativeSharing ? 'Share image' : 'Save image',
              icon: _nativeSharing ? LucideIcons.share : LucideIcons.download,
              onPressed: _saving ? null : () => _shareImage(deck),
              loading: _saving,
            ),
      content: deck == null
          ? const Text('Deck not found')
          : Padding(
              // Reserve space for the rotated corners and the table shadow.
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Transform.rotate(
                    key: const ValueKey('deck-share-tilt'),
                    angle: _angle,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          FlashCardShareCard.cornerRadius,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .18),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .10),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: RepaintBoundary(
                        key: _cardKey,
                        child: FlashCardShareCard(
                          key: const ValueKey('deck-share-card'),
                          deck: deck,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
    if (widget.asSheet) return modal;
    return Scaffold(
      body: SafeArea(child: Center(child: modal)),
    );
  }
}
