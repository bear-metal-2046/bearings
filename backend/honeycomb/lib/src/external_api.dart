import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;

import 'picklists.dart';
import 'security.dart';

class ExternalFailure implements Exception {
  const ExternalFailure(this.status, this.message);
  final int status;
  final String message;
}

Future<dynamic> _fetch(
  String base,
  String endpoint, {
  String? keyHeader,
  String? key,
}) async {
  final response = await http
      .get(
        Uri.parse('$base$endpoint'),
        headers: keyHeader == null || key == null || key.isEmpty
            ? {}
            : {keyHeader: key},
      )
      .timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) {
    throw ExternalFailure(
      response.statusCode == 404 ? 404 : 502,
      'External API error: ' + response.statusCode.toString(),
    );
  }
  try {
    return jsonDecode(response.body);
  } catch (_) {
    throw const ExternalFailure(502, 'Invalid data from external API');
  }
}

Future<dynamic> tba(String endpoint) => _fetch(
  'https://www.thebluealliance.com/api/v3',
  endpoint,
  keyHeader: 'X-TBA-Auth-Key',
  key: Platform.environment['TBA_API_KEY'],
);

Future<dynamic> nexus(String endpoint) => _fetch(
  'https://frc.nexus/api/v1',
  endpoint,
  keyHeader: 'Nexus-Api-Key',
  key: Platform.environment['NEXUS_API_KEY'],
);

Future<dynamic> colors(String endpoint) =>
    _fetch('https://api.frc-colors.com', endpoint);

String? normalizedTeam(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final trimmed = value.trim();
  return RegExp(r'^\d+$').hasMatch(trimmed)
      ? 'frc$trimmed'
      : trimmed.toLowerCase().startsWith('frc')
      ? trimmed.toLowerCase()
      : trimmed;
}

String? eventFromMatch(String? match) => match?.split('_').first;

List<int>? _years(Request request) {
  final raw = request.uri.queryParametersAll['year'];
  if (raw == null) return null;
  final values = raw.map(int.tryParse).toList();
  if (values.any((item) => item == null)) {
    throw const ExternalFailure(400, 'Invalid year parameter');
  }
  return values.whereType<int>().toSet().toList();
}

Future<Response> external(
  Request request,
  Access access,
  String resource,
) async {
  if (!access.has(resource == 'pits' ? 'pits.read' : 'external.read')) {
    return reply({'error': 'Forbidden'}, status: 403);
  }
  try {
    final query = request.uri.queryParameters;
    final team = normalizedTeam(query['team']);
    final match = query['match'];
    final event = query['event'] ?? eventFromMatch(match);
    final years = _years(request);
    switch (resource) {
      case 'matches':
        if (match != null) return reply(await tba('/match/$match'));
        if (team != null && event != null)
          return reply(await tba('/team/$team/event/$event/matches'));
        if (team != null && years != null) {
          return reply(
            _dedupe(
              await Future.wait(
                years.map(
                  (year) async =>
                      await tba('/team/$team/matches/$year') as List,
                ),
              ),
            ),
          );
        }
        if (event != null) return reply(await tba('/event/$event/matches'));
        if (years != null) {
          return reply(
            _dedupe(
              await Future.wait(
                years.map((year) async => await tba('/matches/$year') as List),
              ),
            ),
          );
        }
        return reply({
          'error': 'Provide match, event, team, or year query parameter',
        }, status: 400);
      case 'events':
        final enrich = query['enrich'];
        final shouldEnrich = enrich == null
            ? event != null || team != null || match != null
            : {'true', '1', 'yes', 'y'}.contains(enrich.toLowerCase());
        if (event != null)
          return reply(
            await _mapEvent(await tba('/event/$event'), shouldEnrich),
          );
        List<dynamic> events;
        if (team != null && years != null) {
          events = (await Future.wait(
            years.map(
              (year) async => await tba('/team/$team/events/$year') as List,
            ),
          )).expand((items) => items).toList();
        } else if (team != null) {
          events = await tba('/team/$team/events') as List;
        } else if (years != null) {
          events = (await Future.wait(
            years.map(
              (year) async => await tba('/events/$year') as List,
            ),
          )).expand((items) => items).toList();
        } else {
          return reply({
            'error': 'Provide event, team, year, or match query parameter',
          }, status: 400);
        }
        final mapped = await Future.wait(
          events.map((item) => _mapEvent(item, shouldEnrich)),
        );
        final seen = <dynamic>{};
        return reply(mapped.where((item) => seen.add(item['key'])).toList());
      case 'rankings':
        if (event == null)
          return reply({
            'error': 'Provide an event query parameter',
          }, status: 400);
        final body = await tba('/event/$event/rankings') as Map;
        return reply(
          ((body['rankings'] as List?) ?? []).map((item) {
            final row = item as Map;
            final record = row['record'] as Map? ?? {};
            final stats = row['extra_stats'] as List? ?? [];
            return {
              'teamKey': row['team_key'],
              'rank': row['rank'],
              'rankingPoints': stats.isEmpty ? 0 : stats.first,
              'wins': record['wins'] ?? 0,
              'losses': record['losses'] ?? 0,
              'ties': record['ties'] ?? 0,
              'matchesPlayed': row['matches_played'] ?? 0,
            };
          }).toList(),
        );
      case 'teams':
        List<dynamic> teams;
        if (team != null) {
          teams = [await tba('/team/$team')];
        } else if (match != null) {
          final matchData = await tba('/match/$match') as Map;
          final alliances = matchData['alliances'] as Map? ?? {};
          final keys = <String>{
            ...((alliances['red'] as Map?)?['team_keys'] as List? ?? [])
                .whereType<String>(),
            ...((alliances['blue'] as Map?)?['team_keys'] as List? ?? [])
                .whereType<String>(),
          };
          teams = await Future.wait(keys.map((key) => tba('/team/$key')));
        } else if (event != null) {
          teams = await tba('/event/$event/teams') as List;
        } else if (years != null && years.length == 1) {
          final page = int.tryParse(query['page'] ?? '0');
          if (page == null || page < 0)
            return reply({'error': 'Invalid page parameter'}, status: 400);
          teams =
              await tba('/teams/' + years.first.toString() + '/$page') as List;
        } else {
          return reply({
            'error': 'Provide team, match, event, or year query parameter',
          }, status: 400);
        }
        final mapped = await _enrichTeams(teams);
        return reply(team != null ? mapped.first : mapped);
      case 'pits':
        if (event == null)
          return reply({
            'error': 'Provide event or match query parameter',
          }, status: 400);
        final results = await Future.wait([
          nexus('/event/$event/map'),
          nexus('/event/$event/pits'),
        ]);
        final addresses = results[1] as Map;
        final number = team?.replaceFirst(RegExp(r'^frc'), '');
        if (number != null) {
          final address = addresses[number];
          return reply({
            'event': event,
            'map': results[0],
            'addresses': address == null
                ? <String, dynamic>{}
                : {number: address},
            'address': address,
          });
        }
        return reply({
          'event': event,
          'map': results[0],
          'addresses': addresses,
        });
    }
  } on ExternalFailure catch (error) {
    return reply({'error': error.message}, status: error.status);
  }
  return reply({'error': 'Not found'}, status: 404);
}

