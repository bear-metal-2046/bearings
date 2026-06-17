import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareOrSaveImage(
  BuildContext context,
  Uint8List bytes,
  String filename,
) async {
  final shareOrigin = _getShareOrigin(context);

  if (Platform.isIOS || Platform.isAndroid) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/jpeg', name: filename)],
      subject: filename,
      sharePositionOrigin: shareOrigin,
    );
    return;
  }

  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save image',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png'],
  );
  if (path == null || path.isEmpty) return;

  await File(path).writeAsBytes(bytes, flush: true);
}

Rect _getShareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}
