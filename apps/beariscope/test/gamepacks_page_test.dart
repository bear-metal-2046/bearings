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
import 'package:ui/ui.dart';

class _PilotEvent extends CurrentEvent {
  @override
  String build() => '2026pilot';
}

void main() {
  testWidgets(
    'selects a typed analysis release and inspects its archived source',
    (tester) async {
      const event = '2026pilot';
      const fields = [GamePackField('count', 'Scouted count')];
      final definition = GamePackDefinition.typed(
        name: 'Corrected scoring',
        fields: fields,
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
      await grove.create(
        GamePackRelease(
          id: 'capture',
          document: {...definition.toJson(), 'name': 'Collection'},
        ),
      );
      await grove.create(
        GamePackRelease(id: 'analysis', document: definition.toJson()),
      );
      await grove.create(
        const EventGamePack(id: event, release: EntityRef('capture')),
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
                    gamePackPublishPermission,
                    gamePackObservationReadPermission,
                  },
                ),
              ),
            ],
            child: const MaterialApp(home: GamePacksPage()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Change event'));
        await tester.pumpAndSettle();
        final search = find.widgetWithText(TextField, 'Find an event');
        await tester.enterText(search, 'pilot');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pilot District Event').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BearingsSelect<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Corrected scoring · analysis').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use for analysis'));
        await tester.pumpAndSettle();
        final binding = await grove.query<EventGamePack>().byId(event).one();
        expect(binding.release.id, 'capture');
        expect(binding.effectiveAnalysisRelease.id, 'analysis');
        final field = find.text('Choose field or calculation');
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
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
        final trace = find.text('Contributing records (1)').hitTestable();
        await tester.scrollUntilVisible(
          trace,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(trace);
        await tester.pumpAndSettle();
        expect(find.text('2026pilot_qm1:17'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(grove.close());
        await tester.pump();
      }
    },
  );
}
