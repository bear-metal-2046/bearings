import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bearimetric/models/scouting_session.dart';
import 'package:core/core.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:bearimetric/store/strat_state.dart';

import 'scouting_providers.dart';

class ScoutingFlowController {
  final Ref _ref;
  final List<DateTime> _nextMatchTapTimes = <DateTime>[];

  ScoutingFlowController(this._ref);

  bool shouldWarnForRapidNextMatchTaps() {
    final now = DateTime.now();
    _nextMatchTapTimes.removeWhere(
      (time) => now.difference(time) > const Duration(seconds: 5),
    );
    _nextMatchTapTimes.add(now);
    return _nextMatchTapTimes.length >= 3;
  }

  bool _staging = false;

  /// Persist the current form before leaving it. Training stays device-local.
  Future<bool> submitCurrent() async {
    if (_staging) return false;
    final session = _ref.read(scoutingSessionProvider);
    final eventKey = session.event?.key;
    final number = session.matchNumber;
    final position = session.position;
    if (eventKey == null ||
        number == null ||
        position == null ||
        eventKey == trainingEventKey)
      return true;
    _staging = true;
    try {
      final grove = _ref.read(bearingsGroveProvider);
      if (position.isStrategy) {
        final identity = _ref
            .read(scoutingSessionProvider.notifier)
            .createMatchIdentity();
        final draft = identity == null
            ? null
            : loadStratFormDataForIdentity(identity);
        if (draft != null)
          await grove.stage(
            ScoutingReport.fromPayload(
              draft.toJson()..remove('id'),
              id: draft.id,
              timestamp: draft.lastModified,
            ),
          );
      } else {
        final draft = _ref
            .read(matchFormStoreProvider)
            .load(eventKey, number, position.posIndex);
        if (draft != null) await grove.stage(ScoutingReport.fromMatch(draft));
      }
      if (_ref.mounted)
        _ref.read(scoutingSubmissionErrorProvider.notifier).set(null);
      return true;
    } catch (error) {
      if (_ref.mounted)
        _ref
            .read(scoutingSubmissionErrorProvider.notifier)
            .set('Could not save this submission: $error');
      return false;
    } finally {
      _staging = false;
    }
  }

  Future<bool> nextMatch() async {
    if (!await submitCurrent() || !_ref.mounted) return false;
    _ref.read(scoutingSessionProvider.notifier).nextMatch();
    return true;
  }

  Future<bool> previousMatch() async {
    final current = _ref.read(scoutingSessionProvider).matchNumber;
    if (current == null ||
        current <= 1 ||
        !await submitCurrent() ||
        !_ref.mounted)
      return false;
    _ref.read(scoutingSessionProvider.notifier).previousMatch();
    return true;
  }
}

final scoutingFlowControllerProvider = Provider<ScoutingFlowController>(
  (ref) => ScoutingFlowController(ref),
);

class ScoutingSubmissionError extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? message) => state = message;
}

final scoutingSubmissionErrorProvider =
    NotifierProvider<ScoutingSubmissionError, String?>(
      ScoutingSubmissionError.new,
    );
