import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_qr.dart';
import 'package:beariscope/pages/flash_cards/flash_card_scanner_page.dart';
import 'package:beariscope/pages/flash_cards/flash_card_import_preview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beariscope/pages/flash_cards/flash_card_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

class FlashCardDeckImportPage extends ConsumerStatefulWidget {
  const FlashCardDeckImportPage({super.key, this.asSheet = false});
  final bool asSheet;
  @override
  ConsumerState<FlashCardDeckImportPage> createState() =>
      _FlashCardDeckImportPageState();
}

class _FlashCardDeckImportPageState
    extends ConsumerState<FlashCardDeckImportPage> {
  final _code = TextEditingController();
  FlashCardDeckDefinition? _preview;
  bool _busy = false;
  String? _error;
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
  }

  Future<void> _paste() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      _code.text = clipboard?.text ?? '';
      _previewCode(_code.text, showErrors: true);
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
    _code.text = code;
    _previewCode(code, showErrors: true);
  }

  Future<void> _image() async {
    if (_busy) return;
    setState(() {
      _busy = true;
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
      _code.text = code;
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    _previewCode(_code.text, showErrors: true);
    final preview = _preview;
    if (preview == null) return;
    setState(() => _busy = true);
    try {
      final imported = await ref
          .read(flashCardLibraryProvider.notifier)
          .importDeck(preview);
      if (mounted) Navigator.pop(context, imported);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the imported deck.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FlashCardSheet(
    title: 'Import deck',
    asSheet: widget.asSheet,
    footer: FilledButton(
      onPressed: _busy ? null : _import,
      child: Text(_busy ? 'Importing…' : 'Import deck'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('deck-import-code'),
          controller: _code,
          enabled: !_busy,
          minLines: 3,
          maxLines: 5,
          maxLength: 6000,
          onChanged: (code) => _previewCode(code),
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Deck code',
            counterText: '',
            border: const OutlineInputBorder(),
            errorText: _error,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: 'Paste deck code',
              onPressed: _busy ? null : _paste,
              icon: const Icon(LucideIcons.clipboardPaste),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (flashCardCameraScanningSupported)
              OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(LucideIcons.scanQrCode),
                label: const Text('Scan QR code'),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _image,
              icon: const Icon(LucideIcons.image),
              label: const Text('QR image'),
            ),
          ],
        ),
        if (_preview case final deck?) ...[
          const SizedBox(height: 20),
          FlashCardImportPreview(
            key: const ValueKey('deck-import-preview'),
            deck: deck,
          ),
        ],
      ],
    ),
  );
}
