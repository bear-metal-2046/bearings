import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';
import 'package:ui/widgets/forms/gamepack_form_view.dart';

void main() {
  testWidgets(
    'all grid controls fill their cells without scrolling at every tested size',
    (tester) async {
      const options = ['First option', 'Second option with a longer label'];
      const listType = GamePackType.list(GamePackType.text);
      const fields = {
        'number': GamePackField('number', 'Numeric entry'),
        'stepper': GamePackField(
          'stepper',
          'Stepper',
          type: GamePackType.integer,
        ),
        'counter': GamePackField(
          'counter',
          'Counter',
          type: GamePackType.integer,
        ),
        'slider': GamePackField('slider', 'Slider', minimum: 0, maximum: 10),
        'toggle': GamePackField('toggle', 'Toggle', type: GamePackType.boolean),
        'choice': GamePackField(
          'choice',
          'Dropdown',
          type: GamePackType.text,
          choices: options,
        ),
        'segmented': GamePackField(
          'segmented',
          'Segmented',
          type: GamePackType.text,
          choices: options,
        ),
        'multiChoice': GamePackField(
          'multiChoice',
          'Multiple choices',
          type: listType,
          choices: options,
        ),
        'ranking': GamePackField(
          'ranking',
          'Ranking',
          type: listType,
          choices: options,
        ),
        'text': GamePackField('text', 'Text entry', type: GamePackType.text),
        'multiline': GamePackField(
          'multiline',
          'Long text',
          type: GamePackType.text,
        ),
      };
      final form = GamePackForm(
        id: 'test',
        label: 'Test form',
        kind: GamePackFormKind.match,
        pages: [
          GamePackFormPage.grid(
            id: 'grid',
            label: 'Grid',
            columns: 3,
            rows: 4,
            controls: [
              for (final (index, type) in GamePackControlType.values.indexed)
                GamePackControl(
                  field: type.name,
                  type: type,
                  placement: GamePackPlacement(index % 3, index ~/ 3, 1, 1),
                ),
            ],
          ),
        ],
      );
      Map<String, Object?> answers = {};
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => GamePackFormView(
                fields: fields,
                form: form,
                answers: answers,
                onChanged: (next) => setState(() => answers = next),
              ),
            ),
          ),
        ),
      );
      const sizes = [
        Size(900, 1000),
        Size(300, 360),
        Size(240, 192),
        Size(812, 320),
      ];
      for (final size in sizes) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        expect(find.byType(Scrollable), findsNothing);
        expect(find.byType(BearingsCapsuleBar<int>), findsNothing);
        for (final (index, type) in GamePackControlType.values.indexed) {
          final cell = find.byKey(ValueKey(('tile', type.name)));
          final rect = tester.getRect(cell);
          expect(rect.left, closeTo((index % 3) * size.width / 3, .001));
          expect(rect.top, closeTo((index ~/ 3) * size.height / 4, .001));
          expect(rect.width, closeTo(size.width / 3, .001));
          expect(rect.height, closeTo(size.height / 4, .001));
          expect(find.text(fields[type.name]!.label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }

      await tester.binding.setSurfaceSize(const Size(900, 1000));
      await tester.pumpAndSettle();
      Rect cell(String name) =>
          tester.getRect(find.byKey(ValueKey(('tile', name))));
      // Tap the face away from its label to exercise the scouting hit target.
      final toggle = cell('toggle');
      await tester.tapAt(toggle.bottomLeft + const Offset(8, -8));
      await tester.pump();
      expect(answers['toggle'], true);
      await tester.tapAt(toggle.bottomLeft + const Offset(8, -8));
      await tester.pump();
      expect(answers['toggle'], false);
      final counter = cell('counter');
      await tester.tapAt(counter.topLeft + const Offset(8, 16));
      await tester.pump();
      expect(answers['counter'], 1);
      await tester.tap(find.text('-1').last);
      await tester.pump();
      expect(answers['counter'], 0);

      final dropdown = cell('choice');
      await tester.tapAt(dropdown.bottomRight - const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(PopupMenuItem<String>, options.first),
      );
      await tester.pumpAndSettle();
      expect(answers['choice'], options.first);

      final segment = find.descendant(
        of: find.byKey(const ValueKey(('tile', 'segmented'))),
        matching: find.text(options.first),
      );
      await tester.tap(segment);
      await tester.pump();
      await tester.tap(segment);
      await tester.pump();
      expect(answers['segmented'], options.first);
      expect(find.byTooltip('Toggle answer options'), findsNothing);

      final number = cell('number');
      await tester.tapAt(number.bottomRight - const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '42');
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(answers['number'], 42);
      expect(find.byType(Scrollable), findsNothing);
      await tester.tapAt(number.bottomRight - const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answers['number'], 42);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'applies and round-trips appearance overrides on both page types',
    (tester) async {
      const fields = {
        'grid_auto': GamePackField(
          'grid_auto',
          'Automatic grid',
          type: GamePackType.boolean,
        ),
        'grid_inline': GamePackField(
          'grid_inline',
          'Inline grid',
          type: GamePackType.boolean,
        ),
        'list_auto': GamePackField(
          'list_auto',
          'Automatic list',
          isRequired: false,
          type: GamePackType.boolean,
        ),
        'list_tile': GamePackField(
          'list_tile',
          'Tiled list',
          isRequired: false,
          type: GamePackType.boolean,
        ),
      };
      GamePackControl control(
        String field, {
        GamePackPlacement? placement,
        String? appearance,
      }) {
        final decoded = GamePackControl.fromJson({
          'field': field,
          'type': 'toggle',
          if (placement != null) 'placement': placement.toJson(),
          'appearance': ?appearance,
        });
        expect(decoded.toJson()['appearance'], appearance);
        return decoded;
      }

      final form = GamePackForm(
        id: 'appearance',
        label: 'Appearance',
        kind: GamePackFormKind.match,
        pages: [
          GamePackFormPage.grid(
            id: 'grid',
            label: 'Grid',
            columns: 2,
            rows: 1,
            controls: [
              control(
                'grid_auto',
                placement: const GamePackPlacement(0, 0, 1, 1),
              ),
              control(
                'grid_inline',
                placement: const GamePackPlacement(1, 0, 1, 1),
                appearance: 'inline',
              ),
            ],
          ),
          GamePackFormPage.scrolling(
            id: 'list',
            label: 'List',
            sections: [
              GamePackSection.controls(
                id: 'controls',
                label: 'Controls',
                controls: [
                  control('list_auto'),
                  control('list_tile', appearance: 'tile'),
                ],
              ),
            ],
          ),
        ],
      );
      Map<String, Object?> answers = {};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => GamePackFormView(
                fields: fields,
                form: form,
                answers: answers,
                onChanged: (next) => setState(() => answers = next),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('Unanswered'), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      await tester.tap(find.text('Yes'));
      await tester.pump();
      await tester.tap(find.text('Yes'));
      await tester.pump();
      expect(answers['grid_inline'], true);
      expect(find.byTooltip('Inline grid answer options'), findsNothing);
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('Unanswered'), findsOneWidget);
      expect(find.byType(Scrollable), findsOneWidget);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiled list'));
      await tester.pumpAndSettle();
      expect(answers['list_auto'], true);
      expect(answers['list_tile'], true);
      for (final label in ['Automatic list', 'Tiled list']) {
        await tester.tap(find.byTooltip('$label answer options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear answer'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('$label answer options'), findsNothing);
      }
      expect(answers.containsKey('list_auto'), false);
      expect(answers.containsKey('list_tile'), false);

      expect(tester.takeException(), isNull);
    },
  );
}
