import 'package:material_ui/material_ui.dart';

/// Curated colors keep multicolored emoji thumbnails predictable on every OS.
const picklistEmojiColors = <String, Color>{
  '🐻': Color(0xFF9C6B42),
  '🤖': Color(0xFF607D8B),
  '🚀': Color(0xFFE45858),
  '⚡': Color(0xFFE8B923),
  '🔥': Color(0xFFEF7C30),
  '⭐': Color(0xFFE8B923),
  '🏆': Color(0xFFD4A329),
  '🎯': Color(0xFFD84C58),
  '🦊': Color(0xFFE88036),
  '🐼': Color(0xFF78858C),
  '🐸': Color(0xFF6AAB49),
  '🐯': Color(0xFFE69A36),
  '🦁': Color(0xFFC48B42),
  '🐙': Color(0xFFD46B8D),
  '🦄': Color(0xFFB889CB),
  '🐲': Color(0xFF49A477),
  '🍀': Color(0xFF46A467),
  '🌻': Color(0xFFE6B533),
  '🌵': Color(0xFF6B9D58),
  '🌈': Color(0xFFB78BCB),
  '🌙': Color(0xFFD8B750),
  '🪐': Color(0xFFB59A79),
  '☄️': Color(0xFFDA8154),
  '🌊': Color(0xFF439DC4),
  '🍕': Color(0xFFE5A04C),
  '🍩': Color(0xFFD984A4),
  '🍉': Color(0xFFE57783),
  '🍋': Color(0xFFE3CA3C),
  '🍒': Color(0xFFCD4D63),
  '🥑': Color(0xFF93AF56),
  '🍿': Color(0xFFD97164),
  '🧋': Color(0xFFB79276),
  '🎸': Color(0xFFC76A4B),
  '🎮': Color(0xFF7C7EAC),
  '🎲': Color(0xFFB47F80),
  '🧩': Color(0xFF77AC58),
  '💎': Color(0xFF68B8D6),
  '🧲': Color(0xFFD65D6C),
  '🛠️': Color(0xFF7B939F),
  '🧠': Color(0xFFE08AA8),
  '🏎️': Color(0xFFD85050),
  '🚁': Color(0xFFE4A73D),
  '🛸': Color(0xFF71A98F),
  '⛵': Color(0xFF669FC4),
  '🎈': Color(0xFFDE6578),
  '🎉': Color(0xFFB58ACD),
  '👑': Color(0xFFDCB242),
  '🦋': Color(0xFF639FCC),
};

Color picklistThumbnailColor(String emoji, ColorScheme colors) {
  final accent = picklistEmojiColors[emoji];
  if (accent == null) return colors.primaryContainer;
  return Color.alphaBlend(
    accent.withValues(alpha: colors.brightness == Brightness.dark ? .30 : .22),
    colors.surface,
  );
}
