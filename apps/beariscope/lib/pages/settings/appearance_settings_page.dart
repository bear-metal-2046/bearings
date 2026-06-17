import 'package:beariscope/widgets/settings_group.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // Added for MethodChannel
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
final accentColorProvider = NotifierProvider<AccentColorNotifier, Color>(
  AccentColorNotifier.new,
);
final appIconProvider = NotifierProvider<AppIconNotifier, AppIcon>(
  AppIconNotifier.new,
);

enum AppIcon {
  appIcon(
    displayName: 'Default',
    iconName: null,
    assetPath: 'assets/icon/ios_previews/default',
  ),
  jester(
    displayName: 'Jester',
    iconName: 'Jester',
    assetPath: 'assets/icon/ios_previews/jester',
  ),
  throwback(
    displayName: 'Throwback',
    iconName: 'Throwback',
    assetPath: 'assets/icon/ios_previews/throwback',
  ),
  icon2046(
    displayName: '2046',
    iconName: '2046',
    assetPath: 'assets/icon/ios_previews/2046',
  );

  const AppIcon({
    required this.displayName,
    required this.iconName,
    required this.assetPath,
  });

  final String displayName;
  final String? iconName;
  final String assetPath;
}

class AccentColorNotifier extends Notifier<Color> {
  @override
  Color build() {
    _loadColor();
    return Colors.lightBlue;
  }

  Future<void> _loadColor() async {
    final preferences = await SharedPreferences.getInstance();
    final savedColor = preferences.getInt('accentColor');
    if (savedColor != null) {
      state = Color(savedColor);
    }
  }

  Future<void> setColor(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accentColor', color.toARGB32());
  }
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadThemeMode();
    return ThemeMode.system;
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('themeMode');

    if (savedMode != null) {
      state = ThemeMode.values.firstWhere(
        (mode) => mode.toString() == savedMode,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.toString());
  }
}

class AppIconNotifier extends Notifier<AppIcon> {
  static const platform = MethodChannel('org.tahomarobotics.beariscope/icon');

  @override
  AppIcon build() {
    _loadAppIcon();
    return AppIcon.appIcon;
  }

  Future<void> _loadAppIcon() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIcon = prefs.getString('appIcon');

    if (savedIcon != null) {
      state = AppIcon.values.firstWhere(
        (icon) => icon.displayName == savedIcon,
        orElse: () => AppIcon.appIcon,
      );
    }
  }

  Future<void> setAppIcon(AppIcon icon) async {
    state = icon;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appIcon', icon.displayName);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        // set to 'default' if the icon name is null so fuckass swift knows to reset it
        final targetIconName = icon.iconName ?? 'default';
        await platform.invokeMethod('changeIcon', {'iconName': targetIconName});
      } on PlatformException catch (e) {
        debugPrint("Failed to change icon: '${e.message}'.");
      }
    }
  }
}

final accentColors = [
  Colors.pink,
  Colors.red,
  Colors.orange,
  Colors.amber,
  Colors.lightGreenAccent,
  Colors.green,
  Colors.teal,
  Colors.cyanAccent,
  Colors.lightBlue,
  Colors.purpleAccent,
  Colors.deepPurple,
];

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final selectedColor = ref.watch(accentColorProvider);
    final selectedAppIcon = ref.watch(appIconProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          SettingsGroup(
            title: 'Interface',
            children: [
              ListTile(
                leading: const Icon(Symbols.dark_mode_rounded),
                title: const Text('Theme Mode'),
                contentPadding: EdgeInsets.all(16),
                trailing: DropdownMenu<ThemeMode>(
                  requestFocusOnTap: false,
                  initialSelection: themeMode,
                  inputDecorationTheme: const InputDecorationTheme(
                    border: OutlineInputBorder(),
                  ),
                  onSelected: (ThemeMode? newMode) {
                    if (newMode != null) {
                      ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(newMode);
                    }
                  },
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: ThemeMode.system, label: 'System'),
                    DropdownMenuEntry(value: ThemeMode.light, label: 'Light'),
                    DropdownMenuEntry(value: ThemeMode.dark, label: 'Dark'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          SettingsGroup(
            title: 'Accent Color',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: accentColors.length + 1,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 48,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    if (index == accentColors.length) {
                      return GestureDetector(
                        onTap: () async {
                          final Color newColor = await showColorPickerDialog(
                            context,
                            selectedColor,
                            title: Text(
                              'Custom Color',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            width: 44,
                            height: 44,
                            spacing: 3,
                            runSpacing: 3,
                            borderRadius: 22,
                            wheelDiameter: 169,
                            enableOpacity: false,
                            showColorCode: false,
                            pickersEnabled: const <ColorPickerType, bool>{
                              ColorPickerType.both: false,
                              ColorPickerType.primary: false,
                              ColorPickerType.accent: false,
                              ColorPickerType.bw: false,
                              ColorPickerType.custom: false,
                              ColorPickerType.wheel: true,
                            },
                          );
                          ref
                              .read(accentColorProvider.notifier)
                              .setColor(newColor);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                              width: 2,
                            ),
                          ),
                          child: const Icon(Symbols.add_rounded, size: 24),
                        ),
                      );
                    }

                    final color = accentColors[index];
                    final isSelected =
                        color.toARGB32() == selectedColor.toARGB32();

                    return GestureDetector(
                      onTap: () {
                        ref.read(accentColorProvider.notifier).setColor(color);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: isSelected
                            ? Icon(
                                Symbols.check_rounded,
                                color: Theme.of(context).colorScheme.onSurface,
                                size: 20,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
            const SizedBox(height: 16),
            SettingsGroup(
              title: 'App Icon',
              children: AppIcon.values.map((icon) {
                return RadioListTile<AppIcon>(
                  value: icon,
                  groupValue: selectedAppIcon,
                  contentPadding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 6,
                    bottom: 6,
                  ),
                  onChanged: (AppIcon? newIcon) {
                    if (newIcon != null) {
                      ref.read(appIconProvider.notifier).setAppIcon(newIcon);
                    }
                  },
                  title: Row(
                    children: [
                      Text(icon.displayName),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: Image.asset(
                          '${icon.assetPath}_${Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'}.png',
                          key: ValueKey(Theme.of(context).brightness),
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 64,
                                height: 64,
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: const Icon(
                                  Symbols.image_not_supported_rounded,
                                  size: 24,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
