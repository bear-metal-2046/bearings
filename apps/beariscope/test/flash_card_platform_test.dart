import 'dart:async';

import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_qr.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'flash_card_library_test.dart' show showFlashCardLibraryTestApp;

class _Scanner extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  bool denied = false;
  int stops = 0;
  int disposals = 0;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _FileExport extends FilePickerPlatform {
  ({String name, String mime, Uint8List bytes})? result;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    result = (name: fileName, mime: mimeType, bytes: bytes);
    return Uri.file('/tmp/$fileName');
  }
}

void main() {
  testWidgets(
    'camera rejects unrelated QR codes and previews a valid deck exactly once',
    (tester) async {
      final previous = MobileScannerPlatform.instance;
      final scanner = _Scanner();
      final platform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MobileScannerPlatform.instance = scanner;
      try {
        final app = await showFlashCardLibraryTestApp(tester);
        await tester.tap(find.byTooltip('Import deck'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Scan QR code'));
        await tester.pumpAndSettle();
        scanner.captures.add(
          const BarcodeCapture(
            barcodes: [
              Barcode(rawValue: 'unrelated', format: BarcodeFormat.qrCode),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('This is not a valid flashcard deck code.'),
          findsOneWidget,
        );
        final deck = FlashCardDeckDefinition.create(
          name: 'Scanned deck',
          emoji: '🤖',
          eventKeys: ['2026wabon'],
        );
        scanner.captures.add(
          BarcodeCapture(
            barcodes: [
              Barcode(rawValue: deck.shareCode, format: BarcodeFormat.qrCode),
              Barcode(rawValue: deck.shareCode, format: BarcodeFormat.qrCode),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Scanned deck'), findsOneWidget);
        expect(find.text('Scan deck QR code'), findsNothing);
        expect(scanner.stops, greaterThanOrEqualTo(1));
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Import deck'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
        await tester.pumpAndSettle();
        expect(
          app.container.read(flashCardLibraryProvider).single.name,
          'Scanned deck',
        );
        expect(find.text('254'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        MobileScannerPlatform.instance = previous;
        debugDefaultTargetPlatformOverride = platform;
        await scanner.captures.close();
      }
    },
  );

  testWidgets(
    'camera permission denial leaves paste and image import reachable',
    (tester) async {
      final previous = MobileScannerPlatform.instance;
      final scanner = _Scanner()..denied = true;
      final platform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MobileScannerPlatform.instance = scanner;
      try {
        await showFlashCardLibraryTestApp(
          tester,
          location: '/flash_cards/import',
        );
        await tester.tap(find.text('Scan QR code'));
        await tester.pumpAndSettle();
        expect(find.text('Camera unavailable'), findsOneWidget);
        await tester.tap(find.text('Go back'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Paste deck code'), findsOneWidget);
        expect(find.text('QR image'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        MobileScannerPlatform.instance = previous;
        debugDefaultTargetPlatformOverride = platform;
        await scanner.captures.close();
      }
    },
  );

  testWidgets('download exports a PNG with the exact deck definition', (
    tester,
  ) async {
    final previous = FilePickerPlatform.instance;
    final picker = _FileExport();
    FilePickerPlatform.instance = picker;
    try {
      final deck = FlashCardDeckDefinition.create(
        name: 'PNW deck',
        emoji: '🐻',
        eventKeys: ['2026wabon'],
      );
      await showFlashCardLibraryTestApp(
        tester,
        decks: [deck],
        location: '/flash_cards/share/${deck.id}',
      );
      await tester.scrollUntilVisible(
        find.text('Download QR code'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Download QR code'),
      );
      final saved = await tester.runAsync(() async {
        final completion = Function.apply(button.onPressed!, []);
        if (completion is Future) {
          await completion.timeout(const Duration(seconds: 5));
        }
        return picker.result;
      });
      await tester.pumpAndSettle();
      expect(saved!.name, 'pnw-deck.png');
      expect(saved.mime, 'image/png');
      expect(decodeFlashCardQrImage(saved.bytes), deck.shareCode);
      expect(find.text('QR code saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      FilePickerPlatform.instance = previous;
    }
  });
}
