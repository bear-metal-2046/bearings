import 'package:gamepack/gamepack.dart';
import 'package:test/test.dart';

void main() {
  test(
    'rejects older formats and keeps raw numeric paths in the typed graph',
    () {
      for (final version in [1, 2]) {
        expect(
          () => GamePackDefinition.fromJson({'formatVersion': version}),
          throwsFormatException,
        );
      }
      final graph = GameGraph(
        id: 'scoring',
        nodes: [
          GameGraphNode(
            id: 'total',
            operation: GameGraphOperation.add,
            inputs: const {'left': 'official', 'right': 'scouted'},
          ),
          GameGraphNode(
            id: 'official',
            operation: GameGraphOperation.toNumber,
            inputs: const {'value': 'raw'},
          ),
          GameGraphNode(
            id: 'raw',
            operation: GameGraphOperation.field,
            inputs: const {'value': 'breakdown'},
            options: const {'path': 'results.0.count', 'type': 'json'},
          ),
          GameGraphNode(
            id: 'breakdown',
            operation: GameGraphOperation.source,
            options: const {'name': 'breakdown'},
          ),
          GameGraphNode(
            id: 'scouted',
            operation: GameGraphOperation.source,
            options: const {'name': 'scouted'},
          ),
        ],
        outputs: const {
          'result': GameGraphOutput('total', GamePackType.number),
        },
      );
      final program = GameGraphProgram.fromJson(
        GameGraphProgram(
          graphs: [graph],
          sourceTypes: const {
            'scouted': GamePackType.number,
            'breakdown': GamePackType.json,
          },
        ).toJson(),
      );

      GamePackValue evaluate(List<Object?> results) => program
          .evaluate(
            (graph: 'scoring', output: 'result'),
            sources: {
              'scouted': GamePackValue.of(7),
              'breakdown': GamePackValue.of({'results': results}),
            },
          )
          .result;
      expect(
        evaluate([
          {'count': '0'},
        ]).data,
        7,
      );
      expect(evaluate([]).state, GamePackValueState.missing);
    },
  );
}
