// Generates every non-preview app icon from the SVG masters in
// tool/app_icons/. Inkscape must be available on PATH for SVG rasterization.
// The per-app foreground.svg files are the hand-composed Android foreground
// masters. The per-app desktop.svg files are the baked-white-background
// masters used by Android legacy icons, web, Windows, and Linux.
// Android adaptive foreground and monochrome layers are emitted as vector
// drawables; density-specific PNGs are retained only for legacy launchers.

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

const _androidDensities = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

const _windowsSizes = <int>[16, 24, 32, 48, 64, 128, 256];

class SvgPath {
  const SvgPath({
    required this.data,
    required this.fill,
    required this.opacity,
    this.translateX,
    this.translateY,
  });

  final String data;
  final String fill;
  final double opacity;
  final double? translateX;
  final double? translateY;
}

class IconApp {
  const IconApp(this.name);

  final String name;
}

class IconWriter {
  IconWriter({required this.checkOnly});

  final bool checkOnly;
  final List<String> mismatches = <String>[];

  void bytes(File file, List<int> expected) {
    if (checkOnly) {
      if (!file.existsSync() || !_sameBytes(file.readAsBytesSync(), expected)) {
        mismatches.add(file.path);
      }
      return;
    }

    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(expected);
  }

  void text(File file, String expected) => bytes(file, utf8.encode(expected));

  void absent(File file) {
    if (!file.existsSync()) {
      return;
    }
    if (checkOnly) {
      mismatches.add(file.path);
    } else {
      file.deleteSync();
    }
  }
}

String _path(String root, List<String> parts) =>
    <String>[root, ...parts].join(Platform.pathSeparator);

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

Map<String, String> _attributes(String source) {
  final attributes = <String, String>{};
  final pattern = RegExp(
    r'''([A-Za-z_][A-Za-z0-9_.:-]*)\s*=\s*("([^"]*)"|'([^']*)')''',
  );
  for (final match in pattern.allMatches(source)) {
    attributes[match.group(1)!] = match.group(3) ?? match.group(4) ?? '';
  }
  return attributes;
}

Map<String, String> _styleProperties(String style) {
  final properties = <String, String>{};
  for (final declaration in style.split(';')) {
    final separator = declaration.indexOf(':');
    if (separator == -1) {
      continue;
    }
    properties[declaration.substring(0, separator).trim()] = declaration
        .substring(separator + 1)
        .trim();
  }
  return properties;
}

double _number(String value, String description) {
  final parsed = double.tryParse(value);
  if (parsed == null) {
    throw FormatException('Invalid $description: $value');
  }
  return parsed;
}

(double, double)? _translation(String? transform) {
  if (transform == null || transform.trim().isEmpty) {
    return null;
  }
  final match = RegExp(r'^translate\(([^)]*)\)$').firstMatch(transform.trim());
  if (match == null) {
    throw FormatException('Unsupported SVG transform: $transform');
  }
  final values = match
      .group(1)!
      .trim()
      .split(RegExp(r'[,\s]+'))
      .where((value) => value.isNotEmpty)
      .map((value) => _number(value, 'translation'))
      .toList();
  if (values.isEmpty || values.length > 2) {
    throw FormatException('Invalid SVG translation: $transform');
  }
  return (values[0], values.length == 2 ? values[1] : 0);
}

List<SvgPath> _readSvgPaths(File source) {
  final contents = source.readAsStringSync();
  final paths = <SvgPath>[];
  final pathTags = RegExp(r'<path\b([\s\S]*?)/>');
  for (final match in pathTags.allMatches(contents)) {
    final attributes = _attributes(match.group(1)!);
    final data = attributes['d'];
    if (data == null || data.trim().isEmpty) {
      continue;
    }
    final style = _styleProperties(attributes['style'] ?? '');
    final fill = style['fill'] ?? attributes['fill'] ?? '#000000';
    final opacity = _number(
      style['fill-opacity'] ??
          attributes['fill-opacity'] ??
          style['opacity'] ??
          attributes['opacity'] ??
          '1',
      'fill opacity',
    );
    final translation = _translation(attributes['transform']);
    paths.add(
      SvgPath(
        data: data,
        fill: fill,
        opacity: opacity,
        translateX: translation?.$1,
        translateY: translation?.$2,
      ),
    );
  }
  if (paths.isEmpty) {
    throw FormatException('No SVG paths found in ${source.path}');
  }
  return paths;
}

