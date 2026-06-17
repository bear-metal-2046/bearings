import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/team_lookup/tabs/scouting_tab_widgets.dart';
import 'package:beariscope/providers/strat_z_score_provider.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

class CapabilitiesTab extends ConsumerWidget {
  final int teamNumber;

  const CapabilitiesTab({super.key, required this.teamNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamScoutingProvider(teamNumber));
    final stratZScores =
        ref.watch(stratZScoresProvider).asData?.value ?? StratZScoreData.empty;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (bundle) => _CapabilitiesBody(
        bundle: bundle,
        teamNumber: teamNumber,
        stratZScores: stratZScores,
      ),
    );
  }
}

class _CapabilitiesBody extends StatelessWidget {
  final TeamScoutingBundle bundle;
  final int teamNumber;
  final StratZScoreData stratZScores;

  const _CapabilitiesBody({
    required this.bundle,
    required this.teamNumber,
    required this.stratZScores,
  });

  @override
  Widget build(BuildContext context) {
    if (!bundle.hasPitsData && !bundle.hasMatchData) {
      return const Center(
        child: Text('No scouting data recorded for this team.'),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ScoutingSectionHeader(
          title: 'Drivebase & Mobility',
          icon: Symbols.build_rounded,
        ),
        const SizedBox(height: kScoutingHeaderGap),
        _botCard(context),
        const SizedBox(height: kScoutingSectionGap),
        const ScoutingSectionHeader(
          title: 'Scoring & Ball Handling',
          icon: Symbols.local_fire_department_rounded,
        ),
        const SizedBox(height: kScoutingHeaderGap),
        _outtakeCard(context),
        const SizedBox(height: kScoutingSectionGap),
        const ScoutingSectionHeader(
          title: 'Auto & Pathing',
          icon: Symbols.route_rounded,
        ),
        const SizedBox(height: kScoutingHeaderGap),
        _autoCard(context),
        const SizedBox(height: kScoutingSectionGap),
        const ScoutingSectionHeader(
          title: 'Endgame & Defense',
          icon: Symbols.moving_rounded,
        ),
        const SizedBox(height: kScoutingHeaderGap),
        _climbCard(context),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bot card
  // ---------------------------------------------------------------------------

  Widget _botCard(BuildContext context) {
    final drivetrainType = bundle.getPitsField<String>('drivetrainType') ?? '—';
    final swerveBrand = bundle.getPitsField<String>('swerveBrand');
    final swerveGearRatio = _firstNonEmptyPitsString([
      'swerveGearRatio',
      'swerveGR',
    ]);
    final motorType = bundle.getPitsField<String>('motorType') ?? '—';
    final wheelType = bundle.getPitsField<String>('wheelType') ?? '—';
    final weight = bundle.getPitsDouble('weight');
    final chassisLength = bundle.getPitsDouble('chassisLength');
    final chassisWidth = bundle.getPitsDouble('chassisWidth');
    final chassisHeight = bundle.getPitsDouble('chassisHeight');
    final hExt = bundle.getPitsDouble('horizontalExtensionLimit');
    final vExt = bundle.getPitsDouble('verticalExtensionLimit');
    final hopperSize = bundle.getPitsField<int>('hopperSize') as num?;

    final showSwerve = drivetrainType == 'Swerve';

    return _specsCard(
      context,
      rows: [
        ScoutingDataRow(label: 'Drivetrain', value: drivetrainType),
        if (showSwerve && swerveBrand != null)
          ScoutingDataRow(label: '  Swerve Brand', value: swerveBrand),
        if (showSwerve && swerveGearRatio != null && swerveGearRatio.isNotEmpty)
          ScoutingDataRow(label: '  Gear Ratio', value: swerveGearRatio),
        ScoutingDataRow(label: 'Drive Motor', value: motorType),
        ScoutingDataRow(label: 'Wheel Type', value: wheelType),
        ScoutingDataRow(
          label: 'Chassis (L × W × H)',
          value:
              [
                chassisLength,
                chassisWidth,
                chassisHeight,
              ].every((v) => v != null)
              ? '${chassisLength!.toStringAsFixed(1)}" × ${chassisWidth!.toStringAsFixed(1)}" × ${chassisHeight!.toStringAsFixed(1)}"'
              : '—',
        ),
        ScoutingDataRow(
          label: 'Weight',
          value: weight != null ? '${weight.toStringAsFixed(1)} lbs' : '—',
        ),
        ScoutingDataRow(
          label: 'Extension (H / V)',
          value:
              '${hExt != null ? '${hExt.toStringAsFixed(1)}"' : '—'} / ${vExt != null ? '${vExt.toStringAsFixed(1)}"' : '—'}',
        ),
        ScoutingDataRow(
          label: 'Hopper Size',
          value: hopperSize != null ? '${hopperSize.toInt()} balls' : '—',
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Auto card
  // ---------------------------------------------------------------------------

  Widget _autoCard(BuildContext context) {
    final autoClimb = bundle.getPitsField<String>('autoClimb') ?? '—';
    final collectionLocations = bundle.getPitsListField(
      'fuelCollectionLocation',
    );
    final autoPaths = bundle.getPitsField<String>('autoPaths') ?? '—';
    final pathwayPreference = _firstNonEmptyPitsDisplayValue([
      'pathwayDetails',
      'pathwayPreference',
    ]);
    final trenchCapability =
        bundle.getPitsField<String>('trenchCapability') ?? '—';
    final towerCapability =
        bundle.getPitsField<String>('towerCapability') ?? '—';
    final hasMatchData = bundle.hasMatchData;
    final modalStartPosition = hasMatchData
        ? bundle.modalMatchField(kSectionAuto, kAutoStartPositions)
        : null;
    final outpostRate = hasMatchData
        ? bundle.boolRateMatchField(kSectionAuto, kAutoCollectFromOutpost)
        : null;
    final depotRate = hasMatchData
        ? bundle.boolRateMatchField(kSectionAuto, kAutoCollectFromDepot)
        : null;

    return _specsCard(
      context,
      rows: [
        ScoutingDataRow(label: 'Auto Paths', value: _textOrDash(autoPaths)),
        ScoutingDataRow(label: 'Auto Climb', value: autoClimb),
        ScoutingDataRow(
          label: 'Fuel Collection Spots',
          value: _joinedOrDash(collectionLocations),
        ),
        ScoutingDataRow(label: 'Pathway Preference', value: pathwayPreference),
        ScoutingDataRow(label: 'Trench Capable', value: trenchCapability),
        ScoutingDataRow(label: 'Tower Capable', value: towerCapability),
        if (hasMatchData) ...[
          const ScoutingDataDivider(),
          ScoutingDataRow(
            label: 'Most Common Start Pos.',
            value: modalStartPosition ?? '—',
          ),
          ScoutingDataRow(
            label: 'Outpost Collect Rate',
            value: outpostRate != null ? _fmtPct(outpostRate * 100) : '—',
          ),
          ScoutingDataRow(
            label: 'Depot Collect Rate',
            value: depotRate != null ? _fmtPct(depotRate * 100) : '—',
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Outtake card
  // ---------------------------------------------------------------------------

  Widget _outtakeCard(BuildContext context) {
    final shooterType = bundle.getPitsField<String>('shooter') ?? '—';
    final shooterCount = bundle.getPitsField<num>('shooterNumber');
    final collectorType = bundle.getPitsField<String>('collectorType') ?? '—';
    final indexerType = bundle.getPitsField<String>('indexerType') ?? '—';
    final outtakeRate = bundle.getPitsDouble('fuelOuttakeRate');
    final pitsAccuracy = bundle.getPitsDouble('averageAccuracy');
    final moveWhileShooting = bundle.getPitsListField('moveWhileShooting');
    final rangeFromField = _firstNonEmptyPitsList([
      'shootingRange',
      'rangeFromField',
    ]);
    // Keep observed tele accuracy alongside the pits claim for direct comparison.
    final actualTeleAccuracy = bundle.hasMatchData
        ? bundle.avgMatchAccuracy(kSectionTele)
        : null;

    return _specsCard(
      context,
      rows: [
        ScoutingDataRow(label: 'Shooter Type', value: shooterType),
        ScoutingDataRow(
          label: 'Number of Shooters',
          value: shooterCount != null ? shooterCount.toInt().toString() : '—',
        ),
        ScoutingDataRow(label: 'Collector Type', value: collectorType),
        ScoutingDataRow(label: 'Indexer Type', value: indexerType),
        ScoutingDataRow(
          label: 'Outtake Rate',
          value: outtakeRate != null
              ? '${outtakeRate.toStringAsFixed(1)} balls/s'
              : '—',
        ),
        const ScoutingDataDivider(),
        ScoutingDataRow(
          label: 'Mobile Shooting',
          value: _joinedOrDash(moveWhileShooting),
        ),
        ScoutingDataRow(
          label: 'Range from Field',
          value: _joinedOrDash(rangeFromField, separator: ' · '),
        ),
        ScoutingDataRow(
          label: 'Claimed Accuracy (Pits)',
          value: pitsAccuracy != null
              ? '${pitsAccuracy.toStringAsFixed(1)}%'
              : '—',
        ),
        ScoutingDataRow(
          label: 'Observed Tele Accuracy',
          value: actualTeleAccuracy != null ? _fmtPct(actualTeleAccuracy) : '—',
          highlight: true,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Climb card
  // ---------------------------------------------------------------------------

  Widget _climbCard(BuildContext context) {
    final climbMethod = bundle.getPitsField<String>('climbMethod') ?? '—';
    final climbLevels = bundle.getPitsListField('climbLevel');
    final climbConsistency = bundle.getPitsDouble('climbConsistency');

    // Derive actual endgame climb stats from match data.
    final n = bundle.matchDocs.length;
    final hasMatchData = bundle.hasMatchData;
    final actualClimbRate = hasMatchData
        ? bundle.rateMatchField(
            kSectionEndgame,
            kEndClimb,
            (v) => v != null && v.toString().isNotEmpty,
          )
        : null;
    final climbCounts = <String, int>{};
    if (hasMatchData) {
      for (final doc in bundle.matchDocs) {
        final v = TeamScoutingBundle.getMatchField(
          doc.raw,
          kSectionEndgame,
          kEndClimb,
        )?.toString();
        if (v != null && v.isNotEmpty) {
          climbCounts[v] = (climbCounts[v] ?? 0) + 1;
        }
      }
    }
    final mostCommonClimbLocation = hasMatchData
        ? bundle.modalMatchField(kSectionEndgame, kEndClimbLocation)
        : null;
    final defenseOffShiftRate = hasMatchData
        ? bundle.rateMatchField(
            kSectionEndgame,
            kEndPlayedDefenseOffShift,
            (v) => v == true,
          )
        : null;

    return _specsCard(
      context,
      rows: [
        ScoutingDataRow(label: 'Mechanism', value: climbMethod),
        ScoutingDataRow(
          label: 'Climb Levels',
          value: _joinedOrDash(climbLevels),
        ),
        ScoutingDataRow(
          label: 'Climb Consistency',
          value: climbConsistency != null
              ? '${climbConsistency.toStringAsFixed(1)} / 10'
              : '—',
        ),
        if (hasMatchData) ...[
          const ScoutingDataDivider(),
          ScoutingDataRow(
            label: 'Actual Endgame Climb Rate',
            value: actualClimbRate != null
                ? '${_fmtPct(actualClimbRate * 100)} ($n matches)'
                : '—',
            highlight: true,
          ),
          if (mostCommonClimbLocation != null)
            ScoutingDataRow(
              label: 'Most Common Bar Position',
              value: mostCommonClimbLocation,
            ),
          if (climbCounts.isNotEmpty)
            ScoutingDataRow(
              label: 'Level Breakdown',
              value: climbCounts.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join(' · '),
              highlight: true,
            ),
          if (defenseOffShiftRate != null)
            ScoutingDataRow(
              label: 'Defense Freq. (Off Shift)',
              value: _fmtPct(defenseOffShiftRate * 100),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widget helpers
  // ---------------------------------------------------------------------------

  List<String> _firstNonEmptyPitsList(List<String> keys) {
    for (final key in keys) {
      final values = bundle.getPitsListField(key);
      if (values.isNotEmpty) return values;
    }
    return const [];
  }

  String? _firstNonEmptyPitsString(List<String> keys) {
    for (final key in keys) {
      final value = bundle.getPitsField<String>(key);
      if (value != null && value.trim().isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String _firstNonEmptyPitsDisplayValue(
    List<String> keys, {
    String separator = ', ',
  }) {
    final listValue = _firstNonEmptyPitsList(keys);
    if (listValue.isNotEmpty) {
      return listValue.join(separator);
    }

    final stringValue = _firstNonEmptyPitsString(keys);
    if (stringValue != null) {
      return stringValue;
    }

    return '—';
  }

  String _joinedOrDash(List<String> values, {String separator = ', '}) {
    return values.isNotEmpty ? values.join(separator) : '—';
  }

  String _textOrDash(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '—' : trimmed;
  }

  String _fmtPct(double v) => '${v.toStringAsFixed(1)}%';

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
