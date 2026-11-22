import 'package:gamepack/gamepack.dart';
import 'package:test/test.dart';

const _event = '2028demo';
const _one = '${_event}_qm9';
const _two = '${_event}_qm10';
const _scouted = (graph: gamePackFieldNamespace, output: 'match.pieces');
const _official = (graph: gamePackFieldNamespace, output: 'official_pieces');
const _scaled = (graph: gamePackFieldNamespace, output: 'adjusted_pieces');
const _average = (graph: gamePackFieldNamespace, output: 'average_pieces');
const _robot = (graph: gamePackFieldNamespace, output: 'official_robot');
const _formula = (graph: gamePackFieldNamespace, output: 'custom_formula');
const _number = GamePackType.number;

void main() {
  test('resolves each source by match, team and alliance and reuses it in a custom graph', () {
    final original = _pack();
    final pack = GamePackDefinition.fromJson(original.toJson());
    final runtime = GamePackAnalysisSession(
      analysis: pack.analysis,
      event: _event,
      trace: true,
      sources: {
        'observations': GamePackValue.list([
          _report('first', _one, 'frc2046', 8, 1),
          _report('second', _one, 'frc2046', 10, 2),
          _report('partner', _one, 'frc6443', 5, 1),
          _report('blue', _one, 'frc1678', 13, 1),
          _report('other_match', _two, 'frc2046', 20, 3),
        ]),
        'tba': GamePackValue.list([
          _revision(_two, 10, red: null, blue: 41),
          _revision(_one, 9, red: 30, blue: 100),
        ]),
      },
    );
    const matchTeam = GamePackScope(
      event: _event,
      match: _one,
      team: 'frc2046',
    );
    const blue = GamePackScope(event: _event, match: _one, team: 'frc1678');
    const team = GamePackScope(event: _event, team: 'frc2046');
    GamePackValue value(GameGraphOutputRef field, GamePackScope scope) =>
        runtime.evaluate(field, scope: scope).result;

    expect(value(_scouted, matchTeam).data, 10);
    expect(value(_official, matchTeam).data, 30);
    expect(value(_official, blue).data, 100);
    expect(value(_robot, matchTeam).data, 2);
    expect(value(_robot, blue).data, 4);
    expect(value(_scaled, matchTeam).data, 20);
    expect(value(_scaled, blue).data, 100);
    expect(
      value(_average, team).data,
      20,
    ); // match 10 falls back to the raw 20.
    expect(value(_formula, team).data, 40);
    expect(
      runtime.previewNode(_scaled.output, 'result', matchTeam).explanation,
      '10 × (30 official ÷ 15 reported) = 20',
    );
    expect(
      runtime.previewNode(_average.output, 'result', team).explanation,
      '2 matches used · 20, 20',
    );

    expect(value(_official, team).state, GamePackValueState.missing);
    expect(
      value(_average, team).allEvidence.map((entry) => entry.id),
      containsAll(['second', 'partner', 'other_match', _one, _two]),
    );
    expect(
      value(_scaled, matchTeam).allEvidence.map((entry) => entry.id),
      isNot(contains('first')),
    );
    final chart =
        value(gamePackFieldRef('history'), team).data as List<GamePackValue>;
    expect(chart.map((row) => row.atPath('match').data), ['9', '10']);
    expect(chart.map((row) => row.atPath('value').data), [20, 20]);
    expect(pack.toJson()['program'], isNull);
    expect(
      () => GamePackDefinition.fromJson({...pack.toJson(), 'formatVersion': 5}),
      throwsFormatException,
    );
  });

  test('honors report policy even when the schedule disagrees with submitted station', () {
    final pack = _pack(reportChoice: GamePackReportChoice.earliest);
    final runtime = GamePackAnalysisSession(
      analysis: pack.analysis,
      event: _event,
      sources: {
        'observations': GamePackValue.list([
          _report('first', _one, 'frc2046', 8, 1),
          _report('second', _one, 'frc2046', 10, 2),
        ]),
        'tba': GamePackValue.list([_revision(_one, 9, red: 30, blue: 100)]),
      },
    );
    const scope = GamePackScope(
      event: _event,
      match: _one,
      team: 'frc2046',
      alliance: 'blue',
      station: 5,
    );
    expect(runtime.evaluate(_scouted, scope: scope).result.data, 8);
    expect(runtime.evaluate(_official, scope: scope).result.data, 30);
    expect(
      runtime.evaluate(gamePackFieldRef('station'), scope: scope).result.data,
      1,
    );
  });

  test('scale steps reject a separate adjustment target', () {
    expect(
      () => _pack(
        calculations: [
          GamePackCalculation.recipe(
            id: _scaled.output,
            label: 'Adjusted pieces',
            operation: GamePackRecipe.scale,
            grain: GamePackGrain.teamMatch,
            inputs: {
              'scouted': _scouted,
              'official': _official,
              'target': _robot,
            },
          ),
        ],
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'reason',
          contains('unsupported input "target"'),
        ),
      ),
    );
  });

  test(
    'rejects cycles across calculations and wires inside one calculation',
    () {
      expect(
        () => _pack(
          calculations: [
            GamePackCalculation.recipe(
              id: _average.output,
              label: 'Cycle',
              operation: GamePackRecipe.add,
              grain: GamePackGrain.team,
              inputs: {'value': _formula},
            ),
          ],
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('cycle'),
          ),
        ),
      );
      expect(
        () => _pack(
          calculations: [
            GamePackCalculation(
              id: _average.output,
              label: 'Broken wiring',
              result: 'two',
              nodes: [
                GamePackStepNode(
                  id: 'one',
                  operation: GamePackRecipe.add,
                  grain: GamePackGrain.team,
                  inputs: {'value': 'two'},
                ),
                GamePackStepNode(
                  id: 'two',
                  operation: GamePackRecipe.add,
                  grain: GamePackGrain.team,
                  inputs: {'value': 'one'},
                ),
              ],
            ),
          ],
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('cycle'),
          ),
        ),
      );
    },
  );

  test('reports the incompatible display scope at publish time', () {
    expect(
      () => _pack(
        sorts: [
          const GamePackTeamSort(
            id: 'wrong_scope',
            label: 'Pieces',
            output: _scouted,
          ),
        ],
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'reason',
          contains('requires team in match'),
        ),
      ),
    );
  });

  test(
    'evaluates a multi-step calculation with reproducible independent trials',
    () {
      const scope = GamePackGrain.event;
      final graph = GamePackCalculation(
        id: _average.output,
        label: 'Trials',
        result: 'trial',
        nodes: [
          GamePackStepNode(
            id: 'chance',
            operation: GamePackRecipe.constant,
            grain: scope,
            comparisonValue: .5,
          ),
          GamePackStepNode(
            id: 'distribution',
            operation: GamePackRecipe.bernoulli,
            grain: scope,
            inputs: {'value': 'chance'},
          ),
          GamePackStepNode(
            id: 'sample',
            operation: GamePackRecipe.sample,
            grain: scope,
            inputs: {'value': 'distribution'},
          ),
          GamePackStepNode(
            id: 'trial',
            operation: GamePackRecipe.simulate,
            grain: scope,
            inputs: {'value': 'sample'},
          ),
        ],
      );
      final pack = GamePackAnalysis(
        fields: const [],
        forms: const [],
        calculations: [graph],
      );
      Object? simulate(int seed) => GamePackAnalysisSession(
        analysis: pack,
        event: _event,
        sources: const {},
        seed: seed,
      ).evaluate(_average).result.plainValue;
      final result = simulate(42) as List<Object?>;
      expect(result, hasLength(100));
      expect(result.toSet(), {true, false});
      expect(simulate(42), result);
      expect(simulate(43), isNot(result));
    },
  );
}

