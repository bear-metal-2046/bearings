import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:grove/grove.dart';
import 'package:http/http.dart' as http;

import 'entity_store.dart';

enum _NexusFeed { status, pits }

/// Imports direct Nexus data into the same store used by Grove subscriptions.
class NexusSync {
  NexusSync({
    required this.store,
    this.apiKey,
    this.webhookToken,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _catalogDue = (now ?? DateTime.now)();

  final EntityStore store;
  final String? apiKey;
  final String? webhookToken;
  final http.Client _client;
  final DateTime Function() _now;
  final _jobs = <(String, _NexusFeed), _Refresh>{};
  DateTime _catalogDue;
  DateTime? _pauseUntil;
  DateTime? _nextErrorLog;
  Timer? _timer;
  Future<bool>? _pending;
  bool _started = false;
  bool _closed = false;

  bool get _canPull => apiKey?.isNotEmpty ?? false;
  bool get _canReceive => webhookToken?.isNotEmpty ?? false;

  /// Poll the Nexus event catalog even with no Grove clients connected.
  void start() {
    if (_started || _closed || !_canPull) return;
    _started = true;
    _timer = Timer(Duration.zero, _tick);
  }

  Future<void> _tick() async {
    final didWork = await syncNext();
    if (!_closed) {
      _timer = Timer(Duration(milliseconds: didWork ? 350 : 2000), _tick);
    }
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _client.close();
    await _pending;
  }

  /// Bootstrap a directly requested event, including demo and historical keys
  /// that are absent from the live catalog.
  void onRead(QueryDescription query) {
    final feed = switch (query.type) {
      final type when type == eventStatusSnapshotEntity.type =>
        _NexusFeed.status,
      final type when type == pitLayoutEntity.type => _NexusFeed.pits,
      _ => null,
    };
    if (!_canPull || feed == null) return;
    for (final filter in query.filters) {
      final id = filter.value;
      if (filter.field == 'id' &&
          filter.operator == FilterOperator.equal &&
          id is String &&
          isNexusEventKey(id)) {
        final now = _now();
        _schedule(id, feed, now, now.add(const Duration(minutes: 15)));
        return;
      }
    }
  }

  /// Receives the live event snapshot and handles the registration probe.
  Future<Response> receive(Request request) async {
    if (request.method != HttpMethod.post) {
      return Response(statusCode: 405, headers: {'allow': 'POST'});
    }
    if (!_canReceive) return Response(statusCode: 503);
    final sentToken = request.headers['nexus-token'];
    final authenticated = _matchesToken(sentToken, webhookToken!);
    if (sentToken != null && !authenticated) {
      return Response(statusCode: 401);
    }
    final maxBytes = authenticated ? 1024 * 1024 : 2048;
    final data = BytesBuilder(copy: false);
    try {
      await for (final chunk in request.bytes().timeout(
        const Duration(seconds: 10),
      )) {
        if (data.length + chunk.length > maxBytes)
          return Response(statusCode: 413);
        data.add(chunk);
      }
      final body = utf8.decode(data.takeBytes()).trim();
      if (body.isEmpty) return Response();
      final Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        // Registration can check reachability with plain text.
        if (body.startsWith('{') || body.startsWith('[')) rethrow;
        return Response();
      }
      // A registration probe may carry metadata, including an event key.
      // Only a status payload proceeds to authentication and storage.
      if (decoded is! Json ||
          decoded['test'] == true ||
          !const {
            'dataAsOfTime',
            'matches',
            'match',
            'nowQueuing',
            'announcements',
            'partsRequests',
          }.any(decoded.containsKey)) {
        return Response();
      }
      if (!authenticated) return Response(statusCode: 401);
      final status = parseNexusEventSnapshot(decoded);
      final saved = _saveStatus(status);
      if (_canPull) {
        final now = _now();
        final until = now.add(const Duration(minutes: 15));
        final statusJob = _schedule(status.id, _NexusFeed.status, now, until);
        final fallback = now.add(const Duration(minutes: 1));
        if (saved && statusJob != null && fallback.isAfter(statusJob.due)) {
          statusJob.due = fallback;
        }
        _schedule(status.id, _NexusFeed.pits, now, until);
      }
      return Response();
    } on FormatException {
      return Response(statusCode: 400);
    } on TypeError {
      return Response(statusCode: 400);
    } on ArgumentError {
      return Response(statusCode: 400);
    } on TimeoutException {
      return Response(statusCode: 408);
    }
  }

  static bool _matchesToken(String? sent, String expected) {
    if (sent == null || sent.length != expected.length) return false;
    var mismatch = 0;
    for (var i = 0; i < expected.length; i++) {
      mismatch |= sent.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return mismatch == 0;
  }

  /// Refresh a due dataset. Concurrent callers share the in-flight operation.
  Future<bool> syncNext() =>
      _pending ??= _syncNext().whenComplete(() => _pending = null);

  Future<bool> _syncNext() async {
    final now = _now();
    if (_closed || !_canPull || (_pauseUntil?.isAfter(now) ?? false))
      return false;
    if (!_catalogDue.isAfter(now)) {
      _catalogDue = now.add(const Duration(minutes: 5));
      try {
        final events = await _get('/events');
        _discover(events ?? const {}, _now());
      } catch (error) {
        _report(error);
      }
      return true;
    }
    _jobs.removeWhere((_, job) => job.until.isBefore(now));
    MapEntry<(String, _NexusFeed), _Refresh>? next;
    for (final entry in _jobs.entries) {
      if (entry.value.due.isAfter(now)) continue;
      if (next == null || entry.value.due.isBefore(next.value.due))
        next = entry;
    }
    if (next == null) return false;
    final (event, feed) = next.key;
    final job = next.value;
    try {
      switch (feed) {
        case _NexusFeed.status:
          final response = await _get('/event/$event');
          if (response == null) {
            // A 404 from an in-flight poll must not postpone a newer push.
            if (!job.due.isAfter(now)) {
              job.due = _now().add(const Duration(minutes: 5));
            }
          } else {
            final status = parseNexusEventSnapshot(response);
            if (status.id != event)
              throw const FormatException('Unexpected Nexus event');
            _saveStatus(status);
            final due = _now().add(const Duration(seconds: 30));
            // A newer webhook can arrive while this request is in flight.
            if (due.isAfter(job.due)) job.due = due;
          }
        case _NexusFeed.pits:
          final map = await _get('/event/$event/map');
          final addresses = await _get('/event/$event/pits');
          _save(
            pitLayoutEntity,
            event,
            parseNexusPitLayout(event, map: map, addresses: addresses),
          );
          job.due = _now().add(const Duration(minutes: 5));
      }
    } catch (error) {
      final retry = _now().add(const Duration(minutes: 1));
      if (retry.isAfter(job.due)) job.due = retry;
      _report(error);
    }
    return true;
  }

  void _discover(Json events, DateTime now) {
    for (final entry in events.entries) {
      final value = entry.value;
      if (!isNexusEventKey(entry.key) || value is! Json) continue;
      final start = value['start'];
      final end = value['end'];
      if (start is! num || end is! num) continue;
      final startAt = DateTime.fromMillisecondsSinceEpoch(
        start.toInt(),
        isUtc: true,
      );
      final endAt = DateTime.fromMillisecondsSinceEpoch(
        end.toInt(),
        isUtc: true,
      );
      if (endAt.isBefore(now) ||
          startAt.isAfter(now.add(const Duration(days: 2)))) {
        continue;
      }
      _schedule(entry.key, _NexusFeed.pits, now, endAt);
      if (!startAt.isAfter(now.add(const Duration(hours: 6)))) {
        _schedule(entry.key, _NexusFeed.status, now, endAt);
      }
    }
  }

  _Refresh? _schedule(
    String event,
    _NexusFeed feed,
    DateTime now,
    DateTime until,
  ) {
    final key = (event, feed);
    final current = _jobs[key];
    if (current != null && !current.until.isBefore(now)) {
      if (until.isAfter(current.until)) current.until = until;
      return current;
    }
    _jobs.removeWhere((_, job) => job.until.isBefore(now));
    if (_jobs.length >= 1024) return null;
    return _jobs[key] = _Refresh(due: now, until: until);
  }

  bool _saveStatus(EventStatusSnapshot status) {
    final record = store.get(eventStatusSnapshotEntity.type, status.id);
    if (record != null &&
        !record.deleted &&
        !status.dataAsOfTime.isAfter(
          eventStatusSnapshotEntity.read(record).dataAsOfTime,
        )) {
      return false;
    }
    _save(eventStatusSnapshotEntity, status.id, status);
    return true;
  }

  void _save<T>(EntityDescriptor<T> descriptor, String id, T value) {
    store.replaceExternalDataset(
      '${descriptor.type}/$id',
      [
        EntityRecord(
          type: descriptor.type,
          id: id,
          version: descriptor.version,
          data: descriptor.encode(value),
        ),
      ],
      checkpoint: () {},
    );
  }

  Future<Json?> _get(String path) async {
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 8), abort.complete);
    try {
      final request =
          http.AbortableRequest(
              'GET',
              Uri.https('frc.nexus', '/api/v1$path'),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers['Nexus-Api-Key'] = apiKey!;
      final response = await _client
          .send(request)
          .then(http.Response.fromStream);
      if (response.statusCode == 404) return null;
      if (response.statusCode == 429 ||
          response.statusCode == 503 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        final retry = response.headers['retry-after'];
        final now = _now();
        var seconds = int.tryParse(retry ?? '') ?? 0;
        if (retry != null && seconds == 0) {
          try {
            seconds = HttpDate.parse(retry).difference(now).inSeconds;
          } on FormatException {
            // Use the default pause when the header is malformed.
          }
        }
        _pauseUntil = now.add(Duration(seconds: max(60, seconds)));
      }
      if (response.statusCode != 200) {
        throw HttpException('Nexus returned HTTP ${response.statusCode}');
      }
      return jsonDecode(utf8.decode(response.bodyBytes)) as Json;
    } finally {
      timer.cancel();
    }
  }

  void _report(Object error) {
    final now = _now();
    if (_closed || (_nextErrorLog?.isAfter(now) ?? false)) return;
    stderr.writeln('Nexus import failed (${error.runtimeType})');
    _nextErrorLog = now.add(const Duration(minutes: 1));
  }
}

class _Refresh {
  _Refresh({required this.due, required this.until});

  DateTime due;
  DateTime until;
}
