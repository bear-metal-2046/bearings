import 'dart:io';

import 'package:hive_ce_flutter/adapters.dart';
import 'package:path_provider/path_provider.dart';

/// Initializes Hive in private, app-specific support storage and migrates
/// boxes written to the documents directory by older releases.
Future<void> initializeHiveStorage() async {
  final support = await getApplicationSupportDirectory();
  await support.create(recursive: true);

  // Migration is optional. For example, Linux may not have an XDG documents
  // directory configured at all, and an unreadable legacy file should not
  // prevent the app from opening its new storage location.
  try {
    final documents = await getApplicationDocumentsDirectory();
    if (support.path != documents.path && await documents.exists()) {
      await for (final entity in documents.list()) {
        if (entity is! File ||
            (!entity.path.endsWith('.hive') &&
                !entity.path.endsWith('.lock'))) {
          continue;
        }

        final name = entity.uri.pathSegments.last;
        final destination = File(
          '${support.path}${Platform.pathSeparator}$name',
        );
        if (!await destination.exists()) {
          await entity.copy(destination.path);
          await entity.delete();
        }
      }
    }
  } on FileSystemException catch (error) {
    stderr.writeln('Skipping legacy Hive migration: $error');
  } on MissingPlatformDirectoryException catch (error) {
    stderr.writeln('Skipping legacy Hive migration: $error');
  }

  await Hive.initFlutter(support.path);
}
