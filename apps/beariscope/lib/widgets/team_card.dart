import 'package:beariscope/providers/current_event_provider.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:beariscope/pages/gamepacks/team_card_content.dart';
import 'package:beariscope/pages/gamepacks/observation_list.dart';
import 'package:beariscope/pages/gamepacks/observation_page.dart';
import 'package:beariscope/pages/team_lookup/tabs/media_tab.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/utils/competition_media_display.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:beariscope/widgets/team_avatar.dart';
import 'package:core/core.dart'
    show
        GamePackFormKind,
        GamePackTeamCardKind,
        gamePackReadPermission,
        gamePackSubmitPermission;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ui/widgets/bearings_spinner.dart';

class TeamCard extends ConsumerWidget {
  final String teamKey;
  final String? eventKey;
  final bool headerOnly;
  final double? height;
  final Color? allianceColor;

  static const double _defaultPlaceholderHeight = 120;

  const TeamCard({
    super.key,
    this.headerOnly = false,
    required this.teamKey,
    this.eventKey,
    this.height,
    this.allianceColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = eventKey ?? ref.watch<String>(currentEventProvider);
    final teamsAsync = ref
        .watch(competitionTeamsProvider(event))
        .whenData((result) => result.requireAvailable().items);
    final showSummary =
        !headerOnly &&
        ref.watch(permissionCheckerProvider)?.canReadGamePackAnalysis == true;

    return teamsAsync.when(
      loading: () => _buildCardShell(
        context,
        height: height ?? _defaultPlaceholderHeight,
        child: const Center(child: BearingsSpinner()),
      ),
      error: (err, _) => _buildCardShell(
        context,
        height: height ?? _defaultPlaceholderHeight,
        child: Center(child: Text('Error: $err')),
      ),
      data: (teams) {
        final match = teams
            .where(
              (team) => team.id == teamKey || team.number.toString() == teamKey,
            )
            .firstOrNull;
        final team = match == null ? null : Team.fromCompetition(match);

        if (team == null) {
          return _buildCardShell(
            context,
            height: height ?? _defaultPlaceholderHeight,
            child: const Center(child: Text('Team not in current event')),
          );
        }

        final resolvedTeam = team;

        return _buildCardShell(
          context,
          height: height,
          onTap: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (context) => TeamDetailsPage(
                  teamName: resolvedTeam.name,
                  teamNumber: resolvedTeam.number,
                  teamWebsite: resolvedTeam.website,
                  eventKey: event,
                ),
              ),
            );
          },
          child: showSummary
              ? _GamePackTeamCardSummary(
                  team: resolvedTeam,
                  event: event,
                  fillHeight: height != null,
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: _TeamCardHeader(team: resolvedTeam),
                ),
        );
      },
    );
  }

  Widget _buildCardShell(
    BuildContext context, {
    required Widget child,
    VoidCallback? onTap,
    double? height,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        elevation: 0,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: DecoratedBox(
            decoration: allianceColor != null
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(color: allianceColor!, width: 4),
                    ),
                  )
                : const BoxDecoration(),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GamePackTeamCardSummary extends StatelessWidget {
  const _GamePackTeamCardSummary({
    required this.team,
    required this.event,
    required this.fillHeight,
  });

  final Team team;
  final String event;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final statistics = GamePackTeamCardStatistics(
      event: event,
      team: team.key,
      kind: GamePackTeamCardKind.compact,
      fallback: const SizedBox.shrink(),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 5,
        children: [
          _TeamCardHeader(team: team),
          if (fillHeight)
            Expanded(
              child: SingleChildScrollView(primary: false, child: statistics),
            )
          else
            statistics,
        ],
      ),
    );
  }
}

class _TeamCardHeader extends StatelessWidget {
  final Team team;

