import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';

void main() {
  final release = GamePackRelease(
    id: 'rebuilt-2026',
    document: jsonDecode(
      File('../../gamepacks/2026-rebuilt.json').readAsStringSync(),
    ) as Json,
  );

  test(
    '2026 forms retain their capture workflows and use the scheduled roster',
    () {
      final pack = release.definition;
      expect(pack.season, 2026);
      expect(pack.forms.map((form) => form.kind), GamePackFormKind.values);
      final match = pack.formFor(GamePackFormKind.match)!;
      expect(match.pages.map((page) => page.label), [
        'Autonomous',
        'Tele',
        'Endgame',
      ]);
      expect(
        match.controls.where(
          (control) => control.type == GamePackControlType.counter,
        ),
        hasLength(5),
      );
      final strategy = pack.formFor(GamePackFormKind.strategy)!;
      const roster = ['frc2877', 'frc6201', 'frc4169'];
      final answers = strategy.defaults(pack.fieldById, roster: roster);
      pack.validateAnswers(answers, formId: strategy.id);
      strategy.validateRankings(answers, pack.fieldById, roster: roster);
      expect(answers['driver_skill'], roster);
      expect(
        () => strategy.validateRankings(
          {
            ...answers,
            'driver_skill': ['frc2877', 'frc6201', 'frc2046'],
          },
          pack.fieldById,
          roster: roster,
        ),
        throwsFormatException,
      );
      expect(
        pack
            .formFor(GamePackFormKind.pit)!
            .pages
            .single
            .sections
            .map((section) => section.label),
        ['Bot', 'Climb', 'Auto', 'Outtake', 'Indexer'],
      );
    },
  );

  test('normalizes 2026 alliance scores from archived real TBA breakdowns', () {
    const event = '2026marea';
    const match = '${event}_qm1';
    final timestamp = DateTime.utc(2026, 3, 28);
    // Upstream match-API test fixtures. The records are preserved unchanged.
    final fixtures = (jsonDecode(
      File('test/fixtures/tba_2026marea_matches.json').readAsStringSync(),
    ) as List).cast<Json>();
    final revisions = [
      for (final (index, match) in fixtures.indexed)
        TbaMatchRevision(
          id: '${match['key']}-1',
          event: const EntityRef(event),
          match: EntityRef(match['key'] as String),
          observedAt: timestamp,
          sequence: index + 1,
          payload: match,
        ),
    ];
    GamePackObservation record(
      String id,
      int station,
      String? team,
      Json answers, {
      String? previous,
      String matchKey = match,
    }) => GamePackObservation(
      id: id,
      event: const EntityRef(event),
      match: EntityRef(matchKey),
      team: team == null ? null : EntityRef(team),
      release: EntityRef(release.id),
      station: station,
      capturedAt: timestamp,
      form: team == null ? 'strategy' : 'match',
      answers: answers,
      supersedes: previous == null ? null : EntityRef(previous),
    );

    final strategy = release.definition.formFor(GamePackFormKind.strategy)!;
    final strategyDefaults = strategy.defaults(
      release.definition.fieldById,
      roster: ['frc2877', 'frc6201', 'frc4169'],
    );
    final history = [
      record('target', 0, 'frc2877', {
        'auto_fuel_scored': 10,
        'tele_fuel_scored': 20,
        'auto_fuel_passed': 6,
        'tele_fuel_passed': 9,
        'tele_fuel_poached': 7,
        'auto_fuel_accuracy': 0,
        'tele_lost_comms': true,
        'endgame_played_defense_off_shift': true,
      }),
      record('partner', 1, 'frc6201', {
        'auto_fuel_scored': 4,
        'tele_fuel_scored': 8,
      }),
      record('partner-revision', 1, 'frc6201', {
        'auto_fuel_scored': 5,
        'tele_fuel_scored': 9,
      }, previous: 'partner'),
      record('third-station', 2, 'frc4169', {
        'auto_fuel_scored': 0,
        'tele_fuel_scored': 0,
      }),
      record('human-player', 6, null, {
        ...strategyDefaults,
        'auto_human_player': 2,
        'tele_human_player': 6,
      }),
      record('blue', 3, 'frc433', {
        'auto_fuel_scored': 100,
        'tele_fuel_scored': 37,
      }),
      record('second-match', 0, 'frc133', {
        'auto_fuel_scored': 100,
        'tele_fuel_scored': 20,
      }, matchKey: '${event}_qm2'),
      GamePackObservation(
        id: 'pit-target',
        event: const EntityRef(event),
        team: const EntityRef('frc2877'),
        form: 'pit',
        release: EntityRef(release.id),
        capturedAt: timestamp,
        answers: {
          'pit_trench_capability': 'Trench Capable',
          'pit_climb_method': 'Arm',
        },
      ),
      GamePackObservation(
        id: 'recent-note',
        event: const EntityRef(event),
        team: const EntityRef('frc2877'),
        form: 'observation',
        release: EntityRef(release.id),
        capturedAt: timestamp.add(const Duration(minutes: 1)),
        answers: {'observation_note': 'New bumper fitted'},
      ),
    ];
    final analysis = GamePackEventAnalysis(
      event: event,
      capture: release,
      analysis: release,
      observations: history,
      revisions: revisions,
    );
    const target = GamePackScope(event: event, team: 'frc2877');
    GamePackValue value(String output, GamePackScope scope) =>
        analysis.evaluate(gamePackFieldRef(output), scope: scope).result;

    final auto = value('auto_fuel', target);
    final tele = value('tele_fuel', target);
    // Scored fuel uses the official total divided by the teams' and human player's counts.
    expect(auto.data, closeTo(10 * (21 / (10 + 5 + 2)), 1e-10));
    expect(tele.data, closeTo(20 * (59 / (20 + 9 + 6)), 1e-10));
    final matches = release.definition.results.sheets.singleWhere(
      (sheet) => sheet.id == 'normalized_matches',
    );
    const targetMatch = GamePackScope(
      event: event,
      match: match,
      team: 'frc2877',
    );
    for (final (id, field, count) in [
      ('auto_passed', 'match.auto_fuel_passed', 6),
      ('tele_passed', 'match.tele_fuel_passed', 9),
      ('poached', 'match.tele_fuel_poached', 7),
    ]) {
      expect(value(id, target).data, count);
      final column = matches.columns.singleWhere((column) => column.id == id);
      expect(column.output, gamePackFieldRef(field));
      expect(value(column.output!.output, targetMatch).data, count);
    }
    expect(value('auto_accuracy', target).isKnown, isFalse);
    expect(
      value(
        'adjusted_auto_fuel',
        const GamePackScope(event: event, match: match, team: 'frc433'),
      ).data,
      closeTo(33, 1e-10),
    );
    final second = const GamePackScope(
      event: event,
      match: '${event}_qm2',
      team: 'frc133',
    );
    expect(value('adjusted_auto_fuel', second).data, closeTo(41, 1e-10));
    expect(value('adjusted_tele_fuel', second).data, closeTo(315, 1e-10));
    expect(release.document.containsKey('graphs'), isFalse);
    final calculation = release.definition.analysis.calculationById(
      'auto_fuel',
    )!;
    expect(calculation.nodes, hasLength(2));
    expect(
      auto.allEvidence.map((entry) => entry.id).toSet(),
      containsAll([
        'target',
        'partner',
        'partner-revision',
        'human-player',
        '$match-1',
      ]),
    );
    final driver = analysis
        .evaluate(gamePackFieldRef('driver_skill'), scope: target)
        .result;
    expect(driver.data, closeTo(1.22474487139, 1e-10));
    final card = release.definition.teamCards.first;
    final chart = card.sections.single.blocks
        .singleWhere((block) => block.kind == GamePackCardBlockKind.trend)
        .chart!;
    expect(chart.sharedScale, isTrue);
    expect(chart.series.map((line) => line.label), ['Auto', 'Tele', 'Total']);
    final timeline = analysis.evaluate(chart.output, scope: target).result;
    final point = (timeline.data as List<GamePackValue>).single;
    expect(point.atPath('match').data, '1');
    expect(
      point.atPath('total').data,
      closeTo((auto.data as num) + (tele.data as num), 1e-10),
    );
    expect(point.atPath('breakdown').data, isTrue);
    expect(point.atPath('defense').data, isTrue);
    expect(point.atPath('no_show').data, isFalse);
    GamePackValue profile(String output) =>
        analysis.evaluate(gamePackFieldRef(output), scope: target).result;
    expect(profile('latest_note').data, 'New bumper fitted');
    expect(profile('sample_size').data, '1 match');
    expect(profile('trench').data, isTrue);
    expect(profile('climb_method').data, 'Arm');
    expect(
      analysis
          .evaluate(gamePackFieldRef('driver_skill_rank'), scope: target)
          .result
          .data,
      1,
    );
    final quickView = release.definition.teamCards.last;
    expect(quickView.sections.map((section) => section.title).nonNulls, [
      'Scoring',
      'Endgame',
      'Defense & Reliability',
      'Robot',
      'More scouting stats',
      'Pit scouting',
    ]);
    final corrections = analysis
        .evaluate(gamePackFieldRef('needs_correction'))
        .result;
    final flagged = (corrections.data as List<GamePackValue>).single;
    expect(flagged.atPath('match').data, match);
    expect(flagged.atPath('scouted').data, 44);
    expect(flagged.atPath('official').data, 95);
  });
}
