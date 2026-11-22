import 'package:gamepack/gamepack.dart';
import 'package:test/test.dart';

const _event = '2028demo';
const _team = 'frc2046';
const _first = '${_event}_qm1';
const _pieces = 'match.pieces';
const _docked = 'match.docked';

void main() {
  test('sorts and filters have one shared schema', () {
    const sort = GamePackTeamSort(
      id: 'number',
      label: 'Team number',
      output: (graph: gamePackFieldNamespace, output: 'team_number'),
    );
    const filter = GamePackTeamFilter(
      id: 'reported',
      label: 'Has data',
      output: (graph: gamePackFieldNamespace, output: 'team_number'),
      test: GamePackFilterTest.reported,
    );
    final results = GamePackResults(sorts: [sort], filters: [filter]);
    final document = results.toJson();
    expect(GamePackResults.fromJson(document).toJson(), document);
    expect(sort.toJson(), isNot(contains('list')));
    expect(filter.toJson(), isNot(contains('list')));
    expect(
      () => GamePackTeamSort.fromJson({...sort.toJson(), 'list': 'teamLookup'}),
      throwsFormatException,
    );
    expect(
      () =>
          GamePackTeamFilter.fromJson({...filter.toJson(), 'list': 'picklist'}),
      throwsFormatException,
    );
  });

  test('automatic match summaries work in calculations and worksheets', () {
    final raw = gamePackFieldRef(_pieces);
    final average = gamePackRollupRef(_pieces, GamePackRollup.average);
    final percent = gamePackRollupRef(_docked, GamePackRollup.yesPercent);
    final sheet = GamePackWorksheet(
      id: 'matches',
      name: 'Matches',
      rows: GamePackSheetRows.matches,
      columns: [
        GamePackWorksheetColumn(id: 'pieces', heading: 'Pieces', output: raw),
        GamePackWorksheetColumn(
          id: 'average',
          heading: 'Event average',
          output: average,
        ),
        GamePackWorksheetColumn(
          id: 'docked',
          heading: 'Docked (% Yes)',
          output: percent,
        ),
      ],
    );

    final pack = GamePackDefinition.typed(
      name: 'Results season',
      fields: const [
        GamePackField('pieces', 'Pieces', type: GamePackType.integer),
        GamePackField('docked', 'Docked', type: GamePackType.boolean),
      ],
      forms: [
        GamePackForm(
          id: 'match',
          label: 'Match scouting',
          kind: GamePackFormKind.match,
          pages: [
            GamePackFormPage.scrolling(
              id: 'tele',
              label: 'Teleop',
              sections: [
                GamePackSection.controls(
                  id: 'actions',
                  label: 'Actions',
                  controls: const [
                    GamePackControl(
                      field: 'pieces',
                      type: GamePackControlType.stepper,
                    ),
                    GamePackControl(
                      field: 'docked',
                      type: GamePackControlType.toggle,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
      calculations: [
        GamePackCalculation.recipe(
          id: 'difference',
          label: 'Difference from event average',
          operation: GamePackRecipe.subtract,
          grain: GamePackGrain.teamMatch,
          inputs: {'left': raw, 'right': average},
        ),
      ],
      results: GamePackResults(sheets: [sheet]),
    );

    final json = pack.toJson();
    final reloaded = GamePackDefinition.fromJson(json);
    expect(reloaded.toJson(), json);
    expect(sheet.columns[1].toJson(), {
      'id': 'average',
      'heading': 'Event average',
      'result': _pieces,
      'rollup': 'average',
    });
    expect(reloaded.analysis.calculations, hasLength(1));
    expect(
      reloaded.analysis.calculationById(average.output)!.nodes,
      hasLength(2),
    );
    expect(reloaded.analysis.resultInfo(percent).grain, GamePackGrain.team);

    final runtime = GamePackAnalysisSession(
      analysis: reloaded.analysis,
      event: _event,
      sources: {
        'observations': GamePackValue.list([
          _report(1, {'pieces': 0, 'docked': false}),
          _report(2, {'pieces': 10, 'docked': true}),
          _report(3, {}),
          _report(4, {'pieces': 42}, team: 'frc42'),
        ]),
      },
    );
    const match = GamePackScope(event: _event, team: _team, match: _first);
    expect(runtime.evaluate(raw, scope: match).result.data, 0);
    expect(
      runtime
          .evaluate(gamePackFieldRef('difference'), scope: match)
          .result
          .data,
      -5,
    );
    expect(
      reloaded.results.sheets.single
          .values(runtime, teams: {_team})
          .map((row) => row.map((cell) => cell.plainValue).toList()),
      [
        [0, 5, 50],
        [10, 5, 50],
        [null, 5, 50],
      ],
    );
    final qualifying = GamePackTeamFilter(
      id: 'docking',
      label: 'Docked at least half the time',
      output: percent,
      test: GamePackFilterTest.atLeast,
      value: 50,
    );
    final yes = runtime.evaluate(percent, scope: match).result;
    final missing = runtime
        .evaluate(
          percent,
          scope: const GamePackScope(event: _event, team: 'frc42'),
        )
        .result;
    expect(qualifying.matches(yes), isTrue);
    expect(qualifying.matches(missing), isFalse);
    expect(
      compareGamePackTeamValues(yes, missing, ascending: true),
      lessThan(0),
    );
    expect(
      compareGamePackTeamValues(yes, missing, ascending: false),
      lessThan(0),
    );
  });
}

GamePackValue _report(
  int match,
  Map<String, Object> answers, {
  String team = _team,
}) => GamePackValue.of({
  'id': 'report_$match',
  'event': _event,
  'match': '${_event}_qm$match',
  'team': team,
  'form': 'match',
  'kind': 'match',
  'alliance': 'red',
  'station': 1,
  'captured_at': match,
  'answers': answers,
});
