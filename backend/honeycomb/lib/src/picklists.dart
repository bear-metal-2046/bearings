import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'database.dart';
import 'security.dart';

final _uuid = Uuid();

Response reply(Object? body, {int status = 200}) =>
    Response.json(statusCode: status, body: body);

Future<Response> picklistCollection(Request request, Access access) async {
  final db = await HoneycombDatabase.instance;
  final collection = db.collection('picklists');
  if (request.method == HttpMethod.get) {
    if (!access.has('picklists.read'))
      return reply({'error': 'Forbidden'}, status: 403);
    final eventKey = request.uri.queryParameters['eventKey']?.trim();
    if (eventKey == null || eventKey.isEmpty)
      return reply({'error': 'Missing eventKey'}, status: 400);
    final records = await collection
        .find(
          where.eq('eventKey', eventKey).sortBy('updatedAt', descending: true),
        )
        .toList();
    return reply(records.map(serializePicklist).toList());
  }
  if (request.method == HttpMethod.post) {
    if (!access.has('picklists.manage'))
      return reply({'error': 'Forbidden'}, status: 403);
    final body = await readObject(request);
    if (body == null)
      return reply({'error': 'Invalid picklist payload'}, status: 400);
    final suppliedId = body.containsKey('id') ? bounded(body['id'], 128) : null;
    if (body.containsKey('id') && suppliedId == null) {
      return reply({'error': 'Invalid picklist payload'}, status: 400);
    }
    final id = suppliedId ?? _uuid.v4();
    final eventKey = bounded(body['eventKey'], 64);
    final title = bounded(body['title'], 200);
    final emoji = bounded(body['emoji'], 32);
    final teamKeys = teamKeyList(body['teamKeys'] ?? <dynamic>[]);
    if (eventKey == null ||
        title == null ||
        emoji == null ||
        teamKeys == null) {
      return reply({'error': 'Invalid picklist payload'}, status: 400);
    }
    if (await collection.findOne({'id': id}) != null) {
      return reply({'error': 'Picklist already exists'}, status: 409);
    }
    final now = DateTime.now().toUtc();
    final record = <String, dynamic>{
      'id': id,
      'eventKey': eventKey,
      'title': title,
      'emoji': emoji,
      'teamKeys': teamKeys,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': access.userId,
      'updatedBy': access.userId,
    };
    try {
      await collection.insertOne(record);
    } catch (_) {
      if (await collection.findOne({'id': id}) != null) {
        return reply({'error': 'Picklist already exists'}, status: 409);
      }
      rethrow;
    }
    return reply(serializePicklist(record), status: 201);
  }
  return reply({'error': 'Method not allowed'}, status: 405);
}

Future<Response> picklistItem(Request request, Access access, String id) async {
  final db = await HoneycombDatabase.instance;
  final collection = db.collection('picklists');
  if (request.method == HttpMethod.get) {
    if (!access.has('picklists.read'))
      return reply({'error': 'Forbidden'}, status: 403);
    final record = await collection.findOne({'id': id});
    return record == null
        ? reply({'error': 'Picklist not found'}, status: 404)
        : reply(serializePicklist(record));
  }
  if (!access.has('picklists.manage'))
    return reply({'error': 'Forbidden'}, status: 403);
  if (request.method == HttpMethod.patch) {
    final body = await readObject(request);
    if (body == null || body.isEmpty)
      return reply({'error': 'Invalid picklist projection'}, status: 400);
    final set = <String, dynamic>{
      'updatedAt': DateTime.now().toUtc(),
      'updatedBy': access.userId,
    };
    for (final field in ['title', 'emoji']) {
      if (body.containsKey(field)) {
        final value = bounded(body[field], field == 'title' ? 200 : 32);
        if (value == null)
          return reply({'error': 'Invalid picklist projection'}, status: 400);
        set[field] = value;
      }
    }
    if (body.containsKey('teamKeys')) {
      final keys = teamKeyList(body['teamKeys']);
      if (keys == null)
        return reply({'error': 'Invalid picklist projection'}, status: 400);
      set['teamKeys'] = keys;
    }
    if (set.length == 2)
      return reply({'error': 'Invalid picklist projection'}, status: 400);
    final record = await collection.findAndModify(
      query: {'id': id},
      update: {r'$set': set},
      returnNew: true,
    );
    return record == null
        ? reply({'error': 'Picklist not found'}, status: 404)
        : reply(serializePicklist(record));
  }
  if (request.method == HttpMethod.delete) {
    final result = await collection.deleteOne({'id': id});
    if (result.nRemoved == 0)
      return reply({'error': 'Picklist not found'}, status: 404);
    await db.collection('picklist_relay_rooms').deleteOne({'documentId': id});
    await db.collection('picklist_relay_changes').deleteMany({
      'documentId': id,
    });
    return reply({'success': true});
  }
  return reply({'error': 'Method not allowed'}, status: 405);
}

