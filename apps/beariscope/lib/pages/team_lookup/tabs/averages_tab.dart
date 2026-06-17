import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/team_lookup/tabs/scouting_tab_widgets.dart';
import 'package:beariscope/providers/strat_z_score_provider.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

class AveragesTab extends ConsumerWidget {
  final int teamNumber;

  const AveragesTab({super.key, required this.teamNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamScoutingProvider(teamNumber));
    final stratZScores =
        ref.watch(stratZScoresProvider).asData?.value ?? StratZScoreData.empty;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (bundle) => _AveragesBody(
        bundle: bundle,
        teamNumber: teamNumber,
        stratZScores: stratZScores,
      ),
    );
  }
}

class _AveragesBody extends StatefulWidget {
  final TeamScoutingBundle bundle;
  final int teamNumber;
  final StratZScoreData stratZScores;

  const _AveragesBody({
    required this.bundle,
    required this.teamNumber,
    required this.stratZScores,
  });

  @override
  State<_AveragesBody> createState() => _AveragesBodyState();
}

class _AveragesBodyState extends State<_AveragesBody> {
  // null for all matches, otherwise n matches
  static int? _lastN;

  static const _presets = [null, 1, 2, 3, 5];

  TeamScoutingBundle get _filteredBundle {
    if (_lastN == null) {
      return widget.bundle;
    } else if (_lastN == 0) {
      return TeamScoutingBundle(
        matchDocs: widget.bundle.matchDocs,
        pitsDoc: widget.bundle.pitsDoc,
        stratDocs: widget.bundle.stratDocs,
        driveTeamDocs: widget.bundle.driveTeamDocs,
        observationDocs: widget.bundle.observationDocs,
        weight: 2,
      );
    } else {
      final sortedMatch = [...widget.bundle.matchDocs]
        ..sort((a, b) {
          final ma = TeamScoutingBundle.matchNumber(a.raw) ?? -1;
          final mb = TeamScoutingBundle.matchNumber(b.raw) ?? -1;
          return mb.compareTo(ma);
        });
      final limitedMatch = sortedMatch.take(_lastN!).toList();
      return TeamScoutingBundle(
        matchDocs: limitedMatch,
        pitsDoc: widget.bundle.pitsDoc,
        stratDocs: widget.bundle.stratDocs,
        driveTeamDocs: widget.bundle.driveTeamDocs,
        observationDocs: widget.bundle.observationDocs,
      );
    }
  }

  String _label(int? n) => n == null ? 'All' : 'Last $n';

