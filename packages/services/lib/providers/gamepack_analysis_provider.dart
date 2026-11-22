import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:riverpod/riverpod.dart';

import 'competition_provider.dart';
import 'gamepack_provider.dart';
import 'grove_provider.dart';

final gamePackObservationHistoryProvider = Provider.autoDispose
    .family<AsyncValue<QueryResult<GamePackObservation>>, String>((ref, event) {
      final grove = ref.watch(bearingsGroveProvider);
      return ref.watch(
        groveQueryProvider(
          grove.query<GamePackObservation>().where(
            GamePackObservationFields.event.equals(EntityRef(event)),
          ),
        ),
      );
    });

final activeGamePackObservationsProvider = Provider.autoDispose
    .family<AsyncValue<List<GamePackObservation>>, String>((ref, event) {
      return ref.watch(gamePackObservationHistoryProvider(event)).whenData((
        snapshot,
      ) {
        return activeGamePackObservations(snapshot.requireAvailable().items)
            .toList()
          ..sort((a, b) {
            final chronological = b.capturedAt.compareTo(a.capturedAt);
            return chronological == 0 ? b.id.compareTo(a.id) : chronological;
          });
      });
    });

final gamePackEventAnalysisProvider = Provider.autoDispose
    .family<AsyncValue<GamePackEventAnalysis?>, String>((ref, event) {
      final assigned = ref.watch(eventGamePackBindingProvider(event));
      return assigned.flatMap((binding) {
        if (binding == null) return const AsyncData(null);
        final capture = ref.watch(gamePackReleaseProvider(binding.release.id));
        final analysis = ref.watch(
          gamePackReleaseProvider(binding.effectiveAnalysisRelease.id),
        );
        return capture.flatMap(
          (capture) => analysis.flatMap((analysis) {
            final observations = ref.watch(
              gamePackObservationHistoryProvider(event),
            );
            final official = ref.watch(eventTbaRevisionsProvider(event));
            final schedule =
                ref.watch(competitionMatchesProvider(event)).value?.items ??
                const [];
            return observations.flatMap(
              (reports) => official.whenData(
                (archive) => GamePackEventAnalysis(
                  event: event,
                  capture: capture,
                  analysis: analysis,
                  observations: reports.requireAvailable().items,
                  revisions: archive.requireAvailable().items,
                  schedule: schedule,
                  offline: reports.offline || archive.offline,
                ),
              ),
            );
          }),
        );
      });
    });

/// Projects immutable Grove records into the shared graph value model.
class GamePackEventAnalysis {
  GamePackEventAnalysis({
    required this.event,
    required this.capture,
    required this.analysis,
    required List<GamePackObservation> observations,
    required List<TbaMatchRevision> revisions,
    List<CompetitionMatch> schedule = const [],
    this.offline = false,
  }) : _observations = List.unmodifiable(observations),
       _revisions = List.unmodifiable(revisions),
       _schedule = List.unmodifiable(schedule);

  final String event;
  final GamePackRelease capture;
  final GamePackRelease analysis;
  final bool offline;
  final List<GamePackObservation> _observations;
  final List<TbaMatchRevision> _revisions;
  final List<CompetitionMatch> _schedule;
  final _sessions = <(GamePackAnalysis, int), GamePackAnalysisSession>{};
  late final _scheduled = {
    for (final match in _schedule)
      if (match.event.id == event)
        match.id: GamePackValue.of({
          'comp_level': match.level,
          'match_number': match.matchNumber,
          'set_number': match.setNumber,
          'time':
              (match.playedAt ?? match.scheduledAt)?.millisecondsSinceEpoch ==
                  null
              ? null
              : (match.playedAt ?? match.scheduledAt)!.millisecondsSinceEpoch ~/
                    1000,
          'alliances': {
            for (final (side, lineup) in [
              ('red', match.red),
              ('blue', match.blue),
            ])
              if (lineup != null)
                side: {
                  'team_keys': lineup.teams.map((team) => team.id),
                  'score': lineup.score,
                },
          },
        }),
  };
  late final _sources = _buildSources(
    event,
    capture,
    _observations,
    _revisions,
  );

  GamePackEventAnalysis filterMatches(bool Function(String match) include) =>
      GamePackEventAnalysis(
        event: event,
        capture: capture,
        analysis: analysis,
        offline: offline,
        observations: _observations
            .where((row) => row.match == null || include(row.match!.id))
            .toList(),
        revisions: _revisions.where((row) => include(row.match.id)).toList(),
        schedule: _schedule.where((match) => include(match.id)).toList(),
      );

