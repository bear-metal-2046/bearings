import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/team_lookup/tabs/scouting_tab_widgets.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:beariscope/widgets/settings_group.dart';
import 'package:beariscope/widgets/team_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class PicklistTeamQuickViewSheet extends ConsumerWidget {
  final Team team;

  const PicklistTeamQuickViewSheet({super.key, required this.team});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scouting = ref.watch(teamScoutingProvider(team.number));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .78,
      minChildSize: .5,
      maxChildSize: .92,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    team.name,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Team ${team.number}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: scouting.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _QuickViewBody(
                  bundle: TeamScoutingBundle(
                    matchDocs: const [],
                    pitsDoc: null,
                    stratDocs: const [],
                    driveTeamDocs: const [],
                    observationDocs: const [],
                  ),
                  scrollController: scrollController,
                ),
                data: (bundle) => _QuickViewBody(
                  bundle: bundle,
                  scrollController: scrollController,
                ),
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(LucideIcons.arrowUpRight),
                  label: const Text('Dive deeper'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickViewBody extends StatelessWidget {
  final TeamScoutingBundle bundle;
  final ScrollController scrollController;

  const _QuickViewBody({required this.bundle, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final hasMatches = bundle.hasMatchData;
    final latestNote = _latestScoutNote(bundle);

    final autoFuel = hasMatches
        ? bundle.avgMatchField(kSectionAuto, kAutoFuelScored)
        : null;
    final teleFuel = hasMatches
        ? bundle.avgMatchField(kSectionTele, kTeleFuelScored)
        : null;
    final autoAccuracy = hasMatches
        ? bundle.avgMatchAccuracy(kSectionAuto)
        : null;
    final teleAccuracy = hasMatches
        ? bundle.avgMatchAccuracy(kSectionTele)
        : null;
    final autoL1Rate = hasMatches
        ? bundle.rateMatchField(
            kSectionAuto,
            kAutoClimbL1,
            (value) => value == 'Successful',
          )
        : null;
    final endgameClimbRate = hasMatches
        ? bundle.rateMatchField(
            kSectionEndgame,
            kEndClimb,
            (value) => value != null && value.toString().isNotEmpty,
          )
        : null;
    final defenseRate = hasMatches
        ? bundle.rateMatchField(
            kSectionEndgame,
            kEndPlayedDefenseOnShift,
            (value) => value == true,
          )
        : null;
    final defendedAgainstRate = hasMatches
        ? bundle.rateMatchField(
            kSectionEndgame,
            kEndDefendedAgainst,
            (value) => value == true,
          )
        : null;
    final stoppedWorkingRate = hasMatches
        ? bundle.rateMatchField(
            kSectionTele,
            kTeleStoppedWorking,
            (value) => value == true,
          )
        : null;
    final noShowRate = hasMatches
        ? bundle.rateMatchField(
            kSectionEndgame,
            kEndNoShow,
            (value) => value == true,
          )
        : null;
    final beachedHighCenterRate = hasMatches
        ? bundle.rateMatchField(
            kSectionTele,
            kTeleBeachedHighCenter,
            (value) => value is num && value.toInt() > 0,
          )
        : null;
    final avgFouls = hasMatches
        ? bundle.avgMatchField(kSectionTele, kEndFouls)
        : null;
    final shooterCount = bundle.getPitsField<num>('shooterNumber');
    final pitsAccuracy = bundle.getPitsDouble('averageAccuracy');

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _section('Scoring', [
          if (hasMatches) ...[
            Text(
              'Fuel scored by match',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _FuelTrendChart(bundle: bundle),
            const SizedBox(height: 16),
          ],
          ScoutingDataRow(
            label: 'Total Avg Fuel / Match',
            value: autoFuel != null && teleFuel != null
                ? _decimal(autoFuel + teleFuel)
                : '—',
            highlight: true,
          ),
          ScoutingDataRow(
            label: 'Auto Avg Fuel',
            value: _decimalOrDash(autoFuel),
          ),
          ScoutingDataRow(
            label: 'Tele Avg Fuel',
            value: _decimalOrDash(teleFuel),
          ),
          ScoutingDataRow(
            label: 'Auto Accuracy',
            value: _percentOrDash(autoAccuracy),
          ),
          ScoutingDataRow(
            label: 'Tele Accuracy',
            value: _percentOrDash(teleAccuracy),
          ),
          ScoutingDataRow(
            label: 'Avg Fuel Passed (Tele)',
            value: hasMatches
                ? _decimal(bundle.avgMatchField(kSectionTele, kTeleFuelPassed))
                : '—',
          ),
        ]),
        _section('Endgame', [
          ScoutingDataRow(
            label: 'Endgame Climb Rate',
            value: _rateOrDash(endgameClimbRate),
          ),
          ScoutingDataRow(
            label: 'Most Common Climb Level',
            value: hasMatches
                ? bundle.modalMatchField(kSectionEndgame, kEndClimb) ?? '—'
                : '—',
          ),
          ScoutingDataRow(
            label: 'Auto L1 Climb Rate',
            value: _rateOrDash(autoL1Rate),
          ),
        ]),
        _section('Defense & Reliability', [
          ScoutingDataRow(
            label: 'Defense Frequency',
            value: _rateOrDash(defenseRate),
          ),
          ScoutingDataRow(
            label: 'Defended Against Frequency',
            value: _rateOrDash(defendedAgainstRate),
          ),
          ScoutingDataRow(
            label: 'Stopped Working Rate',
            value: _rateOrDash(stoppedWorkingRate),
          ),
          ScoutingDataRow(
            label: 'No Show Rate',
            value: _rateOrDash(noShowRate),
          ),
          ScoutingDataRow(
            label: 'Beached / High Center Rate',
            value: _rateOrDash(beachedHighCenterRate),
          ),
          ScoutingDataRow(label: 'Avg Fouls', value: _decimalOrDash(avgFouls)),
        ]),
        _section('Robot', [
          ScoutingDataRow(
            label: 'Drivetrain',
            value: bundle.getPitsField<String>('drivetrainType') ?? '—',
          ),
          ScoutingDataRow(
            label: 'Shooter Type',
            value: bundle.getPitsField<String>('shooter') ?? '—',
          ),
          ScoutingDataRow(
            label: 'Number of Shooters',
            value: shooterCount?.toInt().toString() ?? '—',
          ),
          ScoutingDataRow(
            label: 'Collector Type',
            value: bundle.getPitsField<String>('collectorType') ?? '—',
          ),
          ScoutingDataRow(
            label: 'Trench Capable',
            value: bundle.getPitsField<String>('trenchCapability') ?? '—',
          ),
          ScoutingDataRow(
            label: 'Claimed Accuracy (Pits)',
            value: pitsAccuracy != null ? _percent(pitsAccuracy) : '—',
          ),
          ScoutingDataRow(
            label: 'Observed Tele Accuracy',
            value: _percentOrDash(teleAccuracy),
            highlight: true,
          ),
        ]),
        if (latestNote != null) ...[
          const SizedBox(height: 16),
          Text(
            'Latest note: $latestNote',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Based on ${bundle.matchDocs.length} match${bundle.matchDocs.length == 1 ? '' : 'es'}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> rows) => SettingsGroup(
    title: title,
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    ],
  );

  String? _latestScoutNote(TeamScoutingBundle bundle) {
    final notes = <({DateTime timestamp, String note})>[];
    for (final doc in bundle.matchDocs) {
      final note = TeamScoutingBundle.getMatchField(
        doc.raw,
        kSectionEndgame,
        kEndNotes,
      )?.toString().trim();
      if (note?.isNotEmpty == true) {
        notes.add((timestamp: doc.raw.timestamp, note: note!));
      }
    }
    final pitsNote = bundle.pitsDoc?.data['notes']?.toString().trim();
    if (pitsNote?.isNotEmpty == true) {
      notes.add((timestamp: bundle.pitsDoc!.timestamp, note: pitsNote!));
    }
    for (final doc in bundle.driveTeamDocs) {
      final note = doc.data['note']?.toString().trim();
      if (note?.isNotEmpty == true) {
        notes.add((timestamp: doc.timestamp, note: note!));
      }
    }
    for (final doc in bundle.observationDocs) {
      final note = doc.data['note']?.toString().trim();
      if (note?.isNotEmpty == true) {
        notes.add((timestamp: doc.timestamp, note: note!));
      }
    }
    if (notes.isEmpty) return null;
    notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return notes.first.note;
  }

  String _decimal(double value) => value.toStringAsFixed(1);

  String _decimalOrDash(double? value) => value == null ? '—' : _decimal(value);

  String _percent(double value) => '${value.toStringAsFixed(1)}%';

  String _percentOrDash(double? value) => value == null ? '—' : _percent(value);

  String _rateOrDash(double? value) =>
      value == null ? '—' : _percent(value * 100);
}

class _FuelTrendChart extends StatelessWidget {
  final TeamScoutingBundle bundle;

  const _FuelTrendChart({required this.bundle});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: SfCartesianChart(
        margin: EdgeInsets.zero,
        primaryXAxis: CategoryAxis(
          labelPlacement: LabelPlacement.onTicks,
          labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          majorGridLines: MajorGridLines(width: 0),
        ),
        primaryYAxis: NumericAxis(
          labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          majorGridLines: MajorGridLines(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        plotAreaBorderWidth: 0,
        series: buildTeamCardLineSeries(context, bundle.matchDocs),
      ),
    );
  }
}
