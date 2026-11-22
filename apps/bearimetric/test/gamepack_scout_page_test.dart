import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bearimetric/models/scouting_session.dart';
import 'package:bearimetric/pages/flow/gamepack_scout_page.dart';
import 'package:bearimetric/pages/flow/match_select_page.dart';
import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';

class _StrategySession extends ScoutingSessionNotifier {
  @override
  ScoutingSession build() => ScoutingSession(
    event: const ScoutingEventSelection(
      key: '2026marea',
      name: 'District Championship',
      year: 2026,
    ),
    position: ScoutPosition.redStrat,
    matchNumber: 1,
    scout: Scout(uuid: 'scout-a', name: 'Scout A'),
  );
}

class _OfflineTransport implements GroveTransport {
  @override
  Future<QuerySnapshot> fetch(QueryDescription query) async =>
      throw const GroveOffline();

  @override
  Stream<QuerySnapshot> watch(QueryDescription query) =>
      Stream.error(const GroveOffline());

  @override
  Future<EntityRecord> mutate(EntityMutation mutation) async =>
      throw const GroveOffline();

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
    'regular match selection opens the published 2026 strategy form and advances',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1450);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = bearingsEntityRegistry();
      final grove = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
      );
      const event = '2026marea';
      final release = GamePackRelease(
        id: 'rebuilt-2026',
        document: jsonDecode(
          File('../../gamepacks/2026-rebuilt.json').readAsStringSync(),
        ) as Json,
      );
      await grove.create(release);
      await grove.create(
        const EventGamePack(id: event, release: EntityRef('rebuilt-2026')),
      );
      for (final (number, team) in [(1, 'frc2877'), (2, 'frc133')]) {
        await grove.create(
          CompetitionMatch(
            id: '${event}_qm$number',
            event: const EntityRef(event),
            season: 2026,
            level: 'qm',
            setNumber: 1,
            matchNumber: number,
            practice: false,
            red: CompetitionAlliance(
              teams: [
                EntityRef(team),
                const EntityRef('frc6201'),
                const EntityRef('frc4169'),
              ],
            ),
          ),
        );
      }
      final router = GoRouter(
        initialLocation: '/match-select',
        routes: [
          GoRoute(
            path: '/match-select',
            builder: (_, _) => const MatchSelectPage(),
          ),
          GoRoute(
            path: '/gamepack-match',
            builder: (_, _) => Consumer(
              builder: (context, ref, _) {
                final session = ref.read(scoutingSessionProvider);
                return GamePackScoutPage(
                  event: session.event!.key,
                  position: session.position!,
                  scoutId: session.scout!.uuid,
                  initialMatchNumber: session.matchNumber,
                  onMatchChanged: ref
                      .read(scoutingSessionProvider.notifier)
                      .setMatchNumber,
                );
              },
            ),
          ),
        ],
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bearingsGroveProvider.overrideWithValue(grove),
              scoutingSessionProvider.overrideWith(_StrategySession.new),
              teamNumberForSessionProvider.overrideWithValue(
                const AsyncData(null),
              ),
              permissionCheckerProvider.overrideWithValue(
                const PermissionChecker(
                  permissions: {
                    gamePackReadPermission,
                    gamePackSubmitPermission,
                  },
                ),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();
        expect(find.text('2026 REBUILT'), findsOneWidget);
        expect(find.text('QM1 · Red Strat'), findsOneWidget);
        expect(find.text('Driver Skill'), findsOneWidget);
        expect(find.text('2877'), findsWidgets);
        final save = find.text('Save observation');
        await tester.scrollUntilVisible(
          save,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Observation saved'), findsOneWidget);
        await tester.ensureVisible(find.text('Next match'));
        await tester.tap(find.text('Next match'));
        await tester.pumpAndSettle();
        expect(find.text('QM2 · Red Strat'), findsOneWidget);
        expect(find.text('133'), findsWidgets);
        await grove.synchronize();
        final row = (await grove.query<GamePackObservation>().many()).single;
        expect(row.formId, 'strategy');
        expect(row.station, 6);
        expect(row.scout?.id, 'scout-a');
        expect(row.answers['driver_skill'], ['frc2877', 'frc6201', 'frc4169']);

        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey('practice'),
            overrides: [
              bearingsGroveProvider.overrideWithValue(grove),
              eventsProvider.overrideWithValue(
                const AsyncData([
                  CompetitionEvent(
                    id: event,
                    season: 2026,
                    name: 'District Championship',
                    code: 'marea',
                    location: CompetitionLocation(),
                  ),
                ]),
              ),
            ],
            child: const MaterialApp(
              home: GamePackScoutPage(
                event: trainingEventKey,
                position: ScoutPosition.redStrat,
                initialMatchNumber: 1,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Training'), findsOneWidget);
        expect(find.text('Driver Skill'), findsOneWidget);
        await tester.scrollUntilVisible(
          save,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Practice observation saved'), findsOneWidget);
        expect(await grove.pendingMutationCount, 0);
        expect(await grove.query<GamePackObservation>().many(), hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        unawaited(grove.close());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'restores an offline draft and queues it under the pinned GamePack release',
    (tester) async {
      final registry = bearingsEntityRegistry();
      final cache = MemoryGroveCache();
      final online = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
        cache: cache,
      );
      const event = '2026pilot';
      final pack = GamePackRelease(
        id: 'release',
        document: GamePackDefinition.typed(
          name: 'Qualification scouting',
          fields: const [GamePackField('successes', 'Successful shots')],
          forms: [
            GamePackForm(
              id: 'match',
              label: 'Match scouting',
              kind: GamePackFormKind.match,
              pages: [
                GamePackFormPage.scrolling(
                  id: 'match',
                  label: 'Match',
                  sections: [
                    GamePackSection.controls(
                      id: 'answers',
                      label: 'Answers',
                      controls: [
                        const GamePackControl(
                          field: 'successes',
                          type: GamePackControlType.number,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ).toJson(),
      );
      const match = CompetitionMatch(
        id: '2026pilot_qm4',
        event: EntityRef(event),
        season: 2026,
        level: 'qm',
        setNumber: 1,
        matchNumber: 4,
        practice: false,
        blue: CompetitionAlliance(
          teams: [EntityRef('frc1678'), EntityRef('frc2046')],
        ),
      );
      await tester.runAsync(() async {
        await online.create(pack);
        await online.create(
          const EventGamePack(id: event, release: EntityRef('release')),
        );
        await online.create(match);
        final connected = ProviderContainer(
          overrides: [bearingsGroveProvider.overrideWithValue(online)],
        );
        await waitForValue(connected, eventGamePackProvider(event));
        await waitForValue(connected, competitionMatchesProvider(event));
        connected.dispose();
        await online.close();
      });

      final offline = Grove(
        registry: registry,
        transport: _OfflineTransport(),
        cache: cache,
      );
      Widget collector() => ProviderScope(
        overrides: [bearingsGroveProvider.overrideWithValue(offline)],
        child: const MaterialApp(
          home: GamePackScoutPage(event: event, position: ScoutPosition.blue2),
        ),
      );
      try {
        await tester.pumpWidget(collector());
        await tester.pumpAndSettle();
        expect(find.text('Using the downloaded schedule'), findsOneWidget);
        expect(find.text('QM4 · Team 2046'), findsOneWidget);
        expect(find.text('Successful shots'), findsOneWidget);
        await tester.tap(find.text('Save observation'));
        await tester.pumpAndSettle();
        expect(find.text('Enter a value'), findsOneWidget);
        expect(await offline.pendingMutationCount, 0);
        final input = find.byKey(const ValueKey('successes'));
        await tester.enterText(input, '0');
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(collector());
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(input).controller?.text, '0');
        await tester.tap(find.text('Save observation'));
        await tester.pumpAndSettle();
        expect(find.text('Observation saved'), findsOneWidget);
        expect(await offline.pendingMutationCount, 1);
        final state = await cache.read('pending');
        final queued = (state!['mutations'] as List<dynamic>).single as Json;
        final mutation = EntityMutation.fromJson(queued['mutation'] as Json);
        expect(mutation.kind, MutationKind.create);
        final observation = gamePackObservationEntity.decode(mutation.data!);
        expect(observation.answers, {'successes': 0});
        expect(observation.station, 4);
        expect(observation.match?.id, match.id);
        expect(observation.team?.id, 'frc2046');
        expect(observation.release.id, pack.id);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(offline.close());
        await tester.pump();
      }
    },
  );
}
