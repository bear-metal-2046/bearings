import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_provider.dart';

import 'design.dart';

final gamePackFixtureEventProvider = Provider.autoDispose
    .family<AsyncValue<GamePackFixtureEvent>, String>((ref, event) {
      if (event.isEmpty) return AsyncData(GamePackFixtureEvent());
      final schedule = ref.watch(competitionMatchesProvider(event));
      final archived = isMirroredTbaKey(event)
          ? ref.watch(eventTbaRevisionsProvider(event))
          : AsyncData(QueryResult<TbaMatchRevision>([]));
      final teams = ref.watch(competitionTeamsProvider(event)).value?.items;
      final rankings = ref.watch(competitionRankingsProvider(event)).value;
      return schedule.flatMap((matches) {
        final available = matches.requireAvailable();
        return archived.when(
          loading: () => const AsyncLoading(),
          error: (_, _) => AsyncData(
            GamePackFixtureEvent(
              schedule: available.items,
              teams: teams ?? const [],
              rankings: rankings,
              partial: true,
            ),
          ),
          data: (revisions) {
            final hasArchive =
                revisions.hasSnapshot && !revisions.updateRequired;
            return AsyncData(
              GamePackFixtureEvent(
                schedule: available.items,
                revisions: hasArchive ? revisions.items : const [],
                teams: teams ?? const [],
                rankings: rankings,
                partial:
                    !available.complete || !hasArchive || !revisions.complete,
              ),
            );
          },
        );
      });
    });

/// The event data supplied by TBA. Author-entered reports are stored separately.
class GamePackFixtureEvent {
  GamePackFixtureEvent({
    List<CompetitionMatch> schedule = const [],
    List<TbaMatchRevision> revisions = const [],
    List<CompetitionTeam> teams = const [],
    this.rankings,
    this.partial = false,
  }) : schedule = {
         for (final match in schedule)
           match.id: GamePackValue.of(TbaApi.matchJson(match)),
       },
       revisions = List.of(revisions)
         ..sort((a, b) {
           final sequence = a.sequence.compareTo(b.sequence);
           return sequence == 0 ? a.id.compareTo(b.id) : sequence;
         }),
       teamProfiles = {for (final team in teams) team.id: team};

  final Map<String, GamePackValue> schedule;
  final List<TbaMatchRevision> revisions;
  final Map<String, CompetitionTeam> teamProfiles;
  final List<EventRanking>? rankings;
  final bool partial;

  late final _latest = {
    for (final revision in revisions) revision.match.id: revision,
  };
  late final matches = {...schedule.keys, ..._latest.keys}.toList()
    ..sort((a, b) => _matchOrder(a).compareTo(_matchOrder(b)));

  late final _payloads = {
    for (final match in matches)
      match: switch (_latest[match]) {
        final revision? => GamePackValue.of(revision.payload),
        null => schedule[match]!,
      },
  };
  GamePackValue payload(String match) =>
      _payloads[match] ?? GamePackValue.missing;

  late final teams =
      <String>{
        ...teamProfiles.keys,
        for (final match in matches) ...lineup(match).keys,
      }.toList()..sort((a, b) {
        final left = int.tryParse(a.replaceFirst('frc', '')) ?? 0;
        final right = int.tryParse(b.replaceFirst('frc', '')) ?? 0;
        return left == right ? a.compareTo(b) : left.compareTo(right);
      });

  late final _lineups =
      <String, Map<String, ({String alliance, int station})>>{};
  Map<String, ({String alliance, int station})> lineup(String match) =>
      _lineups.putIfAbsent(
        match,
        () => {
          for (final (side, alliance) in ['red', 'blue'].indexed)
            for (final (slot, team) in _teamsFor(match, alliance).indexed)
              team: (alliance: alliance, station: side * 3 + slot),
        },
      );

  List<String> allianceTeams(String? match, String? alliance) =>
      match == null || alliance == null ? const [] : _teamsFor(match, alliance);

  List<String> _teamsFor(String match, String alliance) {
    List<String> read(GamePackValue source) {
      final names = source.atPath('alliances.$alliance.team_keys').data;
      return names is List<GamePackValue>
          ? names.map((item) => item.data).whereType<String>().toList()
          : const [];
    }

    final scheduled = read(schedule[match] ?? GamePackValue.missing);
    return scheduled.isEmpty ? read(payload(match)) : scheduled;
  }

  String? teamName(String team) {
    final profile = teamProfiles[team];
    final name = profile?.nickname ?? profile?.name;
    return name == null || name.isEmpty ? null : name;
  }

  String teamLabel(String team) {
    final number = 'Team ${team.replaceFirst('frc', '')}';
    final name = teamName(team);
    return name == null ? number : '$number · $name';
  }

  late final teamNames = {for (final team in teams) team: teamLabel(team)};

  Iterable<String> matchesFor(String? team) => team == null
      ? matches
      : matches.where((match) => lineup(match).containsKey(team));