Future<Map<String, dynamic>?> readObject(Request request) async {
  try {
    if ((int.tryParse(request.headers['content-length'] ?? '') ?? 0) >
        1024 * 1024)
      return null;
    final decoded = await readJsonLimited(request, 1024 * 1024);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

class PayloadTooLarge implements Exception {}

Future<dynamic> readJsonLimited(Request request, int maxBytes) async {
  final buffer = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in request.bytes()) {
    length += chunk.length;
    if (length > maxBytes) throw PayloadTooLarge();
    buffer.add(chunk);
  }
  return jsonDecode(utf8.decode(buffer.takeBytes()));
}

String? bounded(dynamic value, int max) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isNotEmpty && trimmed.length <= max ? trimmed : null;
}

List<String>? teamKeyList(dynamic value) {
  if (value is! List || value.length > 500) return null;
  final keys = <String>{};
  for (final item in value) {
    final key = bounded(item, 64);
    if (key == null) return null;
    keys.add(key);
  }
  return keys.toList();
}

Map<String, dynamic> serializePicklist(Map<String, dynamic> record) => {
  'id': record['id'],
  'eventKey': record['eventKey'],
  'title': record['title'],
  'emoji': record['emoji'],
  'teamKeys': record['teamKeys'] ?? <String>[],
  'createdAt': jsonSafe(record['createdAt']),
  'updatedAt': jsonSafe(record['updatedAt']),
  'createdBy': record['createdBy'] ?? '',
  'updatedBy': record['updatedBy'] ?? '',
};

class PicklistRealtime {
  PicklistRealtime._();
  static final instance = PicklistRealtime._();
  final _connections = <String, Set<WebSocketChannel>>{};
  final _userConnections = <String, int>{};
  final _queue = <String, Future<void>>{};
  int _pendingBytes = 0;

  String get _secret {
    final value = Platform.environment['REALTIME_TICKET_SECRET'];
    if (value == null || value.length < 32) {
      throw StateError(
        'REALTIME_TICKET_SECRET must contain at least 32 characters',
      );
    }
    return value;
  }

  Future<Response> negotiate(Request request, Access access) async {
    if (!access.has('picklists.read'))
      return reply({'error': 'Forbidden'}, status: 403);
    final id = request.uri.queryParameters['picklistId'];
    if (id == null || id.isEmpty || id.length > 128) {
      return reply({'error': 'Missing picklistId'}, status: 400);
    }
    final db = await HoneycombDatabase.instance;
    if (await db.collection('picklists').findOne({'id': id}) == null) {
      return reply({'error': 'Picklist not found'}, status: 404);
    }
    final ticket = JWT(
      {
        'picklistId': id,
        'userId': access.userId,
        'username': access.username,
      },
      issuer: 'honeycomb',
      audience: Audience.one('picklist-realtime'),
    ).sign(SecretKey(_secret), expiresIn: const Duration(minutes: 1));
    final publicBase = Platform.environment['PUBLIC_BASE_URL'];
    final base = publicBase == null || publicBase.isEmpty
        ? request.uri
        : Uri.parse(publicBase);
    final forwarded = request.headers['x-forwarded-proto'];
    final scheme = (base.scheme == 'https' || forwarded == 'https')
        ? 'wss'
        : 'ws';
    final uri = base.replace(
      scheme: scheme,
      path: '/api/picklists/realtime',
      queryParameters: {'ticket': ticket},
    );
    return reply({'url': uri.toString(), 'documentId': id});
  }

