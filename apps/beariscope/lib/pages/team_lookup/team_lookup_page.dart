import 'package:beariscope/widgets/grove_load_message.dart';
import 'package:services/providers/competition_provider.dart';
// dart format width=120

import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/pages/team_lookup/team_sorting.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/rankings_provider.dart';
import 'package:core/core.dart' show GamePackTeamSort;
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_scaffold.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:beariscope/widgets/team_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_spinner.dart';

class TeamLookupPage extends ConsumerStatefulWidget {
  const TeamLookupPage({super.key});

  @override
  ConsumerState<TeamLookupPage> createState() => _TeamLookupPageState();
}

class _TeamLookupPageState extends ConsumerState<TeamLookupPage> {
  late final TextEditingController _searchController;
  String? _metricId;
  Set<String> _filterIds = {};
  bool _ascending = false;

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
    final event = ref.watch(currentEventProvider);
    final analysis =
        ref.watch(permissionCheckerProvider)?.canReadGamePackAnalysis == true
        ? ref.watch(gamePackEventAnalysisProvider(event)).value
        : null;
    final metrics = teamSortMetrics(analysis);
    final filters = teamFilters(analysis);
    final enabled = filters
        .where((rule) => _filterIds.contains(rule.id))
        .toList();
    final session = analysis?.session(analysis.analysis.definition.analysis);
    final metric = metrics
        .where((binding) => binding.id == _metricId)
        .firstOrNull;
    final roster = ref.watch(competitionTeamsProvider(event));
    final teamsAsync = roster.whenData(
      (result) => result.requireAvailable().items,
    );
    final rankings =
        ref.watch(eventRankingsProvider).value ?? const <int, TeamRanking>{};

    return BearingsScaffold(
      title: const Text('Teams'),
      leading: controller.isDesktop
          ? null
          : IconButton(
              icon: const Icon(LucideIcons.menu),
              onPressed: controller.openDrawer,
            ),
      actions: [
        if (filters.isNotEmpty)
          GamePackTeamFilterMenu(
            filters: filters,
            enabled: enabled.map((rule) => rule.id).toSet(),
            onChanged: (ids) => setState(() => _filterIds = ids),
          ),
        _sortButton(selectedSort, metrics, metric),
      ],
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
            subtitle: groveLoadMessage(error),
          ),
          data: (rawTeams) {
            final teams = rawTeams
                .map(Team.fromCompetition)
                .where(
                  (team) =>
                      teamMatchesSearch(team, searchController.text) &&
                      (session == null ||
                          teamPassesFilters(session, team.key, enabled)),
                )
                .toList();
            if (metric == null) {
              sortTeams(teams, selectedSort, rankings);
            } else {
              sortTeamsByMetric(
                teams,
                analysis!,
                metric,
                ascending: _ascending,
              );
            }
            if (teams.isEmpty) {
              return const BearingsStatusView(
                icon: LucideIcons.users,
                title: 'No teams found',
                subtitle:
                    'Try adjusting your search or selecting another event.',
              );
            }

            return BearingsCardList(
              padding: layout.scrollPadding,
              children: teams
                  .map((team) => TeamCard(teamKey: team.key, eventKey: event))
                  .toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _sortButton(
    TeamSort selectedSort,
    Iterable<GamePackTeamSort> metrics,
    GamePackTeamSort? metric,
  ) {
    return BearingsPopupMenu.icon(
      icon: Icon(
        (metric == null ? selectedSort.isAscending : _ascending)
            ? LucideIcons.arrowUpNarrowWide
            : LucideIcons.arrowDownWideNarrow,
      ),
      tooltip: 'Sort',
      menuChildren: [
        for (final sort in TeamSortOptions.values)
          BearingsMenuItem(
            selected: metric == null && selectedSort.sort == sort,
            onPressed: () {
              final ascending =
                  metric != null ||
                  selectedSort.sort != sort ||
                  !selectedSort.isAscending;
              setState(() => _metricId = null);
              ref.read(teamSortProvider.notifier).setSort(sort, ascending);
            },
            child: Row(
              children: [
                Text(sort.label),
                if (metric == null && selectedSort.sort == sort)
                  Icon(
                    selectedSort.isAscending
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                  ),
              ],
            ),
          ),
        for (final binding in metrics)
          BearingsMenuItem(
            selected: binding == metric,
            onPressed: () => setState(() {
              _ascending = binding == metric ? !_ascending : binding.ascending;
              _metricId = binding.id;
            }),
            child: Text(binding.label),
          ),
      ],
    );
  }
}
