import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:beariscope/providers/appearance_provider.dart';
import 'package:beariscope/providers/match_preview_layout_provider.dart';
import 'package:beariscope/widgets/settings_group.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final supportsSystemColors = ref.watch(supportsSystemColorsProvider);
    final useSystemColors =
        supportsSystemColors &&
        ref.watch(themeColorSourceProvider) == ThemeColorSource.system;
    final systemColors = supportsSystemColors && useSystemColors
        ? ref.watch(systemColorSchemesProvider)
        : null;
    final selectedAppIcon = ref.watch(appIconProvider);
    final matchPreviewLayout = ref.watch(matchPreviewLayoutProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          SettingsGroup(
            title: 'Interface',
            children: [
              ListTile(
                leading: const Icon(LucideIcons.sunMoon),
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
              ListTile(
                leading: const Icon(LucideIcons.galleryHorizontal),
                title: const Text('Match Preview Scroll'),
                contentPadding: const EdgeInsets.all(16),
                trailing: DropdownMenu<MatchPreviewLayout>(
                  requestFocusOnTap: false,
                  initialSelection: matchPreviewLayout,
                  inputDecorationTheme: const InputDecorationTheme(
                    border: OutlineInputBorder(),
                  ),
                  onSelected: (layout) {
                    if (layout != null) {
                      ref
                          .read(matchPreviewLayoutProvider.notifier)
                          .setLayout(layout);
                    }
                  },
                  dropdownMenuEntries: MatchPreviewLayout.values
                      .map(
                        (layout) => DropdownMenuEntry(
                          value: layout,
                          label: layout.label,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          SettingsGroup(
            title: 'Colors',
            children: [
              if (supportsSystemColors)
                SwitchListTile(
                  title: const Text('Use system colors'),
                  subtitle: Text(
                    systemColors != null &&
                            !systemColors.isLoading &&
                            systemColors.value == null
                        ? 'System colors unavailable. Using your custom accent.'
                        : 'Follow your device’s palette or accent color.',
                  ),
                  value: useSystemColors,
                  onChanged: (enabled) => ref
                      .read(themeColorSourceProvider.notifier)
                      .setSource(
                        enabled
                            ? ThemeColorSource.system
                            : ThemeColorSource.custom,
                      ),
                ),
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
                          final newColor = await BeariscopeModal.show<Color>(
                            context,
                            useRootNavigator: true,
                            builder: (_) =>
                                _CustomColorModal(initialColor: selectedColor),
                          );
                          if (newColor != null) {
                            ref
                                .read(accentColorProvider.notifier)
                                .setColor(newColor);
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                              width: 2,
                            ),
                          ),
                          child: const Icon(LucideIcons.plus, size: 24),
                        ),
                      );
                    }

                    final color = accentColors[index];
                    final isSelected =
                        !useSystemColors &&
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: isSelected
                            ? Icon(
                                LucideIcons.check,
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: const Icon(
                                  LucideIcons.fileQuestionMark,
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

class _CustomColorModal extends StatefulWidget {
  const _CustomColorModal({required this.initialColor});
  final Color initialColor;

  @override
  State<_CustomColorModal> createState() => _CustomColorModalState();
}

class _CustomColorModalState extends State<_CustomColorModal> {
  late Color _color = widget.initialColor;

  @override
  Widget build(BuildContext context) => BeariscopeModal(
    title: 'Custom Color',
    actions: const [],
    primaryAction: BeariscopeModalPrimaryAction(
      label: 'Select',
      icon: LucideIcons.check,
      onPressed: () => Navigator.pop(context, _color),
    ),
    content: ColorPicker(
      color: _color,
      onColorChanged: (color) => setState(() => _color = color),
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
    ),
  );
}
