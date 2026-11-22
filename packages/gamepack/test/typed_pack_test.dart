import 'package:gamepack/gamepack.dart';
import 'package:test/test.dart';

void main() {
  test('round trips typed form placement, conditional required answers, and output bindings', () {
    final pack = _pack();
    final reopened = GamePackDefinition.fromJson(pack.toJson());
    expect(reopened.toJson()['formatVersion'], 6);
    final form = reopened.formById('match');
    expect(form.defaults(reopened.fieldById), {'attempted': false});
    expect(form.visibleFields({'attempted': false}), {'attempted'});
    expect(form.pages.single.gridControls.last.placement?.y, 1);
    final unanswered = reopened.decodeAnswers({
      'attempted': true,
      'climb': {'state': 'unknown'},
    });
    expect(unanswered['attempted']!.data, true);
    expect(unanswered['climb']!.state, GamePackValueState.unknown);
    expect(
      reopened.decodeAnswers({'attempted': false})['attempted']!.data,
      false,
    );
    expect(
      () => reopened.validateAnswers({'attempted': true}),
      throwsFormatException,
    );
    expect(
      () => reopened.validateAnswers({'attempted': true, 'climb': 'typo'}),
      throwsFormatException,
    );
    expect(
      () => reopened.validateAnswers({'attempted': false, 'climb': 'high'}),
      throwsFormatException,
    );
    expect(reopened.results.sorts.single.output, gamePackFieldRef('average'));
  });

  test('rejects invalid control types and mismatched view outputs during validation', () {
    expect(
      () => _pack(climbControl: GamePackControlType.toggle),
      throwsFormatException,
    );
    expect(() => _pack(incompatibleSort: true), throwsFormatException);
  });

  test(
    'ignores empty builder form placeholders when compiling a definition',
    () {
      final document = _pack().toJson();
      final forms = document['forms'] as List;
      document['forms'] = [
        ...forms,
        GamePackForm(
          id: 'pit',
          label: 'Pit scouting',
          kind: GamePackFormKind.pit,
          pages: [
            GamePackFormPage.scrolling(
              id: 'questions',
              label: 'Questions',
              sections: [
                GamePackSection.controls(
                  id: 'questions',
                  label: 'Questions',
                  controls: const [],
                ),
              ],
            ),
          ],
        ).toJson(),
      ];

      final reopened = GamePackDefinition.fromJson(document);

      expect(reopened.forms.map((form) => form.id), ['match']);
    },
  );
}

GamePackDefinition _pack({
  GamePackControlType climbControl = GamePackControlType.segmented,
  bool incompatibleSort = false,
}) => GamePackDefinition.typed(
  name: 'Spring',
  season: 2027,
  fields: const [
    GamePackField(
      'attempted',
      'Attempted',
      type: GamePackType.boolean,
      defaultValue: false,
    ),
    GamePackField(
      'climb',
      'Climb',
      type: GamePackType.text,
      choices: ['low', 'high'],
      allowUnknown: true,
    ),
  ],
  forms: [
    GamePackForm(
      id: 'match',
      label: 'Match scouting',
      kind: GamePackFormKind.match,
      pages: [
        GamePackFormPage.grid(
          id: 'finish',
          label: 'Finish',
          columns: 4,
          rows: 6,
          controls: [
            const GamePackControl(
              field: 'attempted',
              type: GamePackControlType.toggle,
              placement: GamePackPlacement(0, 0, 2, 1),
            ),
            GamePackControl(
              field: 'climb',
              type: climbControl,
              placement: const GamePackPlacement(0, 1, 4, 2),
              visibleWhen: const GamePackVisibility('attempted', true),
            ),
          ],
        ),
      ],
    ),
  ],
  calculations: [
    GamePackCalculation.recipe(
      id: 'average',
      label: 'Climb average',
      operation: GamePackRecipe.constant,
      grain: GamePackGrain.event,
      inputs: const {},
      comparisonValue: 1,
    ),
  ],
  results: GamePackResults(
    sorts: [
      GamePackTeamSort(
        id: 'climb_average',
        label: 'Climb average',
        output: gamePackFieldRef(incompatibleSort ? 'match.climb' : 'average'),
      ),
    ],
  ),
);
