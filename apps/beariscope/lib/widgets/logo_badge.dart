import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/widgets.dart';

const logoBadgeLight = Color(0xfff7f8fa);
const logoBadgeDark = Color(0xff23262d);

/// Takes straight RGBA pixels, so translucent white edges aren't read as gray.
Color logoBadgeBackground(Uint8List pixels) {
  var luminance = 0.0;
  var weight = 0.0;
  final step = math.max(1, (pixels.length / 4 / 4096).ceil()) * 4;
  for (var offset = 0; offset + 3 < pixels.length; offset += step) {
    final alpha = pixels[offset + 3] / 255;
    if (alpha < .05) continue;
    luminance +=
        Color.fromARGB(
          255,
          pixels[offset],
          pixels[offset + 1],
          pixels[offset + 2],
        ).computeLuminance() *
        alpha;
    weight += alpha;
  }
  if (weight == 0) return logoBadgeLight;
  luminance /= weight;
  double contrast(Color background) {
    final value = background.computeLuminance();
    return (math.max(luminance, value) + .05) /
        (math.min(luminance, value) + .05);
  }

  return contrast(logoBadgeDark) > contrast(logoBadgeLight)
      ? logoBadgeDark
      : logoBadgeLight;
}

// Bound the cache so browsing events doesn't retain every logo's image bytes.
final _backgrounds = <ImageProvider, Future<Color>>{};

Future<Color> loadLogoBadgeBackground(
  ImageProvider image,
  ImageConfiguration configuration,
) {
  final cached = _backgrounds.remove(image);
  if (cached != null) {
    _backgrounds[image] = cached;
    return cached;
  }
  if (_backgrounds.length >= 128) _backgrounds.remove(_backgrounds.keys.first);
  late final Future<Color> pending;
  pending = _readBackground(image, configuration).then((color) {
    if (identical(_backgrounds[image], pending)) {
      if (color == null) {
        // A later successful load must be able to choose its own background.
        _backgrounds.remove(image);
      } else {
        // Preloaded badges paint immediately, without a FutureBuilder wait frame.
        _backgrounds[image] = SynchronousFuture(color);
      }
    }
    return color ?? logoBadgeLight;
  });
  return _backgrounds[image] = pending;
}

Future<Color?> _readBackground(
  ImageProvider image,
  ImageConfiguration configuration,
) async {
  final stream = image.resolve(configuration);
  final loaded = Completer<ImageInfo>();
  final listener = ImageStreamListener(
    (info, _) {
      if (loaded.isCompleted) {
        info.dispose();
      } else {
        loaded.complete(info);
      }
    },
    onError: (Object error, StackTrace? stack) {
      if (!loaded.isCompleted) loaded.completeError(error, stack);
    },
  );
  ImageInfo? info;
  stream.addListener(listener);
  try {
    info = await loaded.future;
    final data = await info.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return data == null
        ? null
        : logoBadgeBackground(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
  } catch (_) {
    return null;
  } finally {
    stream.removeListener(listener);
    info?.dispose();
  }
}

class LogoBadge extends StatelessWidget {
  const LogoBadge({
    super.key,
    required this.image,
    required this.inset,
    required this.child,
  });

  final ImageProvider image;
  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) => FutureBuilder<Color>(
    future: loadLogoBadgeBackground(
      image,
      createLocalImageConfiguration(context),
    ),
    builder: (context, snapshot) {
      // Show the artwork and its correct background together.
      final background = snapshot.data;
      if (background == null) return const SizedBox.shrink();
      return DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          // A square logo inset by this amount has a concentric outer radius.
          borderRadius: BorderRadius.circular(inset),
          border: Border.all(
            color: background == logoBadgeDark
                ? const Color(0x1affffff)
                : const Color(0x0f000000),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1a000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(padding: EdgeInsets.all(inset), child: child),
      );
    },
  );
}
