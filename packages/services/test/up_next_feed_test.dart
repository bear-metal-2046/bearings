import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services/services.dart';

void main() {
  const eventKey = '2026new';

  final schedule = [
    {
      'key': '2026new_qm1',
      'event_key': eventKey,
      'comp_level': 'qm',
      'match_number': 1,
      'set_number': 1,
      'alliances': {
        'red': {
          'team_keys': ['frc2046', 'frc254', 'frc1678'],
        },
        'blue': {
          'team_keys': ['frc118', 'frc148', 'frc971'],
        },
      },
    },
    {'key': '2026cur_qm1', 'event_key': '2026cur', 'comp_level': 'qm'},
  ];

  NexusAvailable nexusWith(List<Map<String, dynamic>> matches) {
    return NexusAvailable(
      NexusEventStatus.fromHoneycombEvent({
        'nowQueuing': 'Qualification 2',
        'matches': matches,
      }),
    );
  }

  group('selectUpNextFeed', () {
    test('uses Nexus when it has qualification or playoff matches', () {
      final feed = selectUpNextFeed(
        eventKey: eventKey,
        nexus: nexusWith([
          {'label': 'Practice 1', 'status': 'On field'},
          {'label': 'Qualification 1', 'status': 'On field'},
          {'label': 'Qualification 2', 'status': 'Now queuing'},
          {'label': 'Qualification 1 Replay', 'status': 'On deck'},
          {'label': 'Playoff 1', 'status': 'Queuing soon'},
        ]),
        schedule: schedule,
      );

      expect(feed.source, UpNextSource.nexus);
      expect(feed.nexusProblem, isNull);
      expect(feed.nexus?.nowQueuing, 'Qualification 2');
      expect(feed.matches.map((match) => match.key), [
        '2026new_qm1',
        '2026new_qm2',
        '2026new_sf1m1',
      ]);
      expect(feed.matches.first.nexus?['status'], 'On deck');
    });

    test('falls back to the schedule when Nexus only has practice', () {
      final nexus = nexusWith([
        {'label': 'Practice 1', 'status': 'Now queuing'},
      ]);
      expect(needsScheduleFallback(eventKey, nexus), isTrue);

      final feed = selectUpNextFeed(
        eventKey: eventKey,
        nexus: nexus,
        schedule: schedule,
      );

      expect(feed.source, UpNextSource.schedule);
      expect(feed.matches.map((match) => match.key), ['2026new_qm1']);
      expect(feed.nexus?.nowQueuing, 'Qualification 2');
      expect(feed.nexusProblem, isNotNull);
    });

    test('falls back to the schedule when Nexus is empty', () {
      final feed = selectUpNextFeed(
        eventKey: eventKey,
        nexus: const NexusEmpty(),
        schedule: schedule,
      );

      expect(feed.source, UpNextSource.schedule);
      expect(feed.matches, hasLength(1));
      expect(feed.nexusProblem, const NexusEmpty().problem);
    });

    test('falls back to the schedule and keeps the error on failure', () {
      const failure = NexusFailed('HTTP 403', statusCode: 403);
      final feed = selectUpNextFeed(
        eventKey: eventKey,
        nexus: failure,
        schedule: schedule,
      );

      expect(feed.source, UpNextSource.schedule);
      expect(feed.nexus, isNull);
      expect(feed.nexusProblem, 'HTTP 403');
    });
  });

  group('withoutPlayedMatches', () {
    List<String> upNextKeys(List<Map<String, dynamic>> nexusMatches) {
      return selectUpNextFeed(
        eventKey: eventKey,
        nexus: nexusWith(nexusMatches),
      ).matches.map((match) => match.key).toList();
    }

    test('hides matches before the latest one on field', () {
      expect(
        upNextKeys([
          {'label': 'Qualification 1', 'status': 'On field'},
          {
            'label': 'Qualification 2',
            'status': 'On field',
            'times': {'actualOnFieldTime': 1791749519762},
          },
          {'label': 'Qualification 3', 'status': 'On deck'},
          {'label': 'Qualification 4', 'status': 'Now queuing'},
          {'label': 'Qualification 5'},
        ]),
        ['2026new_qm2', '2026new_qm3', '2026new_qm4', '2026new_qm5'],
      );
    });

    test('keeps everything before any match goes on field', () {
      expect(
        upNextKeys([
          {'label': 'Practice 9', 'status': 'On field'},
          {'label': 'Qualification 1', 'status': 'Now queuing'},
          {'label': 'Qualification 2', 'status': 'Queuing soon'},
        ]),
        ['2026new_qm1', '2026new_qm2'],
      );
    });

    test('keeps a late replay that is still to come', () {
      expect(
        upNextKeys([
          {'label': 'Qualification 12', 'status': 'On field'},
          {'label': 'Qualification 13', 'status': 'On field'},
          {'label': 'Qualification 12 Replay', 'status': 'On deck'},
          {'label': 'Qualification 14', 'status': 'Queuing soon'},
        ]),
        ['2026new_qm13', '2026new_qm12', '2026new_qm14'],
      );
    });

    test('hides scheduled matches that have a TBA result', () {
      final feed = selectUpNextFeed(
        eventKey: eventKey,
        nexus: const NexusEmpty(),
        schedule: [
          {
            'key': '2026new_qm1',
            'event_key': eventKey,
            'comp_level': 'qm',
            'match_number': 1,
            'actual_time': 1791749519,
            'alliances': {
              'red': {'score': 40},
              'blue': {'score': 32},
            },
          },
          {
            'key': '2026new_qm2',
            'event_key': eventKey,
            'comp_level': 'qm',
            'match_number': 2,
            'alliances': {
              'red': {'score': -1},
              'blue': {'score': -1},
            },
          },
          {
            'key': '2026new_qm3',
            'event_key': eventKey,
            'comp_level': 'qm',
            'match_number': 3,
          },
        ],
      );

      expect(feed.matches.map((match) => match.key), [
        '2026new_qm2',
        '2026new_qm3',
      ]);
    });
  });

  group('parseNexusEventResponse', () {
    test('picks the matching event from a list response', () {
      final result = parseNexusEventResponse(eventKey, [
        {'key': '2026cur', 'nowQueuing': 'Qualification 9'},
        {'key': eventKey, 'nowQueuing': 'Qualification 3'},
      ]);

      expect(result, isA<NexusAvailable>());
      expect((result as NexusAvailable).status.nowQueuing, 'Qualification 3');
    });

    test('reports an empty Nexus snapshot', () {
      final result = parseNexusEventResponse(eventKey, {
        'key': eventKey,
        'nowQueuing': null,
        'matches': [],
        'announcements': [],
      });

      expect(result, isA<NexusEmpty>());
    });

    test('reports a response without the event', () {
      expect(parseNexusEventResponse(eventKey, null), isA<NexusFailed>());
      expect(parseNexusEventResponse(eventKey, []), isA<NexusFailed>());
    });
  });
}
