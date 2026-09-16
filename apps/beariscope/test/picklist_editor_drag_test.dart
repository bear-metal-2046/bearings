import 'package:beariscope/pages/picklists/picklist_editor_page.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/rankings_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [400.0, 1200.0]) {
    testWidgets('library returns and blank-space drops work at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          teamsProvider.overrideWith(
            (ref) async => [
              {'key': 'frc3', 'team_number': 3, 'nickname': 'Library team'},
            ],
          ),
          eventTeamMediaProvider.overrideWith((ref) async => []),
          eventRankingsProvider.overrideWith((ref) async => {}),
        ],
      );
      addTearDown(container.dispose);
      final picklist = container
          .read(picklistLibraryProvider.notifier)
          .create(title: 'Drop targets', teamKeys: ['frc1', 'frc2']);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: PicklistEditorPage(picklistId: picklist.id)),
        ),
      );
      await tester.pumpAndSettle();
      if (width < 850) {
        await tester.tap(find.text('Library'));
        await tester.pumpAndSettle();
      }
      final blank = Offset(width < 850 ? 200 : 800, 650);
      Future<TestGesture> dragFromLibrary() async {
        final drag = await tester.startGesture(
          tester.getCenter(find.text('Library team')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 400));
        await drag.moveTo(blank);
        await tester.pump(const Duration(milliseconds: 50));
        return drag;
      }

      final canceled = await dragFromLibrary();
      expect(find.text('Drop to return'), findsOneWidget);
      await canceled.moveTo(tester.getCenter(find.text('Drop to return')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byWidgetPredicate((widget) {
          if (widget is! AnimatedContainer) return false;
          final decoration = widget.foregroundDecoration;
          return decoration is BoxDecoration && (decoration.color?.a ?? 0) > 0;
        }),
        findsOneWidget,
      );
      await canceled.up();
      await tester.pumpAndSettle();
      expect(container.read(picklistLibraryProvider).single.teamKeys, [
        'frc1',
        'frc2',
      ]);
      final added = await dragFromLibrary();
      await added.up();
      await tester.pump();
      final landing = find.byKey(const ValueKey('picklist-landing-card'));
      expect(landing, findsOneWidget);
      final destination = find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedPositioned &&
            widget.key == const ValueKey('frc3'),
      );
      expect(
        find.descendant(
          of: destination,
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.opacity == 0,
          ),
        ),
        findsOneWidget,
      );
      final released = tester.getRect(landing);
      expect(released.center.dy, greaterThan(500));
      await tester.pump(); // Start the ticker after the destination layout.
      await tester.pump(const Duration(milliseconds: 100));
      final gliding = tester.getRect(landing);
      final landingMaterial = tester.widget<Material>(landing);
      final shadow = tester.widget<PhysicalShape>(
        find
            .descendant(of: landing, matching: find.byType(PhysicalShape))
            .first,
      );
      expect(landingMaterial.elevation, lessThan(12));
      expect(shadow.elevation, closeTo(landingMaterial.elevation, .001));
      expect(gliding.top, lessThan(released.top));
      if (width >= 850) expect(gliding.width, greaterThan(released.width));
      await tester.pumpAndSettle();
      expect(landing, findsNothing);
      if (width < 850) {
        final header = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Toggle team library',
        );
        expect(tester.getBottomLeft(header).dy, 900);
      }
      expect(
        find.descendant(
          of: destination,
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.opacity == 0,
          ),
        ),
        findsNothing,
      );
      expect(container.read(picklistLibraryProvider).single.teamKeys, [
        'frc1',
        'frc2',
        'frc3',
      ]);
      // Existing picklist teams still return to the library.
      final first = find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedPositioned &&
            widget.key == const ValueKey('frc1'),
      );
      final removed = await tester.startGesture(tester.getCenter(first));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await removed.moveTo(tester.getCenter(find.text('Drop to return')));
      await tester.pump(const Duration(milliseconds: 50));
      await removed.up();
      await tester.pumpAndSettle();
      expect(container.read(picklistLibraryProvider).single.teamKeys, [
        'frc2',
        'frc3',
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'mobile sheet stays at the bottom when teams are added or removed',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          teamsProvider.overrideWith((ref) async => []),
          eventTeamMediaProvider.overrideWith((ref) async => []),
          eventRankingsProvider.overrideWith((ref) async => {}),
        ],
      );
      addTearDown(container.dispose);
      final library = container.read(picklistLibraryProvider.notifier);
      final picklist = library.create(title: 'Mobile');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: PicklistEditorPage(picklistId: picklist.id)),
        ),
      );
      await tester.pumpAndSettle();
      final header = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Toggle team library',
      );
      expect(tester.getBottomLeft(header).dy, 900);
      library.setTeams(picklist.id, ['frc1']);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(header).dy, 900);
      final row = find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedPositioned &&
            widget.key == const ValueKey('frc1'),
      );
      expect(
        tester.getTopLeft(row).dy,
        tester.getBottomLeft(find.byType(AppBar)).dy,
      );
      await tester.tap(
        find.ancestor(of: header, matching: find.byType(GestureDetector)).first,
      );
      await tester.pumpAndSettle();
      final expandedTop = tester.getTopLeft(header).dy;
      expect(expandedTop, lessThan(836));
      library.setTeams(picklist.id, ['frc1', 'frc2']);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header).dy, expandedTop);
      await tester.tap(
        find.ancestor(of: header, matching: find.byType(GestureDetector)).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(header).dy, 900);
      library.setTeams(picklist.id, []);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(header).dy, 900);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drag spacing stays fixed and displaced teams slide to their ranks',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          teamsProvider.overrideWith((ref) async => []),
          eventTeamMediaProvider.overrideWith((ref) async => []),
          eventRankingsProvider.overrideWith((ref) async => {}),
        ],
      );
      addTearDown(container.dispose);
      final picklist = container
          .read(picklistLibraryProvider.notifier)
          .create(title: 'Test', teamKeys: ['frc1', 'frc2', 'frc3', 'frc4']);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: PicklistEditorPage(picklistId: picklist.id)),
        ),
      );
      await tester.pumpAndSettle();
      Finder row(String key) => find.byWidgetPredicate(
        (widget) => widget is AnimatedPositioned && widget.key == ValueKey(key),
      );
      double y(String key) => tester.getTopLeft(row(key)).dy;
      final original = [for (var i = 1; i <= 4; i++) y('frc$i')];
      expect(original.first, tester.getBottomLeft(find.byType(AppBar)).dy);
      final gesture = await tester.startGesture(tester.getCenter(row('frc4')));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 1; i <= 4; i++) {
        expect(y('frc$i'), original[i - 1]);
      }
      for (final key in ['frc2', 'frc3', 'frc1', 'frc2']) {
        await gesture.moveTo(
          tester.getTopLeft(row(key)) + const Offset(100, 16),
        );
        await tester.pump(const Duration(milliseconds: 16));
        for (var i = 1; i <= 4; i++) {
          expect(y('frc$i'), original[i - 1]);
        }
      }
      await gesture.up();
      await tester.pump();
      final landing = find.byKey(const ValueKey('picklist-landing-card'));
      expect(landing, findsOneWidget);
      final releaseRect = tester.getRect(landing);
      // Landing starts at the dragged card, far above its original fourth row.
      expect(releaseRect.top, lessThan(original[3] - 72));
      expect(container.read(picklistLibraryProvider).single.teamKeys, [
        'frc1',
        'frc4',
        'frc2',
        'frc3',
      ]);
      await tester.pump(const Duration(milliseconds: 80));
      expect(y('frc2'), greaterThan(original[1]));
      expect(y('frc2'), lessThan(original[1] + 72));
      await tester.pumpAndSettle();
      expect(y('frc2'), original[1] + 72);
      expect(y('frc3'), original[2] + 72);
      expect(y('frc4'), original[1]);
      expect(landing, findsNothing);
      final downward = await tester.startGesture(tester.getCenter(row('frc4')));
      await tester.pump(const Duration(milliseconds: 300));
      await downward.moveTo(
        tester.getBottomLeft(row('frc3')) + const Offset(100, -16),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await downward.up();
      await tester.pumpAndSettle();
      expect(container.read(picklistLibraryProvider).single.teamKeys, [
        'frc1',
        'frc2',
        'frc3',
        'frc4',
      ]);
      for (var i = 1; i <= 4; i++) {
        expect(y('frc$i'), original[i - 1]);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
