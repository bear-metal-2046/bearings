import 'package:beariscope/pages/gamepacks/builder/form_grid.dart';
import 'package:beariscope/pages/gamepacks/builder/question_editor.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

void main() {
  testWidgets('the question editor saves and reopens a control appearance', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const field = GamePackField('scored', 'Scored', type: GamePackType.integer);
    const placement = GamePackPlacement(0, 0, 1, 1);
    var control = const GamePackControl(
      field: 'scored',
      type: GamePackControlType.counter,
      placement: placement,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final edit = await editGamePackQuestion(
                  context,
                  ids: {field.id},
                  field: field,
                  control: control,
                  page: GamePackFormPage.grid(
                    id: 'scouting',
                    label: 'Scouting',
                    columns: 2,
                    rows: 1,
                    controls: [control],
                  ),
                  placement: placement,
                  conditionFields: const [],
                );
                if (edit != null) control = edit.control;
              },
              child: const Text('Edit control'),
            ),
          ),
        ),
      ),
    );
    final appearance = find.byType(BearingsSelect<GamePackControlAppearance>);
    await tester.tap(find.text('Edit control'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic (Tile)'), findsOneWidget);
    await tester.tap(appearance);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save question'));
    await tester.pumpAndSettle();

    expect(control.appearance, GamePackControlAppearance.inline);
    expect(control.type, GamePackControlType.counter);
    expect(
      controlWithPlacement(control, null).toJson()['appearance'],
      'inline',
    );

    await tester.tap(find.text('Edit control'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: appearance, matching: find.text('Inline')),
      findsOneWidget,
    );
  });
}
