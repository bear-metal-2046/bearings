import 'package:beariscope/models/pits_scouting_models.dart';
import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_map_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_scouting_assets.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/pits_scouting_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:beariscope/utils/platform_utils_stub.dart'
    if (dart.library.io) 'package:beariscope/utils/platform_utils.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:beariscope/widgets/beariscope_search_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/api_provider.dart';

class PitsScoutingHomePage extends ConsumerStatefulWidget {
  const PitsScoutingHomePage({super.key});

  @override
  ConsumerState<PitsScoutingHomePage> createState() =>
      PitsScoutingHomePageState();
}

class PitsScoutingHomePageState extends ConsumerState<PitsScoutingHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
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
    ref
        .read(pitsSearchControllerProvider)
        .addListener(_handleSearchControllerChanged);
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    ref
        .read(pitsSearchControllerProvider)
        .removeListener(_handleSearchControllerChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleSearchControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final main = MainViewController.of(context);
        final selectedEvent = ref.watch(currentEventProvider);
        final teamsAsync = ref.watch(pitsTeamsProvider);
        final scoutedNums = ref.watch(pitsScoutedProvider);
        final teamNameMap = ref.watch(pitsTeamNameMapProvider);
        final searchController = ref.watch(pitsSearchControllerProvider);
        final searchFocusNode = ref.watch(pitsSearchFocusNodeProvider);
        final isMobile = PlatformUtils.isMobile();
        final searchInAppBar = !isMobile && constraints.maxWidth > 900;

        Future<void> onRefresh() async {
          final client = ref.read(honeycombClientProvider);
          client.invalidateCache(
            '/teams',
            queryParams: {'event': selectedEvent},
          );
          client.invalidateCache(
            '/pits',
            queryParams: {'event': selectedEvent},
          );
          ref.invalidate(pitsTeamsProvider);
          ref.invalidate(pitsMapProvider);
          await ref.read(scoutingDataProvider.notifier).refresh();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Pits'),
            flexibleSpace: searchInAppBar
                ? AnimatedBuilder(
                    animation: _tabController.animation!,
                    child: BeariscopeCenteredAppBarSearch(
                      searchBar: _buildSearchBar(
                        controller: searchController,
                        focusNode: searchFocusNode,
                      ),
                    ),
                    builder: (context, child) {
                      final progress = _tabController.animation!.value.clamp(
                        0.0,
                        1.0,
                      );

                      return IgnorePointer(
                        ignoring: progress == 0,
                        child: Opacity(opacity: progress, child: child),
                      );
                    },
                  )
                : null,
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Map'),
                Tab(text: 'List'),
              ],
            ),
            leading: main.isDesktop
                ? null
                : IconButton(
                    icon: const Icon(LucideIcons.menu),
                    onPressed: main.openDrawer,
                  ),
            actions: [
              PopupMenuButton<PitsScoutingFilter>(
                icon: const Icon(LucideIcons.listFilter),
                tooltip: 'Filter & Sort',
                itemBuilder: (context) => [
                  CheckedPopupMenuItem<PitsScoutingFilter>(
                    value: PitsScoutingFilter.allTeams,
                    checked: _statusFilter == PitsScoutingFilter.allTeams,
                    child: const Text('All Teams'),
                  ),
                  CheckedPopupMenuItem<PitsScoutingFilter>(
                    value: PitsScoutingFilter.notScouted,
                    checked: _statusFilter == PitsScoutingFilter.notScouted,
                    child: const Text('Not Scouted'),
                  ),
                  CheckedPopupMenuItem<PitsScoutingFilter>(
                    value: PitsScoutingFilter.scouted,
                    checked: _statusFilter == PitsScoutingFilter.scouted,
                    child: const Text('Scouted'),
                  ),
                ],
                onSelected: (selection) {
                  setState(() {
                    _statusFilter = selection;
                  });
                },
              ),
            ],
          ),
          body: teamsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(
              child: FilledButton(
                onPressed: () => ref.invalidate(pitsTeamsProvider),
                child: const Text('Retry'),
              ),
            ),
            data: (teams) {
              final filteredTeams = filterPitsTeams(
                teams: teams,
                query: searchController.text,
                scoutedTeamNumbers: scoutedNums,
                statusFilter: _statusFilter,
              );

              return TabBarView(
                controller: _tabController,
                physics: _tabController.index == 1
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  _buildMapView(
                    context,
                    onRefresh: onRefresh,
                    scoutedNums: scoutedNums,
                    teamNameMap: teamNameMap,
                  ),
                  _buildListTab(
                    context,
                    onRefresh: onRefresh,
                    teams: filteredTeams,
                    scoutedNums: scoutedNums,
                    searchController: searchController,
                    searchFocusNode: searchFocusNode,
                    searchInAppBar: searchInAppBar,
                  ),
                ],
              );
            },
          ),
        );
      },
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.mapPinXInside,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Pits map unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'No pits map published by Nexus for this event',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTab(
    BuildContext context, {
    required Future<void> Function() onRefresh,
    required List<Team> teams,
    required Set<int> scoutedNums,
    required TextEditingController searchController,
    required FocusNode searchFocusNode,
    required bool searchInAppBar,
  }) {
    final isMobile = PlatformUtils.isMobile();
    final searchAtTop = !isMobile && !searchInAppBar;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final content = Stack(
      children: [
        Positioned.fill(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: _buildTeamList(
              context,
              teams,
              scoutedNums,
              padding: searchInAppBar
                  ? const EdgeInsets.all(16)
                  : searchAtTop
                  ? const EdgeInsets.fromLTRB(16, 72, 16, 16)
                  : EdgeInsets.fromLTRB(16, 16, 16, 120 + safeAreaBottom),
            ),
          ),
        ),
        if (!searchInAppBar && searchAtTop)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: _buildSearchBar(
                      controller: searchController,
                      focusNode: searchFocusNode,
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (!searchInAppBar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            left: 8,
            right: 8,
            bottom: 8,
            child: SafeArea(
              child: _buildSearchBar(
                controller: searchController,
                focusNode: searchFocusNode,
              ),
            ),
          ),
      ],
    );

    return content;
  }

  Widget _buildSearchBar({
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return BeariscopeSearchBar(
      focusNode: focusNode,
      controller: controller,
      hintText: 'Team name or number',
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
    return BeariscopeCardList(
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
