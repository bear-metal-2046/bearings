import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/grove_provider.dart';

/// Downloads existing reports into the local form editor. An unsubmitted draft
/// is never replaced by a remote report for the same match slot.
final scoutSyncServiceProvider = Provider<ScoutSyncService>(
  ScoutSyncService.new,
);

class ScoutSyncService {
  const ScoutSyncService(this.ref);
  final Ref ref;

  Future<void> syncDownEvent(String eventKey) async {
    final grove = ref.read(bearingsGroveProvider);
    final store = ref.read(matchFormStoreProvider);
    final query = grove
        .query<ScoutingReport>()
        .where(ScoutingReport.event.equals(eventKey))
        .where(ScoutingReport.reportType.equals('match'));
    final result = await grove.fetch(query, cacheEntities: true);
    for (final report in result.requireComplete().items) {
      final form = report.toMatch();
      if (form.matchNumber <= 0 || form.pos < 0 || form.pos > 5) continue;
      if (store.load(form.eventKey, form.matchNumber, form.pos) == null) {
        store.save(form);
      }
    }
  }
}
