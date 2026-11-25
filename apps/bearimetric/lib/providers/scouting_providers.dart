import 'dart:convert';

import 'package:core/core.dart'
    show CompetitionEvent, CompetitionMatch, practiceGamePackKey;
import 'package:grove/grove.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:services/providers/gamepack_provider.dart';
import 'package:bearimetric/data/local_data.dart';
import 'package:bearimetric/models/scouting_session.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/competition_provider.dart';

part 'scouting_providers.g.dart';

extension ScoutingStations on CompetitionMatch {
  String? teamNumberAt(ScoutPosition position) {
    final teams = (position.isRed ? red : blue)?.teams;
    final index = position.allianceIndex;
    if (teams == null || index < 0 || index >= teams.length) return null;
    return teams[index].id.replaceFirst('frc', '');
  }
}

@riverpod
AsyncValue<List<CompetitionEvent>> events(Ref ref) {
  final year = DateTime.now().year;
  return ref
      .watch(competitionEventsProvider((year: year, team: 'frc2046')))
      .whenData((data) {
        final events = data.toList();
        events.sort((a, b) {
          if (a.startDate == null && b.startDate == null) return 0;
          if (a.startDate == null) return -1;
          if (b.startDate == null) return 1;
          return a.startDate!.compareTo(b.startDate!);
        });
        return events;
      });
}

final practiceScheduleProvider = Provider.autoDispose<AsyncValue<String?>>((
  ref,
) {
  return ref.watch(eventGamePackBindingProvider(practiceGamePackKey)).flatMap((
    binding,
  ) {
    final event = binding?.practiceEvent?.id;
    return event != null
        ? AsyncData(event)
        : ref
              .watch(eventsProvider)
              .whenData((events) => events.firstOrNull?.id);
  });
});

@Riverpod(keepAlive: true)
AsyncValue<List<CompetitionMatch>> matches(Ref ref, String eventKey) {
  if (eventKey == trainingEventKey) {
    return ref.watch(practiceScheduleProvider).flatMap((event) {
      if (event == null) {
        throw StateError('No event is available for training schedules');
      }
      return ref.watch(matchesProvider(event));
    });
  }
  return ref
      .watch(competitionMatchesProvider(eventKey))
      .whenData(
        (result) =>
            result.requireAvailable().items.toList()
              ..sort(compareScoutingMatches),
      );
}

@Riverpod(keepAlive: true)
class ScoutingSessionNotifier extends _$ScoutingSessionNotifier {
  static const _eventKey = 'selected_event';
  static const _positionKey = 'selected_position';

  @override
  ScoutingSession build() {
    ScoutingEventSelection? savedEvent;
    ScoutPosition? savedPosition;

    final savedEventJson = prefs.getString(_eventKey);
    if (savedEventJson != null) {
      try {
        savedEvent = ScoutingEventSelection.fromJson(
          jsonDecode(savedEventJson),
        );
      } catch (_) {}
    }

    final savedPositionString = prefs.getString(_positionKey);
    if (savedPositionString != null) {
      try {
        savedPosition = ScoutPosition.values.firstWhere(
          (pos) => pos.name == savedPositionString,
        );
      } catch (_) {}
    }

    return ScoutingSession(event: savedEvent, position: savedPosition);
  }

  void selectMatch(CompetitionMatch match) {
    state = state.copyWith(matchId: match.id);
  }

  void setEvent(ScoutingEventSelection event) {
    if (state.event?.key != event.key) {
      state = ScoutingSession(
        event: event,
        position: state.position,
        scout: state.scout,
      );
    } else {
      state = state.copyWith(event: event);
    }
    prefs.setString(_eventKey, jsonEncode(event.toJson()));
  }

  void setPosition(ScoutPosition position) {
    state = state.copyWith(position: position);
    prefs.setString(_positionKey, position.name);
  }

  void setScout(Scout scout) {
    state = state.copyWith(scout: scout);
  }

  void exitToScoutSelect() {
    state = ScoutingSession(
      event: state.event,
      position: state.position,
      matchId: state.matchId,
    );
  }

  void clear() {
    state = const ScoutingSession();
  }
}

String scoutingMatchLabel(CompetitionMatch match) => switch (match.level) {
  'qm' => 'Match ${match.matchNumber}',
  'ef' => 'Eighthfinal ${match.setNumber} · Match ${match.matchNumber}',
  'qf' => 'Quarterfinal ${match.setNumber} · Match ${match.matchNumber}',
  'sf' => 'Semifinal ${match.setNumber} · Match ${match.matchNumber}',
  'f' => 'Final · Match ${match.matchNumber}',
  _ => match.id.split('_').last.toUpperCase(),
};

int compareScoutingMatches(CompetitionMatch left, CompetitionMatch right) {
  final dateOrder = (left.scheduledAt?.millisecondsSinceEpoch ?? 0).compareTo(
    right.scheduledAt?.millisecondsSinceEpoch ?? 0,
  );
  if (dateOrder != 0) return dateOrder;
  const levelOrder = {'qm': 0, 'ef': 1, 'qf': 2, 'sf': 3, 'f': 4};
  final level = (levelOrder[left.level] ?? 5).compareTo(
    levelOrder[right.level] ?? 5,
  );
  if (level != 0) return level;
  final set = left.setNumber.compareTo(right.setNumber);
  if (set != 0) return set;
  final number = left.matchNumber.compareTo(right.matchNumber);
  return number != 0 ? number : left.id.compareTo(right.id);
}

bool canScoutMatch(CompetitionMatch match, ScoutPosition position) {
  final teams = (position.isRed ? match.red : match.blue)?.teams;
  return teams != null &&
      teams.isNotEmpty &&
      (position.isStrategy || position.allianceIndex < teams.length);
}
