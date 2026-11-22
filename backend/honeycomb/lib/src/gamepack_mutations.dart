import 'package:core/core.dart';
import 'package:grove/grove.dart';

import 'package:honeycomb/src/entity_store.dart';

/// Validate references in the same transaction as the create. The original
/// request still goes into the retry receipt, independently of server fields.
Json Function(Json)? gamePackCreateConfirmation(
  EntityStore store,
  EntityMutation mutation,
  String actor,
) {
  if (mutation.kind != MutationKind.create) return null;
  if (mutation.type == gamePackReleaseEntity.type) {
    return (data) =>
        gamePackReleaseEntity.encode(gamePackReleaseEntity.decode(data));
  }
  if (mutation.type == eventGamePackEntity.type) {
    return (data) {
      final binding = eventGamePackEntity.decode(data);
      _validateBinding(store, binding);
      return eventGamePackEntity.encode(binding);
    };
  }
  if (mutation.type != gamePackObservationEntity.type) return null;

  return (data) {
    final observation = gamePackObservationEntity.decode(data);
    final binding = _requireRecord(
      store,
      eventGamePackEntity,
      observation.event.id,
      'Event GamePack assignment',
    );
    if (binding.release.id != observation.release.id) {
      throw const FormatException('This release is not assigned to the event.');
    }
    final release = _requireRecord(
      store,
      gamePackReleaseEntity,
      binding.release.id,
      'GamePack release',
    );
    final form = release.definition.formById(observation.formId);
    final supersedes = observation.supersedes;
    var roster = const <String>[];
    if (supersedes != null) {
      final original = _requireRecord(
        store,
        gamePackObservationEntity,
        supersedes.id,
        'Observation to correct',
      );
      if (!original.hasSameSubject(observation)) {
        throw const FormatException(
          'A correction must preserve the observation subject and release.',
        );
      }
      if (store.hasObservationSuccessor(original.id)) {
        throw const GroveException(
          'conflict',
          'This observation already has a newer revision.',
        );
      }
      if (observation.reason?.trim().isNotEmpty != true ||
          observation.reason!.length > 1000) {
        throw const FormatException(
          'Enter a correction reason of 1–1000 characters.',
        );
      }
      for (final control in form.controls) {
        final field = release.definition.fieldById[control.field]!;
        final answer = original.answers[control.field];
        if (control.type == GamePackControlType.ranking &&
            field.choices.isEmpty &&
            answer is List) {
          roster = answer.cast<String>();
          break;
        }
      }
    } else {
      if (observation.isRetraction || observation.reason != null) {
        throw const FormatException(
          'A correction or retraction needs an existing observation.',
        );
      }
      roster = _validateObservationSubject(store, observation, form.kind);
    }
    if (observation.scout case final scout?) {
      _requireRecord(store, scoutEntity, scout.id, 'Scout');
    }
    if (observation.isRetraction) {
      if (observation.answers.isNotEmpty) {
        throw const FormatException('A retraction cannot contain new answers.');
      }
    } else {
      release.definition.validateAnswers(observation.answers, formId: form.id);
      form.validateRankings(
        observation.answers,
        release.definition.fieldById,
        roster: roster,
      );
    }
    final confirmed = {
      ...gamePackObservationEntity.encode(observation),
      'author': actor,
    };
    if (mutation.version == 1) {
      for (final key in GamePackObservation.groveFieldVersions.keys) {
        if (data.containsKey(key)) {
          throw const FormatException(
            'This observation requires schema version 2.',
          );
        }
        confirmed.remove(key);
      }
    }
    return confirmed;
  };
}

