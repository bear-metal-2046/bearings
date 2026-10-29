import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:flutter/painting.dart';

/// Picks the livelier team color without depending on primary/secondary order.
Color flashCardColor(TeamColors colors) {
  final candidates = [
    Color(colors.primaryArgb),
    if (colors.secondaryArgb case final secondary?) Color(secondary),
  ];

  double chroma(HSLColor color) =>
      (1 - (2 * color.lightness - 1).abs()) * color.saturation;

  double vibrancy(Color color) {
    final hsl = HSLColor.fromColor(color);
    // Chroma rejects black, white, gray, and almost-black saturated colors.
    // Saturation breaks close matches in favor of the purer hue.
    return chroma(hsl) * (.65 + .35 * hsl.saturation);
  }

  candidates.sort((a, b) {
    final score = vibrancy(b).compareTo(vibrancy(a));
    return score != 0 ? score : a.toARGB32().compareTo(b.toARGB32());
  });
  final selected = candidates.first;
  final hsl = HSLColor.fromColor(selected);
  // Don't invent a hue for teams whose entire palette is neutral.
  if (chroma(hsl) < .08) return selected;

  return hsl
      .withSaturation(hsl.saturation + (1 - hsl.saturation) * .2)
      .withLightness(hsl.lightness.clamp(.32, .62))
      .toColor();
}
