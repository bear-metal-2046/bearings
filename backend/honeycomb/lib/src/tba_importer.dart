import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/src/entity_store.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

/// Crawls TBA's public season datasets from catalogs. SQLite records both the
/// work to do and the last successful response, so a restart resumes the crawl.
class TbaImporter {
  /// Create the import queue on the same SQLite database as Grove entities.
  TbaImporter({
    required this._store,
    required this._apiKey,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now {
    _db
      ..execute('''
        CREATE TABLE IF NOT EXISTS tba_sync_jobs (
          path TEXT PRIMARY KEY, season INTEGER, priority INTEGER NOT NULL,
          active_from INTEGER, active_until INTEGER, due INTEGER NOT NULL,
          failures INTEGER NOT NULL DEFAULT 0, etag TEXT
        )
      ''')
      ..execute('CREATE INDEX IF NOT EXISTS tba_sync_due ON tba_sync_jobs(due)')
      ..execute('''
        CREATE TABLE IF NOT EXISTS tba_sync_pause (
          id INTEGER PRIMARY KEY CHECK (id = 1), until INTEGER NOT NULL
        )
      ''');
    _prepareMatchArchive();
    _enqueue(const _TbaJob('/status', priority: 0), _now());
    _enqueue(const _TbaJob('/media/tags', priority: 0), _now());
  }

  // Existing checkpoints can otherwise return 304 indefinitely. Keep their
  // normal due times and refresh the body on the next scheduled poll.
  void _prepareMatchArchive() {
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        'CREATE TABLE IF NOT EXISTS tba_sync_metadata (name TEXT PRIMARY KEY)',
      );
      _db.execute(
        "INSERT OR IGNORE INTO tba_sync_metadata (name) VALUES ('match_archive')",
      );
      if (_db.updatedRows > 0) {
        _db.execute('''
          UPDATE tba_sync_jobs SET etag = NULL
          WHERE path GLOB '/event/*/matches' OR path GLOB '/event/*/matches/practice'
        ''');
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  final EntityStore _store;
  final String _apiKey;
  final http.Client _client;
  final DateTime Function() _now;
  Database get _db => _store.database;
  Timer? _timer;
  Future<bool>? _pending;
  bool _started = false;
  bool _closed = false;
  DateTime? _nextErrorLog;
  int _requests = 0;

  /// Begin polling once for the life of the Honeycomb process.
  void start() {
    if (_started || _closed) return;
    _started = true;
    _timer = Timer(Duration.zero, _tick);
  }

  Future<void> _tick() async {
    if (_closed) return;
    var delay = const Duration(seconds: 20);
    try {
      if (await syncNext()) delay = const Duration(milliseconds: 250);
    } catch (error) {
      _log('could not process the sync queue (${error.runtimeType})');
    }
    if (!_closed) _timer = Timer(delay, _tick);
  }

  /// Stop polling and wait for the current request to finish.
  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _client.close();
    await _pending;
  }

  /// Process one due request. Concurrent callers share the same in-flight work.
  Future<bool> syncNext() =>
      _pending ??= _syncNext().whenComplete(() => _pending = null);

  Future<bool> _syncNext() async {
    if (_closed) return false;
    final now = _now().toUtc();
    final timestamp = now.millisecondsSinceEpoch;
    if (_db.select(
      'SELECT id FROM tba_sync_pause WHERE until > ?',
      [timestamp],
    ).isNotEmpty) {
      return false;
    }

    // Reserve one request in four for the oldest due work so the backfill
    // progresses even during a busy competition weekend.
    final rows = _db.select(
      _requests % 4 == 3
          ? 'SELECT * FROM tba_sync_jobs WHERE due <= ? ORDER BY due LIMIT 1'
          : '''
            SELECT * FROM tba_sync_jobs WHERE due <= ?
            ORDER BY CASE WHEN ? BETWEEN active_from AND active_until AND priority = 2
                          THEN 1 ELSE priority END, due, path LIMIT 1
          ''',
      [timestamp, if (_requests % 4 != 3) timestamp],
    );
    if (rows.isEmpty) return false;

    final row = rows.single;
    _requests++;
    final job = _TbaJob.fromRow(row);
    final etag = row['etag'] as String?;
    final abort = Completer<void>();
    final timeout = Timer(const Duration(seconds: 12), abort.complete);
    try {
      final request = http.AbortableRequest(
        'GET',
        Uri.https('www.thebluealliance.com', '/api/v3${job.path}'),
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers['X-TBA-Auth-Key'] = _apiKey;
      if (etag != null) request.headers['If-None-Match'] = etag;
      final response = await _client
          .send(request)
          .then(http.Response.fromStream);
      final receivedAt = _now().toUtc();
      final status = response.statusCode;
      if (status == 304 && etag != null) {
        _complete(job, receivedAt, response, etag: etag);
        return true;
      }
      if (status == 404 && job.path != '/status') {
        _store.replaceExternalDataset(
          job.path,
          [],
          checkpoint: () {
            _complete(job, receivedAt, response, etag: null);
          },
        );
        return true;
      }
      if (status != 200) {
        _retry(row, receivedAt, 'HTTP $status', response: response);
        return true;
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final (records, discovered, matchSamples) = _import(
        job,
        data,
        receivedAt,
      );
      _store.replaceExternalDataset(
        job.path,
        records,
        tbaSamples: matchSamples,
        checkpoint: () {
          for (final child in discovered) {
            _enqueue(child, receivedAt);
          }
          _complete(job, receivedAt, response, etag: response.headers['etag']);
        },
      );
    } on http.ClientException {
      if (!_closed) _retry(row, _now(), 'connection failed or timed out');
    } on FormatException {
      _retry(row, _now(), 'invalid TBA response');
    } on TypeError {
      _retry(row, _now(), 'unexpected TBA field type');
    } finally {
      timeout.cancel();
    }
    return true;
  }

  void _enqueue(_TbaJob job, DateTime now) {
    _db.execute(
      '''
      INSERT INTO tba_sync_jobs (path,season,priority,active_from,active_until,due)
      VALUES (?,?,?,?,?,?)
      ON CONFLICT(path) DO UPDATE SET priority=excluded.priority,
        active_from=COALESCE(excluded.active_from, tba_sync_jobs.active_from),
        active_until=COALESCE(excluded.active_until, tba_sync_jobs.active_until),
        due=CASE WHEN excluded.active_from IS NOT NULL
                       AND excluded.active_from IS NOT tba_sync_jobs.active_from
                 THEN MIN(tba_sync_jobs.due, excluded.due)
                 ELSE tba_sync_jobs.due END
    ''',
      [
        job.path,
        job.season,
        job.priority,
        job.activeFrom?.millisecondsSinceEpoch,
        job.activeUntil?.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      ],
    );
  }

  void _complete(
    _TbaJob job,
    DateTime now,
    http.Response response, {
    required String? etag,
  }) {
    final maxAge = RegExp(r'(?:^|,)\s*max-age\s*=\s*(\d+)')
        .firstMatch(response.headers['cache-control'] ?? '')
        ?.group(1);
    final interval = job.interval(now);
    var due = now.add(
      Duration(
        seconds: max(
          interval.inSeconds,
          int.tryParse(maxAge ?? '') ?? 0,
        ),
      ),
    );
    final activeFrom = job.activeFrom;
    if (job.priority == 2 &&
        activeFrom != null &&
        activeFrom.isAfter(now) &&
        activeFrom.isBefore(due) &&
        maxAge == null) {
      due = activeFrom;
    }
    _db.execute(
      'UPDATE tba_sync_jobs SET etag=?, due=?, failures=0 WHERE path=?',
      [
        etag,
        due.millisecondsSinceEpoch,
        job.path,
      ],
    );
  }

  void _retry(Row row, DateTime now, String reason, {http.Response? response}) {
    final failures = min((row['failures'] as int) + 1, 10);
    var delay = Duration(seconds: min(3600, 15 * (1 << failures)));
    if (response?.statusCode case 429 || 401 || 403 || 503) {
      final header = response!.headers['retry-after'];
      final seconds = int.tryParse(header ?? '');
      if (seconds != null && seconds >= 0) {
        delay = Duration(seconds: max(delay.inSeconds, seconds));
      } else if (header != null) {
        try {
          final wait = HttpDate.parse(header).difference(now);
          if (wait > delay) delay = wait;
        } on FormatException {
          // Use the exponential delay for an invalid Retry-After header.
        }
      }
      if (delay < const Duration(minutes: 1)) {
        delay = const Duration(minutes: 1);
      }
      _db.execute('REPLACE INTO tba_sync_pause (id,until) VALUES (1,?)', [
        now.add(delay).millisecondsSinceEpoch,
      ]);
    }
    _db.execute('UPDATE tba_sync_jobs SET due=?, failures=? WHERE path=?', [
      now.add(delay).millisecondsSinceEpoch,
      failures,
      row['path'],
    ]);
    _log('${row['path']} failed ($reason)');
  }

  void _log(String message) {
    final now = _now();
    if (_nextErrorLog?.isAfter(now) ?? false) return;
    stderr.writeln('TBA import: $message');
    _nextErrorLog = now.add(const Duration(minutes: 1));
  }

  (List<EntityRecord>, List<_TbaJob>, List<TbaMatchSample>) _import(
    _TbaJob job,
    Object? body,
    DateTime receivedAt,
  ) {
    final path = job.path;
    final segments = path.split('/').skip(1).toList();
    final season = job.season;
    final jobs = <_TbaJob>[];
    final records = <EntityRecord>[];
    final matchSamples = <TbaMatchSample>[];

    void record<T>(T entity) {
      final descriptor = _store.registry.descriptor<T>();
      final data = descriptor.encode(entity);
      records.add(
        EntityRecord(
          type: descriptor.type,
          id: data['id'] as String,
          version: descriptor.version,
          data: data,
        ),
      );
    }

    void teamJobs(String team) {
      jobs.addAll([
        _TbaJob('/team/$team/media/$season', season: season, priority: 4),
        _TbaJob('/team/$team/robots', priority: 4),
        _TbaJob('/team/$team/social_media', priority: 4),
      ]);
    }

    void importMedia({
      String? event,
      String? team,
      String? tag,
      bool roster = false,
    }) {
      final media = _objects(body);
      for (final item in media) {
        record(
          TbaApi.media(
            path,
            item,
            season: season,
            event: event,
            team: team,
            tag: tag,
            rosterMedia: roster,
          ),
        );
      }
      if (team != null && tag == null && season != null && media.isNotEmpty) {
        for (final row in _db.select(
          'SELECT id FROM entities WHERE type = ? AND deleted = 0',
          [
            mediaTagEntity.type,
          ],
        )) {
          jobs.add(_tagJob(team, season, row['id'] as String));
        }
      }
    }

    switch (segments) {
      case ['status']:
        final status = body as Json;
        final maxSeason = status['max_season'] as int;
        final maxTeamPage = status['max_team_page'] as int;
        if (maxSeason < 1992 || maxSeason > 9999 || maxTeamPage < 0) {
          throw const FormatException('Invalid TBA catalog bounds');
        }
        for (var year = firstMirroredTbaSeason; year <= maxSeason; year++) {
          jobs.addAll([
            _TbaJob('/events/$year', season: year, priority: 0),
            _TbaJob('/districts/$year', season: year),
            for (var page = 0; page <= maxTeamPage; page++)
              _TbaJob('/teams/$year/$page', season: year),
            _TbaJob('/regional_advancement/$year', season: year),
            _TbaJob('/regional_advancement/$year/rankings', season: year),
          ]);
        }
      case ['events', _]:
        for (final item in _objects(body)) {
          final key = _key(item['key']);
          final event = TbaApi.event(item);
          record(event);
          for (final endpoint in _eventEndpoints) {
            jobs.add(
              _TbaJob(
                '/event/$key/$endpoint',
                season: season,
                priority: _coreEventEndpoints.contains(endpoint) ? 2 : 3,
                activeFrom: event.startDate?.subtract(const Duration(days: 2)),
                activeUntil: event.endDate?.add(const Duration(days: 2)),
              ),
            );
          }
        }
      case ['districts', _]:
        for (final item in _objects(body)) {
          final key = _key(item['key']);
          record(TbaApi.district(item));
          for (final endpoint in ['advancement', 'rankings', 'teams']) {
            jobs.add(_TbaJob('/district/$key/$endpoint', season: season));
          }
        }
      case ['teams', _, _]:
        for (final item in _objects(body)) {
          final key = _key(item['key']);
          record(TbaApi.team(item));
          record(
            TeamSeason(
              id: '$season:$key',
              season: season!,
              team: EntityRef(key),
            ),
          );
          teamJobs(key);
        }
      case ['event', final event, 'teams']:
        for (final item in _objects(body)) {
          final key = _key(item['key']);
          final team = TbaApi.team(item);
          record(team);
          record(
            EventTeam(
              id: '$event:$key',
              season: season!,
              event: EntityRef(event),
              team: EntityRef(key),
              profile: team,
            ),
          );
          teamJobs(key);
        }
      case ['district', final district, 'teams']:
        for (final item in _objects(body)) {
          final key = _key(item['key']);
          record(TbaApi.team(item));
          record(
            DistrictTeam(
              id: '$district:$key',
              season: season!,
              district: EntityRef(district),
              team: EntityRef(key),
            ),
          );
          teamJobs(key);
        }
      case ['event', _, 'matches'] || ['event', _, 'matches', 'practice']:
        for (final item in _objects(body)) {
          final match = TbaApi.match(item, practice: segments.length == 4);
          record(match);
          matchSamples.add((
            match: EntityRef(match.id),
            event: match.event,
            observedAt: receivedAt,
            payload: item,
          ));
        }
      case ['event', final event, 'rankings']:
        for (final ranking in TbaApi.rankings(event, body as Json?)) {
          record(ranking);
        }
      case ['event', final event, 'teams', 'statuses']:
        for (final entry
            in (body as Json? ?? const <String, dynamic>{}).entries) {
          if (entry.value case final Json status) {
            record(TbaApi.eventTeamStatus(event, entry.key, status));
          }
        }
      case ['event', final event, 'alliances']:
        for (final (index, item) in _objects(body).indexed) {
          record(TbaApi.playoffAlliance(event, index + 1, item));
        }
      case ['event', final event, 'awards']:
        for (final item in _objects(body)) {
          record(TbaApi.award(event, item));
        }
      case ['event', final event, 'playoff_advancement']:
        for (final item in _objects(body)) {
          record(TbaApi.playoffAdvancement(event, item));
        }
      case [
        'event',
        final event,
        'district_points' || 'regional_champs_pool_points',
      ]:
        final pool = segments.last == 'district_points'
            ? 'district'
            : 'regional';
        for (final item in TbaApi.eventPoints(event, pool, body as Json?)) {
          record(item);
        }
      case ['event', final event, 'nexus_info']:
        if (body != null) record(TbaApi.nexus(event, body as Json));
      case ['district', _, 'rankings'] ||
          ['regional_advancement', _, 'rankings']:
        final district = segments.first == 'district' ? segments[1] : null;
        for (final item in _objects(body)) {
          record(TbaApi.advancementRanking(season!, district, item));
        }
      case ['district', final district, 'advancement']:
        final result = body as Json?;
        final teams = result?['teams'] as Json? ?? const {};
        final cutoffs = result?['cutoffs'] as Json?;
        final qualifications =
            cutoffs?['cmp_qualification'] as Json? ?? const {};
        if (cutoffs != null)
          record(TbaApi.advancementCutoffs(district, cutoffs));
        for (final key in {...teams.keys, ...qualifications.keys}) {
          record(
            TbaApi.advancement(
              season!,
              key,
              teams[key] as Json? ?? const {},
              district: district,
              qualification: qualifications[key] as String?,
            ),
          );
        }
      case ['regional_advancement', _]:
        for (final entry
            in (body as Json? ?? const <String, dynamic>{}).entries) {
          record(TbaApi.advancement(season!, entry.key, entry.value as Json));
        }
      case ['team', final team, 'robots']:
        for (final item in _objects(body)) {
          if ((item['year'] as int) >= firstMirroredTbaSeason) {
            record(TbaApi.robot(team, item));
          }
        }
      case ['event', final event, 'media' || 'team_media']:
        importMedia(event: event, roster: segments.last == 'team_media');
      case ['team', final team, 'media', _] ||
          ['team', final team, 'social_media']:
        importMedia(team: team);
      case ['team', final team, 'media', 'tag', final tag, _]:
        importMedia(team: team, tag: tag);
      case ['media', 'tags']:
        final tags = _objects(body)
            .map(
              (item) => MediaTag(
                id: _key(item['code']),
                name: item['name'] as String,
              ),
            )
            .toList();
        for (final tag in tags) {
          record(tag);
        }
        final media = _db.select(
          '''
          SELECT DISTINCT jobs.path, jobs.season FROM tba_sync_jobs AS jobs
          JOIN external_records ON external_records.type = ? AND external_records.source = jobs.path
          WHERE jobs.path GLOB '/team/*/media/[0-9][0-9][0-9][0-9]'
        ''',
          [competitionMediaEntity.type],
        );
        for (final row in media) {
          final team = (row['path'] as String).split('/')[2];
          for (final tag in tags) {
            jobs.add(_tagJob(team, row['season'] as int, tag.id));
          }
        }
      default:
        throw FormatException('Unknown TBA sync endpoint: $path');
    }
    return (records, jobs, matchSamples);
  }

  _TbaJob _tagJob(String team, int season, String tag) => _TbaJob(
    '/team/$team/media/tag/$tag/$season',
    season: season,
    priority: 5,
  );

  static const _coreEventEndpoints = {
    'matches',
    'teams',
    'rankings',
    'team_media',
  };
  static const _eventEndpoints = [
    ..._coreEventEndpoints,
    'alliances',
    'awards',
    'district_points',
    'matches/practice',
    'media',
    'nexus_info',
    'playoff_advancement',
    'regional_champs_pool_points',
    'teams/statuses',
  ];

  static String _key(Object? key) {
    if (key is! String || !RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(key)) {
      throw const FormatException('Invalid TBA key');
    }
    return key;
  }

  static Iterable<Json> _objects(Object? data) =>
      (data as List? ?? const []).cast<Json>();
}

class _TbaJob {
  const _TbaJob(
    this.path, {
    this.season,
    this.priority = 3,
    this.activeFrom,
    this.activeUntil,
  });

  factory _TbaJob.fromRow(Row row) {
    DateTime? date(String key) {
      final value = row[key] as int?;
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    return _TbaJob(
      row['path'] as String,
      season: row['season'] as int?,
      priority: row['priority'] as int,
      activeFrom: date('active_from'),
      activeUntil: date('active_until'),
    );
  }

  final String path;
  final int? season;
  final int priority;
  final DateTime? activeFrom;
  final DateTime? activeUntil;

  Duration interval(DateTime now) {
    if (path == '/status') return const Duration(hours: 6);
    final active =
        activeFrom != null &&
        activeUntil != null &&
        !now.isBefore(activeFrom!) &&
        !now.isAfter(activeUntil!);
    if (active && priority == 2) return const Duration(minutes: 1);
    if (active) return const Duration(minutes: 30);
    if (priority >= 4) return const Duration(days: 30);
    if (season == null || season! < now.year) return const Duration(days: 7);
    if (priority == 0) return const Duration(minutes: 30);
    return const Duration(hours: 6);
  }
}
