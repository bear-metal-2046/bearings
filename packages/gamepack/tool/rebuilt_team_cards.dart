part of 'rebuilt_analysis.dart';

List<GamePackTeamCardLayout> _rebuiltCardLayouts({
  required List<GamePackWorksheetColumn> extraStats,
  required Iterable<GamePackField> pitFields,
}) {
  const profile = 'profile';
  const scoring = 'scoring';
  const strategy = 'strategy';
  const hide = GamePackCardMissing.hide;
  const accent = GamePackCardTone.accent;

  GamePackCardMetric value(
    String graph,
    String id,
    String label, {
    int? decimals,
    String suffix = '',
    String prefix = '',
    GamePackCardTone tone = GamePackCardTone.neutral,
    GamePackCardMissing missing = GamePackCardMissing.dash,
    bool flag = false,
  }) => GamePackCardMetric(
    label: label,
    output:
        graph == profile &&
            const {
              'drivetrain_type',
              'shooter',
              'shooter_number',
              'collector_type',
              'trench_capability',
              'average_accuracy',
            }.contains(id)
        ? _pit('pit_$id')
        : gamePackFieldRef(id),
    decimals: decimals,
    suffix: suffix,
    prefix: prefix,
    tone: tone,
    missing: missing,
    onlyWhenTrue: flag,
  );
  GamePackCardBlock metrics(String id, List<GamePackCardMetric> values) =>
      GamePackCardBlock(
        id: id,
        kind: GamePackCardBlockKind.metrics,
        metrics: values,
      );
  GamePackCardBlock trend({
    required bool shared,
    required int minimum,
    String? title,
  }) => GamePackCardBlock(
    id: 'trend',
    title: title,
    kind: GamePackCardBlockKind.trend,
    chart: GamePackCardChart(
      output: gamePackFieldRef('match_trend'),
      x: 'match',
      sharedScale: shared,
      minimumPoints: minimum,
      series: const [
        GamePackCardSeries(
          field: 'auto',
          label: 'Auto',
          tone: GamePackCardTone.danger,
        ),
        GamePackCardSeries(
          field: 'tele',
          label: 'Tele',
          tone: GamePackCardTone.info,
        ),
        GamePackCardSeries(
          field: 'total',
          label: 'Total',
          tone: GamePackCardTone.positive,
        ),
      ],
      markers: const [
        GamePackCardMarker(
          field: 'breakdown',
          label: 'Breakdown or lost comms',
          tone: GamePackCardTone.danger,
          icon: GamePackCardMarkerIcon.breakdown,
        ),
        GamePackCardMarker(
          field: 'defense',
          label: 'Played defense',
          icon: GamePackCardMarkerIcon.defense,
        ),
        GamePackCardMarker(
          field: 'no_show',
          label: 'No show',
          icon: GamePackCardMarkerIcon.absent,
        ),
      ],
    ),
  );
  GamePackCardMetric stat(
    String id,
    String label, {
    bool percent = false,
    bool highlight = false,
  }) => value(
    scoring,
    id,
    label,
    decimals: 1,
    suffix: percent ? '%' : '',
    tone: highlight ? accent : GamePackCardTone.neutral,
  );
  GamePackCardBlock text(String id, String label) => GamePackCardBlock(
    id: id,
    kind: GamePackCardBlockKind.text,
    metrics: [value(profile, id, label, missing: hide)],
  );
  final remainingPitFields = pitFields
      .where(
        (field) => !const {
          'pit_drivetrain_type',
          'pit_shooter',
          'pit_shooter_number',
          'pit_collector_type',
          'pit_trench_capability',
          'pit_average_accuracy',
        }.contains(field.id),
      )
      .toList();
  return [
    GamePackTeamCardLayout(
      kind: GamePackTeamCardKind.compact,
      sections: [
        GamePackCardSection(
          id: 'overview',
          blocks: [
            GamePackCardBlock(
              id: 'capabilities',
              kind: GamePackCardBlockKind.chips,
              metrics: [
                value(
                  scoring,
                  'play_style',
                  'Play style',
                  missing: hide,
                  tone: accent,
                ),
                value(
                  profile,
                  'trench',
                  'Trench',
                  flag: true,
                  tone: GamePackCardTone.info,
                ),
                value(
                  profile,
                  'climb_method',
                  'Climb',
                  missing: hide,
                  tone: GamePackCardTone.info,
                ),
              ],
            ),
            trend(shared: true, minimum: 2),
            metrics('strategy', [
              for (final (id, label) in [
                ('driver_skill', 'Driver'),
                ('defense_skill', 'Defense'),
                ('defense_resilience', 'Def. Resilience'),
                ('mechanical_stability', 'Stability'),
              ])
                value(
                  strategy,
                  '${id}_rank',
                  label,
                  prefix: '#',
                  missing: hide,
                ),
            ]),
            metrics('scoring', [
              for (final (id, label) in [
                ('auto_fuel', 'Auto'),
                ('tele_fuel', 'Tele'),
                ('total_fuel', 'Total'),
              ])
                value(
                  scoring,
                  id,
                  label,
                  decimals: 1,
                  tone: id == 'total_fuel' ? accent : GamePackCardTone.neutral,
                  missing: hide,
                ),
              value(
                profile,
                'accuracy',
                'Accuracy',
                decimals: 1,
                suffix: '%',
                tone: accent,
                missing: hide,
              ),
            ]),
            GamePackCardBlock(
              id: 'event_rank',
              kind: GamePackCardBlockKind.eventRank,
            ),
          ],
        ),
      ],
    ),
    GamePackTeamCardLayout(
      kind: GamePackTeamCardKind.details,
      sections: [
        GamePackCardSection(
          id: 'scoring',
          title: 'Scoring',
          blocks: [
            trend(shared: false, minimum: 1, title: 'Fuel scored by match'),
            metrics('fuel', [
              stat('total_fuel', 'Total Avg Fuel / Match', highlight: true),
              stat('auto_fuel', 'Auto Avg Fuel'),
              stat('tele_fuel', 'Tele Avg Fuel'),
              stat('auto_accuracy', 'Auto Accuracy', percent: true),
              stat('tele_accuracy', 'Tele Accuracy', percent: true),
              stat('tele_passed', 'Avg Fuel Passed (Tele)'),
            ]),
          ],
        ),
        GamePackCardSection(
          id: 'endgame',
          title: 'Endgame',
          blocks: [
            metrics('climb', [
              stat('end_climb', 'Endgame Climb Rate', percent: true),
              value(scoring, 'climb_level', 'Most Common Climb Level'),
              stat('auto_climb', 'Auto L1 Climb Rate', percent: true),
            ]),
          ],
        ),
        GamePackCardSection(
          id: 'reliability',
          title: 'Defense & Reliability',
          blocks: [
            metrics('reliability', [
              stat('played_defense', 'Defense Frequency', percent: true),
              stat(
                'defended_against',
                'Defended Against Frequency',
                percent: true,
              ),
              stat('stopped_working', 'Stopped Working Rate', percent: true),
              stat('no_show', 'No Show Rate', percent: true),
              stat('high_center', 'Beached / High Center Rate', percent: true),
              stat('fouls', 'Avg Fouls'),
            ]),
          ],
        ),
        GamePackCardSection(
          id: 'robot',
          title: 'Robot',
          blocks: [
            metrics('robot', [
              value(profile, 'drivetrain_type', 'Drivetrain'),
              value(profile, 'shooter', 'Shooter Type'),
              value(
                profile,
                'shooter_number',
                'Number of Shooters',
                decimals: 0,
              ),
              value(profile, 'collector_type', 'Collector Type'),
              value(profile, 'trench_capability', 'Trench Capable'),
              value(
                profile,
                'average_accuracy',
                'Claimed Accuracy (Pits)',
                decimals: 1,
                suffix: '%',
              ),
              stat(
                'tele_accuracy',
                'Observed Tele Accuracy',
                percent: true,
                highlight: true,
              ),
            ]),
          ],
        ),
        GamePackCardSection(
          id: 'scouting_statistics',
          title: 'More scouting stats',
          blocks: [
            metrics('additional_stats', [
              for (final entry in extraStats)
                if (!const {
                  'auto_fuel',
                  'tele_fuel',
                  'total_fuel',
                  'auto_accuracy',
                  'tele_accuracy',
                  'tele_passed',
                  'auto_climb',
                  'end_climb',
                  'climb_level',
                  'played_defense',
                  'defended_against',
                  'stopped_working',
                  'no_show',
                  'high_center',
                  'fouls',
                }.contains(entry.id))
                  GamePackCardMetric(
                    label: entry.heading,
                    output: entry.output!,
                  ),
            ]),
          ],
        ),
        GamePackCardSection(
          id: 'pit_scouting',
          title: 'Pit scouting',
          blocks: [
            for (var i = 0; i < remainingPitFields.length; i += 8)
              metrics('pit_fields_$i', [
                for (final field in remainingPitFields.skip(i).take(8))
                  GamePackCardMetric(
                    label: field.label,
                    output: _pit(field.id),
                    missing: hide,
                  ),
              ]),
          ],
        ),
        GamePackCardSection(
          id: 'notes',
          blocks: [
            text('latest_note', 'Latest note'),
            text('sample_size', 'Based on'),
          ],
        ),
      ],
    ),
  ];
}