GamePackDefinition _pack({
  GamePackReportChoice reportChoice = GamePackReportChoice.latest,
  List<GamePackCalculation>? calculations,
  List<GamePackTeamSort> sorts = const [],
}) => GamePackDefinition.typed(
  name: 'Future season',
  fields: const [GamePackField('pieces', 'Pieces', type: GamePackType.integer)],
  forms: [
    GamePackForm(
      id: 'match',
      label: 'Match scouting',
      kind: GamePackFormKind.match,
      pages: [
        GamePackFormPage.scrolling(
          id: 'score',
          label: 'Score',
          sections: [
            GamePackSection.controls(
              id: 'pieces',
              label: 'Pieces',
              controls: [
                const GamePackControl(
                  field: 'pieces',
                  type: GamePackControlType.stepper,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
  reportChoices: {'match': reportChoice},
  tbaFields: [
    GamePackTbaField(
      id: _official.output,
      label: 'Official Pieces',
      grain: GamePackGrain.allianceMatch,
      type: _number,
      numericText: true,
      paths: [
        'score_breakdown.{alliance}.pieces',
        'score_breakdown.{alliance}.oldPieces',
      ],
    ),
    GamePackTbaField(
      id: _robot.output,
      label: 'Official Robot Pieces',
      grain: GamePackGrain.teamMatch,
      type: _number,
      paths: ['score_breakdown.{alliance}.{robot}Pieces'],
    ),
  ],
  calculations: [
    ...(calculations ??
        [
          GamePackCalculation.recipe(
            id: _scaled.output,
            label: 'Adjusted pieces',
            operation: GamePackRecipe.scale,
            grain: GamePackGrain.teamMatch,
            inputs: {'scouted': _scouted, 'official': _official},
          ),
          GamePackCalculation.recipe(
            id: _average.output,
            label: 'Average pieces',
            operation: GamePackRecipe.average,
            grain: GamePackGrain.team,
            inputs: {'value': _scaled},
          ),
          GamePackCalculation.recipe(
            id: 'history',
            label: 'History',
            operation: GamePackRecipe.rows,
            grain: GamePackGrain.team,
            rowGrain: GamePackGrain.teamMatch,
            inputs: {
              'match': gamePackFieldRef('match_label'),
              'value': _scaled,
            },
          ),
        ]),
    GamePackCalculation(
      id: _formula.output,
      label: 'Double the average',
      result: 'double',
      nodes: [
        GamePackInputNode(id: 'input', field: _average.output),
        GamePackStepNode(
          id: 'double',
          operation: GamePackRecipe.add,
          grain: GamePackGrain.team,
          inputs: {'first': 'input', 'second': 'input'},
        ),
      ],
    ),
  ],
  results: GamePackResults(sorts: sorts),
);

GamePackValue _report(
  String id,
  String match,
  String team,
  int pieces,
  int time,
) => GamePackValue.of({
  'id': id,
  'event': _event,
  'match': match,
  'team': team,
  'form': 'match',
  'kind': 'match',
  'captured_at': time,
  'alliance': 'blue',
  'station': 5,
  'answers': {'pieces': pieces},
}).withEvidence([(type: 'observation', id: id)]);

GamePackValue _revision(String match, int number, {int? red, int? blue}) =>
    GamePackValue.of({
      'event': _event,
      'match': match,
      'payload': {
        'match_number': number,
        'comp_level': 'qm',
        'alliances': {
          'red': {
            'team_keys': ['frc6443', 'frc2046'],
          },
          'blue': {
            'team_keys': ['frc1678'],
          },
        },
        'score_breakdown': {
          'red': {if (red != null) 'oldPieces': '$red', 'robot2Pieces': 2},
          'blue': {if (blue != null) 'pieces': blue, 'robot1Pieces': 4},
        },
      },
    }).withEvidence([(type: 'tba', id: match)]);
