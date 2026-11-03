import 'dart:async';

import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_model.dart';
import 'package:flutter/foundation.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

bool get flashCardCameraScanningSupported =>
    kIsWeb ||
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

class FlashCardScannerPage extends StatefulWidget {
  const FlashCardScannerPage({super.key});
  @override
  State<FlashCardScannerPage> createState() => _FlashCardScannerPageState();
}

class _FlashCardScannerPageState extends State<FlashCardScannerPage>
    with WidgetsBindingObserver {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  String? _error;
  bool _accepted = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_camera.value.hasCameraPermission || _accepted) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_camera.start().catchError((Object _) {}));
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_camera.stop());
    }
  }

  void _detect(BarcodeCapture capture) {
    if (_accepted || !mounted) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null) continue;
      try {
        FlashCardDeckDefinition.fromShareCode(code);
        _accepted = true;
        unawaited(_camera.stop());
        Navigator.pop(context, code);
        return;
      } on FormatException catch (error) {
        setState(() => _error = error.message);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan deck QR code')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _camera,
          onDetect: _detect,
          tapToFocus: true,
          onDetectError: (_, _) {
            if (mounted) {
              setState(() => _error = 'Could not read that code. Try again.');
            }
          },
          errorBuilder: (context, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.cameraOff, size: 40),
                  const SizedBox(height: 16),
                  const Text(
                    'Camera unavailable',
                    style: TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Allow camera access, or go back to import a code or QR image.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go back'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_error != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Card(
                margin: const EdgeInsets.all(20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
