import 'package:core/core.dart';
import 'package:hive_ce/hive.dart';
import 'package:pawfinder/data/local_data.dart';
import 'package:pawfinder/data/upload_queue.dart';
import 'package:pawfinder/providers/scouting_providers.dart';
import 'package:pawfinder/store/strat_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/api_provider.dart';

part 'scout_upload_service.g.dart';

class ScoutUploadService {
  final Ref _ref;
  final HoneycombClient _client;
  bool _draining = false;

  ScoutUploadService(this._ref, this._client);

  Future<void> drainIfOnline() async {
    if (_draining) return;
    _draining = true;
    try {
      await _drain(_ref.read(uploadQueueProvider));
    } catch (_) {
      // keep queue intact; next drain retries
    } finally {
      _draining = false;
    }
  }

  // uploads the provided queue ids and marks successful ids as uploaded.
  // throws on network failure so callers can surface errors if needed.
  Future<int> upload(List<String> pendingIds) async {
    if (pendingIds.isEmpty) return 0;
    return _drain(pendingIds);
  }

  Future<int> _drain(List<String> pendingIds) async {
    if (pendingIds.isEmpty) return 0;

    final store = _ref.read(matchFormStoreProvider);
    final entryById = <String, Map<String, dynamic>>{};
    final uploadedIds = <String>[];

    for (final queueId in pendingIds) {
      final matchDoc = store.loadById(queueId);
      if (matchDoc != null) {
        final payload = _withTeamNumber(matchDoc);
        entryById[payload.id] = payload.toJson();
        uploadedIds.add(matchDoc.id);
        continue;
      }

      final stratDoc = loadStratFormDataById(queueId);
      if (stratDoc != null) {
        entryById[stratDoc.id] = stratDoc.toJson();
        uploadedIds.add(queueId);
        continue;
      }

      // Hard cutoff: unsupported/stale queue IDs are dropped.
      uploadedIds.add(queueId);
    }

    final entries = entryById.values.toList(growable: false);

    if (entries.isEmpty) return 0;

    await _client.post('/scout/ingest', data: {'entries': entries});
    _ref.read(uploadQueueProvider.notifier).markUploaded(uploadedIds);
    return entries.length;
  }

  MatchFormData _withTeamNumber(MatchFormData data) {
    if (data.teamNumber != null) return data;
    final teamNumber = _teamNumberFor(
      data.eventKey,
      data.matchNumber,
      data.pos,
    );
    if (teamNumber == null) return data;
    return data.copyWith(teamNumber: teamNumber);
  }

  int? _teamNumberFor(String eventKey, int matchNumber, int pos) {
    final raw = Hive.box(
      boxKey,
    ).get('MATCH_${eventKey}_${matchNumber}_${pos}_team');
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}

@Riverpod(keepAlive: true)
ScoutUploadService scoutUploadService(Ref ref) {
  final client = ref.watch(honeycombClientProvider);
  return ScoutUploadService(ref, client);
}
