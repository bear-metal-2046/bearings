import 'dart:async';

import 'package:beariscope/pages/flash_cards/flash_card_progress.dart';

/// Owns study progress and its persistence; the deck widget owns animation.
class FlashCardSession {
  FlashCardSession({
    required this.store,
    required this.scope,
    required List<String> teams,
    required bool shuffled,
    required this.onSaveResult,
  }) {
    final saved = store.readProgress(scope);
    progress = saved.order.isEmpty && saved.ratings.isEmpty
        ? saved.round(teams, shuffled)
        : saved.reconcile(teams);
    _persist(progress);
  }

  final FlashCardStore store;
  final String scope;
  final void Function(bool) onSaveResult;
  late FlashCardProgress progress;
  FlashCardProgress? pending;

  void _persist(FlashCardProgress value) {
    unawaited(
      store
          .saveProgress(scope, value)
          .then<void>(
            onSaveResult,
            onError: (Object _, StackTrace _) => onSaveResult(false),
          ),
    );
  }

  void update({
    required List<String> teams,
    required bool shuffled,
    required bool shuffleChanged,
    required bool nameFirstChanged,
  }) {
    progress = progress.reconcile(teams);
    if (pending != null) {
      pending = pending!.reconcile(teams);
      if (shuffleChanged) pending = pending!.round(teams, shuffled);
      _persist(pending!);
      return;
    }
    if (shuffleChanged) {
      progress = progress.round(teams, shuffled);
    } else if (nameFirstChanged && progress.flipped) {
      progress = progress.turn();
    }
    _persist(progress);
  }

  void flip() {
    progress = progress.turn();
    _persist(progress);
  }

  void prepareRating(bool known) {
    pending = progress.rate(known);
    // Save the decision even if the page closes during the exit animation.
    _persist(pending!);
  }

  void finishRating(List<String> teams) {
    progress = pending!.reconcile(teams);
    pending = null;
    _persist(progress);
  }

  void undo() {
    progress = progress.undo();
    _persist(progress);
  }

  void startRound(List<String> teams, bool shuffled) {
    progress = progress.round(teams, shuffled);
    _persist(progress);
  }

  void reset(List<String> teams, bool shuffled) {
    pending = null;
    progress = progress.reset(teams, shuffled);
    _persist(progress);
  }
}
