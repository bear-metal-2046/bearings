import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pawfinder/data/upload_queue.dart';
import 'package:pawfinder/services/scout_upload_service.dart';
import 'package:pawfinder/store/strat_state.dart';

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

  bool markCurrentMatchForUpload() {
    final session = _ref.read(scoutingSessionProvider);
    final eventKey = session.event?.key;
    final matchNumber = session.matchNumber;
    final pos = session.position?.posIndex;
    if (eventKey == null || matchNumber == null || pos == null) return false;

    final data = _ref
        .read(matchFormStoreProvider)
        .load(eventKey, matchNumber, pos);
    if (data == null) return false;

    _ref.read(uploadQueueProvider.notifier).enqueue(data.id);
    return true;
  }

  bool markCurrentStratForUpload() {
    final identity = _ref
        .read(scoutingSessionProvider.notifier)
        .createMatchIdentity();
    if (identity == null) return false;

    final stratDoc = loadStratFormDataForIdentity(identity);
    if (stratDoc == null) return false;

    _ref.read(uploadQueueProvider.notifier).enqueue(stratDoc.id);
    return true;
  }

  bool nextMatch() {
    markCurrentMatchForUpload();
    markCurrentStratForUpload();
    unawaited(_ref.read(scoutUploadServiceProvider).drainIfOnline());
    _ref.read(scoutingSessionProvider.notifier).nextMatch();
    return true;
  }

  bool previousMatch() {
    final current = _ref.read(scoutingSessionProvider).matchNumber;
    if (current == null || current <= 1) return false;

    markCurrentMatchForUpload();
    markCurrentStratForUpload();
    unawaited(_ref.read(scoutUploadServiceProvider).drainIfOnline());
    _ref.read(scoutingSessionProvider.notifier).previousMatch();
    return true;
  }
}

final scoutingFlowControllerProvider = Provider<ScoutingFlowController>(
  (ref) => ScoutingFlowController(ref),
);