  Future<Response> connect(RequestContext context) async {
    final ticket = context.request.uri.queryParameters['ticket'];
    if (ticket == null || ticket.length > 8192)
      return reply({'error': 'Unauthorized'}, status: 401);
    late final Map<String, dynamic> payload;
    try {
      final decoded = JWT.decode(ticket);
      if (decoded.header?['alg'] != 'HS256')
        throw StateError('Invalid algorithm');
      final verified = JWT.verify(
        ticket,
        SecretKey(_secret),
        issuer: 'honeycomb',
        audience: Audience.one('picklist-realtime'),
      );
      payload = Map<String, dynamic>.from(verified.payload as Map);
      if (payload['exp'] is! num) throw StateError('Missing expiry');
    } catch (_) {
      return reply({'error': 'Unauthorized'}, status: 401);
    }
    final id = payload['picklistId'];
    final userId = payload['userId'];
    final username = payload['username'];
    if (id is! String ||
        userId is! String ||
        username is! String ||
        id.isEmpty ||
        id.length > 128) {
      return reply({'error': 'Unauthorized'}, status: 401);
    }
    final access = await AuthService.instance.forIdentity(userId, username);
    if (!access.has('picklists.read'))
      return reply({'error': 'Forbidden'}, status: 403);
    final db = await HoneycombDatabase.instance;
    if (await db.collection('picklists').findOne({'id': id}) == null) {
      return reply({'error': 'Picklist not found'}, status: 404);
    }
    final peers = _connections.putIfAbsent(id, () => {});
    if (peers.length >= 50) return reply({'error': 'Room full'}, status: 429);
    if ((_userConnections[userId] ?? 0) >= 5) {
      return reply({'error': 'Too many connections'}, status: 429);
    }
    return webSocketHandler((channel, _) {
      peers.add(channel);
      _userConnections[userId] = (_userConnections[userId] ?? 0) + 1;
      var pending = Future<void>.value();
      var queued = 0;
      var messageCount = 0;
      var awarenessCount = 0;
      var window = DateTime.now();
      channel.stream.listen(
        (raw) {
          final now = DateTime.now();
          if (now.difference(window).inSeconds >= 1) {
            window = now;
            messageCount = 0;
            awarenessCount = 0;
          }
          messageCount++;
          if (raw is! String) {
            unawaited(channel.sink.close(WebSocketStatus.policyViolation));
            return;
          }
          final byteLength = utf8.encode(raw).length;
          if (messageCount > 30 ||
              byteLength > 9 * 1024 * 1024 ||
              queued >= 4 ||
              _pendingBytes + byteLength > 32 * 1024 * 1024) {
            unawaited(channel.sink.close(WebSocketStatus.policyViolation));
            return;
          }
          queued++;
          _pendingBytes += byteLength;
          pending = pending
              .then((_) async {
                try {
                  final frame = jsonDecode(raw);
                  if (frame is! Map<String, dynamic> ||
                      frame['documentId'] != id) {
                    _send(channel, {
                      'type': 7,
                      'documentId': id,
                      'code': 'invalid_message',
                    });
                    return;
                  }
                  if (frame['type'] == 100 ||
                      frame['type'] == 101 ||
                      frame['type'] == 102) {
                    awarenessCount++;
                    if (awarenessCount > 5 || byteLength > 2048) {
                      await channel.sink.close(WebSocketStatus.policyViolation);
                      return;
                    }
                  }
                  await _handle(id, access, channel, frame);
                } catch (error) {
                  _send(channel, {
                    'type': 7,
                    'documentId': id,
                    'code': 'server_error',
                  });
                  stderr.writeln('picklist relay: $error');
                }
              })
              .whenComplete(() {
                queued--;
                _pendingBytes -= byteLength;
              });
        },
        onDone: () {
          peers.remove(channel);
          if (peers.isEmpty) _connections.remove(id);
          final remaining = (_userConnections[userId] ?? 1) - 1;
          if (remaining <= 0) {
            _userConnections.remove(userId);
          } else {
            _userConnections[userId] = remaining;
          }
        },
      );
    })(context);
  }

