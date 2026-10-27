import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_qr.dart';
import 'package:beariscope/pages/flash_cards/flash_card_scanner_page.dart';
import 'package:beariscope/pages/flash_cards/flash_card_import_preview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:beariscope/pages/flash_cards/flash_card_sheet.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardDeckImportPage extends ConsumerStatefulWidget {
  const FlashCardDeckImportPage({
    super.key,
    this.asSheet = false,
    this.initialCode,
  });
  final bool asSheet;
  final String? initialCode;
  @override
  ConsumerState<FlashCardDeckImportPage> createState() =>
      _FlashCardDeckImportPageState();
}

class _FlashCardDeckImportPageState
    extends ConsumerState<FlashCardDeckImportPage> {
  final _code = TextEditingController();
  FlashCardDeckDefinition? _preview;
  bool _readingImage = false;
  bool _saving = false;
  String? _error;

  bool get _busy => _readingImage || _saving;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode case final code?) {
      _previewCode(code, showErrors: true);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _previewCode(String code, {bool showErrors = false}) {
    FlashCardDeckDefinition? preview;
    String? error;
    try {
      preview = FlashCardDeckDefinition.fromShareCode(code);
    } on FormatException catch (invalid) {
      if (showErrors) error = invalid.message;
    }
    setState(() {
      _preview = preview;
      _error = error;
    });
    if (preview != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      _code.clear();
    }
  }

  void _chooseAnother() {
    _code.clear();
    setState(() {
      _preview = null;
      _error = null;
    });
  }

  Future<void> _paste() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      _previewCode(clipboard?.text ?? '', showErrors: true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the clipboard. Paste the code into the field.',
        );
      }
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FlashCardScannerPage()),
    );
    if (!mounted || code == null) return;
    _previewCode(code, showErrors: true);
  }

  Future<void> _image() async {
    if (_busy) return;
    setState(() {
      _readingImage = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: 'Import deck QR image',
      );
      if (file == null) return;
      if (await file.length() > 12 * 1024 * 1024) {
        throw const FormatException('Choose a QR image smaller than 12 MB.');
      }
      final bytes = await file.readAsBytes();
      final code = await compute(decodeFlashCardQrImage, bytes);
      if (!mounted) return;
      _previewCode(code, showErrors: true);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read the QR image. Try a clearer image.',
        );
      }
    } finally {
      if (mounted) setState(() => _readingImage = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final imported = await ref
          .read(flashCardLibraryProvider.notifier)
          .importDeck(preview);
      if (!mounted) return;
      if (widget.asSheet) {
        BeariscopeModal.complete(context, imported);
      } else {
        context.go('/flash_cards/${imported.id}');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the imported deck.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final existing = preview == null
        ? null
        : ref
              .watch(flashCardLibraryProvider)
              .where((deck) => deck.shareCode == preview.shareCode)
              .firstOrNull;
    return FlashCardSheet(
      title: 'Import deck',
      asSheet: widget.asSheet,
      canDismiss: !_busy,
      primaryAction: _preview == null
          ? null
          : BeariscopeModalPrimaryAction(
              label: existing == null ? 'Import deck' : 'Open deck',
              icon: existing == null
                  ? LucideIcons.check
                  : LucideIcons.arrowRight,
              loading: _saving,
              onPressed: _import,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_preview case final deck?) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                existing == null
                    ? 'Review this deck before adding it to your library.'
                    : 'Already in your library',
              ),
            ),
            const SizedBox(height: 16),
            FlashCardImportPreview(
              key: const ValueKey('deck-import-preview'),
              deck: deck,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _chooseAnother,
                icon: const Icon(LucideIcons.arrowLeft, size: 18),
                label: const Text('Choose another deck'),
              ),
            ),
          ] else ...[
            Text(
              flashCardCameraScanningSupported
                  ? 'Scan a deck QR code or choose a saved QR image.'
                  : 'Choose a saved deck QR image to get started.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (flashCardCameraScanningSupported)
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(LucideIcons.scanQrCode),
                    label: const Text('Scan QR code'),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _image,
                  icon: _readingImage
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.image),
                  label: Text(
                    _readingImage ? 'Reading image…' : 'Choose QR image',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Or paste a deck code or link',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('deck-import-code'),
              controller: _code,
              enabled: !_busy,
              maxLength: 6000,
              onChanged: (code) => _previewCode(code),
              onSubmitted: (code) => _previewCode(code, showErrors: true),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Deck code or link',
                counterText: '',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Paste deck code',
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(LucideIcons.clipboardPaste),
                ),
              ),
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
