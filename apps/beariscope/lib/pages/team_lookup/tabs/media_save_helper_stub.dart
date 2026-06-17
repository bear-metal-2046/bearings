import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

Future<void> shareOrSaveImage(
  BuildContext _,
  Uint8List bytes,
  String filename,
) async {
  await FilePicker.platform.saveFile(
    dialogTitle: 'Save image',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png'],
    bytes: bytes,
  );
}