  Future<void> _handle(
    String id,
    Access access,
    WebSocketChannel channel,
    Map<String, dynamic> frame,
  ) async {
    final type = frame['type'];
    if (type == 20 || type == 26) {
      _send(channel, await _welcome(id));
      return;
    }
    if (type == 5) {
      _send(channel, {
        'type': 6,
        'documentId': id,
        'originalTimestamp':
            frame['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        'responseTimestamp': DateTime.now().millisecondsSinceEpoch,
      });
      return;
    }
    if (type == 100 || type == 101 || type == 102) {
      _broadcast(id, channel, frame);
      return;
    }
    final fresh = await AuthService.instance.forIdentity(
      access.userId,
      access.username,
    );
    if (!fresh.has('picklists.manage')) {
      _send(channel, {'type': 7, 'documentId': id, 'code': 'forbidden'});
      return;
    }
    if (type == 22) {
      final changes = frame['changes'];
      if (changes is! List ||
          changes.length > 64 ||
          changes.any(
            (dynamic item) =>
                item is! String || utf8.encode(item).length > 1024 * 1024,
          ) ||
          utf8.encode(jsonEncode(changes)).length > 2 * 1024 * 1024) {
        _send(channel, {
          'type': 7,
          'documentId': id,
          'code': 'invalid_changes',
        });
        return;
      }
      await _serial(id, () async {
        final db = await HoneycombDatabase.instance;
        final rooms = db.collection('picklist_relay_rooms');
        final now = DateTime.now().toUtc();
        final bytes = changes.fold<int>(
          0,
          (sum, item) => sum + utf8.encode(item as String).length,
        );
        final prior = await rooms.findOne({'documentId': id});
        if ((prior?['logBytes'] as num? ?? 0).toInt() + bytes >
            12 * 1024 * 1024) {
          _send(channel, {'type': 7, 'documentId': id, 'code': 'room_full'});
          return;
        }
        final room = await rooms.findAndModify(
          query: {'documentId': id},
          update: {
            r'$inc': {'nextSeq': changes.length, 'logBytes': bytes},
            r'$set': {'updatedAt': now},
            r'$setOnInsert': {
              'documentId': id,
              'snapshot': null,
              'snapshotSeq': 0,
              'createdAt': now,
            },
          },
          upsert: true,
          returnNew: true,
        );
        if (room == null) throw StateError('Room allocation failed');
        final seq = (room['nextSeq'] as num).toInt();
        for (var i = 0; i < changes.length; i++) {
          await db.collection('picklist_relay_changes').insertOne({
            'documentId': id,
            'seq': seq - changes.length + i + 1,
            'blob': changes[i],
            'createdAt': now,
          });
        }
        final count = await db.collection('picklist_relay_changes').count({
          'documentId': id,
          'seq': {r'$gt': room['snapshotSeq'] ?? 0},
        });
        _send(channel, {
          'type': 23,
          'documentId': id,
          'seq': seq,
          'count': changes.length,
          'logLength': count,
          'compact':
              count >= 500 ||
              (room['logBytes'] as num? ?? 0) >= 8 * 1024 * 1024,
        });
        if (changes.isNotEmpty) {
          _broadcast(id, channel, {
            'type': 24,
            'documentId': id,
            'changes': changes,
            'seq': seq,
            'from': access.userId,
          });
        }
      });
      return;
    }
    if (type == 25) {
      final snapshot = frame['snapshot'];
      final upToSeq = frame['upToSeq'];
      if (snapshot is! String ||
          utf8.encode(snapshot).length > 8 * 1024 * 1024 ||
          upToSeq is! int ||
          upToSeq <= 0) {
        _send(channel, {
          'type': 7,
          'documentId': id,
          'code': 'invalid_snapshot',
        });
        return;
      }
      await _serial(id, () async {
        final db = await HoneycombDatabase.instance;
        final rooms = db.collection('picklist_relay_rooms');
        final room = await rooms.findOne({'documentId': id});
        if (room == null || upToSeq > (room['nextSeq'] as num).toInt()) {
          _send(channel, {
            'type': 7,
            'documentId': id,
            'code': 'invalid_snapshot',
          });
          return;
        }
        await rooms.updateOne(
          {
            'documentId': id,
            'snapshotSeq': {r'$lt': upToSeq},
          },
          {
            r'$set': {
              'snapshot': snapshot,
              'snapshotSeq': upToSeq,
              'updatedAt': DateTime.now().toUtc(),
            },
          },
        );
        await db.collection('picklist_relay_changes').deleteMany({
          'documentId': id,
          'seq': {r'$lte': upToSeq},
        });
        var remainingBytes = 0;
        await for (final change in db.collection('picklist_relay_changes').find(
          {
            'documentId': id,
            'seq': {r'$gt': upToSeq},
          },
        )) {
          remainingBytes += utf8.encode(change['blob'] as String).length;
        }
        await rooms.updateOne(
          {'documentId': id},
          {
            r'$set': {'logBytes': remainingBytes},
          },
        );
      });
      return;
    }
    _send(channel, {'type': 7, 'documentId': id, 'code': 'unsupported_type'});
  }

  Future<Map<String, dynamic>> _welcome(String id) async {
    final db = await HoneycombDatabase.instance;
    final room = await db.collection('picklist_relay_rooms').findOne({
      'documentId': id,
    });
    final snapshotSeq = room?['snapshotSeq'] ?? 0;
    final stream = db
        .collection('picklist_relay_changes')
        .find(
          where.eq('documentId', id).gt('seq', snapshotSeq).sortBy('seq'),
        );
    final changes = <Map<String, dynamic>>[];
    var bytes = 0;
    await for (final change in stream) {
      bytes += utf8.encode(change['blob'] as String).length;
      if (bytes > 12 * 1024 * 1024 || changes.length >= 4096) {
        throw StateError('Picklist change log exceeds relay limit');
      }
      changes.add(change);
    }
    return {
      'type': 21,
      'documentId': id,
      'sessionId': '$id:' + _uuid.v4(),
      'snapshot': room?['snapshot'],
      'changes': changes.map((e) => e['blob']).toList(),
      'seq': room?['nextSeq'] ?? 0,
      'logLength': changes.length,
      'compact': changes.length >= 500 || bytes >= 8 * 1024 * 1024,
    };
  }

  Future<void> _serial(String id, Future<void> Function() action) async {
    final previous = _queue[id] ?? Future<void>.value();
    final current = previous.catchError((Object _) {}).then((_) => action());
    _queue[id] = current;
    try {
      await current;
    } finally {
      if (identical(_queue[id], current)) _queue.remove(id);
    }
  }

  void _send(WebSocketChannel channel, Map<String, dynamic> frame) {
    channel.sink.add(jsonEncode(frame));
  }

  void _broadcast(
    String id,
    WebSocketChannel sender,
    Map<String, dynamic> frame,
  ) {
    final serialized = jsonEncode(frame);
    for (final peer in _connections[id] ?? const <WebSocketChannel>{}) {
      if (!identical(peer, sender)) peer.sink.add(serialized);
    }
  }
}
