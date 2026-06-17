import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/providers/team_scouting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'package:beariscope/models/processed_scouting_doc.dart';

class GraphTab extends ConsumerWidget {
  final int teamNumber;

  const GraphTab({super.key, required this.teamNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamScoutingProvider(teamNumber));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (bundle) => _GraphTabBody(bundle: bundle),
    );
  }
}

class _GraphTabBody extends StatefulWidget {
  final TeamScoutingBundle bundle;

  const _GraphTabBody({required this.bundle});

  @override
  State<_GraphTabBody> createState() => _GraphTabBodyState();
}

class _GraphTabBodyState extends State<_GraphTabBody> {
  @override
  Widget build(BuildContext context) {
    if (!widget.bundle.hasMatchData) {
      return const Center(child: Text('No match data recorded for this team.'));
    }

    final bundle = widget.bundle;
    final matchDocs = bundle.matchDocs;
    final avgAutoFuel = bundle.avgMatchField(kSectionAuto, kAutoFuelScored);
    final avgTeleFuel = bundle.avgMatchField(kSectionTele, kTeleFuelScored);
    final totalAvgFuel = avgAutoFuel + avgTeleFuel;

    double maxDataY = 0;
    for (final doc in bundle.matchDocs) {
      final total =
          _scaledMatchField(doc, kSectionTele, kTeleFuelScored) +
          _scaledMatchField(doc, kSectionAuto, kAutoFuelScored);
      if (total > maxDataY) {
        maxDataY = total;
      }
    }

    final sortedMatchDocs = [...matchDocs]
      ..sort((a, b) {
        final ma = TeamScoutingBundle.matchNumber(a.raw);
        final mb = TeamScoutingBundle.matchNumber(b.raw);
        if (ma == null && mb == null) return 0;
        if (ma == null) return 1;
        if (mb == null) return -1;
        return ma.compareTo(mb);
      });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fuel trend',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _GraphMetric(
                      label: 'Auto',
                      value: avgAutoFuel.toStringAsFixed(1),
                    ),
                    _GraphMetric(
                      label: 'Tele',
                      value: avgTeleFuel.toStringAsFixed(1),
                    ),
                    _GraphMetric(
                      label: 'Total',
                      value: totalAvgFuel.toStringAsFixed(1),
                      emphasize: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: SfCartesianChart(
              margin: EdgeInsets.zero,
              plotAreaBorderWidth: 0,
              primaryXAxis: const CategoryAxis(
                labelPlacement: LabelPlacement.onTicks,
                title: AxisTitle(text: 'Match #'),
                edgeLabelPlacement: EdgeLabelPlacement.shift,
              ),
              primaryYAxis: NumericAxis(
                title: AxisTitle(text: 'Fuel scored'),
                majorGridLines: const MajorGridLines(width: 0),
              ),
              legend: Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                overflowMode: LegendItemOverflowMode.wrap,
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: _buildLineSeries(context, sortedMatchDocs),
            ),
          ),
        ),
      ],
    );
  }
}

class _GraphMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _GraphMetric({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = emphasize
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
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
                  TeamScoutingBundle.getMatchField(
                    doc.raw,
                    kSectionTele,
                    kTeleStoppedWorking,
                  ) ||
                  TeamScoutingBundle.getMatchField(
                    doc.raw,
                    kSectionTele,
                    kTeleLostComms,
                  );
              final bool playedDefense =
                  TeamScoutingBundle.getMatchField(
                    doc.raw,
                    kSectionEndgame,
                    kEndPlayedDefenseOffShift,
                  ) ||
                  TeamScoutingBundle.getMatchField(
                    doc.raw,
                    kSectionEndgame,
                    kEndPlayedDefenseOnShift,
                  );
              final bool noShow = TeamScoutingBundle.getMatchField(
                doc.raw,
                kSectionEndgame,
                kEndNoShow,
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
