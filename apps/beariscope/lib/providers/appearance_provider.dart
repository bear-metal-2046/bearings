import 'package:core/providers/device_info_provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'shared_preferences_provider.dart';

enum ThemeColorSource { custom, system }

typedef AppColorSchemes = ({ColorScheme light, ColorScheme dark});

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(
  AccentColorNotifier.new,
);

final themeColorSourceProvider =
    NotifierProvider<ThemeColorSourceNotifier, ThemeColorSource>(
      ThemeColorSourceNotifier.new,
    );

final supportsSystemColorsProvider = Provider<bool>((ref) {
  return switch (ref.watch(deviceInfoProvider).deviceOS) {
    DeviceOS.android ||
    DeviceOS.linux ||
    DeviceOS.macos ||
    DeviceOS.windows => true,
    DeviceOS.ios || DeviceOS.web => false,
  };
});

final systemColorSchemesProvider = FutureProvider<AppColorSchemes?>((
  ref,
) async {
  if (!ref.watch(supportsSystemColorsProvider) ||
      ref.watch(themeColorSourceProvider) != ThemeColorSource.system) {
    return null;
  }

  // Android supplies a complete palette. Preserve its roles instead of seeding
  // another scheme from just the primary color.
  try {
    final palette = await DynamicColorPlugin.getCorePalette();
    if (palette != null) {
      return (
        light: palette.toColorScheme(),
        dark: palette.toColorScheme(brightness: Brightness.dark),
      );
    }
  } on PlatformException catch (error) {
    debugPrint('Unable to read the system color palette: $error');
  }

  // Desktop platforms expose an accent color rather than a Material palette.
  try {
    final accent = await DynamicColorPlugin.getAccentColor();
    if (accent != null) {
      return (
        light: ColorScheme.fromSeed(seedColor: accent),
        dark: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
      );
    }
  } on PlatformException catch (error) {
    debugPrint('Unable to read the system accent color: $error');
  }

  return null;
});

final appColorSchemesProvider = Provider<AppColorSchemes>((ref) {
  if (ref.watch(supportsSystemColorsProvider) &&
      ref.watch(themeColorSourceProvider) == ThemeColorSource.system) {
    final systemSchemes = ref.watch(systemColorSchemesProvider).value;
    if (systemSchemes != null) return systemSchemes;
  }

  final accent = ref.watch(accentColorProvider);
  return (
    light: ColorScheme.fromSeed(seedColor: accent),
    dark: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
  );
});

class ThemeColorSourceNotifier extends Notifier<ThemeColorSource> {
  @override
  ThemeColorSource build() {
    final savedSource = ref
        .read(sharedPreferencesProvider)
        .getString('themeColorSource');
    return ThemeColorSource.values.firstWhere(
      (source) => source.name == savedSource,
      orElse: () => ThemeColorSource.custom,
    );
  }

  Future<void> setSource(ThemeColorSource source) async {
    state = source;
    await ref
        .read(sharedPreferencesProvider)
        .setString('themeColorSource', source.name);
  }
}

class AccentColorNotifier extends Notifier<Color> {
  @override
  Color build() {
    final savedColor = ref
        .read(sharedPreferencesProvider)
        .getInt('accentColor');
    return savedColor == null ? Colors.lightBlue : Color(savedColor);
  }

  Future<void> setColor(Color color) async {
    state = color;
    await ref
        .read(themeColorSourceProvider.notifier)
        .setSource(ThemeColorSource.custom);
    await ref
        .read(sharedPreferencesProvider)
        .setInt('accentColor', color.toARGB32());
  }
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final savedMode = ref
        .read(sharedPreferencesProvider)
        .getString('themeMode');
    return ThemeMode.values.firstWhere(
      (mode) => mode.toString() == savedMode,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString('themeMode', mode.toString());
  }
}
