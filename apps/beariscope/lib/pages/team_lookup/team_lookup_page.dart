// dart format width=120

import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/rankings_provider.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_scaffold.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:beariscope/widgets/team_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/api_provider.dart';
import 'package:ui/widgets/bearings_spinner.dart';

class TeamLookupPage extends ConsumerStatefulWidget {
  const TeamLookupPage({super.key});

  @override
  ConsumerState<TeamLookupPage> createState() => _TeamLookupPageState();
}

class _TeamLookupPageState extends ConsumerState<TeamLookupPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = ref.read(searchControllerProvider);
    _searchController.addListener(_handleSearchChanged);
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final searchFocusNode = ref.watch(searchFocusNodeProvider);
    final searchController = ref.watch(searchControllerProvider);
    final selectedSort = ref.watch(teamSortProvider);
    final teamsAsync = ref.watch(teamsProvider);
    final rankings = ref.watch(eventRankingsProvider).value ?? const <int, TeamRanking>{};

    return BearingsScaffold(
      title: const Text('Teams'),
      leading: controller.isDesktop
          ? null
          : IconButton(icon: const Icon(LucideIcons.menu), onPressed: controller.openDrawer),
      actions: [_sortButton(selectedSort)],
      content: BearingsPage(
        search: BearingsSearch(
          focusNode: searchFocusNode,
          controller: searchController,
          hintText: 'Team name or number',
        ),
        bodyBuilder: (context, layout) => teamsAsync.when(
          loading: () => const Center(child: BearingsSpinner()),
          error: (error, _) => BearingsStatusView(
            icon: LucideIcons.circleAlert,
            iconColor: Theme.of(context).colorScheme.error,
            title: 'Teams unavailable',
            subtitle: 'Error loading teams: $error',
          ),
          data: (rawTeams) {
            final teams = rawTeams
                .map(Team.fromJson)
                .where((team) => teamMatchesSearch(team, searchController.text))
                .toList();
            _sortTeams(teams, selectedSort, rankings);
            if (teams.isEmpty) {
              return const BearingsStatusView(
                icon: LucideIcons.users,
                title: 'No teams found',
                subtitle: 'Try adjusting your search or selecting another event.',
              );
            }

            final scoutingBundles = <TeamScoutingBundle>[];
            for (final team in teams) {
              final bundle = ref.watch(teamScoutingProvider(team.number)).asData?.value;
              if (bundle != null) scoutingBundles.add(bundle);
            }
            final sharedMaxY = teamCardSharedYAxisMax(scoutingBundles);

            return RefreshIndicator(
              onRefresh: _refresh,
              child: BearingsCardList(
                padding: layout.scrollPadding,
                children: teams.map((team) => TeamCard(teamKey: team.key, minY: 0, maxY: sharedMaxY)).toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sortButton(TeamSort selectedSort) {
    return BearingsPopupMenu.icon(
      icon: Icon(selectedSort.isAscending ? LucideIcons.arrowUpNarrowWide : LucideIcons.arrowDownWideNarrow),
      tooltip: 'Sort',
      menuChildren: [
        for (final sort in TeamSortOptions.values)
          BearingsMenuItem(
            selected: selectedSort.sort == sort,
            onPressed: () {
              final ascending = selectedSort.sort == sort
                  ? !selectedSort.isAscending
                  : sort == TeamSortOptions.teamNumber || sort == TeamSortOptions.rank;
              ref.read(teamSortProvider.notifier).setSort(sort, ascending);
            },
            child: Row(
              children: [
                Text(sort.label),
                if (selectedSort.sort == sort)
                  Icon(selectedSort.isAscending ? LucideIcons.chevronUp : LucideIcons.chevronDown),
              ],
            ),
          ),
      ],
    );
  }

  void _sortTeams(List<Team> teams, TeamSort selectedSort, Map<int, TeamRanking> rankings) {
    final scores = <int, double>{};
    final safety = <int, (int, int, int)>{};
    final needsScouting = selectedSort.sort != TeamSortOptions.teamNumber && selectedSort.sort != TeamSortOptions.rank;
    if (needsScouting) {
      for (final team in teams) {
        final bundle = ref.watch(teamScoutingProvider(team.number)).value;
        if (bundle == null) continue;
        scores[team.number] = _totalAverage(bundle);
        safety[team.number] = _safetyStats(bundle);
      }
    }

    teams.sort((a, b) {
      final comparison = switch (selectedSort.sort) {
        TeamSortOptions.teamNumber => a.number.compareTo(b.number),
        TeamSortOptions.rank => (rankings[a.number]?.rank ?? 999999).compareTo(rankings[b.number]?.rank ?? 999999),
        TeamSortOptions.custom => (scores[a.number] ?? 0).compareTo(scores[b.number] ?? 0),
        TeamSortOptions.defense => (safety[a.number]?.$1 ?? 0).compareTo(safety[b.number]?.$1 ?? 0),
        TeamSortOptions.noShow => (safety[a.number]?.$2 ?? 0).compareTo(safety[b.number]?.$2 ?? 0),
        TeamSortOptions.brokeDown => (safety[a.number]?.$3 ?? 0).compareTo(safety[b.number]?.$3 ?? 0),
      };
      return selectedSort.isAscending ? comparison : -comparison;
    });
  }

  Future<void> _refresh() async {
    final selectedEvent = ref.read(currentEventProvider);
    final client = ref.read(honeycombClientProvider);
    client.invalidateCache('/teams', queryParams: {'event': selectedEvent});
    client.invalidateCache('/rankings', queryParams: {'event': selectedEvent});
    client.invalidateCache('/event/$selectedEvent/team_media');
    ref.invalidate(eventTeamsProvider(selectedEvent));
    ref.invalidate(teamsProvider);
    ref.invalidate(eventRankingsProvider);
    ref.invalidate(eventTeamMediaProvider);
    try {
      await Future.wait([
        ref.read(teamsProvider.future),
        ref.read(eventRankingsProvider.future),
        ref.read(eventTeamMediaProvider.future),
      ]);
    } catch (_) {
      // Keep cached data visible if refresh fails.
    }
  }
}

double _totalAverage(TeamScoutingBundle bundle) =>
    bundle.avgMatchField(kSectionAuto, kAutoFuelScored) + bundle.avgMatchField(kSectionTele, kTeleFuelScored);

(int, int, int) _safetyStats(TeamScoutingBundle bundle) {
  var defense = 0;
  var noShow = 0;
  var breakdown = 0;
  for (final doc in bundle.matchDocs) {
    final playedDefense =
        _truthy(TeamScoutingBundle.getMatchField(doc.raw, kSectionEndgame, kEndPlayedDefenseOffShift)) ||
        _truthy(TeamScoutingBundle.getMatchField(doc.raw, kSectionEndgame, kEndPlayedDefenseOnShift));
    final absent = _truthy(TeamScoutingBundle.getMatchField(doc.raw, kSectionEndgame, kEndNoShow));
    final failed =
        _truthy(TeamScoutingBundle.getMatchField(doc.raw, kSectionTele, kTeleStoppedWorking)) ||
        _truthy(TeamScoutingBundle.getMatchField(doc.raw, kSectionTele, kTeleLostComms));
    if (playedDefense) defense++;
    if (absent) noShow++;
    if (failed) breakdown++;
  }
  return (defense, noShow, breakdown);
}

bool _truthy(Object? value) {
  if (value is bool) return value;
  if (value is num) return value > 0;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1' || text == 'y';
}
