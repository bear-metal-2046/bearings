import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'picklists.dart';
import 'security.dart';

const _uuid = Uuid();
const _scoutingTypes = {'match', 'pits', 'strat', 'drive_team'};

Future<Response> config(
  Request request,
  Access access,
  String yearRaw,
  String typeRaw,
) async {
  if (!access.has('external.read'))
    return reply({'error': 'Forbidden'}, status: 403);
  final year = int.tryParse(yearRaw);
  final type = typeRaw.replaceAll('-', '_');
  if (year == null)
    return reply({'error': 'Invalid year parameter'}, status: 400);
  if (!{'match_data', 'match_ui', 'strat_data', 'pits_data'}.contains(type)) {
    return reply({'error': 'Invalid config type'}, status: 400);
  }
  final db = await HoneycombDatabase.instance;
  final records = await db
      .collection('configurations')
      .modernFind(
        filter: {'year': year, 'configType': type},
        sort: {'version': -1},
        limit: 1,
      )
      .toList();
  return records.isEmpty
      ? reply({'error': 'Configuration not found'}, status: 404)
      : reply(jsonSafe(records.first['content']));
}

Future<Response> breakdowns(Request request, Access access) async {
  if (!access.has('notes.read'))
    return reply({'error': 'Forbidden'}, status: 403);
  final query = request.uri.queryParameters;
  final filter = <String, dynamic>{};
  if (query['team'] case final String team when team.isNotEmpty) {
    filter['team_number'] = team.startsWith('frc') ? team : 'frc$team';
  }
  if (query['year'] case final String yearRaw) {
    final year = int.tryParse(yearRaw);
    if (year == null)
      return reply({'error': 'Invalid year parameter'}, status: 400);
    filter['year'] = year;
  }
  if (query['event'] case final String event) filter['event_code'] = event;
  if (query['match'] case final String match) filter['match_key'] = match;
  final db = await HoneycombDatabase.instance;
  return reply(
    (await db.collection('team_breakdowns').find(filter).toList())
        .map(cleanDocument)
        .toList(),
  );
}

Response deviceCredentials(Access access) {
  if (!access.has('device.provision'))
    return reply({'error': 'Forbidden'}, status: 403);
  final env = Platform.environment;
  final keys = [
    'PAWFINDER_DEVICE_CLIENT_ID',
    'PAWFINDER_DEVICE_CLIENT_SECRET',
    'AUTH0_DOMAIN',
    'AUTH0_AUDIENCE',
  ];
  if (keys.any((key) => env[key] == null || env[key]!.isEmpty)) {
    return reply({'error': 'Device credentials not configured'}, status: 500);
  }
  return reply({
    'clientId': env[keys[0]],
    'clientSecret': env[keys[1]],
    'domain': env[keys[2]],
    'audience': env[keys[3]],
  });
}

Future<Response> scouts(
  Request request,
  Access access, [
  String? scoutId,
]) async {
  final db = await HoneycombDatabase.instance;
  final collection = db.collection('scouts');
  if (scoutId == null && request.method == HttpMethod.get) {
    if (!access.has('scouts.read'))
      return reply({'error': 'Forbidden'}, status: 403);
    final records = await collection
        .modernFind(
          projection: {'_id': 0, 'name': 1, 'uuid': 1},
        )
        .toList();
    return reply(records);
  }
  if (!access.has('scouts.manage'))
    return reply({'error': 'Forbidden'}, status: 403);
  if (scoutId == null && request.method == HttpMethod.post) {
    final body = await readObject(request);
    final name = bounded(body?['name'], 200);
    if (name == null) return reply({'error': 'Invalid payload'}, status: 400);
    final scout = {'name': name, 'uuid': _uuid.v4()};
    await collection.insertOne(scout);
    return reply({'success': true, 'scout': scout}, status: 201);
  }
  if (scoutId != null && request.method == HttpMethod.put) {
    final body = await readObject(request);
    final name = bounded(body?['name'], 200);
    if (name == null) return reply({'error': 'Invalid payload'}, status: 400);
    final result = await collection.updateOne(
      {'uuid': scoutId},
      {
        r'$set': {'name': name},
      },
    );
    return result.nMatched == 0
        ? reply({'error': 'Scout not found'}, status: 404)
        : reply({'success': true, 'message': 'Scout updated'});
  }
  if (scoutId != null && request.method == HttpMethod.delete) {
    final result = await collection.deleteOne({'uuid': scoutId});
    return result.nRemoved == 0
        ? reply({'error': 'Scout not found'}, status: 404)
        : reply({'success': true, 'message': 'Scout deleted'});
  }
  return reply({'error': 'Method not allowed'}, status: 405);
}

