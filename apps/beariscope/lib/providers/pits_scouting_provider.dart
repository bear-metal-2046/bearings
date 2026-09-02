import 'package:beariscope/models/pits_map_data.dart';
import 'package:beariscope/models/pits_scouting_models.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/api_provider.dart';

part 'pits_scouting_provider.g.dart';

final pitsSearchControllerProvider = Provider((ref) => TextEditingController());
final pitsSearchFocusNodeProvider = Provider((ref) => FocusNode());

//teams that are eligible for pits scouting (at the event and not already scouted)
final pitsTeamsProvider = Provider<AsyncValue<List<Team>>>((ref) {
  final teamsAsync = ref.watch(teamsProvider);
  return teamsAsync.whenData(parsePitsTeams);
});

//map of team number to team name for teams eligible for pits scouting
final pitsTeamNameMapProvider = Provider<Map<int, String>>((ref) {
  final teams = ref
      .watch(pitsTeamsProvider)
      .maybeWhen(data: (value) => value, orElse: () => const <Team>[]);
  return {for (final team in teams) team.number: team.name};
});

//teams that have been scouted
@riverpod
Set<int> pitsScouted(Ref ref) {
  final eventKey = ref.watch(currentEventProvider);
  final scoutingAsync = ref.watch(scoutingDataProvider);

  return scoutingAsync.maybeWhen(
    data: (docs) => docs
        .where(
          (doc) =>
              doc.meta?['type'] == 'pits' && doc.meta?['event'] == eventKey,
        )
        .map((doc) {
          final raw = doc.data['teamNumber'];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
          if (raw is String) return int.tryParse(raw);
          return null;
        })
        .whereType<int>()
        .toSet(),
    orElse: () => {},
  );
}

//pits map
@Riverpod(keepAlive: true)
Future<PitsMapData?> pitsMap(Ref ref) async {
  try {
    final tbaEventKey = ref.watch(currentEventProvider);

    final allEvents = await ref.watch(teamEventsProvider.future);

    final matchingEvent = allEvents.firstWhere(
      (eventOption) => eventOption.key == tbaEventKey,
      orElse: () => throw Exception('Event $tbaEventKey not found'),
    );

    final nexusNormalizedEventKey = matchingEvent.firstKey;
    final client = ref.watch(honeycombClientProvider);

    final response = await client.get<Map<String, dynamic>>(
      '/pits',
      queryParams: {'event': nexusNormalizedEventKey},
      cachePolicy: CachePolicy.networkFirst,
    );

    return PitsMapData.fromJson(response);
  } catch (_) {
    return null;
  }
}
