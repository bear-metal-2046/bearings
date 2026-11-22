import 'package:core/core.dart'
    show
        PitLayout,
        GamePackFormKind,
        GamePackObservation,
        gamePackReadPermission,
        gamePackSubmitPermission,
        gamePackCorrectPermission;
import 'package:grove/grove.dart' show QueryResult;
import 'package:beariscope/widgets/grove_load_message.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:beariscope/models/pits_scouting_models.dart';
import 'package:beariscope/pages/gamepacks/observation_page.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_map_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_scouting_assets.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/pits_scouting_provider.dart';
import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_scaffold.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
    final teamsAsync = ref.watch(pitsTeamsProvider);
    final event = ref.watch(currentEventProvider);
    final permission = ref.watch(permissionCheckerProvider);
    final assignment = permission?.hasPermission(gamePackReadPermission) == true
        ? ref.watch(eventGamePackProvider(event)).value
        : null;
    final release = assignment;
    final pitForm = release?.definition.formFor(GamePackFormKind.pit);
    final history =
        release != null && permission?.canReadGamePackAnalysis == true
        ? ref.watch(activeGamePackObservationsProvider(event)).value
        : null;
    final observations = <int, GamePackObservation>{};
    for (final row in history ?? const <GamePackObservation>[]) {
      if (row.formId != pitForm?.id || row.release.id != release!.id) continue;
      final team = int.tryParse(row.team?.id.replaceFirst('frc', '') ?? '');
      if (team != null) observations.putIfAbsent(team, () => row);
    }
    final scoutedNums = history == null ? null : observations.keys.toSet();
    final maySubmit =
        permission?.hasPermission(gamePackSubmitPermission) == true;
    final mayCorrect =
        permission?.hasPermission(gamePackCorrectPermission) == true;
    final canOpen = pitForm != null && (maySubmit || history != null);

    Future<void> openTeam(int number, String name) async {
      final previous = observations[number];
      if (release == null || (previous == null && !maySubmit)) return;
      final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          builder: (_) => GamePackObservationPage(
            title: 'Scouting $number: $name',
            event: event,
            release: release,
            kind: GamePackFormKind.pit,
            team: 'frc$number',
            previous: previous,
            writable: previous == null ? maySubmit : mayCorrect,
          ),
        ),
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pit observation saved')));
      }
    }

    final pitLayout = ref.watch(pitsMapProvider);
    final teamNameMap = {
      for (final team in teamsAsync.value ?? const <Team>[])
        team.number: team.name,
    };
    final searchController = ref.watch(pitsSearchControllerProvider);
    final searchFocusNode = ref.watch(pitsSearchFocusNodeProvider);

    Widget withTeams(Widget Function(List<Team>) builder) => teamsAsync.when(
      loading: () => const Center(child: BearingsSpinner()),
      error: (err, stack) => BearingsStatusView(
        icon: LucideIcons.circleAlert,
        iconColor: Theme.of(context).colorScheme.error,
        title: 'Teams unavailable',
        subtitle: groveLoadMessage(err),
        action: FilledButton.icon(
          onPressed: () => retryCompetitionTeams(
            ProviderScope.containerOf(context, listen: false),
            ref.read(currentEventProvider),
          ),
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
                onPressed:
                    scoutedNums != null || filter == PitsScoutingFilter.allTeams
                    ? () => setState(() => _statusFilter = filter)
                    : null,
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
              bodyBuilder: (context, layout) => _buildMapView(
                context,
                result: pitLayout,
                scoutedNums: scoutedNums,
                teamNameMap: teamNameMap,
                openTeam: canOpen ? openTeam : null,
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
                (teams) => _buildTeamList(
                  context,
                  filterPitsTeams(
                    teams: teams,
                    query: searchController.text,
                    scoutedTeamNumbers: scoutedNums ?? const {},
                    statusFilter: scoutedNums == null
                        ? PitsScoutingFilter.allTeams
                        : _statusFilter,
                  ),
                  scoutedNums,
                  openTeam: canOpen ? openTeam : null,
                  padding: layout.scrollPadding,
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
    required AsyncValue<QueryResult<PitLayout>?> result,
    required Set<int>? scoutedNums,
    required Map<int, String> teamNameMap,
    required void Function(int, String)? openTeam,
  }) {
    final pitLayoutAsync = result.whenData(
      (snapshot) => snapshot?.requireAvailable().items.singleOrNull,
    );

    return pitLayoutAsync.when(
      loading: () => const Center(child: BearingsSpinner()),
      error: (error, _) =>
          _buildMapError(context, subtitle: groveLoadMessage(error)),
      data: (layout) {
        final mapData = layout?.map;
        if (layout == null || mapData == null) {
          return _buildMapError(context);
        }

        return PitsMapView(
          key: ValueKey(layout.id),
          mapData: mapData,
          pits: layout.pits,
          scoutedTeams: scoutedNums,
          teamNames: teamNameMap,
          onTeamTap: openTeam,
        );
      },
    );
  }

  Widget _buildMapError(
    BuildContext context, {
    String subtitle = 'No pits map has been published for this event.',
  }) {
    return BearingsStatusView(
      icon: LucideIcons.mapPinXInside,
      iconColor: Theme.of(context).colorScheme.error,
      title: 'Pits map unavailable',
      subtitle: subtitle,
    );
  }

  // --------------------------------------------------------------------------
  // List view (original behaviour, now scouted status from provider)
  // --------------------------------------------------------------------------

  Widget _buildTeamList(
    BuildContext context,
    List<Team> filteredTeams,
    Set<int>? scoutedNums, {
    required void Function(int, String)? openTeam,
    EdgeInsetsGeometry? padding,
  }) {
    if (filteredTeams.isEmpty) {
      final hasFilters =
          (scoutedNums != null &&
              _statusFilter != PitsScoutingFilter.allTeams) ||
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
              scouted: scoutedNums?.contains(team.number) == true,
              statusKnown: scoutedNums != null,
              onTap: openTeam == null
                  ? null
                  : () => openTeam(team.number, team.name),
            ),
          )
          .toList(),
    );
  }
}