Future<Response> ingest(Request request, Access access) async {
  if (!['match.upload', 'pits.upload', 'drive_team.upload'].any(access.has))
    return reply({'error': 'Forbidden'}, status: 403);
  Map<String, dynamic> body;
  try {
    if ((int.tryParse(request.headers['content-length'] ?? '') ?? 0) >
        8 * 1024 * 1024) {
      return reply({'error': 'Payload too large'}, status: 413);
    }
    body = Map<String, dynamic>.from(
      await readJsonLimited(request, 8 * 1024 * 1024) as Map,
    );
  } on PayloadTooLarge {
    return reply({'error': 'Payload too large'}, status: 413);
  } catch (_) {
    return reply({'error': 'Invalid JSON payload'}, status: 400);
  }
  final entries = body['entries'];
  if (entries is! List ||
      entries.length > 1000 ||
      entries.any((dynamic entry) => entry is! Map)) {
    return reply({'error': 'Invalid payload'}, status: 400);
  }
  final suppliedBatch = body.containsKey('uploadBatchId')
      ? bounded(body['uploadBatchId'], 128)
      : null;
  if (body.containsKey('uploadBatchId') && suppliedBatch == null) {
    return reply({'error': 'Invalid payload'}, status: 400);
  }
  final batchId = suppliedBatch ?? _uuid.v4();
  final now = DateTime.now().toUtc();
  final db = await HoneycombDatabase.instance;
  final collection = db.collection('raw_scouting_data');
  for (final item in entries) {
    final entry = Map<String, dynamic>.from(item as Map);
    final meta = entry['meta'] is Map
        ? Map<String, dynamic>.from(entry['meta'] as Map)
        : null;
    final entryId = bounded(entry.remove('id'), 128);
    final legacyId = meta == null
        ? null
        : bounded(meta.remove('existingId'), 128);
    final targetId = entryId ?? legacyId ?? _uuid.v4();
    if (meta != null) entry['meta'] = meta;
    await collection.replaceOne(
      {'docId': targetId},
      {
        'docId': targetId,
        'uploadBatchId': batchId,
        'timestamp': now,
        'data': entry,
        'processed': false,
      },
      upsert: true,
    );
  }
  return reply({
    'success': true,
    'count': entries.length,
    'message': 'Data synced successfully.',
    'uploadBatchId': batchId,
  }, status: 201);
}

Future<Response> scouting(
  Request request,
  Access access, [
  String? docId,
]) async {
  final db = await HoneycombDatabase.instance;
  final collection = db.collection('raw_scouting_data');
  if (docId == null && request.method == HttpMethod.get) {
    if (!access.has('match.read'))
      return reply({'error': 'Forbidden'}, status: 403);
    final query = request.uri.queryParameters;
    final year = query['year'] == null ? null : int.tryParse(query['year']!);
    final limit = query['limit'] == null ? 1000 : int.tryParse(query['limit']!);
    final skip = query['skip'] == null ? 0 : int.tryParse(query['skip']!);
    if ((query['year'] != null && year == null) ||
        limit == null ||
        limit < 0 ||
        skip == null ||
        skip < 0) {
      return reply({
        'error': 'Invalid pagination or year parameter',
      }, status: 400);
    }
    final filter = <String, dynamic>{};
    if (query['event'] != null) filter['data.meta.event'] = query['event'];
    if (year != null) filter['data.meta.season'] = year;
    final docs = await collection
        .modernFind(
          filter: filter,
          skip: skip,
          limit: limit.clamp(0, 5000),
        )
        .toList();
    final total = await collection.count(filter);
    final rows = docs.map((doc) {
      final copy = cleanDocument(doc);
      copy['_id'] = copy['docId'] ?? jsonSafe(doc['_id']);
      return copy;
    }).toList();
    return reply({
      'data': rows,
      'total': total,
      'limit': limit.clamp(0, 5000),
      'skip': skip,
    });
  }
  if (docId == null) return reply({'error': 'Method not allowed'}, status: 405);
  if (!access.has('match.correct'))
    return reply({'error': 'Forbidden'}, status: 403);
  final type = request.uri.queryParameters['type'];
  if (!_scoutingTypes.contains(type)) {
    return reply({
      'error': 'Missing or invalid required parameter "type".',
    }, status: 400);
  }
  final filter = {'docId': docId, 'data.meta.type': type};
  if (request.method == HttpMethod.delete) {
    final result = await collection.deleteOne(filter);
    return result.nRemoved == 0
        ? reply({'error': 'Document not found (or type mismatch)'}, status: 404)
        : reply({'ok': true, 'docId': docId, 'deletedCount': result.nRemoved});
  }
  if (request.method == HttpMethod.patch) {
    final body = await readObject(request);
    final updates = body?['updates'];
    if (updates is! Map)
      return reply({'error': 'Invalid updates'}, status: 400);
    final set = <String, dynamic>{};
    for (final entry in updates.entries) {
      final key = entry.key.toString();
      if (key.startsWith('_')) continue;
      if (!RegExp(r'^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)*$').hasMatch(key) ||
          key.split('.').any((part) => part == '__proto__')) {
        return reply({'error': 'Invalid field path'}, status: 400);
      }
      set['data.$key'] = entry.value;
    }
    if (set.isEmpty)
      return reply({'error': 'No valid fields to update'}, status: 400);
    final result = await collection.updateOne(filter, {r'$set': set});
    return result.nMatched == 0
        ? reply({'error': 'Document not found (or type mismatch)'}, status: 404)
        : reply({
            'ok': true,
            'docId': docId,
            'modifiedCount': result.nModified,
            'updatedFields': set.keys.toList(),
          });
  }
  return reply({'error': 'Method not allowed'}, status: 405);
}
