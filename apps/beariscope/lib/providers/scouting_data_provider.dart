import 'package:beariscope/providers/current_event_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/grove_provider.dart';

final scoutingQueryProvider = Provider<GroveQuery<ScoutingReport>>((ref) {
  final grove = ref.watch(bearingsGroveProvider);
  final event = ref.watch(currentEventProvider);
  return grove.query<ScoutingReport>().where(
    ScoutingReport.event.equals(event),
  );
});

/// Subscribe to the requested reports and reuse the event snapshot offline
/// until this narrower query has its own local snapshot.
AsyncValue<List<ScoutingReport>> watchScoutingReports(
  Ref ref,
  String kind, {
  String? matchKey,
  String? subject,
}) {
  const reportMatchKey = EntityField<ScoutingReport, String>(
    'data.meta.matchKey',
  );
  const reportUserId = EntityField<ScoutingReport, String>('data.meta.userId');
  final event = ref.watch(scoutingQueryProvider);
  var query = event.where(ScoutingReport.reportType.equals(kind));
  if (matchKey != null) query = query.where(reportMatchKey.equals(matchKey));
  if (subject != null) query = query.where(reportUserId.equals(subject));

  return ref.watch(groveQueryProvider(query)).flatMap((result) {
    if (result.offline && !result.hasSnapshot) {
      return ref
          .watch(groveQueryProvider(event))
          .whenData(
            (fallback) => [
              for (final report in fallback.requireAvailable().items)
                if (report.kind == kind &&
                    (matchKey == null ||
                        report.meta?['matchKey'] == matchKey) &&
                    (subject == null || report.meta?['userId'] == subject))
                  report,
            ],
          );
    }
    return AsyncData(result.requireAvailable().items);
  });
}
