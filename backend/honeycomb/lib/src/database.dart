import 'dart:async';
import 'dart:io';

import 'package:mongo_dart/mongo_dart.dart';

class HoneycombDatabase {
  HoneycombDatabase._();

  static Future<Db>? _opening;

  static Future<Db> get instance =>
      _opening ??= _open().catchError((Object error) {
        _opening = null;
        throw error;
      });

  static Future<Db> _open() async {
    final connection = Platform.environment['COSMOS_CONNECTION_STRING'];
    if (connection == null || connection.isEmpty) {
      throw StateError('COSMOS_CONNECTION_STRING is required');
    }
    final name = Platform.environment['COSMOS_DATABASE_NAME'];
    final uri = Uri.parse(connection);
    final configured = name == null || name.isEmpty
        ? connection
        : uri.replace(path: '/$name').toString();
    final db = await Db.create(configured);
    await db.open();
    if (Platform.environment['COSMOS_ENSURE_INDEXES'] != 'false') {
      try {
        await db
            .collection('users')
            .createIndex(keys: {'id': 1}, name: 'users_id_idx');
        await db
            .collection('users')
            .createIndex(keys: {'username': 1}, name: 'users_username_idx');
        await db
            .collection('users')
            .createIndex(
              keys: {'auth0UserId': 1},
              name: 'users_auth0_user_id_idx',
            );
        await db
            .collection('role_definitions')
            .createIndex(keys: {'id': 1}, name: 'role_definitions_id_idx');
        await db
            .collection('picklists')
            .createIndex(
              keys: {'id': 1},
              name: 'picklists_id_idx',
              unique: true,
            );
        await db
            .collection('picklists')
            .createIndex(
              keys: {'eventKey': 1, 'updatedAt': -1},
              name: 'picklists_event_updated_idx',
            );
        await db
            .collection('picklist_relay_rooms')
            .createIndex(
              keys: {'documentId': 1},
              name: 'picklist_relay_rooms_document_idx',
              unique: true,
            );
        await db
            .collection('picklist_relay_changes')
            .createIndex(
              keys: {'documentId': 1, 'seq': 1},
              name: 'picklist_relay_changes_document_seq_idx',
              unique: true,
            );
      } catch (error) {
        stderr.writeln('Mongo index setup failed: $error');
      }
    }
    return db;
  }
}

Map<String, dynamic> cleanDocument(Map<String, dynamic> document) {
  return {
    for (final entry in document.entries)
      if (entry.key != '_id') entry.key: jsonSafe(entry.value),
  };
}

dynamic jsonSafe(dynamic value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is ObjectId) return value.toHexString();
  if (value is List) return value.map(jsonSafe).toList();
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), jsonSafe(item)));
  }
  return value;
}