  (int, int, int, String) _matchParts(String match) {
    final meta = schedule[match] ?? _payloadsOrArchive(match);
    final suffix = match.split('_').last;
    final fallback = RegExp(r'^(qm|pm|ef|qf|sf|f)(\d+)(?:m(\d+))?$')
        .firstMatch(suffix);
    final level = meta.atPath('comp_level').data as String? ?? fallback?[1];
    const levels = ['pm', 'qm', 'ef', 'qf', 'sf', 'f'];
    final set =
        meta.atPath('set_number').data as int? ??
        (fallback?[3] == null ? 1 : int.parse(fallback![2]!));
    final number =
        meta.atPath('match_number').data as int? ??
        int.tryParse(fallback?[3] ?? fallback?[2] ?? '') ??
        0;
    return (levels.indexOf(level ?? ''), set, number, suffix);
  }

  GamePackValue _payloadsOrArchive(String match) =>
      GamePackValue.of(_latest[match]?.payload);

  String _matchOrder(String match) {
    final (level, set, number, suffix) = _matchParts(match);
    return '${level + 1}:${set.toString().padLeft(5, '0')}:${number.toString().padLeft(5, '0')}:$suffix';
  }

  String matchLabel(String match) {
    final (level, set, number, suffix) = _matchParts(match);
    return switch (level) {
      0 => 'Practice $number',
      1 => 'Qualification $number',
      2 => 'Elimination $set · Match $number',
      3 => 'Quarterfinal $set · Match $number',
      4 => 'Semifinal $set · Match $number',
      5 => 'Final $set · Match $number',
      _ => suffix,
    };
  }

  late final scoreCount = matches.where((match) {
    final current = payload(match);
    return ['red', 'blue'].any((side) {
      final breakdown = current.atPath('score_breakdown.$side').data;
      final score = current.atPath('alliances.$side.score').data;
      return breakdown is Map && breakdown.isNotEmpty ||
          score is num && score >= 0;
    });
  }).length;

  GamePackValue _archivedValue(TbaMatchRevision revision) => GamePackValue.of({
    'id': revision.id,
    'event': revision.event.id,
    'match': revision.match.id,
    'sequence': revision.sequence,
    'observed_at': revision.observedAt.millisecondsSinceEpoch,
    'payload': revision.payload,
  }).withEvidence([(type: tbaMatchRevisionEntity.type, id: revision.id)]);

  late final _official = GamePackValue.list([
    for (final match in matches)
      if (_latest[match] case final revision?)
        _archivedValue(revision)
      else
        GamePackValue.record({
          'match': GamePackValue.of(match),
          'payload': payload(match),
        }),
  ]);
  late final _history = GamePackValue.list(revisions.map(_archivedValue));
}

class GamePackFixtureObservation {
  const GamePackFixtureObservation({
    required this.event,
    required this.form,
    this.match,
    this.team,
    this.alliance,
    required this.answers,
  });

  final String event;
  final String form;
  final String? match;
  final String? team;
  final String? alliance;
  final Map<String, Object?> answers;

  factory GamePackFixtureObservation.fromJson(Json json, String event) =>
      GamePackFixtureObservation(
        event: json['event'] as String? ?? event,
        form: json['form'] as String,
        match: json['match'] as String?,
        team: json['team'] as String?,
        alliance: json['alliance'] as String?,
        answers: json['answers'] as Json,
      );

  Json toJson() => {
    'event': event,
    'form': form,
    'match': ?match,
    'team': ?team,
    'alliance': ?alliance,
    'answers': answers,
  };
}

class GamePackBuilderFixture {
  GamePackBuilderFixture({
    required this.event,
    this.match,
    this.team,
    this.seed = 0,
    this.reports = const [],
    this.data,
  });

  final String event;
  final String? match;
  final String? team;
  final int seed;
  final List<GamePackFixtureObservation> reports;
  final GamePackFixtureEvent? data;

  factory GamePackBuilderFixture.fromJson(
    Object? raw, {
    required String defaultEvent,
    required GamePackDesign design,
  }) {
    if (raw is! Json) return GamePackBuilderFixture(event: defaultEvent);
    final event = raw['event'] as String? ?? defaultEvent;
    final legacySample = raw['sample'] is Json
        ? tbaMatchRevisionEntity.decode(raw['sample'] as Json)
        : null;
    final team = raw['team'] as String?;
    final match = raw['match'] as String? ?? legacySample?.match.id;
    final answers = raw['answers'] as Json?;
    final form =
        design.configuredForms
            .where((form) => form.id == raw['form'])
            .firstOrNull ??
        design.configuredForms.firstOrNull;
    return GamePackBuilderFixture(
      event: event,
      match: match,
      team: team,
      seed: raw['seed'] as int? ?? 0,
      reports: [
        if (answers != null && answers.isNotEmpty && form != null)
          GamePackFixtureObservation(
            event: event,
            form: form.id,
            match: switch (form.kind) {
              GamePackFormKind.match ||
              GamePackFormKind.strategy => match ?? '${event}_qm1',
              GamePackFormKind.observation
                  when raw['observationInMatch'] == true =>
                match ?? '${event}_qm1',
              _ => null,
            },
            team: form.kind == GamePackFormKind.strategy ? null : team,
            alliance: raw['alliance'] as String?,
            answers: answers,
          ),
        for (final row
            in (raw['reports'] ?? raw['additional']) as List? ?? const [])
          GamePackFixtureObservation.fromJson(row as Json, event),
      ],
    );
  }

