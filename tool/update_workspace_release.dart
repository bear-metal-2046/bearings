import 'dart:io';

const _pubspecPaths = <String>[
  'apps/beariscope/pubspec.yaml',
  'apps/bearimetric/pubspec.yaml',
  'packages/core/pubspec.yaml',
  'packages/services/pubspec.yaml',
  'packages/ui/pubspec.yaml',
  'backend/honeycomb/pubspec.yaml',
];

const _codenamePath = 'packages/services/assets/release/codename.txt';

void main(List<String> args) {
  final arguments = _parseArgs(args);
  final version = arguments['version'];
  final codename = arguments['codename'];

  if (version == null || !_isValidVersion(version)) {
    stderr.writeln('Expected --version=x.y.z where x, y, and z are integers.');
    exitCode = 64;
    return;
  }

  if (codename == null) {
    stderr.writeln('Expected --codename to be provided.');
    exitCode = 64;
    return;
  }

  final nextBuildNumber = _findNextBuildNumber();
  final fullVersion = '$version+$nextBuildNumber';

  for (final path in _pubspecPaths) {
    _updateVersionLine(path, fullVersion);
  }

  File(_codenamePath).writeAsStringSync('${codename.trim()}\n');
  stdout.writeln('Updated workspace version to $fullVersion.');
}

int _findNextBuildNumber() {
  final buildRegex = RegExp(
    r'^version:\s+\d+\.\d+\.\d+\+(\d+)',
    multiLine: true,
  );

  var highest = 0;

  for (final path in _pubspecPaths) {
    final file = File(path);
    final contents = file.readAsStringSync();

    final match = buildRegex.firstMatch(contents);
    if (match != null) {
      final build = int.parse(match.group(1)!);
      if (build > highest) {
        highest = build;
      }
    }
  }

  return highest + 1;
}

Map<String, String> _parseArgs(List<String> args) {
  final values = <String, String>{};

  for (final arg in args) {
    if (!arg.startsWith('--') || !arg.contains('=')) {
      continue;
    }

    final separator = arg.indexOf('=');
    final key = arg.substring(2, separator);
    final value = arg.substring(separator + 1);
    values[key] = value;
  }

  return values;
}

bool _isValidVersion(String value) {
  return RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value);
}

void _updateVersionLine(String path, String fullVersion) {
  final file = File(path);
  final contents = file.readAsStringSync();
  final updated = contents.replaceFirst(
    RegExp(r'^version:\s+.+$', multiLine: true),
    'version: $fullVersion',
  );

  if (identical(contents, updated) || contents == updated) {
    stderr.writeln('Could not update version in $path.');
    exitCode = 1;
    throw StateError('Missing version line in $path');
  }

  file.writeAsStringSync(updated);
}
