import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bearimetric/data/upload_queue.dart';
import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:services/providers/api_provider.dart';

class ScoutSyncService {
  final Ref _ref;
  final HoneycombClient _client;

  ScoutSyncService(this._ref, this._client);

  Future<void> syncDownEvent(String eventKey) async {
    try {
      final payload = await _client.get<dynamic>(
        '/scouting',
        queryParams: {'event': eventKey},
        cachePolicy: CachePolicy.networkFirst,
      );

      final serverDocs = _extractServerDocs(payload);
      if (serverDocs.isEmpty) return;

      final store = _ref.read(matchFormStoreProvider);
      final syncedIds = <String>[];

      for (final raw in serverDocs) {
        final serverDoc = _parseMatchDoc(raw);
        if (serverDoc == null) continue;

        final local = store.load(
          serverDoc.eventKey,
          serverDoc.matchNumber,
          serverDoc.pos,
        );

        // server wins only when local is missing or older.
        if (local == null ||
            serverDoc.lastModified.isAfter(local.lastModified)) {
          store.save(serverDoc);
          syncedIds.add(serverDoc.id);
        }
      }

      if (syncedIds.isNotEmpty) {
        _ref.read(uploadQueueProvider.notifier).markUploaded(syncedIds);
      }
    } catch (error, stackTrace) {
      debugPrint('scout sync-down failed for $eventKey: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  List<Map<String, dynamic>> _extractServerDocs(dynamic payload) {
    if (payload is List) {
      return payload.whereType<Map>().map(_toStringMap).toList();
    }

    if (payload is Map) {
      final map = _toStringMap(payload);
      final data = map['data'];
      if (data is List) {
        return data.whereType<Map>().map(_toStringMap).toList();
      }
    }

    return const [];
  }

  MatchFormData? _parseMatchDoc(Map<String, dynamic> raw) {
    try {
      final doc = MatchFormData.fromJson(raw);
      if (doc.id.isEmpty || doc.eventKey.isEmpty || doc.matchNumber <= 0) {
        return null;
      }
      return doc;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _toStringMap(Map<dynamic, dynamic> input) {
    return input.map((key, value) => MapEntry(key.toString(), value));
  }
}

final scoutSyncServiceProvider = Provider<ScoutSyncService>((ref) {
  final client = ref.watch(honeycombClientProvider);
  return ScoutSyncService(ref, client);
});