  Json toJson() => {
    'event': event,
    'match': ?match,
    'team': ?team,
    'seed': seed,
    'reports': reports.map((report) => report.toJson()).toList(),
  };

  late final eventReports = reports
      .where((report) => report.event == event)
      .toList();

  late final scope = _scope();
  GamePackScope _scope() {
    final eventData = data;
    if (eventData == null) {
      return GamePackScope(event: event, team: team, match: match);
    }
    final teams = eventData.teams;
    final picked = teams.contains(team)
        ? team
        : (match == null ? null : eventData.lineup(match!).keys.firstOrNull) ??
              teams.firstOrNull;
    final matches = eventData.matchesFor(picked);
    final focus = matches.contains(match) ? match : matches.firstOrNull;
    final station = focus == null ? null : eventData.lineup(focus)[picked];
    return GamePackScope(
      event: event,
      match: focus,
      team: picked,
      alliance: station?.alliance,
      station: station?.station,
    );
  }

  Iterable<GamePackValue> get testPayloads sync* {
    if (data case final loaded?) {
      final focus = scope.match;
      if (focus != null) yield loaded.payload(focus);
      for (final match in loaded.matches) {
        if (match != focus) yield loaded.payload(match);
      }
    }
  }

  GamePackAnalysisSession analysisFor(
    GamePackDesign design, {
    bool trace = false,
  }) => GamePackAnalysisSession(
    analysis: design.catalog,
    event: event,
    sources: _sourcesFor(design),
    schedule: data?.schedule ?? const {},
    seed: seed,
    trace: trace,
  );

  Map<String, GamePackValue> _sourcesFor(GamePackDesign design) {
    final forms = {for (final form in design.configuredForms) form.id: form};
    final fields = design.fieldById;
    final observations = <GamePackValue>[];
    for (final (index, row) in eventReports.indexed) {
      final form = forms[row.form];
      if (form == null) continue;
      final id = 'fixture-observation-${index + 1}';
      final lineup = row.match == null ? null : data?.lineup(row.match!);
      final entry = lineup?[row.team];
      final alliance = form.kind == GamePackFormKind.strategy
          ? row.alliance
          : entry?.alliance ?? row.alliance;
      final raw = {
        ...form.defaults(
          fields,
          roster: data?.allianceTeams(row.match, alliance) ?? const [],
        ),
        ...row.answers,
      };
      final answers = <String, GamePackValue>{};
      for (final name in form.visibleFields(raw)) {
        if (!raw.containsKey(name) || !fields.containsKey(name)) continue;
        try {
          answers[name] = fields[name]!.readAnswer(raw[name]);
        } on FormatException {
          answers[name] = GamePackValue.unknown;
        }
      }
      observations.add(
        GamePackValue.of({
          'id': id,
          'event': event,
          if (row.match != null && form.kind != GamePackFormKind.pit)
            'match': row.match,
          if (form.kind != GamePackFormKind.strategy) 'team': row.team,
          if (form.kind == GamePackFormKind.match ||
              form.kind == GamePackFormKind.strategy) ...{
            'alliance': alliance,
            'station': form.kind == GamePackFormKind.strategy
                ? (alliance == 'red' ? 6 : 7)
                : entry?.station ?? (alliance == 'red' ? 0 : 3),
          },
          'form': form.id,
          'kind': form.kind.name,
          'gamepack': 'fixture',
          'retracted': false,
          'captured_at': index,
          'answers': GamePackValue.record(answers),
        }).withEvidence([(type: 'fixture', id: id)]),
      );
    }
    final collection = GamePackValue.list(observations);
    return {
      'context': scope.toValue(),
      'observations': collection,
      'observation_history': collection,
      'tba': data?._official ?? GamePackValue.list(const []),
      'tba_history': data?._history ?? GamePackValue.list(const []),
    };
  }

  GamePackBuilderFixture selectEvent(String event) =>
      GamePackBuilderFixture(event: event, seed: seed, reports: reports);

  GamePackBuilderFixture withData(GamePackFixtureEvent? value) =>
      identical(data, value)
      ? this
      : GamePackBuilderFixture(
          event: event,
          match: match,
          team: team,
          seed: seed,
          reports: reports,
          data: value,
        );

  GamePackBuilderFixture copyWith({
    String? Function()? match,
    String? Function()? team,
    int? seed,
    List<GamePackFixtureObservation>? reports,
  }) => GamePackBuilderFixture(
    event: event,
    match: match == null ? this.match : match(),
    team: team == null ? this.team : team(),
    seed: seed ?? this.seed,
    reports: reports ?? this.reports,
    data: data,
  );
}
