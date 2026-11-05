import 'dart:convert';

import 'package:beariscope/pages/flash_cards/study/flash_card_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FlashCardReview {
  const FlashCardReview(this.team, this.previous, this.index);
  final String team;
  final bool? previous;
  final int index;

  Map<String, Object?> toJson() => {
    'team': team,
    'previous': previous,
    'index': index,
  };
}

class FlashCardProgress {
  const FlashCardProgress({
    this.order = const [],
    this.index = 0,
    this.ratings = const {},
    this.flipped = false,
    this.history = const [],
  });

  final List<String> order;
  final int index;
  final Map<String, bool> ratings;
  final bool flipped;
  final List<FlashCardReview> history;
  bool get complete => index >= order.length;
  String? get current => complete ? null : order[index];

  FlashCardProgress round(List<String> teams, bool shuffle) {
    final order = teams.where((team) => ratings[team] != true).toList();
    if (shuffle && order.length > 1) {
      order.shuffle();
      if (order.first == teams.first) order.add(order.removeAt(0));
    }
    return FlashCardProgress(order: order, ratings: ratings);
  }

  FlashCardProgress reset(List<String> teams, bool shuffle) =>
      const FlashCardProgress().round(teams, shuffle);

  /// Preserve the cursor and round order when an event's roster changes.
  FlashCardProgress reconcile(List<String> teams) {
    final available = teams.toSet();
    final visited = order.take(index).where(available.contains).toList();
    final remaining = order
        .skip(index)
        .where((team) => available.contains(team) && ratings[team] != true)
        .toList();
    final existing = {...visited, ...remaining};
    return FlashCardProgress(
      order: [
        ...visited,
        ...remaining,
        ...teams.where(
          (team) => !existing.contains(team) && ratings[team] != true,
        ),
      ],
      index: visited.length,
      // Keep ratings if a team temporarily disappears from an API roster.
      ratings: ratings,
      flipped: current != null && remaining.firstOrNull == current && flipped,
      // A changed roster can invalidate the saved positions used by Undo.
      history:
          order.length == existing.length && order.every(available.contains)
          ? history
          : const [],
    );
  }

  FlashCardProgress turn() => FlashCardProgress(
    order: order,
    index: index,
    ratings: ratings,
    flipped: !flipped,
    history: history,
  );

  FlashCardProgress rate(bool known) {
    final team = current;
    if (team == null) return this;
    return FlashCardProgress(
      order: order,
      index: index + 1,
      ratings: {...ratings, team: known},
      history: [
        ...history.skip(history.length > 49 ? history.length - 49 : 0),
        FlashCardReview(team, ratings[team], index),
      ],
    );
  }

  FlashCardProgress undo() {
    if (history.isEmpty) return this;
    final last = history.last;
    final restored = {...ratings};
    if (last.previous == null) {
      restored.remove(last.team);
    } else {
      restored[last.team] = last.previous!;
    }
    return FlashCardProgress(
      order: order,
      index: last.index,
      ratings: restored,
      flipped: true,
      history: history.take(history.length - 1).toList(),
    );
  }

  Map<String, Object?> toJson() => {
    'order': order,
    'index': index,
    'ratings': ratings,
    'flipped': flipped,
    'history': history.map((entry) => entry.toJson()).toList(),
  };

  factory FlashCardProgress.fromJson(Map<String, dynamic> json) {
    final order = (json['order'] is List ? json['order'] as List : const [])
        .whereType<String>()
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList();
    final index = json['index'] is int
        ? (json['index'] as int).clamp(0, order.length)
        : 0;
    final ratings = <String, bool>{};
    if (json['ratings'] case final Map values) {
      for (final entry in values.entries) {
        if (entry.key is String && entry.value is bool) {
          ratings[entry.key as String] = entry.value as bool;
        }
      }
    }
    final history = <FlashCardReview>[];
    if (json['history'] case final List entries) {
      for (final entry in entries) {
        if (entry is! Map || entry['index'] is! int) continue;
        final position = entry['index'] as int;
        if (position < 0 ||
            position >= index ||
            order[position] != entry['team']) {
          continue;
        }
        final previous = entry['previous'];
        if (previous != null && previous is! bool) continue;
        // Legacy known-card review rounds may undo back into a known card.
        if (previous == true) continue;
        if (history.isNotEmpty && position <= history.last.index) continue;
        history.add(
          FlashCardReview(order[position], previous as bool?, position),
        );
      }
    }
    return FlashCardProgress(
      order: order,
      index: index,
      ratings: ratings,
      flipped: json['flipped'] == true,
      history: history,
    );
  }
}

class FlashCardStore {
  const FlashCardStore(this.preferences);
  final SharedPreferences preferences;
  static const optionsKey = 'flash_cards.options.v1';
  static String progressKey(String event) => 'flash_cards.progress.v1.$event';

  Map<String, dynamic> _read(String key) {
    try {
      final raw = preferences.getString(key);
      final decoded = raw == null ? null : jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  FlashCardProgress readProgress(String event) =>
      FlashCardProgress.fromJson(_read(progressKey(event)));

  FlashCardOptions readOptions() {
    final json = _read(optionsKey);
    return FlashCardOptions(
      nameFirst: json['nameFirst'] == true,
      shuffled: json['shuffled'] == true,
      showPhotos: json['showPhotos'] != false,
    );
  }

  Future<bool> saveProgress(String event, FlashCardProgress progress) =>
      preferences.setString(progressKey(event), jsonEncode(progress.toJson()));

  Future<bool> saveOptions(FlashCardOptions options) => preferences.setString(
    optionsKey,
    jsonEncode({
      'nameFirst': options.nameFirst,
      'shuffled': options.shuffled,
      'showPhotos': options.showPhotos,
    }),
  );
}
