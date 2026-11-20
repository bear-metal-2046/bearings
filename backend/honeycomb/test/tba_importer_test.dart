import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:honeycomb/src/tba_importer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('starting the importer discovers seasons without a client', () async {
    final store = EntityStore(sqlite3.openInMemory(), bearingsEntityRegistry());
    addTearDown(store.close);
    final published = store.externalChanges.firstWhere(
      (change) => change.dataset == '/events/2026',
    );
    final importer = TbaImporter(
      store: store,
      apiKey: 'test-key',
      now: () => DateTime.utc(2026, 3, 12),
      client: MockClient(
        (request) async => switch (request.url.path) {
          '/api/v3/status' => http.Response(
            '{"max_season":2026,"max_team_page":0}',
            200,
          ),
          '/api/v3/events/2026' => http.Response('[{"key":"2026test"}]', 200),
          _ => http.Response('', 404),
        },
      ),
    );
    addTearDown(importer.close);
    importer.start();
    importer.start();
    final change = await published.timeout(const Duration(seconds: 5));
    expect(change.ids, {'2026test'});
  });

  test(
    'discovers seasons, persists checkpoints and publishes corrections',
    () async {
      final directory = Directory.systemTemp.createTempSync('honeycomb-tba');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/honeycomb.sqlite';
      final registry = bearingsEntityRegistry();
      var now = DateTime.utc(2027, 3, 12);
      var edition = 1;
      var status = 200;
      var maxSeason = 2027;
      final calls = <(String, String?)>[];
      final match = <String, dynamic>{
        'key': '2027test_qm1',
        'event_key': '2027test',
        'alliances': {
          'blue': {
            'team_keys': ['frc2046'],
            'score': 42,
          },
        },
        'score_breakdown': {
          'blue': {'gameSpecificField': true},
        },
      };
      http.Client client() => MockClient((request) async {
        final path = request.url.path.substring('/api/v3'.length);
        final etag = request.headers['if-none-match'];
        expect(request.headers['x-tba-auth-key'], 'test-key');
        calls.add((path, etag));
        if (path == '/event/2027test/matches') {
          if (status != 200) {
            return http.Response('', status, headers: {'retry-after': '120'});
          }
          if (etag == 'matches-$edition') return http.Response('', 304);
          return http.Response(
            jsonEncode([
              if (edition == 1) match,
              if (edition > 1) {...match, 'key': '2027test_qm2'},
            ]),
            200,
            headers: {'etag': 'matches-$edition'},
          );
        }
        final data = switch (path) {
          '/status' => {'max_season': maxSeason, 'max_team_page': 2},
          '/media/tags' => [
            {'code': 'chairmans_video', 'name': "Chairman's Video"},
          ],
          '/events/2026' => [
            {'key': '2026test', 'name': 'Previous season'},
          ],
          '/events/2027' => [
            {
              'key': '2027test',
              'start_date': '2027-03-12',
              'end_date': '2027-03-13',
              'first_event_code': 'TEST',
            },
          ],
          '/events/2028' => [
            {'key': '2028test', 'name': 'New season'},
          ],
          '/teams/2027/0' => <Json>[],
          '/teams/2027/2' => [
            {'key': 'frc2046'},
          ],
          '/event/2027test/teams' => [
            {'key': 'frc2046'},
          ],
          '/event/2027test/matches/practice' => [
            {'key': '2027test_pm1'},
          ],
          '/event/2027test/rankings' => {
            'rankings': [
              {
                'team_key': 'frc2046',
                'rank': 1,
                'record': {'wins': 4, 'losses': 0, 'ties': 1},
              },
            ],
            'sort_order_info': [
              {'name': 'Ranking Score', 'precision': 2},
            ],
          },
          '/event/2027test/awards' => [
            {
              'award_type': 0,
              'name': 'Impact Award',
              'recipient_list': [
                {'team_key': 'frc2046'},
              ],
            },
          ],
          '/event/2027test/alliances' => [
            {
              'name': 'Alliance 1',
              'picks': ['frc2046', 'frc254'],
            },
          ],
          '/event/2027test/teams/statuses' => {
            'frc2046': {'pit_location': 'A1'},
          },
          '/event/2027test/team_media' => [
            {
              'type': 'avatar',
              'team_keys': ['frc2046'],
            },
          ],
          '/districts/2027' => [
            {'key': '2027pnw', 'abbreviation': 'pnw'},
          ],
          '/district/2027pnw/advancement' => {
            'teams': {
              'frc2046': {'dcmp': true},
            },
            'cutoffs': {'cmp_effective': 42},
          },
          '/district/2027pnw/rankings' => [
            {'team_key': 'frc2046', 'rank': 1, 'point_total': 42},
          ],
          '/regional_advancement/2027' => {
            'frc254': {'cmp': true, 'qualifying_event': '2027test'},
          },
          '/team/frc2046/media/2027' => [
            {'type': 'onshape'},
          ],
          '/team/frc2046/media/tag/chairmans_video/2027' => [
            {'type': 'youtube'},
          ],
          '/team/frc2046/robots' => [
            {'year': 2025, 'robot_name': 'Old'},
            {'year': 2027, 'robot_name': 'New'},
          ],
          '/team/frc2046/social_media' => [
            {'type': 'youtube-channel'},
          ],
          _ => null,
        };
        return data == null
            ? http.Response('', 404)
            : http.Response(jsonEncode(data), 200, headers: {'etag': 'first'});
      });

      var store = EntityStore(sqlite3.open(path), registry);
      TbaImporter createImporter() => TbaImporter(
        store: store,
        apiKey: 'test-key',
        client: client(),
        now: () => now,
      );
      var importer = createImporter();
      addTearDown(() async {
        await importer.close();
        await store.close();
      });
      Future<void> drain() async {
        for (var i = 0; i < 120; i++) {
          if (!await importer.syncNext()) return;
        }
        fail('TBA sync queue did not drain');
      }

      T? imported<T>(String id) {
        final descriptor = registry.descriptor<T>();
        final row = store.get(descriptor.type, id);
        return row == null ? null : descriptor.read(row);
      }

      await drain();
      expect(
        calls.any(
          (call) => RegExp(
            r'/insights|/coprs|/oprs|/predictions|/timeseries|/zebra_motionworks',
          ).hasMatch(call.$1),
        ),
        isFalse,
      );
      expect(imported<CompetitionEvent>('2026test')?.name, 'Previous season');
      expect(imported<CompetitionEvent>('2027test')?.firstEventCode, 'TEST');
      final recordedMatch = imported<CompetitionMatch>('2027test_qm1')!;
      expect(recordedMatch.blue?.score, 42);
      expect(recordedMatch.blue?.gameBreakdown, {'gameSpecificField': true});
      expect(imported<CompetitionMatch>('2027test_pm1')?.practice, isTrue);
      expect(imported<TeamSeason>('2027:frc2046')?.team.id, 'frc2046');
      expect(imported<CompetitionTeam>('frc2046')?.number, 2046);
      expect(imported<EventTeam>('2027test:frc2046')?.profile.number, 2046);
      expect(
        imported<EventTeamStatus>('2027test:frc2046')?.pitLocation,
        'A1',
      );
      final ranking = imported<EventRanking>('2027test:frc2046')!;
      expect(ranking.result.record?.wins, 4);
      expect(ranking.sortOrderInfo.single.name, 'Ranking Score');
      expect(
        imported<EventAward>('2027test:0')?.recipients.single.team?.id,
        'frc2046',
      );
      expect(
        imported<PlayoffAlliance>('2027test:1')?.picks.last.id,
        'frc254',
      );
      expect(
        imported<AdvancementRanking>('2027pnw:frc2046')?.totalPoints,
        42,
      );
      expect(
        imported<Advancement>('2027pnw:frc2046')?.districtChampionship,
        isTrue,
      );
      expect(
        imported<AdvancementCutoffs>('2027pnw')?.championshipEffective,
        42,
      );
      expect(
        imported<Advancement>('2027:regional:frc254')?.qualifyingEvent?.id,
        '2027test',
      );
      expect(
        imported<CompetitionMedia>('/team/frc2046/media/2027:onshape:')?.type,
        'onshape',
      );
      expect(
        imported<CompetitionMedia>(
          '/team/frc2046/media/tag/chairmans_video/2027:youtube:',
        )?.tag,
        'chairmans_video',
      );
      expect(imported<TeamRobot>('frc2046:2025'), isNull);
      expect(imported<TeamRobot>('frc2046:2027')?.name, 'New');

      final beforeRestart = store.revision;
      await importer.close();
      await store.close();
      store = EntityStore(sqlite3.open(path), registry);
      importer = createImporter();
      expect(store.revision, beforeRestart);
      expect(await importer.syncNext(), isFalse);

      final server = await serve(
        EntityService(
          store: store,
          bootstrapSubject: 'admin',
          authenticate: (token) async => AuthenticatedActor(
            token,
            expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          ),
        ).handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final grove = Grove(
        registry: registry,
        transport: WebSocketGroveTransport(
          uri: Uri.parse('ws://127.0.0.1:${server.port}'),
          accessToken: () async => 'admin',
        ),
      );
      addTearDown(grove.close);
      final query = grove
          .query<CompetitionMatch>()
          .where(
            CompetitionMatchFields.event.equals(
              const EntityRef<CompetitionEvent>('2027test'),
            ),
          )
          .where(
            CompetitionMatch.participatingTeams.contains(
              const EntityRef<CompetitionTeam>('frc2046'),
            ),
          );
      final snapshots = StreamIterator(grove.watch(query));
      addTearDown(snapshots.cancel);
      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current.items.single.id, '2027test_qm1');

      now = now.add(const Duration(minutes: 1));
      await drain();
      expect(
        calls.where((call) => call == ('/event/2027test/matches', 'matches-1')),
        hasLength(1),
      );
      final unchangedRevision = store.revision;
      final unchanged = store
          .get(competitionMatchEntity.type, '2027test_qm1')!
          .revision;

      status = 429;
      now = now.add(const Duration(minutes: 1));
      await drain();
      expect(await importer.syncNext(), isFalse);
      expect(store.revision, unchangedRevision);
      expect(
        store.get(competitionMatchEntity.type, '2027test_qm1')!.revision,
        unchanged,
      );

      status = 200;
      edition++;
      now = now.add(const Duration(minutes: 2));
      await drain();
      expect(
        await snapshots.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(snapshots.current.items.single.id, '2027test_qm2');
      expect(imported<CompetitionMatch>('2027test_qm1'), isNull);

      maxSeason = 2028;
      now = now.add(const Duration(hours: 6));
      await drain();
      expect(imported<CompetitionEvent>('2028test')?.name, 'New season');
    },
  );
}