  @override
  Widget build(BuildContext context) {
    final bundle = _filteredBundle;

    if (!widget.bundle.hasMatchData) {
      return const Center(child: Text('No match data recorded for this team.'));
    }

    final n = bundle.matchDocs.length;
    final avgAutoFuel = bundle.avgMatchField(kSectionAuto, kAutoFuelScored);
    final avgAutoAccuracy = bundle.avgMatchAccuracy(kSectionAuto);
    final autoL1Rate = bundle.rateMatchField(
      kSectionAuto,
      kAutoClimbL1,
      (v) => v == 'Successful',
    );
    final avgTeleFuel = bundle.avgMatchField(kSectionTele, kTeleFuelScored);
    final avgTeleAccuracy = bundle.avgMatchAccuracy(kSectionTele);
    final avgAutoFuelPassed = bundle.avgMatchField(
      kSectionAuto,
      kAutoFuelPassed,
    );
    final avgTeleFuelPassed = bundle.avgMatchField(
      kSectionTele,
      kTeleFuelPassed,
    );
    final avgTeleFuelPoached = bundle.avgMatchField(
      kSectionTele,
      kTeleFuelPoached,
    );
    final totalAvgFuel = avgAutoFuel + avgTeleFuel;

    final endgameClimbRate = bundle.rateMatchField(
      kSectionEndgame,
      kEndClimb,
      (v) => v != null && v.toString().isNotEmpty,
    );
    final mostCommonClimb =
        bundle.modalMatchField(kSectionEndgame, kEndClimb) ?? '—';
    final defenseRate = bundle.rateMatchField(
      kSectionEndgame,
      kEndPlayedDefenseOnShift,
      (v) => v == true,
    );
    final defendedAgainstRate = bundle.rateMatchField(
      kSectionEndgame,
      kEndDefendedAgainst,
      (v) => v == true,
    );
    final beachedHighCenterRate = bundle.rateMatchField(
      kSectionTele,
      kTeleBeachedHighCenter,
      (v) => v is num && v.toInt() > 0,
    );
    final noShowRate = bundle.rateMatchField(
      kSectionEndgame,
      kEndNoShow,
      (v) => v == true,
    );
    final avgFullHopper = bundle.avgMatchField(
      kSectionTele,
      kTelePeriodStartedWithFullHopper,
    );
    final avgFouls = bundle.avgMatchField(kSectionTele, kEndFouls);
    final stoppedWorkingRate = bundle.rateMatchField(
      kSectionTele,
      kTeleStoppedWorking,
      (v) => v == true,
    );

    const playStyleOptions = ['Passing', 'Cycling', 'Shooting', 'Defense'];
    final rawPlayStyle = bundle.modalMatchField(kSectionEndgame, kEndPlayStyle);

    String mostCommonPlayStyle = '—';

    if (rawPlayStyle != null) {
      final input = rawPlayStyle.toString();

      // extract all individual number using a Regex
      final matches = RegExp(r'\d+').allMatches(input);

      if (matches.isNotEmpty) {
        // map each number found to its corresponding option string
        final selectedNames = matches.map((m) {
          final index = int.parse(m.group(0)!);
          return (index >= 0 && index < playStyleOptions.length)
              ? playStyleOptions[index]
              : 'Unknown';
        }).toList();

        // join them with commas
        mostCommonPlayStyle = selectedNames.join(', ');
      } else {
        // fallback if no digits were found but string isn't empty
        mostCommonPlayStyle = input.isEmpty ? '—' : input;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _presets.map((preset) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_label(preset)),
                  selected: _lastN == preset,
                  onSelected: (_) => setState(() => _lastN = preset),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        const ScoutingSectionHeader(
          title: 'Scoring',
          icon: Symbols.local_fire_department_rounded,
        ),
        const SizedBox(height: kScoutingHeaderGap),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScoutingDataRow(
                  label: 'Total Avg Fuel / Match',
                  value: _fmtDec(totalAvgFuel),
                  highlight: true,
                ),
                const ScoutingDataDivider(),
                ScoutingDataRow(
                  label: 'Auto Avg Fuel',
                  value: _fmtDec(avgAutoFuel),
                ),
                ScoutingDataRow(
                  label: 'Auto Accuracy',
                  value: avgAutoAccuracy != null
                      ? _fmtPct(avgAutoAccuracy)
                      : '—',
                ),
                ScoutingDataRow(
                  label: 'Auto L1 Climb Rate',
                  value: _fmtPct(autoL1Rate * 100),
                ),
                const ScoutingDataDivider(),
                ScoutingDataRow(
                  label: 'Tele Avg Fuel',
                  value: _fmtDec(avgTeleFuel),
                ),
                ScoutingDataRow(
                  label: 'Tele Accuracy',
                  value: avgTeleAccuracy != null
                      ? _fmtPct(avgTeleAccuracy)
                      : '—',
                ),
                ScoutingDataRow(
                  label: 'Avg Fuel Passed (Auto)',
                  value: _fmtDec(avgAutoFuelPassed),
                ),
                ScoutingDataRow(
                  label: 'Avg Fuel Passed (Tele)',
                  value: _fmtDec(avgTeleFuelPassed),
                ),
                ScoutingDataRow(
                  label: 'Avg Fuel Poached',
                  value: _fmtDec(avgTeleFuelPoached),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: kScoutingSectionGap),
        const ScoutingSectionHeader(
          title: 'Behaviour',
          icon: Symbols.settings_rounded,
        ),
        const SizedBox(height: kScoutingHeaderGap),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScoutingDataRow(
                  label: 'Endgame Climb Rate',
                  value: _fmtPct(endgameClimbRate * 100),
                ),
                ScoutingDataRow(
                  label: 'Most Common Climb Level',
                  value: mostCommonClimb,
                ),
                ScoutingDataRow(
                  label: 'Defense Frequency (on shift)',
                  value: _fmtPct(defenseRate * 100),
                ),
                ScoutingDataRow(
                  label: 'Defended Against Frequency',
                  value: _fmtPct(defendedAgainstRate * 100),
                ),
                ScoutingDataRow(
                  label: 'Stopped Working Rate',
                  value: _fmtPct(stoppedWorkingRate * 100),
                ),
                ScoutingDataRow(
                  label: 'No Show Rate',
                  value: _fmtPct(noShowRate * 100),
                ),
                ScoutingDataRow(
                  label: 'Beached / High Center Rate',
                  value: _fmtPct(beachedHighCenterRate * 100),
                ),
                ScoutingDataRow(
                  label: 'Most Common Play Style',
                  value: mostCommonPlayStyle,
                ),
                const ScoutingDataDivider(),
                ScoutingDataRow(
                  label: 'Full-Hopper Periods Avg',
                  value: _fmtDec(avgFullHopper),
                ),
                ScoutingDataRow(label: 'Avg Fouls', value: _fmtDec(avgFouls)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _lastN == null
              ? 'Based on $n match${n == 1 ? '' : 'es'}'
              : 'Last $n of ${widget.bundle.matchDocs.length} match${widget.bundle.matchDocs.length == 1 ? '' : 'es'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (bundle.hasStratData) ...[
          const SizedBox(height: kScoutingSectionGap),
          const ScoutingSectionHeader(
            title: 'Z-Score Metrics',
            icon: Symbols.analytics_rounded,
          ),
          const SizedBox(height: kScoutingHeaderGap),
          _zScoreCard(context, widget.stratZScores),
        ],
      ],
    );
  }

