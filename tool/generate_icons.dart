// Run with `melos run icons`. Flutter's headless renderer rasterizes the SVGs;
// no external graphics tools are needed. Only primary app icons are generated.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

const _size = 1024;
const _maskableScale = 0.75;
const _androidDensities = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};
const _windowsSizes = <int>[16, 24, 32, 48, 64, 128, 256];

typedef SvgPath = ({String data, String color, (double, double)? translation});

void _writeBytes(String path, List<int> bytes) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

void _writeText(String path, String text) =>
    _writeBytes(path, utf8.encode(text));

void _remove(String path) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
}

Map<String, String> _properties(XmlElement element) => {
  for (final attribute in element.attributes)
    attribute.name.qualified: attribute.value,
  for (final declaration in (element.getAttribute('style') ?? '').split(';'))
    if (declaration.contains(':'))
      declaration.substring(0, declaration.indexOf(':')).trim(): declaration
          .substring(declaration.indexOf(':') + 1)
          .trim(),
};

void _validatePaint(Map<String, String> properties) {
  for (final entry in const {
    'stroke': 'none',
    'clip-path': 'none',
    'mask': 'none',
    'filter': 'none',
    'display': 'inline',
    'visibility': 'visible',
    'fill-rule': 'nonzero',
  }.entries) {
    if (properties.containsKey(entry.key) &&
        properties[entry.key] != entry.value) {
      throw FormatException('Unsupported Android SVG property: ${entry.key}');
    }
  }
}

