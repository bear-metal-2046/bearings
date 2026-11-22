import 'dart:async';

import 'package:beariscope/pages/gamepacks/gamepacks_page.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';

class _PilotEvent extends CurrentEvent {
  @override
  String build() => '2026pilot';
}

void main() {
  testWidgets('manages library assignments and isolates malformed GamePacks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 4000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const event = '2026pilot';
    final definition = GamePackDefinition.typed(
      name: 'Corrected scoring',
      season: 2026,
      fields: const [GamePackField('count', 'Scouted count')],
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
                  controls: const [
                    GamePackControl(
                      field: 'count',
                      type: GamePackControlType.number,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
      tbaFields: [
        GamePackTbaField(
          id: 'official_points',
          label: 'Official points',
          grain: GamePackGrain.match,
          type: GamePackType.number,
          paths: ['score_breakdown.red.points'],
        ),
      ],
      calculations: [
        GamePackCalculation.recipe(
          id: 'points',
          label: 'Points',
          operation: GamePackRecipe.sum,
          grain: GamePackGrain.event,
          scheduleRows: true,
          inputs: {'value': gamePackFieldRef('official_points')},
        ),
      ],
    );
    final registry = bearingsEntityRegistry();
    final grove = Grove(
      registry: registry,
      transport: MemoryGroveTransport(registry),
    );
    await grove.create(
      const CompetitionEvent(
        id: event,
        season: 2026,
        name: 'Pilot District Event',
        code: 'pilot',
        location: CompetitionLocation(),
      ),
    );
    await grove.create(GamePack(id: 'analysis', document: definition.toJson()));
    await grove.create(
      GamePack(
        id: 'alternate',
        document: {...definition.toJson(), 'name': 'Alternate scoring'},
      ),
    );
    await grove.create(
      GamePack(
        id: 'malformed',
        document: {'name': 'Broken entry', 'unexpectedField': true},
      ),
    );
    await grove.create(
      TbaMatchRevision(
        id: '2026pilot_qm1:17',
        event: const EntityRef(event),
        match: const EntityRef('2026pilot_qm1'),
        observedAt: DateTime.utc(2026, 3),
        sequence: 17,
        payload: {
          'score_breakdown': {
            'red': {'points': 27},
          },
        },
      ),
    );
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentEventProvider.overrideWith(_PilotEvent.new),
            bearingsGroveProvider.overrideWithValue(grove),
            permissionCheckerProvider.overrideWithValue(
              const PermissionChecker(
                permissions: {
                  gamePackReadPermission,
                  gamePackManagePermission,
                  gamePackObservationReadPermission,
                },
              ),
            ),
          ],
          child: const MaterialApp(home: GamePacksPage()),
        ),
      );
      await tester.pumpAndSettle();
      Finder card(String name) => find
          .ancestor(of: find.text(name).first, matching: find.byType(Card))
          .first;

      Future<void> tapCardAction(String name, String action) async {
        final button = find.descendant(
          of: card(name),
          matching: find.text(action),
        );
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> assign(String name, String action) async {
        await tapCardAction(name, action);
        expect(find.text('Assign this GamePack?'), findsOneWidget);
        await tester.tap(find.text('Assign GamePack'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Alternate scoring'), findsOneWidget);
      expect(find.text('Problem GamePack'), findsOneWidget);
      expect(find.text('Corrected scoring'), findsOneWidget);
      expect(find.text('Duplicate'), findsWidgets);

      await assign('Corrected scoring', 'Assign to event');
      expect(
        (await grove.query<EventGamePack>().byId(event).one()).gamePack!.id,
        'analysis',
      );
      ScaffoldMessenger.of(tester.element(find.byType(GamePacksPage)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      final field = find.text('Choose field or calculation');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search questions and metrics'),
        'Points',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Points').hitTestable().last);
      await tester.pumpAndSettle();
      expect(find.text('27'), findsOneWidget);

      await assign('Alternate scoring', 'Replace assignment');
      expect(
        (await grove.query<EventGamePack>().byId(event).one()).gamePack!.id,
        'alternate',
      );
      await tester.tap(
        find.descendant(
          of: card('Problem GamePack'),
          matching: find.byTooltip('Delete GamePack'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete GamePack'));
      await tester.pumpAndSettle();
      expect(find.text('Problem GamePack'), findsNothing);
      expect(
        (await grove.query<GamePack>().result()).items.map((pack) => pack.id),
        unorderedEquals(['analysis', 'alternate']),
      );

      final unassign = find.text('Unassign from event');
      await tester.tap(unassign);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unassign'));
      await tester.pumpAndSettle();
      expect(
        (await grove.query<EventGamePack>().byId(event).one()).gamePack,
        isNull,
      );

      await assign('Alternate scoring', 'Assign to event');
      expect(
        (await grove.query<EventGamePack>().byId(event).one()).gamePack!.id,
        'alternate',
      );
      await grove.create(
        GamePackObservation(
          id: 'saved-observation',
          event: const EntityRef(event),
          gamePack: const EntityRef('alternate'),
          form: 'match',
          capturedAt: DateTime.utc(2026, 3),
          answers: const {'count': 5},
        ),
      );
      expect(
        (await grove.query<GamePackObservation>().result()).items,
        hasLength(1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unassign from event'), findsNothing);
      await tapCardAction('Alternate scoring', 'Edit other sections');
      expect(
        find.textContaining('Forms are locked because an event assigned'),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(grove.close());
      await tester.pump();
    }
  });
}
