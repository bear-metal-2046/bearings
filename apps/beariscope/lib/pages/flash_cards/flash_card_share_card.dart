import 'dart:math' as math;

import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/picklists/picklist_emoji.dart';
import 'package:beariscope/pages/picklists/picklist_emoji_colors.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The complete card shown in the share sheet and captured for image export.
/// Its QR keeps a white quiet zone in both light and dark themes.
class FlashCardShareCard extends StatelessWidget {
  const FlashCardShareCard({super.key, required this.deck});

  // QR radius (12) + inset (20) keeps the lower corners concentric.
  static const cornerRadius = 32.0;

  final FlashCardDeckDefinition deck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final qr = QrCode.fromData(
      data: deck.shareLink,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: picklistThumbnailColor(deck.emoji, colors),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      MediaQuery.withNoTextScaling(
                        child: Text(
                          'Flashcards on Beariscope',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ExcludeSemantics(
                  child: MediaQuery.withNoTextScaling(
                    child: PicklistEmoji(deck.emoji, size: 48),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Semantics(
              image: true,
              label: 'QR code to import ${deck.name}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RepaintBoundary(
                  key: const ValueKey('deck-share-qr'),
                  child: LayoutBuilder(
                    builder: (context, bounds) => QrImageView.withQr(
                      qr: qr,
                      padding: EdgeInsets.all(
                        math.max(
                          20,
                          bounds.maxWidth * 4 / (qr.moduleCount + 8),
                        ),
                      ),
                      backgroundColor: Colors.white,
                      gapless: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
