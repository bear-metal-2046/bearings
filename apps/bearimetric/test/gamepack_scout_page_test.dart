import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bearimetric/models/scouting_session.dart';
import 'package:bearimetric/data/scouting_store.dart';
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
    matchId: '2026marea_qm1',
    scout: Scout(uuid: 'scout-a', name: 'Scout A'),
  );
}

class _OfflineTransport implements GroveConnectionTransport {
  @override
  GroveConnectionState get connectionState => GroveConnectionState.disconnected;

  @override
  Stream<GroveConnectionState> watchConnection() => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  void checkConnection() {}

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
    'regular match selection opens the assigned 2026 strategy form and advances',
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
      final store = ScoutingStore(
        grove,
        box: null,
        endpoint: 'test',
        subject: Future.value('tablet'),
      );
      const event = '2026marea';
      final release = GamePack(
        id: 'rebuilt-2026',
        document: jsonDecode(
          File('../../gamepacks/2026-rebuilt.json').readAsStringSync(),
        ) as Json,
      );
      await grove.create(release);
      await grove.create(
        const EventGamePack(id: event, gamePack: EntityRef('rebuilt-2026')),
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
      await grove.create(
        const CompetitionMatch(
          id: '${event}_sf2m1',
          event: EntityRef(event),
          season: 2026,
          level: 'sf',
          setNumber: 2,
          matchNumber: 1,
          practice: false,
          red: CompetitionAlliance(
            teams: [
              EntityRef('frc133'),
              EntityRef('frc6201'),
              EntityRef('frc4169'),
            ],
          ),
        ),
      );
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
                  initialMatchId: session.matchId!,
                  onMatchSelected: ref
                      .read(scoutingSessionProvider.notifier)
                      .selectMatch,
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
              scoutingStoreProvider.overrideWithValue(store),
              scoutingSessionProvider.overrideWith(_StrategySession.new),
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
        tester.widget<Slider>(find.byType(Slider)).onChanged!(2);
        await tester.pumpAndSettle();
        expect(find.text('Semifinal 2 · Match 1'), findsOneWidget);
        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();
        expect(find.text('Semifinal 2 · Match 1 · Red Strat'), findsOneWidget);
        router.go('/match-select');
        await tester.pumpAndSettle();
        tester.widget<Slider>(find.byType(Slider)).onChanged!(0);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();
        expect(find.text('Match 1 · Red Strat'), findsOneWidget);
        expect(find.text('Driver Skill'), findsOneWidget);
        expect(find.text('2877'), findsWidgets);
        await tester.tap(find.byTooltip('Next Match'));
        await tester.pumpAndSettle();
        expect(find.text('Match 2 · Red Strat'), findsOneWidget);
        expect(await grove.pendingMutationCount, 0);
        await tester.tap(find.byTooltip('Previous Match'));
        await tester.pumpAndSettle();
        tester
            .widget<ReorderableListView>(find.byType(ReorderableListView).first)
            .onReorderItem!(0, 1);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next Match'));
        await tester.pumpAndSettle();
        expect(find.text('Match 2 · Red Strat'), findsOneWidget);
        expect(find.text('133'), findsWidgets);
        await grove.synchronize();
        final row = (await grove.query<GamePackObservation>().many()).single;
        expect(row.formId, 'strategy');
        expect(row.station, 6);
        expect(row.scout?.id, 'scout-a');
        expect(row.answers['driver_skill'], ['frc6201', 'frc2877', 'frc4169']);

        await grove.create(
          GamePack(
            id: 'practice-pack',
            document: {...release.document as Json, 'name': 'Practice scoring'},
          ),
        );
        await grove.create(
          const EventGamePack(
            id: practiceGamePackKey,
            gamePack: EntityRef('practice-pack'),
            practiceEvent: EntityRef(event),
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey('practice'),
            overrides: [
              bearingsGroveProvider.overrideWithValue(grove),
              scoutingStoreProvider.overrideWithValue(store),
              eventsProvider.overrideWithValue(
                const AsyncData([
                  CompetitionEvent(
                    id: '2026other',
                    season: 2026,
                    name: 'Other event',
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
                initialMatchId: '2026marea_qm1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Practice submissions stay on this device.'),
          findsOneWidget,
        );
        expect(find.text('Driver Skill'), findsOneWidget);
        await tester.tap(find.byTooltip('Next Match'));
        await tester.pumpAndSettle();
        expect(find.text('Match 2 · Red Strat'), findsOneWidget);
        await tester.tap(find.byTooltip('Previous Match'));
        await tester.pumpAndSettle();
        expect(find.text('Match 1 · Red Strat'), findsOneWidget);
        expect(find.text('Practice observation saved'), findsNothing);
        expect(await grove.pendingMutationCount, 0);
        expect(await grove.query<GamePackObservation>().many(), hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        store.close();
        unawaited(grove.close());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'restores and coalesces offline answers for the assigned GamePack',
    (tester) async {
      final registry = bearingsEntityRegistry();
      final cache = MemoryGroveCache();
      final online = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
        cache: cache,
      );
      const event = '2026pilot';
      final pack = GamePack(
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
          const EventGamePack(id: event, gamePack: EntityRef('release')),
        );
        await online.create(match);
        await online.create(
          CompetitionMatch(
            id: '${event}_qm3',
            event: match.event,
            season: match.season,
            level: match.level,
            setNumber: match.setNumber,
            matchNumber: 3,
            practice: false,
            blue: match.blue,
          ),
        );
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
      final store = ScoutingStore(
        offline,
        box: null,
        endpoint: 'test',
        subject: Future.value('tablet'),
      );
      Widget collector() => ProviderScope(
        overrides: [
          bearingsGroveProvider.overrideWithValue(offline),
          scoutingStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          home: GamePackScoutPage(
            event: event,
            position: ScoutPosition.blue2,
            initialMatchId: '2026pilot_qm4',
          ),
        ),
      );
      try {
        await tester.pumpWidget(collector());
        await tester.pumpAndSettle();
        expect(find.text('Using the downloaded schedule'), findsOneWidget);
        expect(find.text('Match 4 · Blue 2 · Team 2046'), findsOneWidget);
        expect(find.text('Successful shots'), findsOneWidget);
        expect(find.text('Save observation'), findsNothing);
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
        expect(find.text('Observation saved'), findsNothing);
        expect(await offline.pendingMutationCount, 0);
        final record = (await store.records()).single;
        final subject = record['subject'] as Json;
        expect(record['ready'], {'successes': 0});
        expect(subject['station'], 4);
        expect(subject['match'], match.id);
        expect(subject['team'], 'frc2046');
        expect(subject['gamePack'], pack.id);
        await tester.enterText(input, '1');
        await tester.pumpAndSettle();
        await tester.enterText(input, '0');
        await tester.pumpAndSettle();
        expect(find.text('Save observation'), findsNothing);
        expect((await store.records()).single['ready'], {'successes': 0});

        await tester.enterText(input, '2');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save observation'));
        await tester.pumpAndSettle();
        expect((await store.records()).single['ready'], {'successes': 2});
        await tester.enterText(input, '');
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Select match'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Match 3 · Team 2046'));
        await tester.pumpAndSettle();
        expect(find.text('Match 3 · Blue 2 · Team 2046'), findsOneWidget);
        expect(await offline.pendingMutationCount, 0);
        expect(isScoutingDraft((await store.records()).single), isTrue);
        await tester.tap(find.byTooltip('Select match'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Match 4 · Team 2046 · Draft'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(input).controller?.text, isEmpty);
        await tester.tap(find.byTooltip('Scouting uploads'));
        await tester.pumpAndSettle();
        expect(find.text('QM4 · Blue 2'), findsOneWidget);
        expect(find.text('$event · Draft'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      } finally {
        store.close();
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(offline.close());
        await tester.pump();
      }
    },
  );
}