List<dynamic> _dedupe(List<List<dynamic>> batches) {
  final seen = <dynamic>{};
  return batches
      .expand((items) => items)
      .where((item) => item is Map && seen.add(item['key']))
      .toList();
}

Future<Map<String, dynamic>> _mapEvent(dynamic raw, bool enrich) async {
  final event = raw as Map;
  Map<dynamic, dynamic>? nexusEvent;
  final firstCode = event['first_event_code'];
  if (enrich && firstCode is String && firstCode.isNotEmpty) {
    try {
      nexusEvent =
          await nexus('/event/' + event['year'].toString() + firstCode) as Map;
    } catch (_) {}
  }
  const fields = {
    'address': 'address',
    'city': 'city',
    'country': 'country',
    'district': 'district',
    'divisionKeys': 'division_keys',
    'endDate': 'end_date',
    'eventCode': 'event_code',
    'eventType': 'event_type',
    'eventTypeString': 'event_type_string',
    'firstEventCode': 'first_event_code',
    'firstEventId': 'first_event_id',
    'gmapsPlaceId': 'gmaps_place_id',
    'gmapsUrl': 'gmaps_url',
    'key': 'key',
    'lat': 'lat',
    'lng': 'lng',
    'locationName': 'location_name',
    'name': 'name',
    'parentEventKey': 'parent_event_key',
    'playoffType': 'playoff_type',
    'playoffTypeString': 'playoff_type_string',
    'postalCode': 'postal_code',
    'shortName': 'short_name',
    'startDate': 'start_date',
    'stateProv': 'state_prov',
    'timezone': 'timezone',
    'webcasts': 'webcasts',
    'website': 'website',
    'week': 'week',
    'year': 'year',
  };
  return {
    for (final entry in fields.entries) entry.key: event[entry.value],
    'announcements': nexusEvent?['announcements'] ?? <dynamic>[],
    'matches': nexusEvent?['matches'] ?? <dynamic>[],
    'nexusDataAsOfTime': nexusEvent?['dataAsOfTime'],
    'nowQueuing': nexusEvent?['nowQueuing'],
    'partsRequests': nexusEvent?['partsRequests'] ?? <dynamic>[],
  };
}

Future<List<Map<String, dynamic>>> _enrichTeams(List<dynamic> teams) async {
  final numbers = teams
      .map((team) => (team as Map)['team_number'])
      .whereType<int>()
      .toList();
  final colorsByNumber = <int, dynamic>{};
  if (numbers.length == 1) {
    final result = await colors('/v1/team/' + numbers.first.toString()) as Map;
    colorsByNumber[numbers.first] = result['colors'];
  } else {
    for (var i = 0; i < numbers.length; i += 100) {
      final slice = numbers.skip(i).take(100);
      final query = slice.map((number) => 'team=$number').join('&');
      final response = await colors('/v1/team?$query') as Map;
      final found = response['teams'] as Map? ?? {};
      for (final number in slice) {
        colorsByNumber[number] = (found[number.toString()] as Map?)?['colors'];
      }
    }
  }
  return teams.map((item) {
    final team = Map<String, dynamic>.from(item as Map);
    team['colors'] = colorsByNumber[team['team_number']];
    return team;
  }).toList();
}

Future<Response> teamMedia(Access access, String path) async {
  if (!access.has('external.read'))
    return reply({'error': 'Forbidden'}, status: 403);
  try {
    return reply(await tba('/$path'));
  } on ExternalFailure catch (error) {
    return reply({'error': error.message}, status: error.status);
  }
}
