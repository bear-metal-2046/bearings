import 'dart:ui' show PointerDeviceKind;

import 'package:beariscope/pages/picklists/picklist_editor_page.dart';
import 'package:beariscope/pages/picklists/picklist_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CurrentEvent extends CurrentEvent {
  @override
  String build() => '2026test';
}

void main() {
  testWidgets('mouse and touch can drag the full card and tap Team actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = bearingsEntityRegistry();
    final grove = Grove(
      registry: registry,
      transport: MemoryGroveTransport(registry),
    );
    final container = ProviderContainer(
      overrides: [
        currentEventProvider.overrideWith(_CurrentEvent.new),
        sharedPreferencesProvider.overrideWithValue(prefs),
        bearingsGroveProvider.overrideWithValue(grove),
      ],
    );
    final picklist = await container
        .read(picklistLibraryProvider.notifier)
        .create(
          title: 'Rankings',
          emoji: '🐻',
          teamKeys: ['frc2046', 'frc254'],
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PicklistEditorPage(picklistId: picklist.id)),
      ),
    );
    await tester.pumpAndSettle();

    Finder draggable(String key) => find.byWidgetPredicate(
      (widget) => widget is Draggable<String> && widget.data == key,
    );
    final firstCard = tester.getRect(draggable('frc2046'));
    final blankSpace = Offset(firstCard.right - 72, firstCard.center.dy);
    final grip = tester.getCenter(find.byTooltip('Team actions').first);
    final firstTeamNumber = find.text('2046');

    final mouse = TestPointer(200, PointerDeviceKind.mouse, 12);
    await tester.sendEventToBinding(mouse.addPointer(location: blankSpace));
    await tester.pump();
    for (final position in [blankSpace, grip]) {
      final touch = await tester.startGesture(position);
      await tester.pump(const Duration(milliseconds: 249));
      expect(firstTeamNumber, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(firstTeamNumber, findsNWidgets(2));
      await touch.cancel();
      await tester.pumpAndSettle();
    }
    await tester.sendEventToBinding(mouse.removePointer());

    for (final position in [blankSpace, grip]) {
      final click = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
      );
      await click.moveBy(const Offset(-12, 0));
      await tester.pump();
      expect(firstTeamNumber, findsNWidgets(2));
      await click.cancel();
      await tester.pumpAndSettle();
    }

    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      await tester.tapAt(grip, kind: kind);
      await tester.pumpAndSettle();
      expect(find.text('Remove from list'), findsOneWidget);
      await tester.tapAt(const Offset(900, 500));
      await tester.pumpAndSettle();
      expect(find.text('Remove from list'), findsNothing);
    }

    final destination =
        tester.getRect(draggable('frc254')).bottomCenter + const Offset(0, 12);
    final drag = await tester.startGesture(
      blankSpace,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(0, 20));
    await tester.pumpAndSettle();
    await drag.moveTo(destination);
    await tester.pumpAndSettle();
    await drag.up();
    await tester.pumpAndSettle();
    expect(container.read(picklistLibraryProvider).single.teamKeys, [
      'frc254',
      'frc2046',
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
    await grove.close();
  });
}
