import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs a typed analysis from corrected observations and archived TBA evidence', () {
    const event = '2027test';
    const match = '2027test_qm1';
    const fields = [GamePackField('score', 'Scouted score')];
    final form = GamePackForm(
      id: 'match',
      label: 'Match scouting',
      kind: GamePackFormKind.match,
      pages: [
        GamePackFormPage.scrolling(
          id: 'match',
          label: 'Match',
          sections: [
            GamePackSection.controls(
              id: 'answers',
              label: 'Answers',
              controls: [
                const GamePackControl(
                  field: 'score',
                  type: GamePackControlType.number,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final analysis = GamePack(
      id: 'analysis',
      document: GamePackDefinition.typed(
        name: 'Revised analysis',
        fields: fields,
        forms: [form],
        tbaFields: [
          GamePackTbaField(
            id: 'official_points',
            label: 'Official points',
            grain: GamePackGrain.allianceMatch,
            type: GamePackType.number,
            paths: ['score_breakdown.{alliance}.level_points'],
          ),
        ],
        calculations: [
          GamePackCalculation.recipe(
            id: 'total',
            label: 'Match total',
            operation: GamePackRecipe.add,
            grain: GamePackGrain.teamMatch,
            inputs: {
              'scouted': gamePackFieldRef('match.score'),
              'official': gamePackFieldRef('official_points'),
            },
          ),
        ],
        season: 2027,
      ).toJson(),
    );
    final capture = GamePack(
      id: 'capture',
      document: {...analysis.document, 'name': 'Capture'},
    );
    GamePackObservation row(
      String id, {
      String? predecessor,
      bool retract = false,
    }) => GamePackObservation(
      id: id,
      event: const EntityRef(event),
      match: const EntityRef(match),
      team: const EntityRef('frc2046'),
      gamePack: const EntityRef('capture'),
      station: 0,
      capturedAt: DateTime.utc(2027, 3),
      answers: retract ? {} : {'score': predecessor == null ? 7 : 10},
      supersedes: predecessor == null ? null : EntityRef(predecessor),
      retracted: retract,
    );
    TbaMatchRevision archive(int sequence, int points) => TbaMatchRevision(
      id: 'official:$sequence',
      event: const EntityRef(event),
      match: const EntityRef(match),
      observedAt: DateTime.utc(2027, 3, sequence),
      sequence: sequence,
      payload: {
        'alliances': {
          'red': {
            'team_keys': ['frc2046'],
          },
        },
        'score_breakdown': {
          'red': {'level_points': points},
        },
      },
    );
    final observations = [
      row('original'),
      row('corrected', predecessor: 'original'),
    ];
    final revised = GamePackEventAnalysis(
      event: event,
      capture: capture,
      analysis: analysis,
      observations: observations,
      revisions: [archive(2, 13), archive(1, 6)],
    );
    final output = gamePackFieldRef('total');
    const scope = GamePackScope(event: event, match: match, team: 'frc2046');
    final evaluated = revised.evaluate(output, scope: scope);
    expect(evaluated.result.data, 23);
    expect(evaluated.result.allEvidence.map((ref) => ref.id).toSet(), {
      'original',
      'corrected',
      'official:2',
    });
    final retracted = GamePackEventAnalysis(
      event: event,
      capture: capture,
      analysis: analysis,
      observations: [
        ...observations,
        row('retracted', predecessor: 'corrected', retract: true),
      ],
      revisions: [archive(2, 13)],
    );
    expect(retracted.evaluate(output, scope: scope).result.isKnown, isFalse);
  });
}
