import 'package:gamepack/gamepack.dart';

part 'rebuilt_team_cards.dart';

const rebuiltRankings = [
  ('driver_skill', 'Driver Skill'),
  ('defense_resilience', 'Defensive Resilience'),
  ('defense_skill', 'Defensive Skill'),
  ('mechanical_stability', 'Mechanical Stability'),
];

GameGraphOutputRef _scout(String field) =>
    gamePackFieldRef(gamePackScoutFieldId('match', field));
GameGraphOutputRef _pit(String field) =>
    gamePackFieldRef(gamePackScoutFieldId('pit', field));
GameGraphOutputRef _strategy(String field) =>
    gamePackFieldRef(gamePackScoutFieldId('strategy', field));

({
  List<GamePackTbaField> tbaFields,
  List<GamePackCalculation> calculations,
  GamePackResults results,
})
buildRebuiltAnalysis(List<GamePackField> fields, List<GamePackForm> forms) {
  const event = GamePackGrain.event;
  const team = GamePackGrain.team;
  const teamMatch = GamePackGrain.teamMatch;
  const allianceMatch = GamePackGrain.allianceMatch;
  const number = GamePackType.number;
  final calculation = <GamePackCalculation>[];
  final sorts = <GamePackTeamSort>[];
  final summaries = <GamePackWorksheetColumn>[];
  final tbaFields = [
    for (final (id, label, keys) in [
      (
        'official_auto_fuel',
        'Official Auto Fuel',
        ['autoCount', 'autoFuelScored', 'autoFuelCount'],
      ),
      (
        'official_tele_fuel',
        'Official Teleop Fuel',
        [
          'teleopCount',
          'teleFuelScored',
          'teleopFuelScored',
          'teleopFuelCount',
        ],
      ),
    ])
      GamePackTbaField(
        id: id,
        label: label,
        grain: allianceMatch,
        type: number,
        numericText: true,
        paths: [
          for (final nesting in ['hubScore.', ''])
            for (final key in keys) 'score_breakdown.{alliance}.$nesting$key',
        ],
      ),
  ];

  GameGraphOutputRef field(String id) => gamePackFieldRef(id);
  void sort(String id, String label) {
    sorts.add(GamePackTeamSort(id: id, label: label, output: field(id)));
  }

  void column(String id, String label) => summaries.add(
    GamePackWorksheetColumn(id: id, heading: label, output: field(id)),
  );

  GameGraphOutputRef recipe(
    String id,
    String label,
    GamePackRecipe operation,
    Map<String, GameGraphOutputRef> inputs, {
    GamePackGrain grain = team,
    GamePackGrain? rowGrain,
    bool missingAsZero = false,
    GamePackCondition condition = GamePackCondition.provided,
    Object? comparisonValue,
  }) {
    calculation.add(
      GamePackCalculation.recipe(
        id: id,
        label: label,
        operation: operation,
        grain: grain,
        inputs: inputs,
        rowGrain: rowGrain,
        missingAsZero: missingAsZero,
        condition: condition,
        comparisonValue: comparisonValue,
      ),
    );
    return field(id);
  }

  GameGraphOutputRef aggregate(
    String id,
    String label,
    GamePackRecipe operation,
    GameGraphOutputRef source, {
    GamePackGrain grain = team,
    bool missingAsZero = false,
  }) => recipe(
    id,
    label,
    operation,
    {'value': source},
    grain: grain,
    missingAsZero: missingAsZero,
  );

  const fuelStats = [
    ('auto_fuel', 'Auto Avg Fuel', 'auto_fuel_scored', 'auto'),
    ('tele_fuel', 'Tele Avg Fuel', 'tele_fuel_scored', 'tele'),
    ('auto_passed', 'Avg Fuel Passed (Auto)', 'auto_fuel_passed', null),
    ('tele_passed', 'Avg Fuel Passed (Tele)', 'tele_fuel_passed', null),
    ('poached', 'Avg Fuel Poached', 'tele_fuel_poached', null),
  ];

  final fuelSources = <String, GameGraphOutputRef>{};
  for (final (id, label, input, phase) in fuelStats) {
    final scouted = _scout(input);
    final source = phase == null
        ? scouted
        : recipe('adjusted_$id', 'Adjusted $id', GamePackRecipe.scale, {
            'scouted': scouted,
            'official': field('official_${phase}_fuel'),
            'extra': _strategy('${phase}_human_player'),
          }, grain: teamMatch);
    fuelSources[id] = source;
    aggregate(id, label, GamePackRecipe.average, source);
    sort(id, label);
    column(id, label);
  }

  for (final (id, label, operation, input) in [
    (
      'auto_accuracy',
      'Auto Accuracy (%)',
      GamePackRecipe.average,
      'auto_fuel_accuracy',
    ),
    (
      'tele_accuracy',
      'Tele Accuracy (%)',
      GamePackRecipe.average,
      'tele_fuel_accuracy',
    ),
    (
      'auto_climb',
      'Auto L1 Climb Rate (%)',
      GamePackRecipe.rate,
      'auto_climb_l1',
    ),
    (
      'end_climb',
      'Endgame Climb Rate (%)',
      GamePackRecipe.rate,
      'endgame_climb',
    ),
    (
      'played_defense',
      'Defense Frequency (on shift) (%)',
      GamePackRecipe.rate,
      'endgame_played_defense_on_shift',
    ),
    (
      'defended_against',
      'Defended Against Frequency (%)',
      GamePackRecipe.rate,
      'endgame_defended_against',
    ),
    (
      'stopped_working',
      'Stopped Working Rate (%)',
      GamePackRecipe.rate,
      'tele_stopped_working',
    ),
    ('no_show', 'No Show Rate (%)', GamePackRecipe.rate, 'endgame_no_show'),
    (
      'high_center',
      'Beached / High Center Rate (%)',
      GamePackRecipe.rate,
      'tele_beached_high_center',
    ),
    (
      'full_hopper',
      'Full-Hopper Periods Avg',
      GamePackRecipe.average,
      'tele_periods_started_with_full_hopper',
    ),
    ('fouls', 'Avg Fouls', GamePackRecipe.average, 'endgame_fouls'),
    (
      'climb_level',
      'Most Common Climb Level',
      GamePackRecipe.mostCommon,
      'endgame_climb',
    ),
    (
      'play_style',
      'Most Common Play Style',
      GamePackRecipe.mostCommon,
      'endgame_play_style',
    ),
  ]) {
    final source = switch (id) {
      'auto_climb' => recipe(
        'auto_climb_succeeded',
        'Auto climb succeeded',
        GamePackRecipe.condition,
        {'value': _scout(input)},
        grain: teamMatch,
        condition: GamePackCondition.equals,
        comparisonValue: 'Successful',
        missingAsZero: true,
      ),
      'end_climb' => recipe(
        'end_climb_reported',
        'Endgame climb reported',
        GamePackRecipe.condition,
        {'value': _scout(input)},
        grain: teamMatch,
      ),
      'high_center' => recipe(
        'was_high_centered',
        'Was high centered',
        GamePackRecipe.condition,
        {'value': _scout(input)},
        grain: teamMatch,
        condition: GamePackCondition.positive,
        missingAsZero: true,
      ),
      'play_style' => recipe(
        'play_style_text',
        'Play style in match',
        GamePackRecipe.text,
        {'value': _scout(input)},
        grain: teamMatch,
      ),
      _ => _scout(input),
    };
    if (id.endsWith('_accuracy')) {
      calculation.add(
        GamePackCalculation.recipe(
          id: id,
          label: label,
          operation: operation,
          grain: team,
          inputs: {'value': source},
          positiveOnly: true,
        ),
      );
    } else {
      aggregate(
        id,
        label,
        operation,
        source,
        missingAsZero: operation == GamePackRecipe.rate,
      );
    }
    sort(id, label);
    column(id, label);
  }

  recipe('total_fuel', 'Total Avg Fuel / Match', GamePackRecipe.add, {
    'auto': field('auto_fuel'),
    'tele': field('tele_fuel'),
  });
  sort('total_fuel', 'Total Avg Fuel / Match');
  column('total_fuel', 'Total Avg Fuel / Match');

  final totalPerMatch = recipe(
    'fuel_per_match',
    'Combined Fuel in Match',
    GamePackRecipe.add,
    {'auto': field('adjusted_auto_fuel'), 'tele': field('adjusted_tele_fuel')},
    grain: teamMatch,
  );

  aggregate(
    'submissions',
    'Match scouting submissions for team',
    GamePackRecipe.count,
    field('report_id'),
  );
  for (final (id, label) in rebuiltRankings) {
    aggregate(id, '$label (σ)', GamePackRecipe.ballotScore, _strategy(id));
    aggregate(
      '${id}_rank',
      '$label Rank',
      GamePackRecipe.ballotRank,
      _strategy(id),
    );
    sort(id, '$label (σ)');
    column(id, '$label (σ)');
  }

  calculation.add(
    GamePackCalculation.recipe(
      id: 'score_discrepancies',
      label: 'Score discrepancies',
      operation: GamePackRecipe.compare,
      grain: event,
      inputs: {
        'scouted': _scout('auto_fuel_scored'),
        'scouted_other': _scout('tele_fuel_scored'),
        'official': field('official_score'),
      },
      qualificationsOnly: true,
    ),
  );
  recipe('needs_correction', 'Correction To-Do List', GamePackRecipe.flagged, {
    'value': field('score_discrepancies'),
  }, grain: event);
  final breakdown = recipe(
    'breakdown',
    'Breakdown or lost comms',
    GamePackRecipe.any,
    {
      'stopped': _scout('tele_stopped_working'),
      'comms': _scout('tele_lost_comms'),
    },
    grain: teamMatch,
    missingAsZero: true,
  );
  final defense = recipe(
    'defense',
    'Played defense',
    GamePackRecipe.any,
    {
      'on_shift': _scout('endgame_played_defense_on_shift'),
      'off_shift': _scout('endgame_played_defense_off_shift'),
    },
    grain: teamMatch,
    missingAsZero: true,
  );
  final noShow = recipe(
    'no_show_marker',
    'No show in match',
    GamePackRecipe.any,
    {'value': _scout('endgame_no_show')},
    grain: teamMatch,
    missingAsZero: true,
  );
  recipe('match_trend', 'Fuel scored by match', GamePackRecipe.rows, {
    'match': field('match_label'),
    'auto': field('adjusted_auto_fuel'),
    'tele': field('adjusted_tele_fuel'),
    'total': totalPerMatch,
    'breakdown': breakdown,
    'defense': defense,
    'no_show': noShow,
  }, rowGrain: teamMatch);

  recipe('latest_note', 'Latest note', GamePackRecipe.latestNote, {
    'match': _scout('endgame_notes'),
    'pit': _pit('pit_notes'),
    'team_note': gamePackFieldRef('observation.observation_note'),
  });
  recipe(
    'trench',
    'Trench capable',
    GamePackRecipe.condition,
    {'value': _pit('pit_trench_capability')},
    condition: GamePackCondition.equals,
    comparisonValue: 'Trench Capable',
  );
  recipe('climb_method', 'Climb method', GamePackRecipe.excludeValue, {
    'value': _pit('pit_climb_method'),
  }, comparisonValue: 'No Climb');
  recipe('accuracy', 'Overall accuracy', GamePackRecipe.meanOf, {
    'auto': field('auto_accuracy'),
    'tele': field('tele_accuracy'),
  });
  recipe('sample_size', 'Based on matches', GamePackRecipe.countLabel, {
    'value': field('submissions'),
  });
  final byId = {for (final field in fields) field.id: field};
  GamePackWorksheetColumn metadata(GamePackColumnInfo info) =>
      GamePackWorksheetColumn(
        id: info.name.toLowerCase(),
        heading: info.label,
        info: info,
      );
  List<GamePackWorksheetColumn> reportColumns(GamePackForm form) {
    final fields = {
      for (final page in form.pages)
        for (final control in page.controls) control.field: page.label,
    };
    final frequency = <String, int>{};
    for (final key in fields.keys) {
      final label = byId[key]!.label.toLowerCase();
      frequency.update(label, (count) => count + 1, ifAbsent: () => 1);
    }
    final columns = [
      for (final info in GamePackColumnInfo.values)
        if (info.canUse(GamePackSheetRows.reports, form: form.kind) &&
            info != GamePackColumnInfo.teamKey &&
            info != GamePackColumnInfo.teamName)
          metadata(info),
    ];
    final used = columns.map((column) => column.heading.toLowerCase()).toSet();
    for (final entry in fields.entries) {
      final label = byId[entry.key]!.label;
      final base = frequency[label.toLowerCase()]! > 1
          ? '${entry.value} · $label'
          : label;
      var heading = base;
      for (var i = 2; !used.add(heading.toLowerCase()); i++) {
        heading = '$base ($i)';
      }
      columns.add(
        GamePackWorksheetColumn(
          id: entry.key,
          heading: heading,
          path: entry.key,
        ),
      );
    }
    return columns;
  }

  return (
    tbaFields: tbaFields,
    calculations: calculation,
    results: GamePackResults(
      layouts: _rebuiltCardLayouts(
        extraStats: summaries,
        pitFields: fields.where(
          (field) =>
              field.id.startsWith('pit_') &&
              GamePackCardMetric.supports(field.type),
        ),
      ),
      sorts: sorts,
      sheets: [
        GamePackWorksheet(
          id: 'analysis',
          name: 'Analysis',
          rows: GamePackSheetRows.teams,
          columns: [
            metadata(GamePackColumnInfo.teamNumber),
            metadata(GamePackColumnInfo.teamName),
            ...summaries,
          ],
        ),
        GamePackWorksheet(
          id: 'normalized_matches',
          name: 'Normalized Match Data',
          rows: GamePackSheetRows.matches,
          columns: [
            for (final info in [
              GamePackColumnInfo.match,
              GamePackColumnInfo.teamNumber,
              GamePackColumnInfo.alliance,
              GamePackColumnInfo.station,
            ])
              metadata(info),
            GamePackWorksheetColumn(
              id: 'observation_id',
              heading: 'Report ID',
              output: field('report_id'),
            ),
            for (final (id, label, _, _) in fuelStats)
              GamePackWorksheetColumn(
                id: id,
                heading: label,
                output: fuelSources[id]!,
              ),
          ],
        ),
        for (final form in forms)
          GamePackWorksheet(
            id: 'reports_${form.id}',
            name: form.kind.label,
            rows: GamePackSheetRows.reports,
            form: form.id,
            columns: reportColumns(form),
          ),
        GamePackWorksheet(
          id: 'needs_correction',
          name: 'Correction To-Do List',
          rows: GamePackSheetRows.calculation,
          table: field('needs_correction'),
          columns: [
            for (final (path, heading) in [
              ('match', 'Match'),
              ('alliance', 'Alliance'),
              ('scouted', 'Scouted'),
              ('official', 'Official'),
              ('deviation_percent', 'Difference (%)'),
            ])
              GamePackWorksheetColumn(id: path, heading: heading, path: path),
          ],
        ),
      ],
    ),
  );
}
