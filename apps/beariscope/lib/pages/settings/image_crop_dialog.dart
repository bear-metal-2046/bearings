import 'package:beariscope/widgets/beariscope_modal.dart';

import 'dart:typed_data';

import 'package:beariscope/utils/image_processor.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const ImageCropDialog({required this.imageBytes, super.key});

  static Future<Uint8List?> show(
    BuildContext context,
    Uint8List imageBytes,
  ) async {
    return BeariscopeModal.show<Uint8List>(
      context,
      useRootNavigator: true,
      builder: (context) => ImageCropDialog(imageBytes: imageBytes),
    );
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  final _cropController = CropController();
  bool _isProcessing = false;

  Future<void> _confirm() async {
    setState(() => _isProcessing = true);

    try {
      _cropController.crop();
    } catch (e) {
      debugPrint('Crop error: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to crop image: $e')));
      }
    }
  }

  Future<void> _onCropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        final processed = await ImageProcessor.processCroppedImage(
          croppedImage,
        );

        if (!mounted) return;

        if (processed == null) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to process image')),
          );
          return;
        }

        debugPrint(
          'Processed image: ${ImageProcessor.formatFileSize(processed.length)}',
        );

        BeariscopeModal.complete(context, processed);

      case CropFailure(:final cause, :final stackTrace):
        if (!mounted) return;

        setState(() => _isProcessing = false);
        debugPrint('Crop failed: $cause\n$stackTrace');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Crop failed: $cause')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BeariscopeModal(
      title: 'Crop Photo',
      size: BeariscopeModalSize.expansive,
      scrolling: BeariscopeModalScrolling.content,
      dismissal: BeariscopeModalDismissal.fixed,
      canDismiss: !_isProcessing,
      actions: const [],
      primaryAction: BeariscopeModalPrimaryAction(
        label: 'Done',
        icon: LucideIcons.check,
        loading: _isProcessing,
        onPressed: _confirm,
      ),
      content: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Crop(
                  controller: _cropController,
                  image: widget.imageBytes,
                  onCropped: _onCropped,
                  aspectRatio: 1.0,
                  withCircleUi: true,
                  baseColor: Colors.black,
                  maskColor: Colors.black.withAlpha((0.7 * 255).round()),
                  radius: 0,
                  interactive: true,
                  fixCropRect: false,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: SafeArea(
              top: false,
              child: const Text(
                'Drag and pinch to adjust',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
