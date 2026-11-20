import 'package:core/core.dart' show ScoutingReport;
import 'package:grove/grove.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_logic.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_preferences_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/competition_provider.dart';

final scoutAuditSnapshotProvider = Provider<AsyncValue<ScoutAuditSnapshot>>((
  ref,
) {
  final eventKey = ref.watch(currentEventProvider);
  final threshold = ref.watch(scoutAuditIncorrectThresholdProvider);

  final reports = ref.watch(
    groveQueryProvider(ref.watch(scoutingQueryProvider)),
  );
  final matches = ref.watch(competitionMatchesProvider(eventKey));
  return reports.flatMap(
    (docs) => matches.whenData((schedule) {
      docs.requireComplete();
      schedule.requireComplete();
      if (!schedule.items.any(
        (match) =>
            match.level == 'qm' &&
            (match.red?.teams.length ?? 0) >= 3 &&
            (match.blue?.teams.length ?? 0) >= 3,
      )) {
        throw const GroveException(
          'schedule_unavailable',
          'The event schedule is not available yet.',
        );
      }

      return buildScoutAuditSnapshot(
        docs: docs.items,
        tbaMatches: schedule.items,
        eventKey: eventKey,
        incorrectThreshold: threshold,
      );
    }),
  );
});

List<ScoutingReport> matchDocsForMatch(
  List<ScoutingReport> docs,
  String eventKey,
  int matchNumber,
) {
  return docs
      .where((doc) {
        return doc.kind == 'match' &&
            doc.eventKey == eventKey &&
            (doc.data['matchNumber'] == matchNumber ||
                int.tryParse(doc.data['matchNumber']?.toString() ?? '') ==
                    matchNumber);
      })
      .toList(growable: false);
}
