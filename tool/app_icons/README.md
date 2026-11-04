# App icon sources

Run `melos run icons` from the repository root after changing an icon, review the
results visually, and commit the generated files. The generator uses Flutter's
bundled headless renderer through `flutter_svg`; no external graphics tools are
required. The Flutter runner is used only to provide rendering, not as a CI check.
You can also run `flutter test --no-pub tool/generate_icons.dart` directly.

Each app has a directory under `tool/app_icons` matching its project name under
`apps`. The generator discovers these directories and writes icons only for
platforms present in the app project.

The SVG masters are the source of truth for artwork:

- `<app>/foreground.svg`: the combined artwork for Android and raster icons.
- `common/desktop_background.svg`: the rounded white background for regular
  raster icons. Web maskable icons use an opaque white square with inset artwork.
- `<app>/base.svg` or `common/base.svg`: the bear layer for Apple icons.
- `<app>/badge.svg`: each app's Apple badge layer.

Android artwork must use a `0 0 1024 1024` view box and filled paths. Individual
path translations are supported. Convert shapes and strokes to paths before
exporting; unsupported elements and paint effects produce an error.

Each app's `AppIcon.icon` bundle holds its Apple Icon Composer settings. Both
current apps use Beariscope's iOS settings with their own artwork and badge color.
Edit these source bundles in Icon Composer. Each image name in `icon.json` maps
to a master SVG with the same filename in the app's source directory, falling
back to `common`. The generator refreshes the bundle's `Assets` from those
masters and copies the complete icon into the iOS and macOS projects.

To add an app, create its source directory and `foreground.svg`. For Apple
platforms, also add an `AppIcon.icon/icon.json` and its referenced SVG masters.
Register `AppIcon` in the new Xcode projects as usual; the generator only manages
assets.

Alternate icons and their settings preview images are maintained separately and
are outside this generator's scope.