  static String _fmtDec(double v) => v.toStringAsFixed(1);
  static String _fmtPct(double v) => '${v.toStringAsFixed(1)}%';

  // ---------------------------------------------------------------------------
  // Z-score card
  // ---------------------------------------------------------------------------

  Widget _zScoreCard(BuildContext context, StratZScoreData stratZScores) {
    var stratRanks = stratZScores.changeToRanks();
    return _specsCard(
      context,
      rows: [
        ScoutingDataRow(
          label: 'Driver Skill',
          value:
              '${formattedRank(stratRanks.driverSkillZ[widget.teamNumber] ?? 0)}[${StratZScoreData.zLabel(stratZScores.driverSkillZ[widget.teamNumber] ?? 0)}]',
          highlight: true,
        ),
        ScoutingDataRow(
          label: 'Defensive Skill',
          value:
              '${formattedRank(stratRanks.defensiveSkillZ[widget.teamNumber] ?? 0)}[${StratZScoreData.zLabel(stratZScores.defensiveSkillZ[widget.teamNumber] ?? 0)}]',
          highlight: true,
        ),
        ScoutingDataRow(
          label: 'Defense Resilience',
          value:
              '${formattedRank(stratRanks.defensiveResilienceZ[widget.teamNumber] ?? 0)}[${StratZScoreData.zLabel(stratZScores.defensiveResilienceZ[widget.teamNumber] ?? 0)}]',
          highlight: true,
        ),
        ScoutingDataRow(
          label: 'Mech. Stability',
          value:
              '${formattedRank(stratRanks.mechanicalStabilityZ[widget.teamNumber] ?? 0)}[${StratZScoreData.zLabel(stratZScores.mechanicalStabilityZ[widget.teamNumber] ?? 0)}]',
          highlight: true,
        ),
      ],
    );
  }

  Widget _specsCard(BuildContext context, {required List<Widget> rows}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }
}