  const _TeamCardHeader({required this.team});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final mediaAsync = ref.watch(teamMediaProvider(team.number));

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: mediaAsync.when(
                loading: () => _fallbackAvatar(context),
                error: (_, _) => _fallbackAvatar(context),
                data: (media) {
                  return TeamAvatarImage(
                    images: teamAvatarImages(media, 'frc${team.number}'),
                    width: 32,
                    height: 32,
                    fallbackBuilder: _fallbackAvatar,
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                team.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  // font,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              team.number.toString(),
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _fallbackAvatar(BuildContext context) {
    return Icon(
      LucideIcons.bot,
      size: 32,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

class TeamDetailsPage extends ConsumerWidget {
  final String teamName;
  final int teamNumber;
  final String? teamWebsite;
  final String? eventKey;

  const TeamDetailsPage({
    super.key,
    required this.teamName,
    required this.teamNumber,
    this.teamWebsite,
    this.eventKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(permissionCheckerProvider);
    final event = eventKey ?? ref.watch<String>(currentEventProvider);
    final assigned = permission?.hasPermission(gamePackReadPermission) == true
        ? ref.watch(eventGamePackProvider(event)).value
        : null;
    final pack = assigned;
    final showObservations =
        pack != null && permission?.canReadGamePackAnalysis == true;
    final canAddObservation =
        showObservations &&
        pack.definition.formFor(GamePackFormKind.observation) != null &&
        permission?.hasPermission(gamePackSubmitPermission) == true;
    final mediaAsync = ref.watch(teamMediaProvider(teamNumber));

    return mediaAsync.when(
      loading: () => const Scaffold(body: Center(child: BearingsSpinner())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text('$teamName — $teamNumber')),
        body: BearingsStatusView(
          icon: LucideIcons.circleAlert,
          iconColor: Theme.of(context).colorScheme.error,
          title: 'Team details unavailable',
          subtitle: 'Error loading team details: $e',
        ),
      ),
      data: (media) {
        final hasMedia = media.any((record) {
          return record.hasRenderableMedia &&
              record.openUrl?.isNotEmpty == true;
        });
        final hasWebsite = teamWebsite?.isNotEmpty == true;
        final hasMediaTabContent = hasMedia || hasWebsite;

        return DefaultTabController(
          key: ValueKey('$showObservations-$hasMediaTabContent'),
          length: 2 + (showObservations ? 1 : 0) + (hasMediaTabContent ? 1 : 0),
          child: Builder(
            builder: (context) {
              final tabController = DefaultTabController.of(context);

              return AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  final showObservationFab =
                      showObservations &&
                      canAddObservation &&
                      tabController.index == 1;

                  return Scaffold(
                    floatingActionButton: showObservationFab
                        ? FloatingActionButton.extended(
                            onPressed: () async {
                              final saved =
                                  await Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => GamePackObservationPage(
                                        title: 'Observation · $teamName',
                                        event: event,
                                        release: pack,
                                        kind: GamePackFormKind.observation,
                                        team: 'frc$teamNumber',
                                      ),
                                    ),
                                  );
                              if (saved == true && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Observation saved'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(LucideIcons.messageSquarePlus),
                            label: const Text('Add observation'),
                          )
                        : null,
                    appBar: AppBar(
                      title: Text('$teamName — $teamNumber'),
                      actions: [
                        BearingsPopupMenu.overflow(
                          tooltip: 'More options',
                          menuChildren: [
                            BearingsMenuItem(
                              onPressed: () => _handleAction(
                                context,
                                _TeamAction.openTba,
                                ref,
                              ),
                              leadingIcon: const Icon(LucideIcons.externalLink),
                              child: const Text('Open in TBA'),
                            ),
                            BearingsMenuItem(
                              onPressed: () => _handleAction(
                                context,
                                _TeamAction.openStatbotics,
                                ref,
                              ),
                              leadingIcon: const Icon(LucideIcons.externalLink),
                              child: const Text('Open in Statbotics'),
                            ),
                            BearingsMenuItem(
                              onPressed: () => _handleAction(
                                context,
                                _TeamAction.openFrcEvents,
                                ref,
                              ),
                              leadingIcon: const Icon(LucideIcons.externalLink),
                              child: const Text('Open in FRC Events'),
                            ),
                            const Divider(height: 16),
                            BearingsMenuItem(
                              onPressed: () => _handleAction(
                                context,
                                _TeamAction.copyNumber,
                                ref,
                              ),
                              leadingIcon: const Icon(LucideIcons.copy),
                              child: const Text('Copy team number'),
                            ),
                          ],
                        ),
                      ],
                      bottom: TabBar(
                        tabAlignment: TabAlignment.start,
                        isScrollable: true,
                        tabs: [
                          const Tab(text: 'Details'),
                          if (showObservations) const Tab(text: 'Observations'),
                          const Tab(text: 'Matches'),
                          if (hasMediaTabContent) const Tab(text: 'Media'),
                        ],
                      ),
                    ),
                    body: TabBarView(
                      children: [
                        GamePackTeamCardStatistics(
                          event: event,
                          team: 'frc$teamNumber',
                          kind: GamePackTeamCardKind.details,
                          scrollable: true,
                          fallback: const Center(
                            child: Text('No team details configured.'),
                          ),
                        ),
                        if (showObservations)
                          GamePackTeamObservations(
                            event: event,
                            team: 'frc$teamNumber',
                            release: pack,
                            notesOnly: true,
                            kinds: const {
                              GamePackFormKind.observation,
                              GamePackFormKind.match,
                              GamePackFormKind.pit,
                            },
                          ),
                        if (showObservations) ...[
                          GamePackTeamObservations(
                            event: event,
                            team: 'frc$teamNumber',
                            release: pack,
                            kinds: const {GamePackFormKind.match},
                          ),
                        ] else ...[
                          const Center(
                            child: Text(
                              'Match observations unavailable for this event.',
                            ),
                          ),
                        ],
                        if (hasMediaTabContent)
                          MediaTab(
                            teamNumber: teamNumber,
                            teamWebsite: teamWebsite,
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _handleAction(BuildContext context, _TeamAction action, WidgetRef ref) {
    switch (action) {
      case _TeamAction.openTba:
        launchUrl(
          ref.tbaWebsiteUri('/team/$teamNumber'),
          mode: LaunchMode.externalApplication,
        );
      case _TeamAction.openStatbotics:
        launchUrl(
          Uri.parse('https://www.statbotics.io/team/$teamNumber'),
          mode: LaunchMode.externalApplication,
        );
      case _TeamAction.openFrcEvents:
        launchUrl(
          Uri.parse('https://frc-events.firstinspires.org/team/$teamNumber'),
          mode: LaunchMode.externalApplication,
        );
      case _TeamAction.copyNumber:
        Clipboard.setData(ClipboardData(text: teamNumber.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Team number $teamNumber copied'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }
}

enum _TeamAction { openTba, openStatbotics, openFrcEvents, copyNumber }