  Json? evidenceDocument(GamePackEvidenceRef source) {
    if (source.type == gamePackObservationEntity.type) {
      final observation = _observations
          .where((row) => row.id == source.id)
          .firstOrNull;
      return observation == null
          ? null
          : gamePackObservationEntity.encode(observation);
    }
    if (source.type == tbaMatchRevisionEntity.type) {
      final revision = _revisions
          .where((row) => row.id == source.id)
          .firstOrNull;
      return revision == null ? null : tbaMatchRevisionEntity.encode(revision);
    }
    return null;
  }

  GameGraphEvaluation evaluate(
    GameGraphOutputRef output, {
    GamePackScope? scope,
    int seed = 0,
  }) => session(
    analysis.definition.analysis,
    seed: seed,
  ).evaluate(output, scope: scope);

  GamePackAnalysisSession session(GamePackAnalysis definition, {int seed = 0}) {
    final key = (definition, seed);
    if (_sessions[key] case final existing?) return existing;
    if (_sessions.length >= 8) _sessions.remove(_sessions.keys.first);
    return _sessions[key] = GamePackAnalysisSession(
      analysis: definition,
      event: event,
      sources: _sources,
      schedule: _scheduled,
      seed: seed,
    );
  }
}

Map<String, GamePackValue> _buildSources(
  String event,
  GamePackRelease capture,
  List<GamePackObservation> observations,
  List<TbaMatchRevision> revisions,
) {
  final history =
      observations
          .where((row) => row.event.id == event && row.release.id == capture.id)
          .toList()
        ..sort((a, b) {
          final time = a.capturedAt.compareTo(b.capturedAt);
          return time == 0 ? a.id.compareTo(b.id) : time;
        });
  final byId = {for (final row in history) row.id: row};
  final rows = {
    for (final row in history) row.id: _observationValue(row, capture, byId),
  };
  final orderedRevisions =
      revisions.where((revision) => revision.event.id == event).toList()
        ..sort((a, b) {
          final order = a.sequence.compareTo(b.sequence);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
  final archive = <GamePackValue>[];
  final current = <String, GamePackValue>{};
  for (final revision in orderedRevisions) {
    final value = _revisionValue(revision);
    current[revision.match.id] = value;
    archive.add(value);
  }
  return {
    'observations': GamePackValue.list(
      activeGamePackObservations(history).map((row) => rows[row.id]!),
    ),
    'observation_history': GamePackValue.list(rows.values),
    'tba': GamePackValue.list(current.values),
    'tba_history': GamePackValue.list(archive),
  };
}

GamePackValue _observationValue(
  GamePackObservation row,
  GamePackRelease capture,
  Map<String, GamePackObservation> byId,
) {
  final evidence = <GamePackEvidenceRef>{};
  GamePackObservation? parent = row;
  while (parent != null) {
    if (!evidence.add((type: gamePackObservationEntity.type, id: parent.id))) {
      break;
    }
    parent = byId[parent.supersedes?.id];
  }
  final answers = row.isRetraction
      ? const <String, GamePackValue>{}
      : capture.definition.decodeAnswers(row.answers, formId: row.formId);
  return GamePackValue.of({
    'id': row.id,
    'event': row.event.id,
    if (row.match case final match?) 'match': match.id,
    if (row.team case final team?) 'team': team.id,
    if (row.station case final station?) ...{
      'station': station,
      'alliance': station < 3 || station == 6 ? 'red' : 'blue',
    },
    'form': row.formId,
    'kind': capture.definition.formById(row.formId).kind.name,
    'release': row.release.id,
    if (row.scout case final scout?) 'scout': scout.id,
    if (row.author case final author?) 'author': author,
    'captured_at': row.capturedAt.millisecondsSinceEpoch,
    if (row.supersedes case final prior?) 'supersedes': prior.id,
    'retracted': row.isRetraction,
    'answers': GamePackValue.record(answers),
  }).withEvidence(evidence);
}

GamePackValue _revisionValue(TbaMatchRevision revision) => GamePackValue.of({
  'id': revision.id,
  'event': revision.event.id,
  'match': revision.match.id,
  'sequence': revision.sequence,
  'observed_at': revision.observedAt.millisecondsSinceEpoch,
  'payload': revision.payload,
}).withEvidence([(type: tbaMatchRevisionEntity.type, id: revision.id)]);
