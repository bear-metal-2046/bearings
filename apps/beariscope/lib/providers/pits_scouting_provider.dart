import 'package:core/core.dart' show PitLayout, ScoutingReport;
import 'package:grove/grove.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:beariscope/models/pits_scouting_models.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/nexus_event_key_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/competition_provider.dart';

final pitsSearchControllerProvider = Provider((ref) {
  final controller = TextEditingController();
  ref.onDispose(controller.dispose);
  return controller;
});

final pitsSearchFocusNodeProvider = Provider((ref) {
  final focusNode = FocusNode();
  ref.onDispose(focusNode.dispose);
  return focusNode;
});

//teams that are eligible for pits scouting (at the event and not already scouted)
final pitsTeamsProvider = Provider<AsyncValue<List<Team>>>((ref) {
  final teamsAsync = ref
      .watch(competitionTeamsProvider(ref.watch(currentEventProvider)))
      .whenData((result) => result.requireAvailable().items);
  return teamsAsync.whenData(parsePitsTeams);
});

final pitsReportsProvider = Provider<AsyncValue<Map<int, ScoutingReport>>>((
  ref,
) {
  return watchScoutingReports(ref, 'pits').whenData((reports) {
    final latest = <int, ScoutingReport>{};
    for (final report in reports) {
      final raw = report.data['teamNumber'];
      final team = raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '');
      if (team == null) continue;
      final previous = latest[team];
      if (previous == null || report.timestamp.isAfter(previous.timestamp)) {
        latest[team] = report;
      }
    }
    return latest;
  });
});

final pitsMapProvider =
    Provider.autoDispose<AsyncValue<QueryResult<PitLayout>?>>(
      (ref) => ref.watch(nexusEventKeyProvider).flatMap((key) {
        if (key == null || key.isEmpty) return const AsyncData(null);
        final grove = ref.watch(bearingsGroveProvider);
        return ref.watch(
          groveQueryProvider(grove.query<PitLayout>().byId(key)),
        );
      }),
    );
