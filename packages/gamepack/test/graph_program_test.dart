import 'package:gamepack/gamepack.dart';
import 'package:test/test.dart';

const _number = GamePackType.number;
const _integer = GamePackType.integer;
const _text = GamePackType.text;
const _boolean = GamePackType.boolean;

GameGraphNode _node(
  String id,
  GameGraphOperation operation, {
  Map<String, String> inputs = const {},
  Map<String, Object?> options = const {},
}) => GameGraphNode(
  id: id,
  operation: operation,
  inputs: inputs,
  options: options,
);

GameGraphNode _parameter(String id) =>
    _node(id, GameGraphOperation.parameter, options: {'name': id});

GameGraphNode _source(String id) =>
    _node(id, GameGraphOperation.source, options: {'name': id});

GameGraphNode _literal(String id, GamePackType type, Object value) => _node(
  id,
  GameGraphOperation.literal,
  options: {'type': type.toJson(), 'value': value},
);

GameGraphNode _field(String id, String from, String path) => _node(
  id,
  GameGraphOperation.field,
  inputs: {'value': from},
  options: {'path': path},
);

GameGraph _graph(
  String id,
  List<GameGraphNode> nodes,
  GamePackType result, {
  Map<String, GamePackType> parameters = const {},
}) => GameGraph(
  id: id,
  parameters: parameters,
  nodes: nodes,
  outputs: {'result': GameGraphOutput(nodes.last.id, result)},
);

