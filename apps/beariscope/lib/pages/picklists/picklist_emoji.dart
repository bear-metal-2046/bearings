import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Select native emoji before the app's text font. A fallback alone cannot
/// replace monochrome glyphs already found in the inherited primary font.
class PicklistEmoji extends StatelessWidget {
  final String emoji;
  final double size;

  const PicklistEmoji(this.emoji, {super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final families = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const ['Apple Color Emoji'],
      TargetPlatform.windows => const ['Segoe UI Emoji'],
      TargetPlatform.android ||
      TargetPlatform.fuchsia => const ['Noto Color Emoji'],
      TargetPlatform.linux => const [
        'Noto Color Emoji',
        'Segoe UI Emoji',
        'Twemoji Mozilla',
        'EmojiOne Color',
      ],
    };
    return Text(
      emoji,
      textAlign: TextAlign.center,
      style: TextStyle(
        inherit: false,
        fontFamily: families.first,
        fontFamilyFallback: families.skip(1).toList(),
        fontSize: size,
        height: 1.2,
        fontWeight: FontWeight.normal,
        fontStyle: FontStyle.normal,
      ),
    );
  }
}
