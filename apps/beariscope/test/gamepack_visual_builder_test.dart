import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:bearimetric/data/scouting_store.dart';
import 'package:bearimetric/pages/flow/gamepack_scout_page.dart';
import 'package:beariscope/pages/export/gamepack_export.dart';
import 'package:beariscope/pages/gamepacks/builder/design.dart';
import 'package:beariscope/pages/gamepacks/builder/fixture_editor.dart';
import 'package:beariscope/pages/gamepacks/builder/form_editor.dart';
import 'package:beariscope/pages/gamepacks/builder/form_grid.dart';
import 'package:beariscope/pages/gamepacks/builder/workspace_dock.dart';
import 'package:beariscope/pages/gamepacks/builder/workspace_page.dart';
import 'package:beariscope/pages/gamepacks/gamepacks_page.dart';
import 'package:beariscope/pages/picklists/picklist_team_quick_view_sheet.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/widgets/team_card.dart';
import 'package:core/core.dart';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:ui/ui.dart';
import 'package:ui/widgets/forms/gamepack_form_view.dart';

class _NextSeasonEvent extends CurrentEvent {
  @override
  String build() => '2027demo';
}

Finder _formAction<T extends Widget>(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is T),
);

Future<void> _selectSidebar(
  WidgetTester tester,
  GamePackDockTab tab, {
  String? choice,
}) async {
  final sidebar = find.byType(GamePackWorkspaceSidebar);
  Future<void> tap(String label) async {
    final target = find.descendant(of: sidebar, matching: find.text(label));
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  if (choice == null ||
      tester.widget<GamePackWorkspaceSidebar>(sidebar).expanded != tab) {
    await tap(tab.label);
  }
  if (choice != null) await tap(choice);
}

Future<void> _selectMetricView(WidgetTester tester, String view) async {
  await tester.tap(find.byTooltip('Switch metrics view').hitTestable());
  await tester.pumpAndSettle();
  await tester.tap(find.text(view).hitTestable().last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('moves scrolling questions across sections and shared rows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final formSelection = ValueNotifier<String?>('pit');
    addTearDown(formSelection.dispose);
    GamePackControl question(String id) =>
        GamePackControl(field: id, type: GamePackControlType.number);

    const labels = {
      'drive': 'Drive type',
      'hopper': 'Hopper size',
      'climb': 'Climb height',
      'balance': 'Balance time',
      'repair': 'Repair time',
    };
    var design = GamePackDesign(
      fields: [
        for (final entry in labels.entries)
          GamePackField(entry.key, entry.value),
      ],
      forms: [
        GamePackForm(
          id: 'pit',
          label: 'Pit scouting',
          kind: GamePackFormKind.pit,
          pages: [
            GamePackFormPage.scrolling(
              id: 'checks',
              label: 'Checks',
              sections: [
                GamePackSection(
                  id: 'robot',
                  label: 'Robot',
                  items: [
                    GamePackListItem.control(question('drive')),
                    GamePackListItem.row([question('hopper')]),
                  ],
                ),
                GamePackSection(
                  id: 'endgame',
                  label: 'Endgame',
                  items: [
                    GamePackListItem.row([
                      question('climb'),
                      question('balance'),
                    ]),
                    GamePackListItem.control(question('repair')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => GamePackFormsEditor(
              design: design,
              onChanged: (next) => setState(() => design = next),
              compact: false,
              formSelection: formSelection,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder gap(String target, int item, [int? control]) =>
        find.byKey(ValueKey(('form-list-gap', target, item, control)));
    final landing = find.byKey(const ValueKey('form-list-landing-card'));

    Future<void> drag(
      String label,
      Finder destination, {
      bool mouse = false,
      bool animate = false,
      bool cancel = false,
      bool instant = false,
      Finder? rowTarget,
    }) async {
      final stationary = find.text('Endgame');
      final originalHeading = tester.getRect(stationary);
      final originalGap = tester.getRect(destination);
      final source = mouse ? find.text(label) : find.byTooltip('Drag $label');
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
      );
      if (mouse) await gesture.moveBy(const Offset(16, 0));
      await tester.pump(
        mouse ? Duration.zero : const Duration(milliseconds: 260),
      );
      expect(originalGap.height, 4);
      expect(tester.getRect(destination), originalGap);
      expect(tester.getRect(stationary), originalHeading);
      await gesture.moveTo(tester.getCenter(rowTarget ?? destination));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      if (animate) {
        final marker = find.descendant(
          of: destination,
          matching: find.byType(AnimatedContainer),
        );
        final indicator = tester.widget<AnimatedContainer>(marker);
        expect(tester.getSize(marker).height, 2);
        expect(
          (indicator.decoration as BoxDecoration).color,
          isNot(Colors.transparent),
        );
      }
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      if (animate) {
        await tester.pump();
        expect(landing, findsOneWidget);
        final start = tester.getRect(landing);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getRect(landing), isNot(start));
      }
      if (instant) {
        await tester.pump();
        expect(landing, findsNothing);
      }
      await tester.pumpAndSettle();
      expect(landing, findsNothing);
    }

    List<List<String>> items(String section) => design.forms
        .firstWhere((form) => form.id == 'pit')
        .pages
        .single
        .sections
        .firstWhere((item) => item.id == section)
        .items
        .map((item) => item.controls.map((control) => control.field).toList())
        .toList();

    final header = find.text('Pit scouting');
    final page = find.byTooltip('Switch page');
    final content = tester.getRect(find.byType(SingleChildScrollView));
    expect(content.width, closeTo(712, 1));
    expect(content.center.dx, closeTo(640, 1));
    expect(tester.getRect(header).left, closeTo(24, 1));
    expect(
      tester.getRect(_formAction<OutlinedButton>('Preview')).right,
      closeTo(1256, 1),
    );
    expect(tester.getCenter(header).dy, closeTo(tester.getCenter(page).dy, 1));

    await drag(
      'Drive type',
      gap('endgame', 0, 1),
      rowTarget: find.text('Balance time'),
      animate: true,
      cancel: true,
    );
    expect(items('robot'), [
      ['drive'],
      ['hopper'],
    ]);
    await drag(
      'Drive type',
      gap('endgame', 0, 1),
      rowTarget: find.text('Balance time'),
      animate: true,
    );
    expect(items('robot'), [
      ['hopper'],
    ]);
    expect(items('endgame'), [
      ['climb', 'drive', 'balance'],
      ['repair'],
    ]);

    await drag('Balance time', gap('endgame', 0, 0), mouse: true);
    expect(items('endgame'), [
      ['balance', 'climb', 'drive'],
      ['repair'],
    ]);

    await drag('Hopper size', gap('endgame', 2));
    expect(items('robot'), isEmpty);
    expect(items('endgame'), [
      ['balance', 'climb', 'drive'],
      ['repair'],
      ['hopper'],
    ]);

    await drag('Climb height', gap('robot', 0));
    expect(items('robot'), [
      ['climb'],
    ]);
    expect(items('endgame'), [
      ['balance', 'drive'],
      ['repair'],
      ['hopper'],
    ]);
    await drag('Repair time', gap('endgame', 0, 1));
    await drag('Hopper size', gap('endgame', 0, 0));
    expect(items('endgame'), [
      ['hopper', 'balance', 'repair', 'drive'],
    ]);
    await drag('Climb height', gap('endgame', 0, 1));
    expect(items('robot'), [
      ['climb'],
    ]);
    expect(items('endgame').single, ['hopper', 'balance', 'repair', 'drive']);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await drag('Climb height', gap('endgame', 1), instant: true);
    expect(items('endgame').last, ['climb']);
    expect(design.fields.map((field) => field.id), labels.keys);
  });

  testWidgets('saves, assigns and scouts a new season with the same apps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registry = bearingsEntityRegistry();
    final grove = Grove(
      registry: registry,
      transport: MemoryGroveTransport(registry),
    );
    final scoutingStore = ScoutingStore(
      grove,
      box: null,
      endpoint: 'test',
      subject: Future.value('tablet'),
    );
    addTearDown(scoutingStore.close);
    const team = CompetitionTeam(
      id: 'frc2046',
      number: 2046,
      nickname: 'Bear Metal',
      location: CompetitionLocation(),
    );
    try {
      await grove.create(
        const CompetitionMatch(
          id: '2027demo_qm1',
          event: EntityRef('2027demo'),
          season: 2027,
          level: 'qm',
          setNumber: 1,
          matchNumber: 1,
          practice: false,
          red: CompetitionAlliance(
            teams: [EntityRef('frc2046')],
            gameBreakdown: {'stages_stabilized': 23},
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bearingsGroveProvider.overrideWithValue(grove),
            scoutingStoreProvider.overrideWithValue(scoutingStore),
            currentEventProvider.overrideWith(_NextSeasonEvent.new),
            competitionTeamsProvider('2027demo')
                .overrideWithValue(AsyncData(QueryResult([team]))),
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

      Future<void> tap(String text) async {
        final label = find.text(text).hitTestable();
        expect(label, findsWidgets);
        await tester.tap(label.last);
        await tester.pumpAndSettle();
      }

      Future<void> tooltip(String value) async {
        await tester.tap(find.byTooltip(value));
        await tester.pumpAndSettle();
      }

      Future<void> enter(String label, String text) async {
        final input = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        await tester.enterText(input, text);
        await tester.pumpAndSettle();
      }

      Future<void> select<T>(String label, String option) async {
        final menu = find.widgetWithText(BearingsSelect<T>, label);
        await tester.tap(menu.first);
        await tester.pumpAndSettle();
        await tap(option);
      }

      Future<void> addStep(String operation) async {
        await tap('Add step');
        await enter('Find a step', operation);
        await tap(operation);
      }

      Future<void> pickField(
        String button,
        String field, {
        String variant = 'This match',
      }) async {
        await tap(button);
        await enter('Search questions and metrics', field.split(' · ').first);
        await tap(field);
        if (find.text('Back to results').hitTestable().evaluate().isNotEmpty ||
            find
                .byTooltip('Back to results')
                .hitTestable()
                .evaluate()
                .isNotEmpty) {
          await tap(variant);
        }
      }

      await tap('New GamePack');
      await tooltip('Edit GamePack details');
      await enter('Pack name', 'Skyway');
      await tap('Done');
      expect(find.text('Add question'), findsOneWidget);
      final pageSettings = tester.getCenter(find.byTooltip('Page settings'));
      final addQuestion = tester.getCenter(
        _formAction<FilledButton>('Add question'),
      );
      final previewAction = tester.getCenter(
        _formAction<OutlinedButton>('Preview'),
      );
      expect(addQuestion.dy, closeTo(pageSettings.dy, 1));
      expect(previewAction.dy, closeTo(pageSettings.dy, 1));
      expect(addQuestion.dx, greaterThan(pageSettings.dx));
      expect(find.byTooltip('Rename form'), findsNothing);
      await _selectSidebar(tester, GamePackDockTab.metrics);
      expect(find.text('Graphs'), findsNothing);
      await tooltip('Builder help');
      expect(find.text('Builder guide'), findsOneWidget);
      expect(find.text('Build a calculation'), findsOneWidget);
      await tester.tap(find.byTooltip('Close').hitTestable().last);
      await tester.pumpAndSettle();
      await _selectSidebar(
        tester,
        GamePackDockTab.forms,
        choice: 'Match scouting',
      );
      await tooltip('Page settings');
      await enter('Rows', '5');
      await tap('Save page');
      expect(find.text('Add section'), findsNothing);
      await tap('Add question');
      await enter('Question label', 'Robots docked');
      await enter('Default answer', '0');
      expect(find.text('Advanced options'), findsNothing);
      expect(find.text('Allow Unknown'), findsNothing);
      expect(find.text('Allow Not applicable'), findsNothing);
      await select<GamePackControlType>('Display as', 'Counter');
      await select<GamePackControlType>('Display as', 'Number');
      await tap('Save question');
      final control = find.byKey(const ValueKey('robots_docked'));
      final block = find.descendant(
        of: control,
        matching: find.text('Robots docked'),
      );
      expect(block, findsOneWidget);
      final before = tester.getCenter(block);
      final bounds = tester.getSize(find.byType(GamePackGridEditor));
      final cell = Size(bounds.width / 6, bounds.height / 5);
      expect(bounds.width, closeTo(1280 - 208 - 1 - 48, 1));
      expect(tester.getSize(control).width, closeTo(3 * cell.width, 1));
      expect(tester.getSize(control).height, closeTo(2 * cell.height, 1));
      final drag = await tester.startGesture(before);
      await drag.moveBy(Offset(2 * cell.width, cell.height));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.getCenter(block).dx, greaterThan(before.dx + 30));
      final originalWidth = tester.getSize(control).width;
      await tester.drag(
        find.byTooltip('Drag to resize Robots docked'),
        Offset(cell.width, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(control).width, greaterThan(originalWidth));
      await tap('Preview');
      await tap('Robots docked');
      Finder numericInput() => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      expect(numericInput(), findsOneWidget);
      await tap('Cancel');
      Future<void> answerDocked(String value) async {
        await tap('Robots docked');
        await tester.enterText(numericInput(), value);
        await tap('Done');
      }

      await tooltip('Back to editing');
      await tooltip('Switch page');
      await tap('Add page');
      await enter('Page name', 'Quick checks');
      await tap('Scrolling list');
      await tap('Save page');
      await tooltip('Page options');
      expect(find.text('Move page earlier'), findsOneWidget);
      await tap('Page settings');
      await tap('Save page');
      final sectionAdd = tester.getCenter(
        _formAction<FilledButton>('Add question'),
      );
      final addRow = tester.getCenter(_formAction<TextButton>('Add row'));
      expect(sectionAdd.dy, closeTo(addRow.dy, 1));
      expect(sectionAdd.dx, lessThan(addRow.dx));
      await tap('Add question');
      expect(find.text('Question label'), findsOneWidget);
      await tooltip('Close');
      await tap('Add row');
      for (final field in ['Alignment', 'Stability']) {
        await tooltip('Add question to row');
        await enter('Question label', field);
        await tap('Require an answer');
        await tap('Save question');
      }
      await tooltip('Options for Stability');
      await tap('Move earlier in row');
      await tap('Preview');
      final left = tester.getCenter(
        find.widgetWithText(TextFormField, 'Stability'),
      );
      final right = tester.getCenter(
        find.widgetWithText(TextFormField, 'Alignment'),
      );
      expect(left.dx, lessThan(right.dx));
      expect(left.dy, closeTo(right.dy, 1));
      await tooltip('Back to editing');
      await _selectSidebar(tester, GamePackDockTab.review);
      await tap('Save GamePack');
      expect(
        find.textContaining('Saved Skyway to the GamePacks library'),
        findsOneWidget,
      );
      await tooltip('GamePack options for Skyway');
      await tap('Edit');

      await tap('Edit test data');
      await tap('Add report');
      await tap('Enter answers');
      await tap('Save report');
      await tap('Apply to previews');
      await _selectSidebar(tester, GamePackDockTab.metrics);
      expect(find.text('No calculations yet'), findsOneWidget);
      await _selectMetricView(tester, 'Official values');
      expect(find.text('No official values linked'), findsOneWidget);
      await tap('Link a TBA value');
      await enter('Field name', 'Official level points');
      await tap('Choose breakdown field');
      await enter('Search fields', 'stabilized');
      await tap('Score breakdown › Red › Stages stabilized');
      await tap('Save mapping');

      expect(find.text('Official level points'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
      await _selectMetricView(tester, 'Calculations');
      await tap('Add calculation');
      await enter('Calculation name', 'Adjusted level points');
      await addStep('Add values');
      await pickField('Choose first value', 'Robots docked · Match scouting');
      await tap('Add input');
      await pickField('Choose a field', 'Official level points');
      await addStep('Fixed value');
      await enter('Value', '2');
      await tap('Save step');
      await tooltip('Connect from Fixed value');
      await tap('Add input');
      await addStep('Average');
      expect(find.text('Average across team matches'), findsOneWidget);
      final result = find.byKey(
        const ValueKey(('calculation-value', 'average')),
      );
      expect(tester.widget<Text>(result).data, '25');
      await tap('Save calculation');

      await _selectSidebar(
        tester,
        GamePackDockTab.outputs,
        choice: 'Sorting & filters',
      );
      await tap('Add sort');
      await pickField('Choose field', 'Adjusted level points');
      await enter('Menu label', 'Level points');
      await tap('Save sort');
      await tap('Add filter');
      await pickField('Choose field', 'Adjusted level points');
      await enter('Menu label', 'At least 20 points');
      await select<GamePackFilterTest>('Condition', 'At least');
      await enter('Compare with', '20');
      await tap('Save filter');

      await _selectSidebar(
        tester,
        GamePackDockTab.outputs,
        choice: 'Export sheets',
      );
      await tap('Add sheet');
      await tap('Team Summary');
      await tooltip('Worksheet options');
      await tap('Rename worksheet');
      await enter('Sheet name', 'Analysis');
      await tap('Save name');
      await tap('Add column');
      await pickField('Choose field', 'Adjusted level points');
      await tap('Save column');
      await tap('Add sheet');
      await tap('Match Results');
      await tap('Add column');
      await pickField('Choose field', 'Robots docked · Match scouting');
      await tap('Save column');
      await tap('Add column');
      await pickField(
        'Choose field',
        'Robots docked · Match scouting',
        variant: 'Average across this event',
      );
      await tap('Save column');

      await _selectSidebar(
        tester,
        GamePackDockTab.outputs,
        choice: 'Team card',
      );
      await tap('Add block');
      await tap('Metric row');
      await tap('Add value');
      await pickField('Team key', 'Adjusted level points');
      await enter('Value label', 'Docking index');
      await enter('Decimal places', '1');
      await enter('Suffix', ' pts');
      await tap('Save value');
      await tap('Save block');
      expect(find.text('25.0 pts'), findsOneWidget);

      await _selectSidebar(
        tester,
        GamePackDockTab.outputs,
        choice: 'Team details',
      );
      await tap('Add section');
      await enter('Section title', 'Docking trends');
      await tap('Save section');
      await tap('Add block');
      await tap('Build match trend');
      await pickField('Add match value', 'Robots docked · Match scouting');
      await pickField('Add match value', 'Station');
      await tap('Add trend');
      expect(find.byType(SfCartesianChart), findsOneWidget);

      await _selectSidebar(tester, GamePackDockTab.review);
      expect(find.text('Ready to assign').hitTestable(), findsOneWidget);
      await tap('Save GamePack');
      final gamePack = (await grove.query<GamePack>().many()).single;
      final definition = GamePackDesign.fromJson(gamePack.document).compile();
      expect(
        GamePackDesign.fromJson(gamePack.document).forms
            .map((form) => form.kind),
        GamePackFormKind.values,
      );
      expect(definition.forms.single.kind, GamePackFormKind.match);
      expect(
        (gamePack.document['builderFixture'] as Json)['reports'],
        hasLength(1),
      );
      expect(definition.season, 2027);
      expect(definition.fieldById['robots_docked']?.defaultValue, 0);
      expect(gamePack.document.containsKey('graphs'), isFalse);
      final calculation = definition.analysis.calculationById(
        'adjusted_level_points',
      )!;
      expect(calculation.nodes, hasLength(5));
      expect(calculation.nodesById[calculation.result]!.inputs, {
        'value': 'add',
      });
      expect(
        (calculation.nodesById['add'] as GamePackStepNode).inputs.values,
        contains('constant'),
      );
      final form = definition.formFor(GamePackFormKind.match)!;
      final grid = form.pages.first;
      final placed = grid.gridControls.single.placement!;
      expect(grid.rows, 5);
      expect((placed.x, placed.y, placed.width), (2, 1, 4));
      final list = form.pages.last;
      expect(list.layout, GamePackPageLayout.scrolling);
      final row = list.sections.single.items.single;
      expect(row.isRow, isTrue);
      expect(row.controls.map((control) => control.field), [
        'stability',
        'alignment',
      ]);
      expect(definition.results.sorts.single.label, 'Level points');
      expect(definition.results.filters.single.label, 'At least 20 points');
      final sheets = definition.results.sheets;
      expect(sheets.map((sheet) => sheet.rows), [
        GamePackSheetRows.teams,
        GamePackSheetRows.matches,
      ]);
      expect(
        sheets.last.columns.last.output,
        gamePackRollupRef('match.robots_docked', GamePackRollup.average),
      );
      expect(definition.teamCards.map((layout) => layout.kind), [
        GamePackTeamCardKind.compact,
        GamePackTeamCardKind.details,
      ]);
      await tooltip('GamePack options for Skyway');
      await tap('Assign to event');
      await tap('Assign GamePack');
      final card = (await grove.query<EventGamePack>().byId('2027demo').one());
      expect(card.gamePack!.id, gamePack.id);

      final official = TbaMatchRevision(
        id: '2027demo_qm1-1',
        event: const EntityRef('2027demo'),
        match: const EntityRef('2027demo_qm1'),
        observedAt: DateTime.utc(2027, 3, 1),
        sequence: 1,
        payload: {
          'score_breakdown': {
            'red': {'stages_stabilized': 28},
          },
        },
      );
      await grove.create(official);
      final manager = tester.element(find.byType(GamePacksPage));
      ScaffoldMessenger.of(manager).clearSnackBars();
      await tester.pumpAndSettle();
      final navigator = Navigator.of(manager);
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const GamePackScoutPage(
              event: '2027demo',
              position: ScoutPosition.red1,
              scoutId: 'scout-2027',
              initialMatchId: '2027demo_qm1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Match 1 · Red 1 · Team 2046'), findsOneWidget);
      await answerDocked('4');
      await tester.tap(find.text('Save observation').hitTestable());
      await tester.pumpAndSettle();
      expect((await scoutingStore.records()).single['ready'], {
        'robots_docked': 4,
      });
      await grove.synchronize();
      final observations = await grove.query<GamePackObservation>().many();
      final captured = observations.single;
      expect(captured.gamePack.id, gamePack.id);
      expect(captured.answers, {'robots_docked': 4});
      navigator.pop();
      await tester.pumpAndSettle();

      final analysis = GamePackEventAnalysis(
        event: '2027demo',
        capture: gamePack,
        analysis: gamePack,
        observations: observations,
        revisions: [official],
      );
      final workbook = Excel.decodeBytes(
        buildGamePackWorkbook(analysis: analysis, includeScout: false),
      );
      final analysisRows = workbook.sheets['Analysis']!.rows;
      expect(analysisRows[0][2]?.value?.toString(), 'Adjusted level points');
      expect(
        analysisRows[1][2]?.value,
        anyOf(IntCellValue(34), DoubleCellValue(34)),
      );

      unawaited(
        Navigator.of(tester.element(find.byType(GamePacksPage))).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                const TeamDetailsPage(teamNumber: 2046, teamName: 'Bear Metal'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Docking trends'), findsOneWidget);
      expect(find.text('Averages'), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 420,
                  child: TeamCard(teamKey: 'frc2046'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Docking index'), findsOneWidget);
      expect(find.text('34.0 pts'), findsOneWidget);
      expect(find.text('Docking trends'), findsNothing);
      unawaited(
        BearingsModal.show<bool>(
          tester.element(find.byType(TeamCard)),
          builder: (_) =>
              PicklistTeamQuickViewSheet(team: Team.fromCompetition(team)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Docking trends'), findsOneWidget);
      final chart = tester.widget<SfCartesianChart>(
        find.byType(SfCartesianChart),
      );
      expect(chart.series.map((series) => series.name), [
        'Robots docked',
        'Station',
      ]);
      expect(chart.series.map((series) => series.color).toSet(), hasLength(2));
      await tester.tap(find.byTooltip('Close').hitTestable().last);
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      await tooltip('GamePack options for Skyway');
      await tap('Edit other sections');
      expect(find.text('Match scouting'), findsWidgets);
      await _selectSidebar(
        tester,
        GamePackDockTab.forms,
        choice: 'Pit scouting',
      );
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Add question'), findsOneWidget);
      await _selectSidebar(
        tester,
        GamePackDockTab.outputs,
        choice: 'Team card',
      );
      expect(find.text('Preview data'), findsNothing);
      await tap('Edit test data');
      expect(
        find.text('1 match · 1 with official scores · 1 with scouting reports'),
        findsOneWidget,
      );
      await tap('Add report');
      await tap('Enter answers');
      await answerDocked('6');
      await tap('Save report');
      await tap('Apply to previews');
      expect(find.text('36.0 pts'), findsOneWidget);
      await _selectSidebar(
        tester,
        GamePackDockTab.outputs,
        choice: 'Sorting & filters',
      );
      expect(find.text('Use event teams'), findsNothing);
      expect(find.text('Preview sort'), findsOneWidget);
      await _selectSidebar(
        tester,
        GamePackDockTab.outputs,
        choice: 'Export sheets',
      );
      expect(find.text('Use event data'), findsNothing);
      expect(find.text('Worksheet preview'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(grove.close());
      await tester.pump();
    }
  });

  testWidgets(
    'saves calculation canvases with cards and a worked TBA example',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 1260);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = bearingsEntityRegistry();
      final grove = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
      );
      try {
        await grove.create(
          const CompetitionEvent(
            id: '2027sample',
            season: 2027,
            name: 'Sample Regional',
            code: 'sample',
            location: CompetitionLocation(),
          ),
        );
        for (final (number, units) in [(1, 20), (2, 40)]) {
          await grove.create(
            CompetitionMatch(
              id: '2027sample_qm$number',
              event: const EntityRef('2027sample'),
              season: 2027,
              level: 'qm',
              setNumber: 1,
              matchNumber: number,
              practice: false,
              red: CompetitionAlliance(
                teams: const [EntityRef('frc2046')],
                gameBreakdown: {
                  'official_units': units,
                  if (number == 1) 'first_match_units': 10,
                },
              ),
            ),
          );
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bearingsGroveProvider.overrideWithValue(grove),
              currentEventProvider.overrideWith(_NextSeasonEvent.new),
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

        Future<void> tap(String label) async {
          final finder = find.text(label).hitTestable();
          expect(finder, findsWidgets, reason: label);
          await tester.tap(finder.last);
          await tester.pumpAndSettle();
        }

        Finder textField(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        Future<void> enter(String label, String text) async {
          await tester.enterText(textField(label), text);
          await tester.pumpAndSettle();
        }

        Future<void> field(String button, String value) async {
          await tap(button);
          await enter('Search questions and metrics', value.split(' · ').first);
          await tap(value);
          if (find
              .byTooltip('Back to results')
              .hitTestable()
              .evaluate()
              .isNotEmpty) {
            await tap('This match');
          }
        }

        await tap('New GamePack');
        await tester.tap(find.byTooltip('Edit GamePack details'));
        await tester.pumpAndSettle();
        await enter('Pack name', '2027 Scoped Pack');
        await enter('Season', '2027');
        await tap('Done');
        await tap('Add question');
        await enter('Question label', 'Game units');
        await enter('Default answer', '5');
        await tap('Save question');

        await _selectSidebar(tester, GamePackDockTab.metrics);
        await tap('Edit test data');
        await tap('2027demo');
        await tap('Sample Regional');
        await tester.tap(find.byTooltip('Close').hitTestable().last);
        await tester.pumpAndSettle();
        await tap('Edit test data');
        await tap('2027demo');
        await tap('Sample Regional');
        expect(find.text('Paste TBA response'), findsNothing);
        await tap('Add report');
        await tap('Enter answers');
        await tap('Save report');
        await tap('Add report');
        await tap('Report match');
        await tap('Qualification 2');
        await tap('Enter answers');
        await tap('Save report');
        expect(
          find.text(
            '2 matches · 2 with official scores · 2 with scouting reports',
          ),
          findsOneWidget,
        );
        await tap('Preview match');
        final nextMatch = find
            .descendant(
              of: find.byType(BearingsMenuItem),
              matching: find.text('Qualification 2'),
            )
            .hitTestable();
        expect(nextMatch, findsOneWidget);
        await tester.tap(nextMatch);
        await tester.pumpAndSettle();
        await tap('Apply to previews');
        await _selectMetricView(tester, 'Official values');
        await tap('Link a TBA value');
        expect(find.text('Sample score breakdown'), findsNothing);
        await enter('Field name', 'Official Alliance Units');
        await tap('Choose breakdown field');
        await enter('Search fields', 'units');
        expect(
          find.text('Score breakdown › Red › First match units'),
          findsOneWidget,
        );
        await tap('Score breakdown › Red › Official units');
        await tap('Save mapping');

        await _selectMetricView(tester, 'Calculations');
        await tap('Add calculation');
        await field('Start with a value', 'Game units · Match scouting');
        expect(find.byTooltip('Connect from Game units'), findsOneWidget);
        await tap('Add step');
        await tap('Scale to official total');
        await enter('Calculation name', 'Adjusted Units');
        await field(
          'Choose official alliance total',
          'Official Alliance Units',
        );
        expect(
          find.text('5 × (40 official ÷ 5 reported) = 40'),
          findsOneWidget,
        );
        await tap('Add input');
        expect(find.text('Extra alliance contribution'), findsOneWidget);
        expect(find.text('Value to adjust'), findsNothing);
        await tester.tap(find.byTooltip('Close').hitTestable().last);
        await tester.pumpAndSettle();
        await tap('Save calculation');

        await _selectSidebar(
          tester,
          GamePackDockTab.outputs,
          choice: 'Team card',
        );
        await tap('Add block');
        await tap('Create metric');
        await field('Start with a value', 'Adjusted Units');
        await tap('Add step');
        await tap('Average');
        await enter('Calculation name', 'Custom Units Average');
        expect(find.text('2 matches used · 20, 40'), findsOneWidget);
        expect(find.byTooltip('Use as result'), findsNothing);
        await tap('Adjusted Units');
        final nodeActions = find.byTooltip('Use as result');
        expect(nodeActions.hitTestable(), findsOneWidget);
        final actionSize = tester.getSize(nodeActions);
        final actionOrigin = tester.getTopLeft(nodeActions);
        await tester.tap(find.byTooltip('Zoom in').hitTestable());
        await tester.pumpAndSettle();
        expect(tester.getSize(nodeActions), actionSize);
        expect(tester.getTopLeft(nodeActions), isNot(actionOrigin));
        await tester.tap(find.byTooltip('Fit calculation').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(
          find.byTooltip('Open Adjusted Units calculation').hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('5 × (40 official ÷ 5 reported) = 40'),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Remove selected node').hitTestable(),
          findsNothing,
        );
        await tester.tap(find.byTooltip('Close').hitTestable().last);
        await tester.pumpAndSettle();
        await tap('Save calculation');
        expect(find.text('30'), findsOneWidget);
        await tap('Add block');
        await tap('Metric row');
        await tap('Add value');
        await field('Team key', 'Average Adjusted Units');
        await enter('Value label', 'Auto event average');
        await tap('Save value');
        await tap('Save block');

        await _selectSidebar(
          tester,
          GamePackDockTab.outputs,
          choice: 'Team details',
        );
        await tap('Add block');
        await tap('Build match trend');
        await enter('Chart title', 'Units over time');
        await field('Add match value', 'Adjusted Units');
        await tap('Add trend');
        expect(find.byType(SfCartesianChart), findsOneWidget);

        await _selectSidebar(tester, GamePackDockTab.review);
        await tap('Save GamePack');
        final saved = (await grove.query<GamePack>().many()).single;
        final fixture = saved.document['builderFixture'] as Json;
        expect(
          fixture.keys,
          unorderedEquals(['event', 'match', 'team', 'seed', 'reports']),
        );
        expect(fixture['event'], '2027sample');
        expect(fixture['match'], '2027sample_qm2');
        expect(
          (fixture['reports'] as List).cast<Json>().map(
            (report) => report['match'],
          ),
          ['2027sample_qm1', '2027sample_qm2'],
        );
        final pack = GamePackDesign.fromJson(saved.document).compile();
        expect(saved.document.containsKey('graphs'), isFalse);
        expect(saved.document.containsKey('builderFixture'), isTrue);
        expect(pack.analysis.tbaFields.single.paths, [
          'score_breakdown.{alliance}.official_units',
        ]);
        expect(
          pack.analysis.calculations.map(
            (item) =>
                (item.nodesById[item.result] as GamePackStepNode).operation,
          ),
          [GamePackRecipe.scale, GamePackRecipe.average, GamePackRecipe.rows],
        );
        final metrics = pack.teamCards.first.sections.single.blocks.expand(
          (block) => block.metrics,
        );
        expect(
          metrics.map((metric) => metric.output),
          contains(gamePackRollupRef('adjusted_units', GamePackRollup.average)),
        );
        expect(pack.teamCards.map((card) => card.kind), [
          GamePackTeamCardKind.compact,
          GamePackTeamCardKind.details,
        ]);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(grove.close());
        await tester.pump();
      }
    },
  );

  testWidgets('finds, previews and edits existing questions on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final registry = bearingsEntityRegistry();
    final grove = Grove(
      registry: registry,
      transport: MemoryGroveTransport(registry),
    );
    final design = GamePackDesign.fromJson(
      jsonDecode(File('../../gamepacks/2026-rebuilt.json').readAsStringSync())
          as Json,
    );

    Future<void> tap(Finder finder) async {
      await tester.tap(finder.hitTestable().last);
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bearingsGroveProvider.overrideWithValue(grove)],
          child: MaterialApp(
            home: GamePackWorkspacePage(
              event: '2026demo',
              imported: design,
              onSaved: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Questions'), findsNothing);
      expect(find.text('Layout'), findsNothing);
      final title = find.text('Match scouting');
      expect(
        tester.widget<Text>(title).style,
        Theme.of(tester.element(title)).textTheme.titleLarge,
      );
      final titleCenter = tester.getCenter(title);
      final picker = tester.getCenter(find.byTooltip('Switch page'));
      final search = tester.getCenter(find.byTooltip('Find a question'));
      final addQuestion = _formAction<FilledButton>('Add question');
      final addBounds = tester.getRect(addQuestion);
      final gridBounds = tester.getRect(find.byType(GamePackGridEditor));
      final preview = find.byTooltip('Preview');
      final previewAction = tester.getCenter(
        find.descendant(
          of: preview,
          matching: find.byWidgetPredicate((widget) => widget is IconButton),
        ),
      );
      expect(picker.dy, closeTo(titleCenter.dy, 1));
      expect(picker.dx, greaterThan(titleCenter.dx));
      expect(search.dy, closeTo(titleCenter.dy, 1));
      expect(previewAction.dy, closeTo(titleCenter.dy, 1));
      expect(search.dx, greaterThan(picker.dx));
      expect(search.dx, lessThan(previewAction.dx));
      expect(addBounds.top, greaterThanOrEqualTo(gridBounds.bottom));
      expect(addBounds.center.dx, closeTo(gridBounds.center.dx, 1));
      expect(find.byTooltip('Page options'), findsNothing);
      await tap(find.byTooltip('Switch page'));
      await tap(find.text('Page settings'));
      expect(field('Page name'), findsOneWidget);
      await tap(find.byTooltip('Close'));
      await tap(find.byTooltip('Find a question'));
      await tester.enterText(
        field('Search by question, page or form'),
        'scored',
      );
      await tester.pumpAndSettle();
      expect(find.text('Autonomous › Scored'), findsOneWidget);
      await tap(find.text('Tele › Scored'));

      expect(find.byTooltip('Options for Scored'), findsNothing);
      await tap(find.byTooltip('Remove question'));
      expect(find.text('Scored is in use'), findsOneWidget);
      expect(find.text('Metrics › Adjusted tele_fuel'), findsOneWidget);
      await tap(find.byTooltip('Close'));

      await tap(find.byTooltip('Edit question'));
      final visibility = find.widgetWithText(
        BearingsSelect<GamePackField?>,
        'Show question',
      );
      await tester.ensureVisible(visibility);
      await tap(visibility);
      await tap(find.text('A-Stop'));
      expect(find.text('When the answer is'), findsOneWidget);
      await tap(visibility);
      await tap(find.text('Always visible'));
      expect(find.text('When the answer is'), findsNothing);
      await tester.ensureVisible(field('Question label'));
      await tester.enterText(field('Question label'), 'Fuel scored');
      await tap(find.text('Save question'));
      await tap(preview);
      expect(find.byTooltip('Zoom tablet preview'), findsNothing);
      expect(find.byTooltip('Fit tablet preview'), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);
      final previewBounds = tester.getSize(find.byType(GamePackFormView));
      expect(previewBounds.width, closeTo(390 - 24 - 32, 1));
      expect(previewBounds.height, greaterThan(600));
      expect(find.text('Try questions'), findsNothing);
      expect(find.text('Tablet layout'), findsNothing);
      final pageBar = find.descendant(
        of: find.byType(GamePackFormView),
        matching: find.byType(BearingsCapsuleBar<int>),
      );
      await tap(find.descendant(of: pageBar, matching: find.text('Endgame')));
      final navigation = tester.widget<BearingsCapsuleBar<int>>(pageBar);
      expect(navigation.destinations[navigation.selected].label, 'Endgame');
      await tap(find.byTooltip('Back to editing'));
      expect(find.text('Save GamePack'), findsNothing);
      await tap(find.text('Review'));
      final choices = find.byKey(const ValueKey('gamepack-dock-choices'));
      Future<void> openOutput(String label) async {
        await tap(find.text('Outputs'));
        expect(
          find.descendant(of: choices, matching: find.text('Views & exports')),
          findsNothing,
        );
        final target = find.descendant(of: choices, matching: find.text(label));
        if (target.hitTestable().evaluate().isEmpty) {
          await tester.drag(choices, const Offset(-340, 0));
          await tester.pumpAndSettle();
        }
        await tap(target);
      }

      await openOutput('Team card');
      final switcher = find.byKey(
        const ValueKey('gamepack-edit-preview-capsule'),
      );
      final indicator = find.descendant(
        of: switcher,
        matching: find.byKey(const ValueKey('bearings-capsule-indicator')),
      );
      final origin = tester.getCenter(indicator);
      final travel = Offset(tester.getSize(indicator).width * .85, 0);
      expect(tester.getRect(indicator).left - tester.getRect(switcher).left, 4);
      final canceled = await tester.startGesture(origin);
      await canceled.moveBy(travel);
      await tester.pump();
      expect(tester.getCenter(indicator).dx, closeTo(origin.dx + travel.dx, 1));
      expect(find.text('Add block'), findsOneWidget);
      await canceled.cancel();
      await tester.pumpAndSettle();
      expect(tester.getCenter(indicator), origin);
      await tester.dragFrom(origin, travel);
      await tester.pumpAndSettle();
      expect(find.text('Test data'), findsOneWidget);
      expect(find.text('Preview data'), findsNothing);
      expect(find.text('Add block'), findsNothing);
      expect(
        tester.getRect(switcher).right - tester.getRect(indicator).right,
        4,
      );
      await tap(find.descendant(of: switcher, matching: find.text('Edit')));
      expect(find.text('Add block'), findsOneWidget);

      await openOutput('Export sheets');
      expect(find.text('Worksheet preview'), findsOneWidget);
      expect(find.text('Find a column'), findsOneWidget);
      expect(find.text('Add sheet'), findsNothing);
      await tap(find.byTooltip('Switch worksheet'));
      final addSheet = find.widgetWithText(BearingsMenuItem, 'Add sheet');
      expect(tester.widget<BearingsMenuItem>(addSheet).leadingIcon, isNotNull);
      await tap(find.text('Normalized Match Data'));
      await tap(find.byTooltip('Switch worksheet'));
      expect(find.text('Rename worksheet'), findsOneWidget);
      final includeUnscouted = find.widgetWithText(
        BearingsMenuItem,
        'Include matches without scout reports',
      );
      expect(
        tester.widget<BearingsMenuItem>(includeUnscouted).leadingIcon,
        isNotNull,
      );
      await tap(find.text('Include matches without scout reports'));
      await tap(find.byTooltip('Switch worksheet'));
      await tap(addSheet);
      await tap(find.text('Team Summary'));
      expect(find.text('Team Summary'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(grove.close());
      await tester.pump();
    }
  });

  testWidgets('the phone dock switches among the four GamePack forms', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 670);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    final registry = bearingsEntityRegistry();
    final grove = Grove(
      registry: registry,
      transport: MemoryGroveTransport(registry),
    );

    Future<void> tap(Finder finder) async {
      await tester.tap(finder.hitTestable().last);
      await tester.pumpAndSettle();
    }

    final choices = find.byKey(const ValueKey('gamepack-dock-choices'));
    final capsule = find.byKey(const ValueKey('gamepack-dock-capsule'));
    final selector = find.descendant(
      of: capsule,
      matching: find.byKey(const ValueKey('bearings-capsule-indicator')),
    );
    final dock = find.byType(GamePackWorkspaceDock);
    final testData = find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip('Edit test data'),
    );
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bearingsGroveProvider.overrideWithValue(grove)],
          child: MaterialApp(
            home: GamePackWorkspacePage(event: '2027demo', onSaved: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save GamePack'), findsNothing);
      final editor = find.byType(GamePackFormsEditor);
      final editorState = tester.state(editor);
      final editorBounds = tester.getRect(editor);
      final bounds = tester.getRect(capsule);
      expect(bounds.top - editorBounds.bottom, closeTo(5, 1));

      tester.view.padding = const FakeViewPadding(bottom: 24);
      await tester.pumpAndSettle();
      expect(tester.getRect(capsule).bottom, closeTo(bounds.bottom - 24, 1));
      expect(
        tester.getRect(editor).bottom,
        closeTo(editorBounds.bottom - 24, 1),
      );
      tester.view.resetPadding();
      await tester.pumpAndSettle();

      await tap(find.text('Forms'));
      expect(choices, findsOneWidget);
      expect(tester.getRect(editor), editorBounds);
      expect(
        tester.getCenter(testData).dx,
        lessThan(tester.getCenter(find.byTooltip('Builder help')).dx),
      );
      await tap(testData);
      expect(choices, findsNothing);
      expect(find.text('Edit test data'), findsOneWidget);
      expect(find.byType(GamePackFixtureEditor), findsOneWidget);
      await tap(find.byTooltip('Close'));

      tester.view.viewInsets = const FakeViewPadding(bottom: 160);
      await tester.pumpAndSettle();
      expect(capsule, findsNothing);
      expect(tester.state(editor), same(editorState));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.getRect(editor), editorBounds);

      final inset = tester.getRect(selector).top - bounds.top;
      expect(tester.getRect(selector).left - bounds.left, inset);
      expect(bounds.bottom - tester.getRect(selector).bottom, inset);
      final clip = tester.widget<ClipPath>(
        find.descendant(
          of: capsule,
          matching: find.byKey(const ValueKey('bearings-capsule-clip')),
        ),
      );
      expect(clip.clipBehavior, Clip.antiAlias);
      expect(clip.clipper, isA<ShapeBorderClipper>());
      expect((clip.clipper as ShapeBorderClipper).shape, isA<StadiumBorder>());

      // Sample the spring near the peak of its first overshoot.
      await tester.tap(find.text('Review').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getRect(selector).right, greaterThan(bounds.right));
      await tester.pumpAndSettle();
      expect(bounds.right - tester.getRect(selector).right, inset);
      expect(testData.hitTestable(), findsOneWidget);

      await tester.tap(find.text('Forms').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getRect(selector).left, lessThan(bounds.left));
      await tester.pumpAndSettle();
      expect(tester.getRect(selector).left - bounds.left, inset);
      expect(choices, findsOneWidget);
      final tray = find.byKey(const ValueKey('gamepack-dock-tray'));
      expect(tester.getRect(choices).left, tester.getRect(tray).left);
      expect(tester.getRect(choices).right, tester.getRect(tray).right);
      expect(tester.widget<Container>(tray).clipBehavior, Clip.antiAlias);
      final listPadding =
          tester.widget<ListView>(choices).padding as EdgeInsets;
      expect(listPadding.left, greaterThan(0));
      expect(listPadding.left, listPadding.right);
      expect(
        find.descendant(of: tray, matching: find.text('Scout forms')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(choices, findsNothing);

      final reviewCenter = tester.getCenter(selector);
      final tabWidth = tester.getSize(selector).width;
      final travel = Offset(-tabWidth * 1.15, 0);
      final canceled = await tester.startGesture(reviewCenter);
      await canceled.moveBy(travel);
      await tester.pump();
      expect(
        tester.getCenter(selector).dx,
        closeTo(reviewCenter.dx + travel.dx, 1),
      );
      expect(choices, findsNothing);
      await canceled.cancel();
      await tester.pumpAndSettle();
      expect(tester.getCenter(selector), reviewCenter);

      await tester.dragFrom(reviewCenter, travel);
      await tester.pumpAndSettle();
      expect(
        tester.widget<GamePackWorkspaceDock>(dock).expanded,
        GamePackDockTab.outputs,
      );
      expect(choices, findsOneWidget);
      await tester.dragFrom(
        tester.getCenter(selector),
        Offset(-tabWidth * 2, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<GamePackWorkspaceDock>(dock).expanded,
        GamePackDockTab.forms,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      for (final kind in GamePackFormKind.values) {
        await tap(find.text('Forms'));
        final choice = find.descendant(
          of: choices,
          matching: find.text(kind.label),
        );
        if (choice.hitTestable().evaluate().isEmpty) {
          await tester.drag(choices, const Offset(-215, 0));
          await tester.pumpAndSettle();
        }
        await tap(choice);
        expect(choices, findsNothing);
        expect(find.text(kind.label), findsOneWidget);
        expect(find.text('Page 1'), findsOneWidget);
        expect(find.text('Add question'), findsOneWidget);
        expect(find.byTooltip('Rename form'), findsNothing);
        if (kind == GamePackFormKind.match) {
          await tap(find.text('Add question'));
          expect(
            find.widgetWithText(TextField, 'Question label'),
            findsOneWidget,
          );
          await tap(find.byTooltip('Close'));
        }
      }
      await tester.dragFrom(
        tester.getCenter(selector),
        Offset(tabWidth * 3, 0),
      );
      await tester.pumpAndSettle();
      await tap(find.byTooltip('Edit GamePack details'));
      final season = find.widgetWithText(TextField, 'Season');
      final theme = InputDecorationTheme.of(tester.element(season));
      expect(theme.border, isA<OutlineInputBorder>());
      await tester.enterText(season, '1980');
      await tap(find.text('Done'));
      expect(find.text('Enter a valid FRC season.'), findsOneWidget);
      await tester.enterText(season, '2028');
      await tap(find.text('Done'));
      expect(season, findsNothing);
      expect(
        find.text('Add at least one question to a scouting form.'),
        findsOneWidget,
      );
      expect(find.text('Save GamePack'), findsOneWidget);

      await tap(find.text('Forms'));
      await tester.drag(choices, const Offset(-215, 0));
      await tester.pumpAndSettle();
      await tap(
        find.descendant(of: choices, matching: find.text('Pit scouting')),
      );
      await tap(find.text('Add question'));
      final label = find.widgetWithText(TextField, 'Question label');
      await tester.enterText(label, 'Drive train checks');
      await tap(find.text('Save question'));
      expect(find.text('Drive train checks'), findsOneWidget);
      expect(find.byTooltip('Remove question'), findsOneWidget);
      expect(find.byTooltip('Options for Drive train checks'), findsNothing);
      await tap(find.text('Review'));
      await tap(find.text('Save GamePack'));
      final changed = (await grove.query<GamePack>().many()).single;
      expect(changed.document['season'], 2028);
      expect(
        GamePackDesign.fromJson(changed.document).questions.single.field.label,
        'Drive train checks',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(grove.close());
      await tester.pump();
    }
  });
}
