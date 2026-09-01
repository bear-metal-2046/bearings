import 'dart:io';

import 'package:hive_ce_flutter/adapters.dart';
import 'package:path_provider/path_provider.dart';

/// Initializes Hive in private, app-specific support storage.
///
/// Older releases used the documents directory. Move their boxes once so an
/// upgrade does not make locally stored data disappear.
Future<void> initializeHiveStorage() async {
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();

  await support.create(recursive: true);
  if (support.path != documents.path && await documents.exists()) {
    await for (final entity in documents.list()) {
      if (entity is! File ||
          (!entity.path.endsWith('.hive') && !entity.path.endsWith('.lock'))) {
        continue;
      }

      final name = entity.uri.pathSegments.last;
      final destination = File('${support.path}${Platform.pathSeparator}$name');
      if (!await destination.exists()) {
        await entity.copy(destination.path);
        await entity.delete();
      }
    }
  }

  await Hive.initFlutter(support.path);
}
