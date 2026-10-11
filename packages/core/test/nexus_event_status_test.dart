import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('NexusEventStatus.fromHoneycombEvent', () {
    test('parses the Honeycomb enriched event shape', () {
      final status = NexusEventStatus.fromHoneycombEvent({
        'key': '2026new',
        'nowQueuing': 'Qualification 2',
        'nexusDataAsOfTime': '2026-04-30T18:00:00.000Z',
        'announcements': [
          {'id': 'a1', 'announcement': 'Lunch at noon', 'postedTime': 1},
        ],
        'matches': [
          {
            'label': 'Qualification 2',
            'status': 'Now queuing',
            'redTeams': ['2046', '254', '1678'],
            'blueTeams': ['118', '148', '971'],
            'times': {'estimatedQueueTime': 1777572000000},
          },
        ],
      });

      expect(status.nowQueuing, 'Qualification 2');
      expect(status.announcements, ['Lunch at noon']);
      expect(status.dataAsOfTime, DateTime.utc(2026, 4, 30, 18));
      expect(status.matches.single.status, 'Now queuing');
      expect(
        status.matches.single.times.estimatedQueueTime?.millisecondsSinceEpoch,
        1777572000000,
      );
      expect(status.parseWarnings, isEmpty);
      expect(status.hasData, isTrue);
    });

    test('keeps matches with empty stations and missing status', () {
      final status = NexusEventStatus.fromHoneycombEvent({
        'matches': [
          {
            'label': 'Practice 1',
            'redTeams': ['2046', null, '254'],
            'blueTeams': null,
            'times': {},
          },
        ],
      });

      final match = status.matches.single;
      expect(match.status, isNull);
      expect(match.redTeams, ['2046', null, '254']);
      expect(match.blueTeams, isNull);
      expect(match.isPractice, isTrue);
      expect(status.parseWarnings, isEmpty);
    });

    test('skips one bad match and keeps the rest', () {
      final status = NexusEventStatus.fromHoneycombEvent({
        'matches': [
          {'label': 'Qualification 1', 'status': 'On field'},
          {'status': 'On deck'},
          'not a match',
          {'label': 'Qualification 3', 'status': 'Queuing soon'},
        ],
        'announcements': 'oops',
        'nowQueuing': 7,
      });

      expect(status.matches.map((match) => match.label), [
        'Qualification 1',
        'Qualification 3',
      ]);
      expect(status.parseWarnings, hasLength(4));
    });

    test('handles empty and null Nexus fields', () {
      final status = NexusEventStatus.fromHoneycombEvent({
        'nowQueuing': null,
        'announcements': [],
        'matches': [],
        'nexusDataAsOfTime': null,
      });

      expect(status.hasData, isFalse);
      expect(status.parseWarnings, isEmpty);
    });
  });

  group('NexusMatch.toScoutingMatch', () {
    test('maps teams, key, and predicted time', () {
      final match = NexusMatch.fromJson({
        'label': 'Playoff 4',
        'status': 'On deck',
        'redTeams': ['2046', '254', '1678', '9999'],
        'blueTeams': ['118', null, '971'],
        'times': {'estimatedStartTime': 1777572000000},
      });

      final scoutingMatch = match.toScoutingMatch('2026new')!;
      expect(scoutingMatch.key, '2026new_sf4m1');
      expect(scoutingMatch.compLevel, 'sf');
      expect(scoutingMatch.setNumber, 4);
      expect(scoutingMatch.redAlliance?.teamKeys, [
        'frc2046',
        'frc254',
        'frc1678',
        'frc9999',
      ]);
      expect(scoutingMatch.blueAlliance?.teamKeys, ['frc118', 'frc971']);
      expect(scoutingMatch.predictedTime, 1777572000);
      expect(scoutingMatch.nexus?['status'], 'On deck');
    });

    test('returns null for practice matches', () {
      final match = NexusMatch.fromJson({'label': 'Practice 2'});
      expect(match.toScoutingMatch('2026new'), isNull);
    });
  });
}
