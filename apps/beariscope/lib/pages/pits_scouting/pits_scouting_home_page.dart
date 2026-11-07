import 'package:beariscope/models/pits_scouting_models.dart';
import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_map_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_scouting_assets.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/pits_scouting_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_scaffold.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/api_provider.dart';
import 'package:ui/widgets/bearings_spinner.dart';

class PitsScoutingHomePage extends ConsumerStatefulWidget {
  const PitsScoutingHomePage({super.key});

  @override
  ConsumerState<PitsScoutingHomePage> createState() =>
      PitsScoutingHomePageState();
}

class PitsScoutingHomePageState extends ConsumerState<PitsScoutingHomePage> {
  late final TextEditingController _searchController;
  PitsScoutingFilter _statusFilter = PitsScoutingFilter.allTeams;

  void _openScoutingForm(
    BuildContext context,
    int teamNumber,
    String teamName,
    bool scouted,
  ) {
    ScoutingDocument? existingDoc;
    if (scouted) {
      final eventKey = ref.read(currentEventProvider);
      final allDocs = ref.read(scoutingDataProvider).asData?.value ?? [];
      final pitsDocs =
          allDocs
              .where(
                (doc) =>
                    doc.meta?['type'] == 'pits' &&
                    doc.meta?['event'] == eventKey &&
                    (doc.data['teamNumber'] as num?)?.toInt() == teamNumber,
              )
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      existingDoc = pitsDocs.firstOrNull;
    }

    Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => PitsScoutingFormPage(
              teamNumber: teamNumber,
              teamName: teamName,
              scouted: scouted,
              initialDoc: existingDoc,
            ),
          ),
        )
        .then((result) {
          if (result == true) {
            // Refresh cross-device scouted status from honeycomb.
            ref.read(scoutingDataProvider.notifier).refresh();
          }
        });
  }

  @override
  void initState() {
    super.initState();
    _searchController = ref.read(pitsSearchControllerProvider);
    _searchController.addListener(_handleSearchControllerChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchControllerChanged);
    super.dispose();
  }

  void _handleSearchControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final main = MainViewController.of(context);
    final selectedEvent = ref.watch(currentEventProvider);
    final teamsAsync = ref.watch(pitsTeamsProvider);
    final scoutedNums = ref.watch(pitsScoutedProvider);
    final teamNameMap = ref.watch(pitsTeamNameMapProvider);
    final searchController = ref.watch(pitsSearchControllerProvider);
    final searchFocusNode = ref.watch(pitsSearchFocusNodeProvider);

    Future<void> onRefresh() async {
      final client = ref.read(honeycombClientProvider);
      client.invalidateCache('/teams', queryParams: {'event': selectedEvent});
      client.invalidateCache('/pits', queryParams: {'event': selectedEvent});
      ref.invalidate(pitsTeamsProvider);
      ref.invalidate(pitsMapProvider);
      await ref.read(scoutingDataProvider.notifier).refresh();
    }

    Widget withTeams(Widget Function(List<Team>) builder) => teamsAsync.when(
      loading: () => const Center(child: BearingsSpinner()),
      error: (err, stack) => BearingsStatusView(
        icon: LucideIcons.circleAlert,
        iconColor: Theme.of(context).colorScheme.error,
        title: 'Teams unavailable',
        subtitle: 'Error loading teams: $err',
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(pitsTeamsProvider),
          icon: const Icon(LucideIcons.rotateCw),
          label: const Text('Retry'),
        ),
      ),
      data: builder,
    );

    return BearingsScaffold(
      title: const Text('Pits'),
      leading: main.isDesktop
          ? null
          : IconButton(
              icon: const Icon(LucideIcons.menu),
              onPressed: main.openDrawer,
            ),
      actions: [
        BearingsPopupMenu.icon(
          icon: const Icon(LucideIcons.listFilter),
          tooltip: 'Filter & Sort',
          menuChildren: [
            for (final filter in PitsScoutingFilter.values)
              BearingsMenuItem(
                selected: _statusFilter == filter,
                onPressed: () => setState(() => _statusFilter = filter),
                child: Text(switch (filter) {
                  PitsScoutingFilter.allTeams => 'All Teams',
                  PitsScoutingFilter.notScouted => 'Not Scouted',
                  PitsScoutingFilter.scouted => 'Scouted',
                }),
              ),
          ],
        ),
      ],
      content: BearingsTabs(
        tabs: [
          BearingsTab(
            id: 'map',
            label: const Text('Map'),
            swipeEnabled: false,
            page: BearingsPage(
              bodyBuilder: (context, layout) => withTeams(
                (_) => _buildMapView(
                  context,
                  onRefresh: onRefresh,
                  scoutedNums: scoutedNums,
                  teamNameMap: teamNameMap,
                ),
              ),
            ),
          ),
          BearingsTab(
            id: 'list',
            label: const Text('List'),
            page: BearingsPage(
              search: BearingsSearch(
                controller: searchController,
                focusNode: searchFocusNode,
                hintText: 'Team name or number',
              ),
              bodyBuilder: (context, layout) => withTeams(
                (teams) => RefreshIndicator(
                  onRefresh: onRefresh,
                  child: _buildTeamList(
                    context,
                    filterPitsTeams(
                      teams: teams,
                      query: searchController.text,
                      scoutedTeamNumbers: scoutedNums,
                      statusFilter: _statusFilter,
                    ),
                    scoutedNums,
                    padding: layout.scrollPadding,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView(
    BuildContext context, {
    required Future<void> Function() onRefresh,
    required Set<int> scoutedNums,
    required Map<int, String> teamNameMap,
  }) {
    final pitsMapAsync = ref.watch(pitsMapProvider);

    return pitsMapAsync.when(
      loading: () => const Center(child: BearingsSpinner()),
      error: (err, stack) => _buildMapError(context),
      data: (mapData) {
        if (mapData == null) {
          return _buildMapError(context);
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          // RefreshIndicator needs a scrollable child; wrap PitsMapView in a
          // LayoutBuilder + Stack with a hidden ListView for scroll detection.
          child: Stack(
            children: [
              // Invisible scrollable so RefreshIndicator triggers.
              ListView(physics: const AlwaysScrollableScrollPhysics()),
              PitsMapView(
                mapData: mapData,
                scoutedTeams: scoutedNums,
                teamNames: teamNameMap,
                onTeamTap: (teamNum, teamName) {
                  _openScoutingForm(
                    context,
                    teamNum,
                    teamName,
                    scoutedNums.contains(teamNum),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapError(BuildContext context) {
    return BearingsStatusView(
      icon: LucideIcons.mapPinXInside,
      iconColor: Theme.of(context).colorScheme.error,
      title: 'Pits map unavailable',
      subtitle: 'No pits map published by Nexus for this event',
    );
  }

  // --------------------------------------------------------------------------
  // List view (original behaviour, now scouted status from provider)
  // --------------------------------------------------------------------------

  Widget _buildTeamList(
    BuildContext context,
    List<Team> filteredTeams,
    Set<int> scoutedNums, {
    EdgeInsetsGeometry? padding,
  }) {
    if (filteredTeams.isEmpty) {
      final hasFilters =
          _statusFilter != PitsScoutingFilter.allTeams ||
          ref.read(pitsSearchControllerProvider).text.trim().isNotEmpty;

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: [
          SizedBox(
            height: 320,
            child: BearingsStatusView(
              icon: LucideIcons.users,
              title: hasFilters ? 'No matching teams' : 'No teams found',
              subtitle: hasFilters
                  ? 'Try adjusting your search or filters.'
                  : 'No teams are available for this event.',
            ),
          ),
        ],
      );
    }

    return BearingsCardList(
      padding: padding,
      children: filteredTeams
          .map(
            (team) => PitsScoutingTeamCard(
              teamName: team.name,
              teamNumber: team.number,
              scouted: scoutedNums.contains(team.number),
              onScoutedChanged: (value) {
                if (!value) return;
                // The provider updates automatically; just refresh it.
                ref.read(scoutingDataProvider.notifier).refresh();
              },
            ),
          )
          .toList(),
    );
  }
}
