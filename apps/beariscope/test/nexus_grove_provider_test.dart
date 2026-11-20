import 'dart:async';

import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/pits_scouting_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/nexus_provider.dart';
import 'package:services/providers/up_next_feed_provider.dart';

class _Event extends CurrentEvent {
  @override
  String build() => '2026test';
}

void main() {
  test(
    'typed competition queries keep each event roster and schedule separate',
    () async {
      final registry = bearingsEntityRegistry();
      final grove = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
      );
      addTearDown(grove.close);
      for (final (event, number) in [('2026one', 2046), ('2026two', 254)]) {
        final team = CompetitionTeam(
          id: 'frc$number',
          number: number,
          location: const CompetitionLocation(),
        );
        await grove.create(
          EventTeam(
            id: '${event}_${team.id}',
            season: 2026,
            event: EntityRef(event),
            team: EntityRef(team.id),
            profile: team,
          ),
        );
        await grove.create(
          TbaApi.match({'key': '${event}_qm1', 'event_key': event}),
        );
      }
      final container = ProviderContainer(
        overrides: [bearingsGroveProvider.overrideWithValue(grove)],
      );
      addTearDown(container.dispose);
      for (final (event, number) in [('2026two', 254), ('2026one', 2046)]) {
        final roster = await waitForValue(
          container,
          competitionTeamsProvider(event),
        );
        final schedule = await waitForValue(
          container,
          competitionMatchesProvider(event),
        );
        expect(roster.requireComplete().items.single.number, number);
        expect(schedule.requireComplete().items.single.event.id, event);
      }
    },
  );

  test('Up Next and pit map react to direct Nexus Grove entities', () async {
    final registry = bearingsEntityRegistry();
    final grove = Grove(
      registry: registry,
      transport: MemoryGroveTransport(registry),
    );
    addTearDown(grove.close);
    await grove.create(
      TbaApi.event({
        'key': '2026test',
        'first_event_code': 'OFFICIAL',
        'playoff_type': 10,
      }),
    );
    await grove.create(
      const CompetitionMatch(
        id: '2026test_qm1',
        season: 2026,
        event: EntityRef('2026test'),
        level: 'qm',
        setNumber: 1,
        matchNumber: 1,
        practice: false,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        bearingsGroveProvider.overrideWithValue(grove),
        currentEventProvider.overrideWith(_Event.new),
      ],
    );
    addTearDown(container.dispose);
    final status = nexusEventStatusProvider('2026test');
    final feed = upNextFeedProvider('2026test');
    final schedule = await waitForValue(container, feed);
    expect(schedule.source, UpNextSource.schedule);
    expect(schedule.doubleElimination, isTrue);
    expect(schedule.matches.single.schedule?.id, '2026test_qm1');
    final liveFeed = Completer<UpNextFeed>();
    final feedSubscription = container.listen(feed, (previous, next) {
      if (previous?.hasValue == true) expect(next.isLoading, isFalse);
      if (next.value case final value?
          when value.source == UpNextSource.nexus) {
        if (!liveFeed.isCompleted) liveFeed.complete(value);
      }
    });
    addTearDown(feedSubscription.close);
    final queueUpdated = Completer<EventStatusSnapshot>();
    final pitUpdated = Completer<String>();
    container.listen(status, (_, next) {
      if (next.value case NexusAvailable(:final status)) {
        if (!queueUpdated.isCompleted) queueUpdated.complete(status);
      }
    });
    container.listen(pitsMapProvider, (_, next) {
      final pit = next.asData?.value?.items.singleOrNull?.pits['A1'];
      if (pit?.team case final team?) {
        if (!pitUpdated.isCompleted) pitUpdated.complete(team.id);
      }
    });
    expect(await waitForValue(container, status), isA<NexusEmpty>());
    expect((await waitForValue(container, pitsMapProvider))?.items, isEmpty);

    final estimatedQueueTime = DateTime.utc(2026, 3, 14, 22);
    await grove.create(
      EventStatusSnapshot(
        id: '2026official',
        dataAsOfTime: DateTime.now(),
        nowQueuing: 'Qualification 1',
        matches: [
          const QueueMatch(label: 'Qualification 1', status: 'On field'),
          QueueMatch(
            label: 'Qualification 1 Replay',
            status: 'Now queuing',
            redTeams: ['2046', null, 'frc254'],
            times: QueueMatchTimes(estimatedQueueTime: estimatedQueueTime),
            replayOf: 'Qualification 1',
          ),
        ],
      ),
    );
    await grove.create(
      const PitLayout(
        id: '2026official',
        map: PitMapBackground(size: PitMapPoint(x: 100, y: 100)),
        pits: {'A1': Pit(team: EntityRef('frc2046'))},
      ),
    );
    final queue = await queueUpdated.future.timeout(const Duration(seconds: 3));
    expect(queue.nowQueuing, 'Qualification 1');
    expect(queue.id, '2026official');
    final live = await liveFeed.future.timeout(const Duration(seconds: 3));
    expect(live.doubleElimination, isTrue);
    final replay = live.matches.single;
    expect(replay.key, '2026test_qm1');
    expect(replay.redTeamKeys, ['frc2046', 'frc254']);
    expect(replay.nexus?.replayOf, 'Qualification 1');
    expect(replay.nexus?.times.estimatedQueueTime, estimatedQueueTime);

    final fallback = Completer<UpNextFeed>();
    final fallbackSubscription = container.listen(feed, (_, next) {
      if (next.value case final value?
          when value.source == UpNextSource.schedule && !fallback.isCompleted) {
        fallback.complete(value);
      }
    });
    addTearDown(fallbackSubscription.close);
    await grove.update<EventStatusSnapshot>(
      '2026official',
      (snapshot) => EventStatusSnapshot(
        id: snapshot.id,
        dataAsOfTime: DateTime.now().subtract(const Duration(minutes: 3)),
        matches: snapshot.matches,
      ),
    );
    final stale = await fallback.future.timeout(const Duration(seconds: 3));
    expect(stale.matches.single.schedule?.id, '2026test_qm1');
    expect(stale.doubleElimination, isTrue);
    expect(stale.nexusProblem, 'Nexus event status is stale');

    expect(
      await pitUpdated.future.timeout(const Duration(seconds: 3)),
      'frc2046',
    );
  });
}
