// TEMPORARY: Nexus debug tooling. Remove this `debug/` folder, the
// `/nexus_debug` route and `nexusDebugOverrides` in main.dart, and the tile in
// advanced_settings_page.dart once the backend serves real Nexus data.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:services/services.dart';

class NexusFixtureToggle extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool enabled) => state = enabled;
}

final nexusFixtureEnabledProvider = NotifierProvider<NexusFixtureToggle, bool>(
  NexusFixtureToggle.new,
);

/// Serves [nexusFixtureEvent] instead of Honeycomb while the fixture toggle is
/// on. Debug builds only.
final List<Override> nexusDebugOverrides = [
  if (kDebugMode)
    nexusEventStatusProvider.overrideWith((ref, eventKey) {
      if (ref.watch(nexusFixtureEnabledProvider)) {
        return parseNexusEventResponse(eventKey, nexusFixtureEvent(eventKey));
      }
      return fetchNexusEventStatus(ref, eventKey);
    }),
];

/// A Honeycomb `/events?enrich=true` response with the awkward cases Nexus
/// sends: empty practice stations, a 4-team playoff alliance, a replay, and a
/// match with no status.
Map<String, dynamic> nexusFixtureEvent(String eventKey) {
  final now = DateTime.now();
  int at(Duration offset) => now.add(offset).millisecondsSinceEpoch;

  Map<String, dynamic> times(Duration start) => {
    'scheduledStartTime': at(start),
    'estimatedQueueTime': at(start - const Duration(minutes: 20)),
    'estimatedOnDeckTime': at(start - const Duration(minutes: 7)),
    'estimatedOnFieldTime': at(start - const Duration(minutes: 3)),
    'estimatedStartTime': at(start),
    'actualQueueTime': null,
  };

  return {
    'key': eventKey,
    'name': 'Nexus fixture',
    'nexusDataAsOfTime': now.toUtc().toIso8601String(),
    'nowQueuing': 'Qualification 12',
    'announcements': [
      {
        'id': 'fixture-1',
        'announcement': 'Fixture data: not from FRC Nexus.',
        'postedTime': at(const Duration(minutes: -5)),
      },
    ],
    'partsRequests': [],
    'matches': [
      {
        'label': 'Practice 3',
        'status': 'On field',
        'redTeams': ['2046', null, null],
        'blueTeams': [null, null, null],
        'times': times(const Duration(minutes: -30)),
      },
      {
        'label': 'Qualification 11',
        'status': 'On field',
        'redTeams': ['2046', '254', '1678'],
        'blueTeams': ['4414', '1323', '971'],
        'times': times(const Duration(minutes: 1)),
      },
      {
        'label': 'Qualification 12',
        'status': 'On deck',
        'redTeams': ['2910', '1690', '6328'],
        'blueTeams': ['2046', '3476', '604'],
        'times': times(const Duration(minutes: 8)),
      },
      {
        'label': 'Qualification 12 Replay',
        'status': 'Now queuing',
        'redTeams': ['2910', '1690', '6328'],
        'blueTeams': ['2046', '3476', '604'],
        'times': times(const Duration(minutes: 15)),
        'replayOf': 'Qualification 12',
      },
      {
        'label': 'Qualification 13',
        'redTeams': ['2046', '5940', '1072'],
        'blueTeams': ['118', '148', '2056'],
        'times': {'scheduledStartTime': at(const Duration(minutes: 22))},
      },
      {
        'label': 'Playoff 1',
        'status': 'Queuing soon',
        'redTeams': ['2046', '254', '1678', '4414'],
        'blueTeams': ['1323', '971', '2910', '1690'],
        'times': times(const Duration(minutes: 60)),
        'breakAfter': 'Field reset',
      },
      {
        'label': 'Final 1',
        'redTeams': ['2046', '254', '1678'],
        'blueTeams': null,
        'times': {'scheduledStartTime': at(const Duration(hours: 3))},
      },
    ],
  };
}
