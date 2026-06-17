import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/team_lookup/tabs/averages_tab.dart';
import 'package:beariscope/pages/team_lookup/tabs/capabilities_tab.dart';
import 'package:beariscope/pages/team_lookup/tabs/matches_tab.dart';
import 'package:beariscope/pages/team_lookup/tabs/media_tab.dart';
import 'package:beariscope/pages/team_lookup/tabs/notes_tab.dart';
import 'package:beariscope/pages/team_lookup/tabs/observation_sheet.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/rankings_provider.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/processed_scouting_doc.dart';
import '../providers/strat_z_score_provider.dart';

class TeamCard extends ConsumerWidget {
  final String teamKey;
  final double? height;
  final Color? allianceColor;

  static const double _defaultPlaceholderHeight = 120;

  const TeamCard({
    super.key,
    required this.teamKey,
    this.height,
    this.allianceColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamsProvider);

    return teamsAsync.when(
      loading: () => _buildCardShell(
        context,
        height: height ?? _defaultPlaceholderHeight,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => _buildCardShell(
        context,
        height: height ?? _defaultPlaceholderHeight,
        child: Center(child: Text('Error: $err')),
      ),
      data: (teams) {
        final teamList = teams
            .whereType<Map<String, dynamic>>()
            .map((json) => Team.fromJson(json))
            .toList();

        Team? team;
        for (final t in teamList) {
          if (t.key == teamKey || t.number.toString() == teamKey) {
            team = t;
            break;
          }
        }

        if (team == null) {
          return _buildCardShell(
            context,
            height: height ?? _defaultPlaceholderHeight,
            child: const Center(child: Text('Team not found')),
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
                ),
              ),
            );
          },
          child: _TeamCardSummary(
            team: resolvedTeam,
            expandToFillHeight: height != null,
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

class _TeamCardSummary extends ConsumerWidget {
  final Team team;
  final bool expandToFillHeight;

  const _TeamCardSummary({
    required this.team,
    required this.expandToFillHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundleAsync = ref.watch(teamScoutingProvider(team.number));
    final rankingsAsync = ref.watch(eventRankingsProvider);
    final rankings = switch (rankingsAsync) {
      AsyncData(:final value) => value,
      _ => const <int, TeamRanking>{},
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: expandToFillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TeamCardHeader(team: team),
          bundleAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (bundle) =>
                SizedBox(height: bundle.matchDocs.length > 1 ? 12 : 4),
          ),
          bundleAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (bundle) {
              final summary = _SummaryMetrics(
                teamNumber: team.number,
                bundle: bundle,
                expandToFillHeight: expandToFillHeight,
                stratZScores:
                    ref
                        .watch(stratZScoresProvider)
                        .asData
                        ?.value
                        .changeToRanks() ??
                    StratZScoreData.empty,
                ranking: rankings[team.number],
              );

              // Only reserve expandable vertical space when chart data exists.
              if (expandToFillHeight && bundle.matchDocs.length > 1) {
                return Expanded(child: summary);
              }
              return summary;
            },
          ),
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
                  final avatar = media
                      .where((record) => record.isAvatar)
                      .toList();
                  final preferredAvatar = avatar.firstWhere(
                    (record) => record.preferred && record.base64Image != null,
                    orElse: () => avatar.firstWhere(
                      (record) => record.base64Image != null,
                      orElse: () => const TeamMediaRecord(
                        foreignKey: '',
                        type: '',
                        preferred: false,
                        teamKeys: [],
                        details: {},
                        directUrl: null,
                        viewUrl: null,
                        base64Image: null,
                      ),
                    ),
                  );
                  final bytes = preferredAvatar.base64Image;
                  if (bytes == null) return _fallbackAvatar(context);
                  return Image.memory(
                    bytes,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        _fallbackAvatar(context),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                team.name,
                style: const TextStyle(fontSize: 20, fontFamily: 'Xolonium'),
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
      Icons.account_circle,
      size: 32,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

class _SummaryMetrics extends ConsumerWidget {
  final int teamNumber;
  final TeamScoutingBundle bundle;
  final bool expandToFillHeight;
  final StratZScoreData? stratZScores;
  final TeamRanking? ranking;

  const _SummaryMetrics({
    required this.teamNumber,
    required this.bundle,
    required this.expandToFillHeight,
    required this.stratZScores,
    required this.ranking,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const playStyleOptions = ['Passing', 'Cycling', 'Shooting', 'Defense'];

    final trenchCapable =
        bundle.getPitsField<String>('trenchCapability') == 'Trench Capable';
    final climbCapable = bundle.getPitsField<String>('climbMethod');

    final mostCommonPlayStyle = RegExp(r'\d+')
        .allMatches(
          bundle.modalMatchField(kSectionEndgame, kEndPlayStyle).toString(),
        )
        .map((m) {
          final index = int.parse(m.group(0)!);
          return (index >= 0 && index < playStyleOptions.length)
              ? playStyleOptions[index]
              : null;
        })
        .whereType<String>()
        .join(', ');

    final avgAutoFuel = bundle.avgMatchField(kSectionAuto, kAutoFuelScored);
    final avgTeleFuel = bundle.avgMatchField(kSectionTele, kTeleFuelScored);
    final avgAccuracy = bundle.avgMatchAccuracyTotal();
    final hasMatch = bundle.hasMatchData;
    final hasEnoughMatchDataForGraph = bundle.matchDocs.length > 1;
    final hasZScores = stratZScores?.hasDataForTeam(teamNumber) ?? false;
    final hasPitsData = bundle.hasPitsData;

    return Column(
      mainAxisSize: expandToFillHeight ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPitsData) ...[
          _ChipsRow(
            mostCommonPlayStyle: mostCommonPlayStyle,
            trenchCapable: trenchCapable,
            climbCapable: climbCapable,
          ),
          const SizedBox(height: 8),
        ],
        if (hasEnoughMatchDataForGraph) ...[
          const SizedBox(height: 8),
          if (expandToFillHeight)
            Expanded(
              child: SfCartesianChart(
                margin: EdgeInsets.zero,
                primaryXAxis: const CategoryAxis(
                  labelPlacement: LabelPlacement.onTicks,
                ),
                primaryYAxis: const NumericAxis(),
                plotAreaBorderWidth: 0,
                series: _buildLineSeries(context, bundle.matchDocs),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: SfCartesianChart(
                margin: EdgeInsets.zero,
                primaryXAxis: const CategoryAxis(
                  labelPlacement: LabelPlacement.onTicks,
                ),
                primaryYAxis: const NumericAxis(),
                plotAreaBorderWidth: 0,
                series: _buildLineSeries(context, bundle.matchDocs),
              ),
            ),
          const Divider(height: 8, thickness: 1),
        ],
        if (hasZScores) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              _zScoreLabel(
                context,
                'Driver',
                stratZScores!.driverSkillZ[teamNumber] ?? 0,
              ),
              _zScoreLabel(
                context,
                'Defense',
                stratZScores!.defensiveSkillZ[teamNumber] ?? 0,
              ),
              _zScoreLabel(
                context,
                'Def. Resilience',
                stratZScores!.defensiveResilienceZ[teamNumber] ?? 0,
              ),
              _zScoreLabel(
                context,
                'Stability',
                stratZScores!.mechanicalStabilityZ[teamNumber] ?? 0,
              ),
            ],
          ),
        ],

        if (hasMatch) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 12,
                children: [
                  _StatPill(
                    label: 'Auto',
                    value: avgAutoFuel.toStringAsFixed(1),
                  ),
                  _StatPill(
                    label: 'Tele',
                    value: avgTeleFuel.toStringAsFixed(1),
                  ),
                  _StatPill(
                    label: 'Total',
                    value: (avgAutoFuel + avgTeleFuel).toStringAsFixed(1),
                    highlight: true,
                  ),
                  _StatPill(
                    label: 'Accuracy',
                    value: avgAccuracy != null
                        ? '${avgAccuracy.toStringAsFixed(1)}%'
                        : '?',
                    highlight: true,
                  ),
                ],
              ),
              if (ranking != null) _RankBadge(ranking: ranking!),
            ],
          ),
        ],
      ],
    );
  }

