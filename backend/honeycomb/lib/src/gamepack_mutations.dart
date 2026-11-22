import 'dart:convert';

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
  if (mutation.type == gamePackEntity.type) {
    return (data) {
      final gamePack = gamePackEntity.decode(data);
      _validateLibraryDocument(gamePack.document);
      return gamePackEntity.encode(gamePack);
    };
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
    if (binding.gamePack?.id != observation.gamePack.id) {
      throw const FormatException(
        'This GamePack is not assigned to the event.',
      );
    }
    final gamePack = _requireRecord(
      store,
      gamePackEntity,
      binding.gamePack!.id,
      'GamePack',
    );
    final definition = gamePack.definition;
    final form = definition.formById(observation.formId);
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
          'A correction must preserve the observation subject and GamePack.',
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
        final field = definition.fieldById[control.field]!;
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
      definition.validateAnswers(observation.answers, formId: form.id);
      form.validateRankings(
        observation.answers,
        definition.fieldById,
        roster: roster,
      );
    }
    final confirmed = {
      ...gamePackObservationEntity.encode(observation),
      'author': actor,
    };
    return confirmed;
  };
}

/// Enforces deletion and form-schema locks for library GamePacks.
void authorizeGamePackUpdate(EntityStore store, EntityMutation mutation) {
  if (mutation.kind == MutationKind.delete) {
    _requireRecord(store, gamePackEntity, mutation.id, 'GamePack');
    if (store.isGamePackAssigned(mutation.id) ||
        store.hasGamePackObservations(mutation.id)) {
      throw const GroveException(
        'conflict',
        'Unassign this GamePack before deleting it. '
            'GamePacks with saved data cannot be deleted.',
      );
    }
    return;
  }
  if (mutation.kind != MutationKind.update) return;

  final previous = _requireRecord(
    store,
    gamePackEntity,
    mutation.id,
    'GamePack',
  );
  final updated = gamePackEntity.decode(
    applyChanges(gamePackEntity.encode(previous), mutation.changes),
  );
  _validateLibraryDocument(updated.document);
  final hasData =
      store.hasGamePackObservations(mutation.id) ||
      store.gamePackEvents(mutation.id).any(store.hasEventObservations);
  if (hasData &&
      _formSchema(previous.document) != _formSchema(updated.document)) {
    throw const GroveException(
      'conflict',
      'Forms cannot be edited after an assigned event has saved data.',
    );
  }
}

/// Locks an event's GamePack assignment after its first observation.
void authorizeEventGamePackMutation(
  EntityStore store,
  EntityMutation mutation,
) {
  if (mutation.kind == MutationKind.create ||
      mutation.kind == MutationKind.update ||
      mutation.kind == MutationKind.delete) {
    if (store.hasEventObservations(mutation.id)) {
      throw const GroveException(
        'conflict',
        'This event has saved GamePack data, so its assignment is locked.',
      );
    }
  }
  if (mutation.kind == MutationKind.update) {
    final updated = eventGamePackEntity.decode(
      applyChanges(
        eventGamePackEntity.encode(
          _requireRecord(
            store,
            eventGamePackEntity,
            mutation.id,
            'Event GamePack assignment',
          ),
        ),
        mutation.changes,
      ),
    );
    _validateBinding(store, updated);
  }
}

/// Keeps observations append-only after their initial submission.
void authorizeGamePackObservationMutation(EntityMutation mutation) {
  if (mutation.kind != MutationKind.create) {
    throw const GroveException(
      'forbidden',
      'GamePack observations are append-only.',
    );
  }
}

void _validateLibraryDocument(dynamic document) {
  if (utf8.encode(jsonEncode(document)).length > 1024 * 1024) {
    throw const FormatException('A GamePack document must be up to 1 MB.');
  }
}

/// The fields referenced by form controls are captured answer schema too.
/// Other fields, calculations, layouts, and metadata remain editable.
String _formSchema(dynamic document) {
  if (document is! Json) return canonicalJson({'invalid': document});
  final rawForms = document['forms'];
  final forms = rawForms is List ? rawForms : const <dynamic>[];
  try {
    final fieldIds = <String>{};
    for (final raw in forms) {
      if (raw is! Map) throw const FormatException('Invalid form');
      final form = GamePackForm.fromJson(Map<String, dynamic>.from(raw));
      fieldIds.addAll(form.controls.map((control) => control.field));
    }
    final rawFields = document['fields'];
    final fields = rawFields is List
        ? rawFields.where((field) {
            if (field is! Map) return false;
            return fieldIds.contains(field['id']);
          }).toList()
        : const <dynamic>[];
    return canonicalJson({'forms': forms, 'fields': fields});
  } on Object {
    // If a stored form is already unreadable, fail closed for its schema while
    // still allowing edits to other document sections.
    return canonicalJson({'forms': forms, 'fields': document['fields']});
  }
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

void _validateBinding(EntityStore store, EventGamePack binding) {
  final event = _requireRecord(
    store,
    competitionEventEntity,
    binding.id,
    'Event',
  );
  if (binding.gamePack == null) return;
  final gamePack = _requireRecord(
    store,
    gamePackEntity,
    binding.gamePack!.id,
    'GamePack',
  );
  _validateLibraryDocument(gamePack.document);
  final definition = gamePack.definition;
  if (!definition.forms.any((form) => form.controls.isNotEmpty)) {
    throw const FormatException(
      'Add at least one question before assigning this GamePack.',
    );
  }
  if (definition.season case final year? when year != event.season) {
    throw FormatException(
      'The GamePack is for $year, not ${event.season}.',
    );
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