String _argbColor(String fill, double opacity) {
  final normalized = fill.trim().toLowerCase();
  final rgb = switch (normalized) {
    'black' => '000000',
    'white' => 'ffffff',
    _ when RegExp(r'^#[0-9a-f]{6}$').hasMatch(normalized) =>
      normalized.substring(1),
    _ when RegExp(r'^#[0-9a-f]{3}$').hasMatch(normalized) =>
      normalized.substring(1).split('').map((value) => '$value$value').join(),
    _ => throw FormatException('Unsupported SVG fill color: $fill'),
  };
  final alpha = (opacity.clamp(0, 1) * 255).round();
  return '#${alpha.toRadixString(16).padLeft(2, '0')}$rgb';
}

String _xmlAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _decimal(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _vectorDrawable(List<SvgPath> paths, {required bool monochrome}) {
  final output = StringBuffer('''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="1024"
    android:viewportHeight="1024">
''');
  for (final path in paths) {
    final fill = monochrome ? '#FFFFFFFF' : _argbColor(path.fill, path.opacity);
    final pathXml =
        '        <path android:fillColor="$fill" android:pathData="${_xmlAttribute(path.data)}" />\n';
    if (path.translateX == null || path.translateY == null) {
      output.write(pathXml.replaceFirst('        ', '    '));
      continue;
    }
    output.write('''    <group
        android:translateX="${_decimal(path.translateX!)}"
        android:translateY="${_decimal(path.translateY!)}">
$pathXml    </group>
''');
  }
  output.write('</vector>\n');
  return output.toString();
}

img.Image _renderSvg(File source, Directory temporaryDirectory) {
  final output = File(
    _path(temporaryDirectory.path, <String>[
      '${source.uri.pathSegments.last}.png',
    ]),
  );
  final result = Process.runSync('inkscape', <String>[
    source.path,
    '--export-filename=${output.path}',
    '--export-width=1024',
    '--export-height=1024',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Inkscape failed for ${source.path}: ${result.stderr}'.trim(),
    );
  }

  final rendered = img.decodeImage(output.readAsBytesSync());
  if (rendered == null) {
    throw StateError('Could not decode rendered SVG: ${source.path}');
  }
  return rendered;
}

List<int> _png(img.Image source, int size) => img.encodePng(
  img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  ),
);

void _writeAndroid(
  String root,
  IconWriter writer,
  String app,
  img.Image desktop,
  List<SvgPath> foregroundPaths,
) {
  writer.text(
    File(
      _path(root, <String>[
        'apps',
        app,
        'android',
        'app',
        'src',
        'main',
        'res',
        'drawable',
        'ic_launcher_foreground.xml',
      ]),
    ),
    _vectorDrawable(foregroundPaths, monochrome: false),
  );
  writer.text(
    File(
      _path(root, <String>[
        'apps',
        app,
        'android',
        'app',
        'src',
        'main',
        'res',
        'drawable',
        'ic_launcher_monochrome.xml',
      ]),
    ),
    _vectorDrawable(foregroundPaths, monochrome: true),
  );
  writer.text(
    File(
      _path(root, <String>[
        'apps',
        app,
        'android',
        'app',
        'src',
        'main',
        'res',
        'drawable',
        'ic_launcher_monochrome_inset.xml',
      ]),
    ),
    '''<?xml version="1.0" encoding="utf-8"?>
<inset xmlns:android="http://schemas.android.com/apk/res/android"
    android:drawable="@drawable/ic_launcher_monochrome"
    android:inset="25%" />
''',
  );
  writer.text(
    File(
      _path(root, <String>[
        'apps',
        app,
        'android',
        'app',
        'src',
        'main',
        'res',
        'values',
        'icon_colors.xml',
      ]),
    ),
    '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="icon_background">#FFFFFF</color>
</resources>
''',
  );
  writer.text(
    File(
      _path(root, <String>[
        'apps',
        app,
        'android',
        'app',
        'src',
        'main',
        'res',
        'mipmap-anydpi-v26',
        'launcher_icon.xml',
      ]),
    ),
    '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/icon_background"/>
  <foreground>
      <inset
          android:drawable="@drawable/ic_launcher_foreground"
          android:inset="25%" />
  </foreground>
  <monochrome android:drawable="@drawable/ic_launcher_monochrome_inset" />
</adaptive-icon>
''',
  );

  for (final entry in _androidDensities.entries) {
    writer.bytes(
      File(
        _path(root, <String>[
          'apps',
          app,
          'android',
          'app',
          'src',
          'main',
          'res',
          'mipmap-${entry.key}',
          'launcher_icon.png',
        ]),
      ),
      _png(desktop, entry.value),
    );
  }
  for (final density in _androidDensities.keys) {
    writer.absent(
      File(
        _path(root, <String>[
          'apps',
          app,
          'android',
          'app',
          'src',
          'main',
          'res',
          'drawable-$density',
          'ic_launcher_foreground.png',
        ]),
      ),
    );
  }
}