  Widget _zScoreLabel(BuildContext context, String label, double value) {
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodySmall,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: formattedRank(value)),
        ],
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  final String mostCommonPlayStyle;
  final bool trenchCapable;
  final String? climbCapable;

  const _ChipsRow({
    required this.mostCommonPlayStyle,
    required this.trenchCapable,
    required this.climbCapable,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (mostCommonPlayStyle.isNotEmpty)
          Chip(
            label: Text(
              mostCommonPlayStyle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        if (trenchCapable)
          _OutlinedChip(
            icon: Symbols.merge_type_rounded,
            label: 'Trench',
            color: secondaryColor,
          ),
        if (climbCapable != null && climbCapable != 'No Climb')
          _OutlinedChip(
            icon: Symbols.arrow_upload_ready_rounded,
            label: climbCapable!,
            color: secondaryColor,
          ),
      ],
    );
  }
}

class _OutlinedChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _OutlinedChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatPill({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _RankBadge extends StatelessWidget {
  final TeamRanking ranking;

  const _RankBadge({required this.ranking});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '#${ranking.rank}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '${ranking.rankingPoints} RP — ${ranking.rankingScore.toStringAsFixed(2)} RS',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class TeamDetailsPage extends ConsumerWidget {
  final String teamName;
  final int teamNumber;
  final String? teamWebsite;

  const TeamDetailsPage({
    super.key,
    required this.teamName,
    required this.teamNumber,
    this.teamWebsite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showNotes =
        ref
            .watch(permissionCheckerProvider)
            ?.hasPermission(PermissionKey.notesRead) ??
        false;
    final mediaAsync = ref.watch(teamMediaProvider(teamNumber));

    return mediaAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text('$teamName — $teamNumber')),
        body: Center(child: Text('Error: $e')),
      ),
      data: (media) {
        final hasMedia = media.any((record) {
          return record.hasRenderableMedia &&
              record.openUrl?.isNotEmpty == true;
        });
        final hasWebsite = teamWebsite?.isNotEmpty == true;
        final hasMediaTabContent = hasMedia || hasWebsite;

        return DefaultTabController(
          key: ValueKey('$showNotes-$hasMediaTabContent'),
          length: 3 + (showNotes ? 1 : 0) + (hasMediaTabContent ? 1 : 0),
          child: Builder(
            builder: (context) {
              final tabController = DefaultTabController.of(context);

              return AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  final showObservationFab =
                      showNotes && tabController.index == 1;

                  return Scaffold(
                    floatingActionButton: showObservationFab
                        ? FloatingActionButton.extended(
                            onPressed: () {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (_) => ObservationSheet(
                                  teamName: teamName,
                                  teamNumber: teamNumber,
                                ),
                              );
                            },
                            icon: const Icon(Symbols.add_comment_rounded),
                            label: const Text('Observation'),
                          )
                        : null,
                    appBar: AppBar(
                      title: Text('$teamName — $teamNumber'),
                      actions: [
                        PopupMenuButton<_TeamAction>(
                          icon: const Icon(Icons.more_vert),
                          tooltip: 'More options',
                          onSelected: (action) =>
                              _handleAction(context, action, ref),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: _TeamAction.openTba,
                              child: ListTile(
                                leading: const Icon(
                                  Symbols.open_in_new_rounded,
                                ),
                                title: const Text('Open in TBA'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: _TeamAction.openStatbotics,
                              child: ListTile(
                                leading: const Icon(
                                  Symbols.open_in_new_rounded,
                                ),
                                title: const Text('Open in Statbotics'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: _TeamAction.openFrcEvents,
                              child: ListTile(
                                leading: const Icon(
                                  Symbols.open_in_new_rounded,
                                ),
                                title: const Text('Open in FRC Events'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: _TeamAction.copyNumber,
                              child: ListTile(
                                leading: const Icon(
                                  Symbols.content_copy_rounded,
                                ),
                                title: const Text('Copy team number'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                      bottom: TabBar(
                        tabAlignment: TabAlignment.start,
                        isScrollable: true,
                        tabs: [
                          const Tab(text: 'Averages'),
                          if (showNotes) const Tab(text: 'Notes'),
                          const Tab(text: 'Capabilities'),
                          const Tab(text: 'Matches'),
                          if (hasMediaTabContent) const Tab(text: 'Media'),
                        ],
                      ),
                    ),
                    body: TabBarView(
                      children: [
                        AveragesTab(teamNumber: teamNumber),
                        if (showNotes) NotesTab(teamNumber: teamNumber),
                        CapabilitiesTab(teamNumber: teamNumber),
                        MatchesTab(teamNumber: teamNumber),
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

List<LineSeries<ProcessedScoutingDoc, String>> _buildLineSeries(
  BuildContext context,
  List<ProcessedScoutingDoc> data,
) {
  const markerSettings = MarkerSettings(
    isVisible: true,
    height: 6,
    width: 6,
    shape: DataMarkerType.verticalLine,
    borderWidth: 2,
  );

  return [
    LineSeries<ProcessedScoutingDoc, String>(
      dataSource: data,
      xValueMapper: (doc, index) => doc.raw.data['matchNumber'].toString(),
      yValueMapper: (doc, _) =>
          _scaledMatchField(doc, kSectionAuto, kAutoFuelScored),
      name: 'Auto',
      color: Colors.red,
      markerSettings: markerSettings,
      animationDuration: 1000,
    ),
    LineSeries<ProcessedScoutingDoc, String>(
      dataSource: data,
      xValueMapper: (doc, index) => doc.raw.data['matchNumber'].toString(),
      yValueMapper: (doc, _) =>
          _scaledMatchField(doc, kSectionTele, kTeleFuelScored),
      name: 'Tele',
      color: Colors.blue,
      markerSettings: markerSettings,
      animationDuration: 1000,
    ),
    LineSeries<ProcessedScoutingDoc, String>(
      dataSource: data,
      xValueMapper: (doc, index) => doc.raw.data['matchNumber'].toString(),
      yValueMapper: (doc, _) =>
          _scaledMatchField(doc, kSectionTele, kTeleFuelScored) +
          _scaledMatchField(doc, kSectionAuto, kAutoFuelScored),
      name: 'Total',
      color: Colors.green,
      markerSettings: markerSettings,
      dataLabelSettings: DataLabelSettings(
        isVisible: true,
        labelAlignment: ChartDataLabelAlignment.top,
        offset: Offset(0, 8),
        builder:
            (
              dynamic data,
              dynamic point,
              dynamic series,
              int pointIndex,
              int seriesIndex,
            ) {
              final doc = data as ProcessedScoutingDoc;

              final bool brokeDown =
                  _parseSafetyBool(
                    TeamScoutingBundle.getMatchField(
                      doc.raw,
                      kSectionTele,
                      kTeleStoppedWorking,
                    ),
                  ) ||
                  _parseSafetyBool(
                    TeamScoutingBundle.getMatchField(
                      doc.raw,
                      kSectionTele,
                      kTeleLostComms,
                    ),
                  );

              final bool playedDefense =
                  _parseSafetyBool(
                    TeamScoutingBundle.getMatchField(
                      doc.raw,
                      kSectionEndgame,
                      kEndPlayedDefenseOffShift,
                    ),
                  ) ||
                  _parseSafetyBool(
                    TeamScoutingBundle.getMatchField(
                      doc.raw,
                      kSectionEndgame,
                      kEndPlayedDefenseOnShift,
                    ),
                  );

              final bool noShow = _parseSafetyBool(
                TeamScoutingBundle.getMatchField(
                  doc.raw,
                  kSectionEndgame,
                  kEndNoShow,
                ),
              );

              if (!brokeDown && !playedDefense && !noShow) {
                return const SizedBox.shrink();
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (brokeDown)
                    Icon(
                      Symbols.build_circle_rounded,
                      color: Theme.of(context).colorScheme.error,
                      size: 14,
                    ),
                  if (playedDefense)
                    Icon(
                      Symbols.shield_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 14,
                    ),
                  if (noShow)
                    Icon(
                      Symbols.help_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 14,
                    ),
                ],
              );
            },
      ),
      animationDuration: 1000,
    ),
  ];
}

// temp until we make fields typed/versioned
bool _parseSafetyBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value > 0;
  if (value is String) {
    final lower = value.toLowerCase();
    return lower == 'true' || lower == '1' || lower == 'y';
  }
  return false;
}

double _scaledMatchField(
  ProcessedScoutingDoc doc,
  String sectionId,
  String fieldId,
) {
  final value = TeamScoutingBundle.getMatchField(doc.raw, sectionId, fieldId);
  if (value is! num) return 0.0;

  final raw = value.toDouble();
  if (sectionId == kSectionAuto && _scaledAutoFields.contains(fieldId)) {
    return raw * doc.autoFuelScalar;
  }
  if (sectionId == kSectionTele && _scaledTeleFields.contains(fieldId)) {
    return raw * doc.teleFuelScalar;
  }
  return raw;
}

const _scaledAutoFields = {kAutoFuelScored, kAutoFuelPassed};
const _scaledTeleFields = {kTeleFuelScored, kTeleFuelPassed, kTeleFuelPoached};

enum _TeamAction { openTba, openStatbotics, openFrcEvents, copyNumber }
