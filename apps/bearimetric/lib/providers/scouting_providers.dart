import 'dart:convert';

import 'package:core/core.dart' show CompetitionEvent, CompetitionMatch;
import 'package:grove/grove.dart';
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

List<CompetitionMatch> _sortMatches(List<CompetitionMatch> rawData) {
  final matches = rawData.toList();

  matches.sort((a, b) {
    const levelOrder = {'qm': 0, 'sf': 1, 'f': 2};
    final levelA = levelOrder[a.level] ?? 3;
    final levelB = levelOrder[b.level] ?? 3;
    if (levelA != levelB) return levelA.compareTo(levelB);
    if (a.setNumber != b.setNumber) return a.setNumber.compareTo(b.setNumber);
    return a.matchNumber.compareTo(b.matchNumber);
  });

  return matches;
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

@Riverpod(keepAlive: true)
AsyncValue<List<CompetitionMatch>> matches(Ref ref, String eventKey) {
  if (eventKey == trainingEventKey) {
    return ref.watch(eventsProvider).flatMap((events) {
      if (events.isEmpty) {
        throw StateError('No event is available for training schedules');
      }
      return ref.watch(matchesProvider(events.first.id));
    });
  }
  return ref
      .watch(competitionMatchesProvider(eventKey))
      .whenData((result) => _sortMatches(result.requireAvailable().items));
}

@riverpod
AsyncValue<String?> teamForMatchPosition(
  Ref ref,
  String eventKey,
  int matchNumber,
  ScoutPosition position,
) {
  if (position.isStrategy) return const AsyncData(null);
  return ref
      .watch(matchesProvider(eventKey))
      .when(
        data: (matches) =>
            AsyncData(_findMatch(matches, matchNumber)?.teamNumberAt(position)),
        error: (_, _) => const AsyncData(null),
        loading: AsyncLoading<String?>.new,
      );
}

@riverpod
AsyncValue<Map<ScoutPosition, String>> allTeamsForMatch(
  Ref ref,
  String eventKey,
  int matchNumber,
) {
  return ref
      .watch(matchesProvider(eventKey))
      .when(
        data: (matches) {
          final match = _findMatch(matches, matchNumber);
          return AsyncData({
            if (match != null)
              for (final pos in ScoutPosition.values)
                if (!pos.isStrategy) pos: match.teamNumberAt(pos) ?? '???',
          });
        },
        error: (_, _) => const AsyncData({}),
        loading: AsyncLoading<Map<ScoutPosition, String>>.new,
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

  void setMatchNumber(int matchNumber) {
    state = state.copyWith(matchNumber: matchNumber);
  }

  void nextMatch() {
    if (state.matchNumber != null) {
      state = state.copyWith(matchNumber: state.matchNumber! + 1);
    }
  }

  void previousMatch() {
    if (state.matchNumber != null && state.matchNumber! > 1) {
      state = state.copyWith(matchNumber: state.matchNumber! - 1);
    }
  }

  void setEvent(ScoutingEventSelection event) {
    state = state.copyWith(event: event);
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
      matchNumber: state.matchNumber,
    );
  }

  void clear() {
    state = const ScoutingSession();
  }
}

CompetitionMatch? _findMatch(List<CompetitionMatch> matches, int matchNumber) {
  final sameNumber = matches.where((match) => match.matchNumber == matchNumber);
  return sameNumber.where((match) => match.level == 'qm').firstOrNull ??
      sameNumber.firstOrNull;
}

@riverpod
AsyncValue<int?> teamNumberForSession(Ref ref) {
  final session = ref.watch(scoutingSessionProvider);
  final event = session.event;
  final position = session.position;
  final matchNumber = session.matchNumber;

  if (event == null ||
      position == null ||
      matchNumber == null ||
      position.isStrategy) {
    return const AsyncData(null);
  }
  return ref
      .watch(teamForMatchPositionProvider(event.key, matchNumber, position))
      .whenData((number) => int.tryParse(number ?? ''));
}

@riverpod
AsyncValue<List<String>> allianceTeamsForSession(Ref ref) {
  final session = ref.watch(scoutingSessionProvider);
  final event = session.event;
  final position = session.position;
  final matchNumber = session.matchNumber;

  if (event == null || position == null || matchNumber == null)
    return const AsyncData([]);
  return ref
      .watch(allTeamsForMatchProvider(event.key, matchNumber))
      .whenData(
        (teams) => [
          for (final entry in teams.entries)
            if (entry.key.isRed == position.isRed) entry.value,
        ],
      );
}
