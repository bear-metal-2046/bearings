import 'package:core/core.dart';

import 'dart:convert';

import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/study/flash_card_progress.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/utils/competition_media_display.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/competition_provider.dart';

class FlashCardLibrary extends Notifier<List<FlashCardDeckDefinition>> {
  static const storageKey = 'flash_cards.library.v1';

  @override
  List<FlashCardDeckDefinition> build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(storageKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final decks = <String, FlashCardDeckDefinition>{};
      for (final item in decoded.whereType<Map>()) {
        try {
          final deck = FlashCardDeckDefinition.fromJson(
            Map<String, dynamic>.from(item),
          );
          decks[deck.id] = deck;
        } on FormatException {
          continue;
        }
      }
      return decks.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<FlashCardDeckDefinition> next) async {
    final previous = state;
    state = next;
    try {
      final saved = await ref
          .read(sharedPreferencesProvider)
          .setString(
            storageKey,
            jsonEncode(next.map((deck) => deck.toJson()).toList()),
          );
      if (!saved) throw StateError('The deck library could not be saved.');
    } catch (_) {
      if (identical(state, next)) state = previous;
      rethrow;
    }
  }

  Future<FlashCardDeckDefinition> save(FlashCardDeckDefinition deck) async {
    await _save([deck, ...state.where((item) => item.id != deck.id)]);
    return deck;
  }

  Future<FlashCardDeckDefinition> importDeck(
    FlashCardDeckDefinition deck,
  ) async {
    final existing = state
        .where((item) => item.shareCode == deck.shareCode)
        .firstOrNull;
    if (existing != null) return existing;
    return save(deck);
  }

  Future<void> delete(FlashCardDeckDefinition deck) async {
    await _save(state.where((item) => item.id != deck.id).toList());
    await ref
        .read(sharedPreferencesProvider)
        .remove(FlashCardStore.progressKey(deck.progressScope));
  }
}

final flashCardLibraryProvider =
    NotifierProvider<FlashCardLibrary, List<FlashCardDeckDefinition>>(
      FlashCardLibrary.new,
    );

FlashCardDeckDefinition? findFlashCardDeck(
  Iterable<FlashCardDeckDefinition> decks,
  String? id,
) => decks.where((deck) => deck.id == id).firstOrNull;

/// Apply the same filtering, deduplication and ordering to every study roster.
List<Team> normalizeFlashCardRoster(Iterable<Team> teams) {
  final byNumber = <int, Team>{};
  for (final team in teams) {
    if (team.number > 0) byNumber[team.number] = team;
  }
  return byNumber.values.toList()..sort((a, b) => a.number.compareTo(b.number));
}

AsyncValue<List<Team>> normalizeCurrentFlashCardRoster(
  AsyncValue<QueryResult<CompetitionTeam>> rows,
) => rows.whenData(
  (items) => normalizeFlashCardRoster(
    items.requireAvailable().items.map(Team.fromCompetition),
  ),
);

final flashCardEventCatalogProvider = Provider.autoDispose
    .family<AsyncValue<List<EventOption>>, int>((ref, year) {
      return ref
          .watch(competitionEventsProvider((year: year, team: null)))
          .whenData(
            (events) =>
                events
                    .map(EventOption.fromCompetition)
                    .where((event) => event.key.isNotEmpty)
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name)),
          );
    });

/// These providers take explicit event keys and never read currentEventProvider.
final flashCardEventRosterProvider = Provider.autoDispose
    .family<AsyncValue<List<Team>>, String>(
      (ref, event) => normalizeCurrentFlashCardRoster(
        ref.watch(competitionTeamsProvider(event)),
      ),
    );

List<Team> combineFlashCardRosters(Map<String, List<Team>> rosters) {
  final combined = <int, Team>{};
  // Later seasons win if a team's name or metadata changed.
  for (final event in rosters.keys.toList()..sort()) {
    for (final team in rosters[event]!) {
      if (team.number <= 0) continue;
      final previous = combined[team.number];
      combined[team.number] = Team(
        key: 'frc${team.number}',
        number: team.number,
        name: team.name,
        website: team.website ?? previous?.website,
        colors: team.colors ?? previous?.colors,
      );
    }
  }
  return combined.values.toList()..sort((a, b) => a.number.compareTo(b.number));
}

