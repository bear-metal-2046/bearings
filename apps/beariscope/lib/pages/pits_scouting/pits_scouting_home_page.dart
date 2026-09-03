import 'package:beariscope/models/pits_scouting_models.dart';
import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_map_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_scouting_assets.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/pits_scouting_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
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

  final TextEditingController _searchTEC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchTEC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final main = MainViewController.of(context);
    final selectedEvent = ref.watch(currentEventProvider);
    final teamsAsync = ref.watch(pitsTeamsProvider);
    final scoutedNums = ref.watch(pitsScoutedProvider);
    final teamNameMap = ref.watch(pitsTeamNameMapProvider);

    Future<void> onRefresh() async {
      final client = ref.read(honeycombClientProvider);
      client.invalidateCache('/teams', queryParams: {'event': selectedEvent});
      client.invalidateCache('/pits', queryParams: {'event': selectedEvent});
      ref.invalidate(pitsTeamsProvider);
      ref.invalidate(pitsMapProvider);
      await ref.read(scoutingDataProvider.notifier).refresh();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pits'),
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
            query: _searchTEC.text,
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
              ),
            ],
          );
        },
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
  }) {
    final content = Stack(
      children: [
        Positioned.fill(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: _buildTeamList(
              context,
              teams,
              scoutedNums,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 0) {
                  FocusScope.of(context).unfocus();
                }
              },
              child: SearchBar(
                controller: _searchTEC,
                hintText: 'Team name or number',
                padding: const WidgetStatePropertyAll<EdgeInsets>(
                  EdgeInsets.symmetric(horizontal: 16.0),
                ),
                leading: const Icon(LucideIcons.search),
                trailing: _searchTEC.text.isNotEmpty
                    ? [
                        IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () {
                            _searchTEC.clear();
                            setState(() {});
                          },
                        ),
                      ]
                    : null,
                onChanged: (_) {
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      ],
    );

    return content;
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