(double, double)? _translation(String? transform) {
  if (transform == null || transform.trim().isEmpty) return null;
  final match = RegExp(r'^translate\(([^)]*)\)$').firstMatch(transform.trim());
  if (match == null) {
    throw FormatException('Unsupported SVG transform: $transform');
  }
  final values = match
      .group(1)!
      .trim()
      .split(RegExp(r'[,\s]+'))
      .map(double.parse)
      .toList();
  if (values.isEmpty || values.length > 2) {
    throw FormatException('Invalid SVG translation: $transform');
  }
  return (values[0], values.length == 2 ? values[1] : 0);
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

List<SvgPath> _readSvgPaths(XmlElement svg) {
  final viewBox = (svg.getAttribute('viewBox') ?? '')
      .trim()
      .split(RegExp(r'[,\s]+'))
      .map(double.parse)
      .toList();
  if (viewBox.length != 4 ||
      viewBox[0] != 0 ||
      viewBox[1] != 0 ||
      viewBox[2] != _size ||
      viewBox[3] != _size) {
    throw const FormatException(
      'Android artwork must use viewBox="0 0 1024 1024".',
    );
  }
  final inherited = _properties(svg);
  _validatePaint(inherited);
  if (inherited.containsKey('transform')) {
    throw const FormatException('Move SVG root transforms into the paths.');
  }
  final paths = <SvgPath>[];
  for (final element in svg.childElements) {
    if (element.namespaceUri != null &&
        element.namespaceUri != 'http://www.w3.org/2000/svg')
      continue;
    final name = element.name.local;
    if (name == 'metadata' || name == 'title' || name == 'desc') continue;
    if (name == 'defs' && element.childElements.isEmpty) continue;
    if (name != 'path') {
      throw FormatException(
        'Unsupported Android SVG element <$name>. Convert artwork to paths.',
      );
    }
    final local = _properties(element);
    final properties = {...inherited, ...local};
    _validatePaint(properties);
    final data = element.getAttribute('d');
    if (data == null || data.isEmpty) continue;
    final opacity =
        double.parse(inherited['opacity'] ?? '1') *
        double.parse(local['opacity'] ?? '1') *
        double.parse(properties['fill-opacity'] ?? '1');
    paths.add((
      data: data,
      color: _argbColor(properties['fill'] ?? '#000000', opacity),
      translation: _translation(local['transform']),
    ));
  }
  if (paths.isEmpty) throw const FormatException('No SVG paths found.');
  return paths;
}

String _vectorDrawable(List<SvgPath> paths, {required bool monochrome}) {
  final vector = XmlElement.tag(
    'vector',
    attributes:
        {
          'xmlns:android': 'http://schemas.android.com/apk/res/android',
          'android:width': '108dp',
          'android:height': '108dp',
          'android:viewportWidth': '$_size',
          'android:viewportHeight': '$_size',
        }.entries.map(
          (entry) => XmlAttribute(XmlName.fromString(entry.key), entry.value),
        ),
  );
  for (final path in paths) {
    final node = XmlElement.tag(
      'path',
      attributes: [
        XmlAttribute(
          XmlName.fromString('android:fillColor'),
          monochrome ? '#FFFFFFFF' : path.color,
        ),
        XmlAttribute(XmlName.fromString('android:pathData'), path.data),
      ],
    );
    if (path.translation case final translation?) {
      vector.children.add(
        XmlElement.tag(
          'group',
          attributes: [
            XmlAttribute(
              XmlName.fromString('android:translateX'),
              '${translation.$1}',
            ),
            XmlAttribute(
              XmlName.fromString('android:translateY'),
              '${translation.$2}',
            ),
          ],
          children: [node],
        ),
      );
    } else {
      vector.children.add(node);
    }
  }
  return '<?xml version="1.0" encoding="utf-8"?>\n${vector.toXmlString(pretty: true)}\n';
}

Future<img.Image> _renderIcon(
  XmlDocument foreground, {
  File? background,
  bool maskable = false,
}) async {
  final document = foreground.copy();
  if (background != null) {
    document.rootElement.children.insertAll(
      0,
      XmlDocument.parse(background.readAsStringSync()).rootElement.childElements
          .map((element) => element.copy()),
    );
  }
  // Editor metadata and empty definitions do not contribute to the drawing.
  document.rootElement.children.removeWhere(
    (node) =>
        node is XmlElement &&
        ((node.namespaceUri != null &&
                node.namespaceUri != 'http://www.w3.org/2000/svg') ||
            node.name.local == 'metadata' ||
            (node.name.local == 'defs' && node.childElements.isEmpty)),
  );
  final picture = await vg.loadPicture(
    SvgStringLoader(document.toXmlString()),
    null,
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final scale = maskable ? _maskableScale : 1.0;
  if (maskable) {
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    canvas.translate(_size * (1 - scale) / 2, _size * (1 - scale) / 2);
  }
  canvas
    ..scale(
      _size * scale / picture.size.width,
      _size * scale / picture.size.height,
    )
    ..drawPicture(picture.picture);
  final scaled = recorder.endRecording();
  try {
    final raster = await scaled.toImage(_size, _size);
    try {
      final bytes = (await raster.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      return img.Image.fromBytes(
        width: _size,
        height: _size,
        bytes: bytes.buffer,
        bytesOffset: bytes.offsetInBytes,
        numChannels: 4,
      );
    } finally {
      raster.dispose();
    }
  } finally {
    scaled.dispose();
    picture.picture.dispose();
  }
}

img.Image _resize(img.Image source, int size) => img.copyResize(
  source,
  width: size,
  height: size,
  interpolation: img.Interpolation.average,
);
List<int> _png(img.Image source, int size) =>
    img.encodePng(_resize(source, size));

void _writeAndroid(String resources, img.Image desktop, List<SvgPath> paths) {
  _writeText(
    '$resources/drawable/ic_launcher_foreground.xml',
    _vectorDrawable(paths, monochrome: false),
  );
  _writeText(
    '$resources/drawable/ic_launcher_monochrome.xml',
    _vectorDrawable(paths, monochrome: true),
  );
  _writeText(
    '$resources/drawable/ic_launcher_monochrome_inset.xml',
    '''<?xml version="1.0" encoding="utf-8"?>
<inset xmlns:android="http://schemas.android.com/apk/res/android"
    android:drawable="@drawable/ic_launcher_monochrome"
    android:inset="25%" />
''',
  );
  _writeText(
    '$resources/values/icon_colors.xml',
    '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="icon_background">#FFFFFF</color>
</resources>
''',
  );
  _writeText(
    '$resources/mipmap-anydpi-v26/launcher_icon.xml',
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
    _writeBytes(
      '$resources/mipmap-${entry.key}/launcher_icon.png',
      _png(desktop, entry.value),
    );
    _remove('$resources/drawable-${entry.key}/ic_launcher_foreground.png');
  }
}

void _writeWeb(String web, img.Image desktop, img.Image maskable) {
  _writeBytes('$web/favicon.png', _png(desktop, 32));
  for (final size in [192, 512]) {
    _writeBytes('$web/icons/Icon-$size.png', _png(desktop, size));
    _writeBytes('$web/icons/Icon-maskable-$size.png', _png(maskable, size));
  }
}

void _writeWindows(String windows, img.Image desktop) {
  final frames = _windowsSizes.map((size) => _resize(desktop, size)).toList();
  final icon = frames.first;
  for (final frame in frames.skip(1)) {
    icon.addFrame(frame);
  }
  _writeBytes('$windows/runner/resources/app_icon.ico', img.encodeIco(icon));
}

Map<String, List<int>> _composerFiles(String source, String common) {
  final metadata = File('$source/AppIcon.icon/icon.json').readAsBytesSync();
  final config = jsonDecode(utf8.decode(metadata)) as Map<String, dynamic>;
  final files = <String, List<int>>{'icon.json': metadata};
  for (final group in config['groups'] as List) {
    for (final layer in group['layers'] as List) {
      final name = layer['image-name'] as String?;
      if (name == null) continue;
      if (name.contains('/') || name.contains('\\'))
        throw FormatException('Invalid Composer image name: $name');
      final local = File('$source/$name');
      final master = local.existsSync() ? local : File('$common/$name');
      files['Assets/$name'] = master.readAsBytesSync();
    }
  }
  return files;
}

void _writeBundle(String destination, Map<String, List<int>> files) {
  final directory = Directory(destination);
  for (final entry in files.entries) {
    _writeBytes('$destination/${entry.key}', entry.value);
  }
  for (final file in directory.listSync(recursive: true).whereType<File>()) {
    final relative = file.path
        .substring(directory.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (!files.containsKey(relative)) file.deleteSync();
  }
}

Future<void> _generateApp(String source, String project, String common) async {
  bool hasPlatform(String name) => Directory('$project/$name').existsSync();
  final foreground = XmlDocument.parse(
    File('$source/foreground.svg').readAsStringSync(),
  );
  final paths = hasPlatform('android')
      ? _readSvgPaths(foreground.rootElement)
      : <SvgPath>[];
  final composer = hasPlatform('ios') || hasPlatform('macos')
      ? _composerFiles(source, common)
      : null;
  final desktop = await _renderIcon(
    foreground,
    background: File('$common/desktop_background.svg'),
  );
  if (hasPlatform('android'))
    _writeAndroid('$project/android/app/src/main/res', desktop, paths);
  if (hasPlatform('web')) {
    _writeWeb(
      '$project/web',
      desktop,
      await _renderIcon(foreground, maskable: true),
    );
  }
  if (hasPlatform('windows')) _writeWindows('$project/windows', desktop);
  if (hasPlatform('linux'))
    _writeBytes('$project/linux/icon.png', _png(desktop, 64));
  if (composer != null) {
    _writeBundle('$source/AppIcon.icon', composer);
    for (final platform in ['ios', 'macos']) {
      if (hasPlatform(platform))
        _writeBundle('$project/$platform/Runner/AppIcon.icon', composer);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The Flutter runner supplies dart:ui for rendering; this is a manual tool,
  // outside the test suite and CI.
  test('Generate primary app icons', () async {
    final root = Directory.current.path;
    final sources =
        Directory('$root/tool/app_icons')
            .listSync()
            .whereType<Directory>()
            .where(
              (directory) =>
                  directory.uri.pathSegments
                      .where((part) => part.isNotEmpty)
                      .last !=
                  'common',
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final source in sources) {
      final name = source.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      final project = '$root/apps/$name';
      if (!Directory(project).existsSync())
        throw FileSystemException('No app project for icon source', project);
      try {
        await _generateApp(source.path, project, '$root/tool/app_icons/common');
      } catch (error) {
        throw StateError('Failed to generate $name icons: $error');
      }
      print('Generated $name icons.');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