void main() {
  test('batch previews preserve seeded samples and show independent draft branches', () {
    final broken = _graph('broken', [
      _node('incomplete', GameGraphOperation.add, inputs: {'left': 'missing'}),
    ], _number);
    final graph = _graph('draft', [
      _literal('zero', _integer, 0),
      _literal('one', _integer, 1),
      _literal('chance', _number, 0.38),
      _node(
        'distribution',
        GameGraphOperation.bernoulli,
        inputs: {'chance': 'chance'},
      ),
      for (final name in ['draw_a', 'draw_b'])
        _node(
          name,
          GameGraphOperation.sample,
          inputs: {'distribution': 'distribution'},
        ),
      _node(
        'broken_call',
        GameGraphOperation.call,
        options: {'graph': 'broken', 'output': 'result'},
      ),
      _node('incomplete', GameGraphOperation.add, inputs: {'left': 'zero'}),
      _node(
        'total',
        GameGraphOperation.add,
        inputs: {'left': 'zero', 'right': 'one'},
      ),
    ], _number);
    final inspector = GameGraphInspector(
      graph: graph,
      graphs: [graph, broken],
      sourceTypes: {},
    );
    final preview = inspector.previewAll(seed: 37);
    expect(preview.values['zero']!.data, 0);
    expect(preview.values['total']!.data, 1);
    for (final id in ['draw_a', 'draw_b']) {
      expect(
        preview.values[id]!.data,
        inspector.preview(id, seed: 37).result.data,
      );
    }
    expect(preview.issues.keys, containsAll(['broken_call', 'incomplete']));
    expect(inspector.previewAll(workLimit: 1).issues, contains('total'));
  });

  test('compiles cross-graph calls and retains only the evaluated branch and its evidence', () {
    final identity = _graph(
      'identity',
      [_parameter('count')],
      _number,
      parameters: {'count': _number},
    );
    final graph = _graph('select', [
      _source('condition'),
      _source('scout'),
      _source('tba'),
      _node(
        'official',
        GameGraphOperation.call,
        inputs: {'count': 'tba'},
        options: {'graph': 'identity', 'output': 'result'},
      ),
      _node(
        'preferred',
        GameGraphOperation.ifElse,
        inputs: {'condition': 'condition', 'then': 'scout', 'else': 'official'},
      ),
    ], _number);
    final program = GameGraphProgram(
      graphs: [graph, identity],
      sourceTypes: {'condition': _boolean, 'scout': _number, 'tba': _number},
    );
    final restored = GameGraphProgram.fromJson(program.toJson());
    const scout = (type: 'scouting.observation', id: '042');
    const tba = (type: 'external.tba_revision', id: 'a1');
    final data = {
      'condition': GamePackValue.of(false),
      'scout': GamePackValue.of(7).withEvidence([scout]),
      'tba': GamePackValue.of(0).withEvidence([tba]),
    };
    final result = restored.evaluate((
      graph: 'select',
      output: 'result',
    ), sources: data);
    expect(result.result.data, 0);
    expect(result.result.allEvidence.toSet(), {tba});
    expect(result.nodes, isNot(contains('scout')));
    expect(restored.nodeType('select', 'preferred'), _number);
    expect(
      restored
          .inspect('select', 'scout', sources: data)
          .result
          .allEvidence
          .toSet(),
      {scout},
    );
    for (final value in [
      GamePackValue.missing,
      GamePackValue.unknown,
      GamePackValue.notApplicable,
    ]) {
      final unscored = restored.evaluate(
        (graph: 'select', output: 'result'),
        sources: {...data, 'tba': value},
      );
      expect(unscored.result.state, value.state);
    }
  });

  test('rejects incompatible ports, hidden output references, and inter-graph cycles', () {
    final wrong = _graph('wrong', [
      _literal('count', _integer, 1),
      _node('is_valid', GameGraphOperation.not, inputs: {'value': 'count'}),
    ], _boolean);
    expect(() => GameGraphProgram(graphs: [wrong]), throwsFormatException);

    GameGraph invokes(String id, String target, String output) => _graph(id, [
      _node(
        'invoke',
        GameGraphOperation.call,
        options: {'graph': target, 'output': output},
      ),
    ], _number);
    final a = invokes('a', 'b', 'result');
    final b = invokes('b', 'a', 'result');
    expect(
      () => GameGraphProgram(graphs: [a, b]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('cycle'),
        ),
      ),
    );
    final onlyExport = _graph('only_export', [
      _literal('private', _number, 5),
    ], _number);
    expect(
      () => GameGraphProgram(
        graphs: [onlyExport, invokes('bad', 'only_export', 'private')],
      ),
      throwsFormatException,
    );
  });

  test('joins records, filters with a bound parameter, groups by team, and ranks evidence', () {
    final scouted = GamePackType.record({'team': _text, 'scored': _number});
    final official = GamePackType.record({'team': _text, 'bonus': _number});
    final pair = GamePackType.record({'left': scouted, 'right': official});
    final keep = _graph(
      'keep',
      [
        _parameter('row'),
        _parameter('threshold'),
        _field('score', 'row', 'left.scored'),
        _node(
          'qualifies',
          GameGraphOperation.less,
          inputs: {'left': 'threshold', 'right': 'score'},
        ),
      ],
      _boolean,
      parameters: {'row': pair, 'threshold': _number},
    );
    final score = _graph(
      'score',
      [
        _parameter('entry'),
        _field('scouted', 'entry', 'left.scored'),
        _field('official', 'entry', 'right.bonus'),
        _node(
          'total',
          GameGraphOperation.add,
          inputs: {'left': 'scouted', 'right': 'official'},
        ),
      ],
      _number,
      parameters: {'entry': pair},
    );
    final team = _graph(
      'team',
      [_parameter('entry'), _field('key', 'entry', 'left.team')],
      _text,
      parameters: {'entry': pair},
    );
    final main = GameGraph(
      id: 'main',
      nodes: [
        _source('scouting'),
        _source('tba'),
        _literal('minimum', _number, 2),
        _node(
          'paired',
          GameGraphOperation.join,
          inputs: {'left': 'scouting', 'right': 'tba'},
          options: {'leftKey': 'team', 'rightKey': 'team', 'mode': 'left'},
        ),
        _node(
          'eligible',
          GameGraphOperation.filter,
          inputs: {'items': 'paired', 'threshold': 'minimum'},
          options: {
            'graph': 'keep',
            'output': 'result',
            'itemParameter': 'row',
          },
        ),
        _node(
          'groups',
          GameGraphOperation.groupBy,
          inputs: {'items': 'eligible'},
          options: {'graph': 'team', 'output': 'result'},
        ),
        _node(
          'ranked',
          GameGraphOperation.rankBy,
          inputs: {'items': 'eligible'},
          options: {'graph': 'score', 'output': 'result', 'descending': true},
        ),
      ],
      outputs: {
        'groups': GameGraphOutput(
          'groups',
          GamePackType.list(
            GamePackType.record({
              'key': _text,
              'items': GamePackType.list(pair),
            }),
          ),
        ),
        'ranking': GameGraphOutput(
          'ranked',
          GamePackType.list(
            GamePackType.record({
              'rank': _integer,
              'value': pair,
              'key': _number,
            }),
          ),
        ),
      },
    );
    final program = GameGraphProgram(
      graphs: [main, keep, score, team],
      sourceTypes: {
        'scouting': GamePackType.list(scouted),
        'tba': GamePackType.list(official),
      },
    );
    GamePackValue evidence(String id, Map<String, Object?> row) =>
        GamePackValue.of(row).withEvidence([(type: 'record', id: id)]);
    final sources = {
      'scouting': GamePackValue.list([
        evidence('scout_a', {'team': 'a', 'scored': 4}),
        evidence('scout_b', {'team': 'b', 'scored': 7}),
        evidence('scout_c', {'team': 'c', 'scored': 0}),
        evidence('scout_d', {'team': 'd', 'scored': 9}),
      ]),
      'tba': GamePackValue.list([
        evidence('tba_a', {'team': 'a', 'bonus': 7}),
        evidence('tba_b', {'team': 'b', 'bonus': 0}),
      ]),
    };
    final ranking = program.evaluate((
      graph: 'main',
      output: 'ranking',
    ), sources: sources);
    final rows = ranking.result.data as List<GamePackValue>;
    expect(rows.map((row) => row.atPath('value.left.team').data), [
      'a',
      'b',
      'd',
    ]);
    expect(rows.map((row) => row.atPath('key').data), [11, 7, null]);
    expect(rows.last.atPath('rank').state, GamePackValueState.missing);
    expect(ranking.result.allEvidence.map((source) => source.id).toSet(), {
      'scout_a',
      'scout_b',
      'scout_c',
      'scout_d',
      'tba_a',
      'tba_b',
    });
    final groups = program.evaluate((
      graph: 'main',
      output: 'groups',
    ), sources: sources);
    expect(
      (groups.result.data as List<GamePackValue>).map(
        (row) => row.atPath('key').data,
      ),
      ['a', 'b', 'd'],
    );
  });

  test(
    'runs reproducible seeded simulations with bounded work and statistics',
    () {
      final sample = _graph(
        'sample',
        [
          _parameter('chance'),
          _node(
            'distribution',
            GameGraphOperation.bernoulli,
            inputs: {'chance': 'chance'},
          ),
          _node(
            'sample',
            GameGraphOperation.sample,
            inputs: {'distribution': 'distribution'},
          ),
        ],
        _boolean,
        parameters: {'chance': _number},
      );
      final main = GameGraph(
        id: 'main',
        nodes: [
          _source('chance'),
          _literal('iterations', _integer, 100),
          _node(
            'rolls',
            GameGraphOperation.simulate,
            inputs: {'iterations': 'iterations', 'chance': 'chance'},
            options: {'graph': 'sample', 'output': 'result'},
          ),
          _node(
            'probability',
            GameGraphOperation.probability,
            inputs: {'items': 'rolls'},
          ),
        ],
        outputs: {
          'rolls': const GameGraphOutput('rolls', GamePackType.list(_boolean)),
          'success': const GameGraphOutput('probability', _number),
        },
      );
      final program = GameGraphProgram(
        graphs: [main, sample],
        sourceTypes: {'chance': _number},
      );
      final sources = {'chance': GamePackValue.of(.5)};
      final result = program.evaluate(
        (graph: 'main', output: 'rolls'),
        sources: sources,
        seed: 12,
      );
      expect(
        result.result.plainValue,
        program
            .evaluate(
              (graph: 'main', output: 'rolls'),
              sources: sources,
              seed: 12,
            )
            .result
            .plainValue,
      );
      expect(
        result.result.plainValue,
        isNot(
          program
              .evaluate(
                (graph: 'main', output: 'rolls'),
                sources: sources,
                seed: 15,
              )
              .result
              .plainValue,
        ),
      );
      expect(
        program
            .evaluate(
              (graph: 'main', output: 'success'),
              sources: sources,
              seed: 12,
            )
            .result
            .data,
        inInclusiveRange(.25, .75),
      );
      expect(
        () => program.evaluate(
          (graph: 'main', output: 'rolls'),
          sources: sources,
          workLimit: 60,
        ),
        throwsA(isA<GameGraphLimitExceeded>()),
      );
    },
  );
}
