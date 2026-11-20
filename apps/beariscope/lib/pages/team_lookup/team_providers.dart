import 'package:core/core.dart' show CompetitionMedia;

import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/utils/competition_media_display.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/competition_provider.dart';

final searchControllerProvider = Provider((ref) {
  final controller = TextEditingController();
  ref.onDispose(controller.dispose);
  return controller;
});

final searchFocusNodeProvider = Provider((ref) {
  final focusNode = FocusNode();
  ref.onDispose(focusNode.dispose);
  return focusNode;
});

class TeamSort {
  TeamSortOptions sort = TeamSortOptions.teamNumber;
  bool isAscending = true;

  TeamSort(this.sort, this.isAscending);
}

enum TeamSortOptions { teamNumber, rank, custom, defense, noShow, brokeDown }

extension TeamSortLabel on TeamSortOptions {
  String get label => switch (this) {
    TeamSortOptions.teamNumber => 'Team #',
    TeamSortOptions.rank => 'Rank',
    TeamSortOptions.custom => 'Total #',
    TeamSortOptions.defense => 'Played Defense',
    TeamSortOptions.noShow => 'No Shows',
    TeamSortOptions.brokeDown => 'Breakdowns',
  };
}

class TeamSortNotifier extends Notifier<TeamSort> {
  @override
  TeamSort build() => TeamSort(TeamSortOptions.teamNumber, true);

  void setSort(TeamSortOptions sort, bool isAscending) =>
      state = TeamSort(sort, isAscending);

  TeamSortOptions getSort() => state.sort;

  bool getIsAscending() => state.isAscending;
}

final teamSortProvider = NotifierProvider<TeamSortNotifier, TeamSort>(
  () => TeamSortNotifier(),
);

final eventTeamMediaProvider = Provider<AsyncValue<List<CompetitionMedia>>>((
  ref,
) {
  final event = ref.watch(currentEventProvider);
  return ref.watch(competitionMediaProvider(event));
});

final teamMediaProvider = Provider.autoDispose
    .family<AsyncValue<List<CompetitionMedia>>, int>((ref, teamNumber) {
      final key = 'frc$teamNumber';
      return ref
          .watch(eventTeamMediaProvider)
          .whenData(
            (records) =>
                records.where((record) => record.includesTeam(key)).toList(),
          );
    });