/// Resolve positions before combining rosters so removing a team applies to all
/// of its appearances. API response order never determines a team's position.
Set<int> resolveFlashCardExcludedTeams(
  Map<String, List<int>> overrides,
  Map<String, List<Team>> rosters,
) {
  final excluded = <int>{};
  for (final entry in overrides.entries) {
    final roster = normalizeFlashCardRoster(rosters[entry.key] ?? []);
    for (final index in entry.value) {
      if (index >= 0 && index < roster.length) {
        excluded.add(roster[index].number);
      }
    }
  }
  return excluded;
}

/// Choose one reference per excluded team, preferring the smallest roster index
/// to keep shared codes compact. Event keys break ties deterministically.
Map<String, List<int>> buildFlashCardTeamOverrides(
  Set<int> excludedTeams,
  Map<String, List<Team>> rosters,
) {
  final references = <int, (String, int)>{};
  for (final event in rosters.keys.toList()..sort()) {
    final roster = normalizeFlashCardRoster(rosters[event]!);
    for (var index = 0; index < roster.length; index++) {
      final team = roster[index].number;
      if (!excludedTeams.contains(team)) continue;
      final previous = references[team];
      if (previous == null || index < previous.$2) {
        references[team] = (event, index);
      }
    }
  }
  final result = <String, List<int>>{};
  for (final (event, index) in references.values) {
    result.putIfAbsent(event, () => []).add(index);
  }
  for (final indexes in result.values) {
    indexes.sort();
  }
  return result;
}

List<Team> flashCardTeamsForDeck(
  FlashCardDeckDefinition deck,
  Map<String, List<Team>> rosters,
) {
  final selected = {
    for (final event in deck.eventKeys) event: rosters[event] ?? <Team>[],
  };
  final excluded = resolveFlashCardExcludedTeams(
    deck.excludedTeamIndexes,
    selected,
  );
  return combineFlashCardRosters(selected)
      .where((team) => !excluded.contains(team.number))
      .toList();
}

/// Pick usable media per team and type, preferring later event keys.
Map<String, List<CompetitionMedia>> combineFlashCardMedia(
  Map<String, List<CompetitionMedia>> sources,
) {
  final chosen = <(String, String), String>{};
  final result = <String, List<CompetitionMedia>>{};
  for (final event in sources.keys.toList()..sort((a, b) => b.compareTo(a))) {
    for (final record in sources[event]!) {
      if (!record.isAvatar && !record.isPhoto) continue;
      final hasPreview = record.previewImageUrl != null;
      if (!hasPreview &&
          (!record.isAvatar || record.avatarBytes?.isNotEmpty != true)) {
        continue;
      }
      for (final teamKey in {for (final team in record.teams) team.id}) {
        final source = chosen.putIfAbsent((teamKey, record.type), () => event);
        if (source == event) {
          result.putIfAbsent(teamKey, () => []).add(record);
        }
      }
    }
  }
  return result;
}

final flashCardCustomTeamsProvider = Provider.autoDispose
    .family<AsyncValue<List<Team>>, String>((ref, id) {
      final deck = findFlashCardDeck(ref.watch(flashCardLibraryProvider), id);
      if (deck == null) {
        return AsyncError(StateError('Deck not found.'), StackTrace.current);
      }
      final rosters = {
        for (final event in deck.eventKeys)
          event: ref.watch(flashCardEventRosterProvider(event)),
      };
      final ready = <String, List<Team>>{};
      for (final entry in rosters.entries) {
        final roster = entry.value;
        if (roster.hasError) {
          return AsyncError(
            StateError('Could not load teams for ${entry.key}.'),
            roster.stackTrace ?? StackTrace.current,
          );
        }
        if (roster.value case final teams?) ready[entry.key] = teams;
      }
      if (ready.length != rosters.length) return const AsyncLoading();
      return AsyncData(flashCardTeamsForDeck(deck, ready));
    });

final flashCardCustomMediaProvider = Provider.autoDispose
    .family<AsyncValue<Map<String, List<CompetitionMedia>>>, String>((ref, id) {
      final deck = findFlashCardDeck(ref.watch(flashCardLibraryProvider), id);
      if (deck == null) return const AsyncData({});
      return AsyncData(
        combineFlashCardMedia({
          for (final event in deck.eventKeys)
            event: ref.watch(competitionMediaProvider(event)).value ?? const [],
        }),
      );
    });
