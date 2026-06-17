import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:pawfinder/data/local_data.dart';
import 'package:pawfinder/data/match_form_store.dart';
import 'package:pawfinder/data/match_json_gen.dart';
import 'package:pawfinder/models/scouting_session.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/api_provider.dart';

part 'scouting_providers.g.dart';

final matchFormStoreProvider = Provider<MatchFormStore>((ref) {
  return MatchFormStore();
});

List<ScoutingMatch> _parseAndSortMatches(List<dynamic> rawData) {
  final matches = rawData
      .whereType<Map>()
      .map(
        (e) =>
            ScoutingMatch.fromJson(e.map((k, v) => MapEntry(k.toString(), v))),
      )
      .toList();

  matches.sort((a, b) {
    const levelOrder = {'qm': 0, 'sf': 1, 'f': 2};
    final levelA = levelOrder[a.compLevel] ?? 3;
    final levelB = levelOrder[b.compLevel] ?? 3;
    if (levelA != levelB) return levelA.compareTo(levelB);
    if (a.setNumber != b.setNumber) return a.setNumber.compareTo(b.setNumber);
    return a.matchNumber.compareTo(b.matchNumber);
  });

  return matches;
}

@riverpod
Future<List<ScoutingEvent>> events(Ref ref) async {
  final client = ref.read(honeycombClientProvider);
  final year = DateTime.now().year.toString();

  final data = await client.get<List<dynamic>>(
    '/events',
    queryParams: {'team': 'frc2046', 'year': year},
  );

  final events = data
      .map((e) => ScoutingEvent.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  events.sort((a, b) {
    if (a.startDate == null && b.startDate == null) return 0;
    if (a.startDate == null) return 1;
    if (b.startDate == null) return -1;
    return a.startDate!.compareTo(b.startDate!);
  });

  return events;
}

// fetches schedule from honeycomb — caching is handled by the honeycomb client
@Riverpod(keepAlive: true)
Future<List<ScoutingMatch>> matches(Ref ref, String eventKey) async {
  final client = ref.read(honeycombClientProvider);

  final rawData = await client.get<List<dynamic>>(
    '/matches',
    queryParams: {'event': eventKey},
    cachePolicy: CachePolicy.networkFirst,
  );

  return _parseAndSortMatches(rawData);
}

@riverpod
Future<String?> teamForMatchPosition(
  Ref ref,
  String eventKey,
  int matchNumber,
  ScoutPosition position,
) async {
  if (position.isStrategy) return null;
  try {
    final allMatches = await ref.watch(matchesProvider(eventKey).future);
    final match = _findMatch(allMatches, matchNumber);
    if (match == null) return null;
    final num = match.teamNumberAt(position);
    return num == '???' ? null : num;
  } catch (_) {
    return null;
  }
}

@riverpod
Future<Map<ScoutPosition, String>> allTeamsForMatch(
  Ref ref,
  String eventKey,
  int matchNumber,
) async {
  try {
    final allMatches = await ref.watch(matchesProvider(eventKey).future);
    final match = _findMatch(allMatches, matchNumber);
    if (match == null) return {};
    return {
      for (final pos in ScoutPosition.values)
        if (!pos.isStrategy) pos: match.teamNumberAt(pos),
    };
  } catch (_) {
    return {};
  }
}

@riverpod
Future<List<Scout>> scouts(Ref ref) async {
  final client = ref.read(honeycombClientProvider);

  final data = await client.get<List<dynamic>>(
    '/scouts',
    cachePolicy: CachePolicy.networkFirst,
  );

  final scouts = data
      .map((e) => Scout.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  scouts.sort((a, b) => a.name.compareTo(b.name));

  return scouts;
}

@Riverpod(keepAlive: true)
class ScoutingSessionNotifier extends _$ScoutingSessionNotifier {
  static const _eventKey = 'selected_event';
  static const _positionKey = 'selected_position';

  @override
  ScoutingSession build() {
    ScoutingEvent? savedEvent;
    ScoutPosition? savedPosition;

    final savedEventJson = prefs.getString(_eventKey);
    if (savedEventJson != null) {
      try {
        savedEvent = ScoutingEvent.fromJson(jsonDecode(savedEventJson));
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

  void setEvent(ScoutingEvent event) {
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

  MatchIdentity? createMatchIdentity() {
    final s = state;
    if (s.position != null &&
        s.matchNumber != null &&
        s.event != null &&
        s.scout != null) {
      return (
        position: s.position!,
        matchNumber: s.matchNumber!,
        event: s.event!,
        scout: s.scout!,
      );
    }
    return null;
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

ScoutingMatch? _findMatch(List<ScoutingMatch> matches, int matchNumber) {
  // prefer qual matches
  try {
    return matches.firstWhere(
      (m) => m.compLevel == 'qm' && m.matchNumber == matchNumber,
    );
  } catch (_) {}
  try {
    return matches.firstWhere((m) => m.matchNumber == matchNumber);
  } catch (_) {}
  return null;
}

@riverpod
Future<int?> teamNumberForSession(Ref ref) async {
  final session = ref.watch(scoutingSessionProvider);
  final event = session.event;
  final position = session.position;
  final matchNumber = session.matchNumber;

  if (event == null ||
      position == null ||
      matchNumber == null ||
      position.isStrategy) {
    return null;
  }

  final numStr = await ref.watch(
    teamForMatchPositionProvider(event.key, matchNumber, position).future,
  );
  return int.tryParse(numStr ?? '');
}

@riverpod
Future<List<String>> allianceTeamsForSession(Ref ref) async {
  final session = ref.watch(scoutingSessionProvider);
  final event = session.event;
  final position = session.position;
  final matchNumber = session.matchNumber;

  if (event == null || position == null || matchNumber == null) return [];

  final allTeams = await ref.watch(
    allTeamsForMatchProvider(event.key, matchNumber).future,
  );

  final isRed = position.isRed;
  return [
    for (final entry in allTeams.entries)
      if (entry.key.isRed == isRed) entry.value,
  ];
}