void _writeWeb(String root, IconWriter writer, String app, img.Image desktop) {
  writer.bytes(
    File(_path(root, <String>['apps', app, 'web', 'favicon.png'])),
    _png(desktop, 32),
  );
  for (final size in <int>[192, 512]) {
    writer.bytes(
      File(
        _path(root, <String>['apps', app, 'web', 'icons', 'Icon-$size.png']),
      ),
      _png(desktop, size),
    );
    writer.bytes(
      File(
        _path(root, <String>[
          'apps',
          app,
          'web',
          'icons',
          'Icon-maskable-$size.png',
        ]),
      ),
      _png(desktop, size),
    );
  }
}

void _writeWindows(
  String root,
  IconWriter writer,
  String app,
  img.Image desktop,
) {
  final frames = _windowsSizes.map(
    (size) => img.copyResize(
      desktop,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    ),
  );
  final iterator = frames.iterator..moveNext();
  final ico = iterator.current;
  while (iterator.moveNext()) {
    ico.addFrame(iterator.current);
  }
  writer.bytes(
    File(
      _path(root, <String>[
        'apps',
        app,
        'windows',
        'runner',
        'resources',
        'app_icon.ico',
      ]),
    ),
    img.encodeIco(ico),
  );
}

void _writeLinux(
  String root,
  IconWriter writer,
  String app,
  img.Image desktop,
) {
  writer.bytes(
    File(_path(root, <String>['apps', app, 'linux', 'icon.png'])),
    _png(desktop, 64),
  );
}

void _writeComposerLayers(
  String root,
  IconWriter writer,
  String app,
  File base,
  File badge,
) {
  for (final platform in <String>['ios', 'macos']) {
    final directory = <String>[
      'apps',
      app,
      platform,
      'Runner',
      'AppIcon.icon',
      'Assets',
    ];
    writer.bytes(
      File(_path(root, <String>[...directory, '1 – Layer.svg'])),
      base.readAsBytesSync(),
    );
    writer.bytes(
      File(_path(root, <String>[...directory, '2 – Layer.svg'])),
      badge.readAsBytesSync(),
    );
  }
}

void _writeApp(
  String root,
  IconWriter writer,
  IconApp app,
  Directory temporaryDirectory,
) {
  final common = _path(root, <String>['tool', 'app_icons', 'common']);
  final appSource = _path(root, <String>['tool', 'app_icons', app.name]);
  final baseFile = File(_path(common, <String>['base.svg']));
  final badgeFile = File(_path(appSource, <String>['badge.svg']));
  final foregroundFile = File(_path(appSource, <String>['foreground.svg']));
  final desktopFile = File(_path(appSource, <String>['desktop.svg']));

  final foregroundPaths = _readSvgPaths(foregroundFile);
  final desktop = _renderSvg(desktopFile, temporaryDirectory);

  _writeAndroid(root, writer, app.name, desktop, foregroundPaths);
  _writeWeb(root, writer, app.name, desktop);
  _writeWindows(root, writer, app.name, desktop);
  _writeLinux(root, writer, app.name, desktop);
  _writeComposerLayers(root, writer, app.name, baseFile, badgeFile);
}

void main(List<String> arguments) {
  final checkOnly = arguments.contains('--check');
  final unknownArguments = arguments.where((argument) => argument != '--check');
  if (unknownArguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/generate_icons.dart [--check]');
    exitCode = 64;
    return;
  }

  final root = Directory.current.path;
  final writer = IconWriter(checkOnly: checkOnly);
  final temporaryDirectory = Directory.systemTemp.createTempSync(
    'bearings-icons-',
  );

  try {
    for (final app in <IconApp>[
      const IconApp('beariscope'),
      const IconApp('bearimetric'),
    ]) {
      _writeApp(root, writer, app, temporaryDirectory);
    }
  } finally {
    temporaryDirectory.deleteSync(recursive: true);
  }

  if (writer.mismatches.isNotEmpty) {
    stderr.writeln('Icon outputs are stale or missing:');
    for (final mismatch in writer.mismatches) {
      stderr.writeln('  $mismatch');
    }
    stderr.writeln('Run: dart run tool/generate_icons.dart');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    checkOnly ? 'Icon outputs are up to date.' : 'Icons generated.',
  );
}