List<String> _validateObservationSubject(
  EntityStore store,
  GamePackObservation observation,
  GamePackFormKind kind,
) {
  final team = observation.team;
  final station = observation.station;
  final matchRef = observation.match;
  final needsMatch =
      kind == GamePackFormKind.match || kind == GamePackFormKind.strategy;
  if (kind != GamePackFormKind.observation &&
      (matchRef != null) != needsMatch) {
    throw const FormatException(
      'This form and observation have different match scopes.',
    );
  }
  if ((team == null) != (kind == GamePackFormKind.strategy)) {
    throw const FormatException(
      'This form and observation have different team scopes.',
    );
  }
  if ((matchRef == null || kind == GamePackFormKind.observation) &&
      station != null) {
    throw const FormatException('This observation has no scout station.');
  }
  if (matchRef == null) {
    _requireRecord(store, competitionTeamEntity, team!.id, 'Team');
    return const [];
  }
  final match = _requireRecord(
    store,
    competitionMatchEntity,
    matchRef.id,
    'Match',
  );
  if (match.event.id != observation.event.id) {
    throw const FormatException('The match belongs to a different event.');
  }
  switch (kind) {
    case GamePackFormKind.match:
      if (station == null || station < 0 || station > 5) {
        throw const FormatException('Choose a robot station.');
      }
      final teams = observation.allianceFor(match)?.teams ?? [];
      final index = station % 3;
      if (teams.length <= index || teams[index].id != team!.id) {
        throw const FormatException(
          'The team does not match the selected alliance station.',
        );
      }
    case GamePackFormKind.strategy:
      if ((station != 6 && station != 7) ||
          observation.allianceFor(match)?.teams.isNotEmpty != true) {
        throw const FormatException('Choose a scheduled alliance.');
      }
    case GamePackFormKind.observation:
      final lineup = [...?match.red?.teams, ...?match.blue?.teams];
      if (!lineup.any((entry) => entry.id == team!.id)) {
        throw const FormatException(
          'Choose a team scheduled for this match.',
        );
      }
    case GamePackFormKind.pit:
      break;
  }
  return (observation.allianceFor(match)?.teams ?? [])
      .map((team) => team.id)
      .toList();
}

void authorizeGamePackAnalysisUpdate(
  EntityStore store,
  EntityMutation mutation,
) {
  if (mutation.changes.any(
    (change) =>
        change.path.length != 1 || change.path.single != 'analysisRelease',
  )) {
    throw const GroveException(
      'forbidden',
      'The collection release is pinned.',
    );
  }
  final previous = _requireRecord(
    store,
    eventGamePackEntity,
    mutation.id,
    'Event GamePack assignment',
  );
  final updated = eventGamePackEntity.decode(
    applyChanges(
      eventGamePackEntity.encode(previous),
      mutation.changes,
    ),
  );
  _validateBinding(store, updated);
}

void _validateBinding(EntityStore store, EventGamePack binding) {
  final event = _requireRecord(
    store,
    competitionEventEntity,
    binding.id,
    'Event',
  );
  final capture = _requireRecord(
    store,
    gamePackReleaseEntity,
    binding.release.id,
    'Collection release',
  );
  if (capture.definition.season case final year? when year != event.season) {
    throw FormatException(
      'The collection release is for $year, not ${event.season}.',
    );
  }
  final analysisId = binding.effectiveAnalysisRelease.id;
  if (analysisId == capture.id) return;
  final analysis = _requireRecord(
    store,
    gamePackReleaseEntity,
    analysisId,
    'Analysis release',
  );
  if (analysis.definition.season case final year? when year != event.season) {
    throw FormatException(
      'The analysis release is for $year, not ${event.season}.',
    );
  }

  for (final field in capture.definition.fields) {
    final replacement = analysis.definition.fieldById[field.id];
    if (replacement == null ||
        !replacement.type.accepts(field.type) ||
        (replacement.choices.isNotEmpty &&
            (field.choices.isEmpty ||
                !replacement.choices.toSet().containsAll(field.choices)))) {
      throw FormatException(
        'The analysis release cannot read captured field ${field.id}.',
      );
    }
  }
}

T _requireRecord<T>(
  EntityStore store,
  EntityDescriptor<T> descriptor,
  String id,
  String label,
) {
  final record = store.get(descriptor.type, id);
  if (record == null || record.deleted) {
    throw GroveException('not_found', '$label unavailable: $id');
  }
  return descriptor.read(record);
}
