import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('a standalone selector works in a row with keyboard focus', (
    tester,
  ) async {
    int? activated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              BearingsCapsuleSelector(
                selected: 1,
                onSelected: (index) => activated = index,
                segments: const [
                  BearingsCapsuleSegment(Text('First')),
                  BearingsCapsuleSegment(Text('Second')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(BearingsCapsuleSelector)).width, 120);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, 0);
  });

  testWidgets('scrolls overflowing destinations and reactivates selection', (
    tester,
  ) async {
    final activations = <int>[];
    var selected = 9;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: StatefulBuilder(
                builder: (context, setState) => BearingsCapsuleBar<int>(
                  selected: selected,
                  onActivated: (value) {
                    activations.add(value);
                    setState(() => selected = value);
                  },
                  destinations: [
                    for (var index = 0; index < 10; index++)
                      BearingsCapsuleDestination(
                        value: index,
                        label: 'Page $index',
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byType(BearingsCapsuleBar<int>);
    final first = find.text('Page 0');
    final last = find.text('Page 9');
    expect(last.hitTestable(), findsOneWidget);
    expect(first.hitTestable(), findsNothing);

    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(activations, [9]);

    for (var step = 0; step < 3; step++) {
      await tester.drag(bar, const Offset(180, 0));
      await tester.pumpAndSettle();
    }
    expect(activations, [9]);
    await tester.tap(first.hitTestable());
    await tester.pumpAndSettle();
    expect(activations, [9, 0]);
    expect(tester.widget<BearingsCapsuleBar<int>>(bar).selected, 0);
  });
}
