import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zxing2/qrcode.dart' as zx;

/// Keep the registered deep-link scheme lowercase in a byte segment, then use
/// alphanumeric mode for the Base41 code. fromData() would encode both as bytes.
QrCode createFlashCardQr(String code) {
  const prefix = '$flashCardDeckLinkScheme://deck/';
  final linked = code.startsWith(prefix);
  final payload = linked ? code.substring(prefix.length) : code;
  if (!payload.startsWith('BFC3:Q')) {
    return QrCode.fromData(
      data: code,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
  }
  for (var version = 1; version <= 40; version++) {
    final qr = QrCode(version, QrErrorCorrectLevel.M);
    if (linked) qr.addData(prefix);
    qr.addAlphaNumeric(payload);
    try {
      // Validate capacity with a fixed mask; rendering chooses its best mask.
      QrImage.withMaskPattern(qr, 0);
      return qr;
    } on InputTooLongException {
      continue;
    }
  }
  throw const FormatException('The deck is too large for a QR code.');
}

/// Includes a white quiet zone, independent of the app's current theme.
Future<Uint8List> renderFlashCardQr(String code) async {
  const size = 1024.0;
  final qr = createFlashCardQr(code);
  // Four clear modules on every side, with whole-pixel modules for export.
  final moduleSize = (size / (qr.moduleCount + 8)).floorToDouble();
  final qrSize = moduleSize * qr.moduleCount;
  final quietZone = (size - qrSize) / 2;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, size, size),
    ui.Paint()..color = const ui.Color(0xffffffff),
  );
  canvas.translate(quietZone, quietZone);
  QrPainter.withQr(
    qr: qr,
    gapless: true,
  ).paint(canvas, ui.Size(qrSize, qrSize));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('The QR code could not be rendered.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Runs in compute() for file imports; camera imports use mobile_scanner.
String decodeFlashCardQrImage(Uint8List bytes) {
  try {
    return _readQrImage(bytes);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Could not read this QR image.');
  }
}

String _readQrImage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 12 * 1024 * 1024) {
    throw const FormatException('Choose a QR image smaller than 12 MB.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 16000000) {
    throw const FormatException('Choose a smaller PNG or JPEG QR image.');
  }
  var image =
      decoder!.decodeFrame(0) ??
      (throw const FormatException('Could not read this image.'));
  if (image.width > 1800 || image.height > 1800) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1800 : null,
      height: image.height > image.width ? 1800 : null,
    );
  }
  // Some valid data patterns confuse the detector in one orientation.
  for (var turns = 0; turns < 4; turns++) {
    final code = _readQrOrientation(image);
    if (code != null) return code;
    if (turns < 3) image = img.copyRotate(image, angle: 90);
  }
  throw const FormatException('No readable QR code was found in this image.');
}

String? _readQrOrientation(img.Image image) {
  final rgba = image
      .convert(numChannels: 4)
      .getBytes(order: img.ChannelOrder.rgba);
  final pixels = Int32List(image.width * image.height);
  for (var i = 0; i < pixels.length; i++) {
    final offset = i * 4;
    final alpha = rgba[offset + 3];
    int composite(int channel) =>
        (channel * alpha + 255 * (255 - alpha)) ~/ 255;
    pixels[i] =
        (composite(rgba[offset]) << 16) |
        (composite(rgba[offset + 1]) << 8) |
        composite(rgba[offset + 2]);
  }
  final source = zx.RGBLuminanceSource(image.width, image.height, pixels);
  final hints = zx.DecodeHints()..put(zx.DecodeHintType.tryHarder);
  for (final luminance in [source, source.invert()]) {
    try {
      return zx.QRCodeReader()
          .decode(zx.BinaryBitmap(zx.HybridBinarizer(luminance)), hints: hints)
          .text;
    } catch (_) {
      continue;
    }
  }
  return null;
}
