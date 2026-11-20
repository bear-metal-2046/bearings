import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:http/http.dart' as http;

import 'entity_store.dart';

/// Serves Nexus, historical TBA lookups and the legacy competition RPC.
class CompetitionSources {
  CompetitionSources({
    required this.store,
    this.tbaKey,
    this.nexusKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final EntityStore store;
  final String? tbaKey;
  final String? nexusKey;
  final http.Client _client;
  final _cache = <Uri, ({DateTime expires, Object? data})>{};
  final _pending = <Uri, Future<Object?>>{};

  Future<Object?> load(String resource, Json args) {
    String key(String name) {
      final value = args[name];
      if (value is! String || !RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(value)) {
        throw ArgumentError('Invalid competition key: $name');
      }
      return value;
    }

    int year() {
      final value = args['year'];
      if (value is! int || value < 1992 || value > DateTime.now().year + 1) {
        throw ArgumentError('Invalid competition year');
      }
      return value;
    }

    return switch (resource) {
      'events' => _events(year()),
      'teamEvents' => _events(year(), team: key('team')),
      'event' => _byKey('event', key('event')),
      'matches' => _matches(key('event')),
      'match' => _byKey('match', key('match')),
      'teamMatches' => _teamMatches(key('team')),
      'historicalTeamMatches' => _historicalTeamMatches(key('team')),
      'rankings' => _rankings(key('event')),
      'teams' => _teams(key('event')),
      'media' => _media(key('event')),
      'nexus' => _nexusStatus(key('event'), key('nexusEvent')),
      'pitMap' => _pitMap(key('event')),
      _ => throw ArgumentError('Unknown competition resource'),
    };
  }

  T? _entity<T>(String id) {
    final descriptor = store.registry.descriptor<T>();
    final record = store.get(descriptor.type, id);
    return record == null ? null : descriptor.read(record);
  }

  List<T> _rows<T>(List<QueryFilter> filters) {
    final descriptor = store.registry.descriptor<T>();
    return store
        .query(
          QueryDescription(
            type: descriptor.type,
            schemaVersion: descriptor.version,
            filters: filters,
          ),
        )
        .records
        .map(descriptor.read)
        .toList();
  }

  Future<Object?> _events(int year, {String? team}) async {
    if (year < firstMirroredTbaSeason) {
      return _tba(team == null ? '/events/$year' : '/team/$team/events/$year');
    }
    final season = QueryFilter('season', FilterOperator.equal, year);
    final events = _rows<CompetitionEvent>([season]);
    if (team == null) return events.map(_eventJson).toList();
    final ids = _rows<EventTeam>([
      season,
      QueryFilter('team', FilterOperator.equal, team),
    ]).map((row) => row.event.id).toSet();
    return events
        .where((event) => ids.contains(event.id))
        .map(_eventJson)
        .toList();
  }

  Json _eventJson(CompetitionEvent event) {
    final reference = event.district;
    final district = reference == null ? null : _entity<District>(reference.id);
    return {
      ...TbaApi.eventJson(event),
      'district': district == null
          ? null
          : {
              'key': district.id,
              'year': district.season,
              'abbreviation': district.abbreviation,
              'display_name': district.name,
              'official_advancement_counts': {
                'dcmp': district.officialDistrictChampionshipSpots,
                'cmp': district.officialChampionshipSpots,
              },
            },
    };
  }

  Future<Object?> _byKey(String resource, String key) async {
    if (!isMirroredTbaKey(key)) return _tba('/$resource/$key');
    return switch (resource) {
      'event' => switch (_entity<CompetitionEvent>(key)) {
        final event? => _eventJson(event),
        null => null,
      },
      _ => switch (_entity<CompetitionMatch>(key)) {
        final match? => TbaApi.matchJson(match),
        null => null,
      },
    };
  }

  Future<Object?> _matches(String event) async => isMirroredTbaKey(event)
      ? _rows<CompetitionMatch>([
          QueryFilter('event', FilterOperator.equal, event),
          const QueryFilter('practice', FilterOperator.equal, false),
        ]).map(TbaApi.matchJson).toList()
      : _tba('/event/$event/matches');

  Future<Object?> _teams(String event) async {
    if (!isMirroredTbaKey(event)) return _tba('/event/$event/teams');
    return [
      for (final row in _rows<EventTeam>([
        QueryFilter('event', FilterOperator.equal, event),
      ]))
        TbaApi.teamJson(row.profile),
    ];
  }

  Future<Object?> _tba(String path) => _get(
    Uri.https('www.thebluealliance.com', '/api/v3$path'),
    'X-TBA-Auth-Key',
    tbaKey,
    const Duration(seconds: 50),
  );

  Future<Object?> _nexus(String path) => _get(
    Uri.https('frc.nexus', '/api/v1$path'),
    'Nexus-Api-Key',
    nexusKey,
    const Duration(seconds: 12),
  );

  Future<Object?> _get(
    Uri uri,
    String header,
    String? key,
    Duration ttl,
  ) async {
    if (key == null || key.isEmpty) {
      throw const GroveException(
        'unavailable',
        'Competition source is not configured',
      );
    }
    final cached = _cache[uri];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.data;
    }
    return _pending.putIfAbsent(uri, () async {
      try {
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..headers[header] = key;
        final response = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 7));
        if (response.statusCode != 200 && response.statusCode != 404) {
          throw const GroveException(
            'unavailable',
            'Competition source is unavailable',
          );
        }
        final data = response.statusCode == 404
            ? null
            : jsonDecode(response.body);
        if (_cache.length >= 1024) _cache.remove(_cache.keys.first);
        _cache[uri] = (expires: DateTime.now().add(ttl), data: data);
        return data;
      } on TimeoutException {
        throw const GroveException(
          'unavailable',
          'Competition source timed out',
        );
      } on http.ClientException {
        throw const GroveException(
          'unavailable',
          'Competition source is unavailable',
        );
      } on FormatException {
        throw const GroveException(
          'unavailable',
          'Competition source returned invalid data',
        );
      } finally {
        _pending.remove(uri);
      }
    });
  }

  Future<List<Json>> _rankings(String event) async {
    if (isMirroredTbaKey(event)) {
      final rankings = _rows<EventRanking>([
        QueryFilter('event', FilterOperator.equal, event),
      ])..sort((a, b) => a.result.rank.compareTo(b.result.rank));
      return rankings.map(TbaApi.rankingJson).toList();
    }
    final data = await _tba('/event/$event/rankings') as Json?;
    return (data?['rankings'] as List? ?? []).cast<Json>();
  }

  Future<List<Json>> _teamMatches(String team) async => [
    ...await _historicalTeamMatches(team),
    ..._rows<CompetitionMatch>([
      const QueryFilter('practice', FilterOperator.equal, false),
      QueryFilter('teams', FilterOperator.contains, team),
    ]).map(TbaApi.matchJson),
  ];

  Future<List<Json>> _historicalTeamMatches(String team) async {
    final years = (await _tba('/team/$team/years_participated') as List? ?? [])
        .cast<int>()
        .where((year) => year < firstMirroredTbaSeason)
        .toList();
    final results = <Json>[];
    for (var start = 0; start < years.length; start += 8) {
      final batch = await Future.wait(
        years
            .skip(start)
            .take(8)
            .map((year) => _tba('/team/$team/matches/$year')),
      );
      for (final matches in batch) {
        results.addAll((matches as List? ?? []).cast<Json>());
      }
    }
    return results;
  }

  Future<List<Json>> _media(String event) async {
    if (isMirroredTbaKey(event)) {
      return _rows<CompetitionMedia>([
        QueryFilter('event', FilterOperator.equal, event),
        const QueryFilter('rosterMedia', FilterOperator.equal, true),
      ]).map(TbaApi.mediaJson).toList();
    }
    final teams = (await _tba('/event/$event/teams/keys') as List? ?? [])
        .cast<String>();
    if (!RegExp(r'^\d{4}').hasMatch(event)) {
      throw ArgumentError(
        'A season-prefixed event key is required for team media',
      );
    }
    final year = event.substring(0, 4);
    final results = <Json>[];
    for (var start = 0; start < teams.length; start += 8) {
      final batch = await Future.wait(
        teams.skip(start).take(8).map((team) async {
          final media = await _tba('/team/$team/media/$year') as List? ?? [];
          return media.cast<Json>().map(
            (item) => {
              ...item,
              'team_keys': [team],
            },
          );
        }),
      );
      results.addAll(batch.expand((items) => items));
    }
    return results;
  }

  Future<Json?> _nexusStatus(String event, String nexusEvent) async {
    final status = await _nexus('/event/$nexusEvent') as Json?;
    if (status == null) return null;
    final tba = await _byKey('event', event).onError<GroveException>(
      (_, _) => null,
    ) as Json?;
    return {...status, 'playoff_type': tba?['playoff_type']};
  }

  Future<Json?> _pitMap(String event) async {
    final map = await _nexus('/event/$event/map') as Json?;
    if (map == null) return null;
    final addresses = await _nexus('/event/$event/pits');
    return {'event': event, 'map': map, 'addresses': addresses ?? {}};
  }
}
