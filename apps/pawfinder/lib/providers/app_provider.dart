import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pawfinder/data/local_data.dart';

const _colorSchemePrefKey = 'color_scheme';

class BrightnessProvider extends Notifier<Brightness> {
  @override
  Brightness build() => Brightness.light;

  void changeBrightness(bool value) =>
      value ? state = Brightness.dark : state = Brightness.light;
}

final brightnessNotifierProvider =
    NotifierProvider<BrightnessProvider, Brightness>(BrightnessProvider.new);

enum AppColorScheme {
  red('Robototes Red', Color.fromARGB(255, 255, 0, 0)),
  orange('Future Martian Orange', Color.fromARGB(255, 237, 95, 21)),
  yellow('Bear Metal Yellow', Color.fromARGB(255, 255, 241, 32)),
  green('Jack in the Bot Green', Color.fromARGB(255, 7, 160, 0)),
  cyan('Chill Out Cyan', Color.fromARGB(255, 0, 188, 212)),
  blue('Arrowdynamics Blue', Color.fromARGB(255, 35, 109, 200)),
  purple('Code Purple', Color.fromARGB(255, 85, 0, 144));

  const AppColorScheme(this.label, this.seedColor);

  final String label;
  final Color seedColor;
}

class ColorSchemeProvider extends Notifier<AppColorScheme> {
  @override
  AppColorScheme build() {
    final storedScheme = prefs.getString(_colorSchemePrefKey);
    return AppColorScheme.values.firstWhere(
      (scheme) => scheme.name == storedScheme,
      orElse: () => AppColorScheme.cyan,
    );
  }

  void changeColorScheme(AppColorScheme value) {
    state = value;
    prefs.setString(_colorSchemePrefKey, value.name);
  }
}

final colorSchemeNotifierProvider =
    NotifierProvider<ColorSchemeProvider, AppColorScheme>(
      ColorSchemeProvider.new,
    );

class PapyrusFontProvider extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final papyrusFontProvider = NotifierProvider<PapyrusFontProvider, bool>(
  PapyrusFontProvider.new,
);
