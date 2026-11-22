import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_spinner.dart';

import 'gamepack_displays.dart';

typedef GamePackCardRank = ({
  int rank,
  int? rankingPoints,
  double? rankingScore,
});
typedef GamePackCardRange = ({double min, double max});
typedef GamePackCardOutput = GamePackValue Function(GameGraphOutputRef);

/// The same card content is rendered by the builder preview and live screens.
class GamePackTeamCardContent extends StatelessWidget {
  const GamePackTeamCardContent({
    super.key,
    required this.layout,
    required this.output,
    this.rank,
    this.sharedRange,
  });

  final GamePackTeamCardLayout layout;
  final GamePackCardOutput output;
  final GamePackCardRank? rank;
  final GamePackCardRange? Function(GamePackCardChart)? sharedRange;

  @override
  Widget build(BuildContext context) {
    final expanded = layout.kind == GamePackTeamCardKind.details;
    final sections = <Widget>[];
    for (final section in layout.sections) {
      final blocks = <Widget>[];
      for (final block in section.blocks) {
        final content = _buildBlock(context, block, expanded);
        if (content == null) continue;
        blocks.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              if (block.title case final title?)
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              content,
            ],
          ),
        );
      }
      if (blocks.isEmpty) continue;
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          if (section.title case final title?)
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ...blocks,
        ],
      );
      sections.add(
        expanded && section.title != null
            ? Card.outlined(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: content,
                ),
              )
            : content,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: expanded ? 12 : 8,
      children: sections,
    );
  }

  Widget? _buildBlock(
    BuildContext context,
    GamePackCardBlock block,
    bool expanded,
  ) {
    final theme = Theme.of(context);
    if (block.table case final table?) {
      final value = output(table.output);
      final rows = value.data;
      if (rows is! List<GamePackValue> || rows.isEmpty)
        return const Text('No rows yet');
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: [
            for (final label in table.columns.values)
              DataColumn(label: Text(label)),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  for (final path in table.columns.keys)
                    DataCell(Text(formatGamePackValue(row.atPath(path)))),
                ],
              ),
          ],
        ),
      );
    }
    if (block.kind == GamePackCardBlockKind.trend) {
      final chart = block.chart!;
      final points = _points(output(chart.output), chart);
      if (points.length < chart.minimumPoints) return null;
      return _TrendChart(
        chart: chart,
        points: points,
        expanded: expanded,
        range: chart.sharedScale ? sharedRange?.call(chart) : null,
      );
    }
    if (block.kind == GamePackCardBlockKind.eventRank) {
      final record = rank;
      if (record == null) return null;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '#${record.rank}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (record.rankingPoints != null && record.rankingScore != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${record.rankingPoints} RP · ${record.rankingScore!.toStringAsFixed(2)} RS',
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      );
    }
    final values = [
      for (final metric in block.metrics)
        if (_format(metric, output(metric.output)) case final text?)
          (metric, text),
    ];
    if (values.isEmpty) return null;

    return switch (block.kind) {
      GamePackCardBlockKind.chips => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final (metric, text) in values)
            Chip(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              label: Text(metric.onlyWhenTrue ? metric.label : text),
              side: BorderSide(color: _tone(theme.colorScheme, metric.tone)),
            ),
        ],
      ),
      GamePackCardBlockKind.text => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${values.single.$1.label} ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: values.single.$2),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      GamePackCardBlockKind.metrics when expanded => Column(
        spacing: 6,
        children: [
          for (final (metric, text) in values)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(metric.label)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.end,
                    style: _metricStyle(theme, metric),
                  ),
                ),
              ],
            ),
        ],
      ),
      GamePackCardBlockKind.metrics => Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final (metric, text) in values)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric.label, style: theme.textTheme.labelSmall),
                Text(text, style: _metricStyle(theme, metric)),
              ],
            ),
        ],
      ),
      _ => throw StateError('Unexpected card block ${block.kind.name}'),
    };
  }
}

TextStyle? _metricStyle(ThemeData theme, GamePackCardMetric metric) =>
    theme.textTheme.bodyMedium?.copyWith(
      color: _tone(theme.colorScheme, metric.tone),
      fontWeight: metric.tone == GamePackCardTone.neutral
          ? FontWeight.w500
          : FontWeight.w700,
    );

String? _format(GamePackCardMetric metric, GamePackValue value) {
  if (metric.onlyWhenTrue && value.data != true) return null;
  if (!value.isKnown ||
      (value.data is String && (value.data as String).trim().isEmpty)) {
    return switch (metric.missing) {
      GamePackCardMissing.hide => null,
      GamePackCardMissing.dash => '—',
      GamePackCardMissing.showState =>
        value.isKnown ? 'Missing' : formatGamePackValue(value),
    };
  }
  final data = value.data;
  final text = switch (data) {
    final num number when metric.decimals != null => number.toStringAsFixed(
      metric.decimals!,
    ),
    true => 'Yes',
    false => 'No',
    _ => formatGamePackValue(value),
  };
  final suffix =
      metric.suffix.isEmpty &&
          gamePackRollupOf(metric.output.output)?.rollup ==
              GamePackRollup.yesPercent
      ? '%'
      : metric.suffix;
  return '${metric.prefix}$text$suffix';
}

typedef _TrendPoint = ({String label, GamePackValue record});

List<_TrendPoint> _points(GamePackValue value, GamePackCardChart chart) => [
  if (value.data case final List<GamePackValue> records)
    for (final row in records)
      if (row.atPath(chart.x).isKnown &&
          chart.series.any((line) => row.atPath(line.field).data is num))
        (label: formatGamePackValue(row.atPath(chart.x)), record: row),
];

GamePackCardRange? _range(
  Iterable<_TrendPoint> points,
  GamePackCardChart chart,
) {
  double? low;
  double? high;
  for (final point in points) {
    for (final series in chart.series) {
      if (point.record.atPath(series.field).data case final num value) {
        low = math.min(low ?? 0, value.toDouble());
        high = math.max(high ?? 0, value.toDouble());
      }
    }
  }
  return low == null ? null : (min: low, max: high!);
}

GamePackCardRange? gamePackCardChartRange(
  GamePackCardChart chart,
  Iterable<GamePackValue> rows,
) => _range(rows.expand((row) => _points(row, chart)), chart);

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.chart,
    required this.points,
    required this.expanded,
    this.range,
  });
  final GamePackCardChart chart;
  final List<_TrendPoint> points;
  final bool expanded;
  final GamePackCardRange? range;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bounds = range ?? _range(points, chart)!;
    final padding = math.max(
      1.0,
      (bounds.max - bounds.min) * (chart.markers.isEmpty ? .08 : .2),
    );
    final marks = <CartesianChartAnnotation>[];
    for (final (index, point) in points.indexed) {
      final items = chart.markers
          .where((marker) => point.record.atPath(marker.field).data == true)
          .toList();
      if (items.isEmpty) continue;
      final top = chart.series
          .map((series) => point.record.atPath(series.field).data)
          .whereType<num>()
          .reduce(math.max);
      marks.add(
        CartesianChartAnnotation(
          coordinateUnit: CoordinateUnit.point,
          region: AnnotationRegion.plotArea,
          x: index + 1,
          y: top + padding * .45,
          widget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final marker in items)
                Tooltip(
                  message: marker.label,
                  child: Icon(
                    _markerIcon(marker.icon),
                    size: 14,
                    color: _tone(colors, marker.tone),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: expanded ? 220 : 158,
      child: SfCartesianChart(
        margin: EdgeInsets.zero,
        plotAreaBorderWidth: 0,
        legend: Legend(
          isVisible: chart.series.length > 1,
          position: LegendPosition.bottom,
          overflowMode: LegendItemOverflowMode.wrap,
        ),
        tooltipBehavior: TooltipBehavior(enable: true),
        primaryXAxis: NumericAxis(
          minimum: 0,
          maximum: points.length + 1.0,
          interval: math
              .max(1, (points.length / (expanded ? 8 : 5)).ceil())
              .toDouble(),
          majorGridLines: const MajorGridLines(width: 0),
          axisLabelFormatter: (details) {
            final index = details.value.toInt() - 1;
            return ChartAxisLabel(
              index < 0 || index >= points.length ? '' : points[index].label,
              details.textStyle,
            );
          },
        ),
        primaryYAxis: NumericAxis(
          minimum: bounds.min,
          maximum: bounds.max + padding,
        ),
        annotations: marks,
        series: [
          for (final line in chart.series)
            LineSeries<_TrendPoint, num>(
              name: line.label,
              color: _tone(colors, line.tone),
              dataSource: points,
              xValueMapper: (_, i) => i + 1,
              yValueMapper: (point, _) =>
                  point.record.atPath(line.field).data as num?,
              animationDuration: 0,
              markerSettings: const MarkerSettings(
                isVisible: true,
                width: 5,
                height: 5,
              ),
            ),
        ],
      ),
    );
  }
}

Color _tone(ColorScheme colors, GamePackCardTone tone) => switch (tone) {
  GamePackCardTone.neutral => colors.onSurface,
  GamePackCardTone.accent => colors.primary,
  GamePackCardTone.info =>
    colors.brightness == Brightness.dark
        ? Colors.lightBlueAccent
        : Colors.blue.shade800,
  GamePackCardTone.positive =>
    colors.brightness == Brightness.dark
        ? Colors.greenAccent
        : Colors.green.shade800,
  GamePackCardTone.warning =>
    colors.brightness == Brightness.dark
        ? Colors.amberAccent
        : Colors.brown.shade700,
  GamePackCardTone.danger => colors.error,
};

IconData _markerIcon(GamePackCardMarkerIcon icon) => switch (icon) {
  GamePackCardMarkerIcon.alert => LucideIcons.triangleAlert,
  GamePackCardMarkerIcon.breakdown => LucideIcons.boneFracture,
  GamePackCardMarkerIcon.defense => LucideIcons.shield,
  GamePackCardMarkerIcon.absent => LucideIcons.mapPinXInside,
  GamePackCardMarkerIcon.star => LucideIcons.star,
  GamePackCardMarkerIcon.flag => LucideIcons.flag,
};

/// Cache graph results and comparison ranges for the lifespan of a live input
/// snapshot. A new Grove snapshot or release gets a fresh cache.
final _cardCaches = Expando<_CardCache>();

class _CardCache {
  _CardCache(this.analysis);
  final GamePackEventAnalysis analysis;
  final _values = <(String, GameGraphOutputRef), GamePackValue>{};
  final _scales =
      <(GamePackCardChart, List<CompetitionTeam>), GamePackCardRange?>{};

  GamePackValue value(String team, GameGraphOutputRef output) =>
      _values.putIfAbsent((team, output), () {
        try {
          return analysis
              .evaluate(
                output,
                scope: GamePackScope(event: analysis.event, team: team),
              )
              .result;
        } on GameGraphLimitExceeded {
          return GamePackValue.unknown;
        }
      });

  GamePackCardRange? shared(
    GamePackCardChart chart,
    List<CompetitionTeam> roster,
  ) => _scales.putIfAbsent(
    (chart, roster),
    () => _range(
      roster.expand((team) => _points(value(team.id, chart.output), chart)),
      chart,
    ),
  );
}

GamePackCardRank? gamePackEventRank(List<EventRanking>? rankings, String team) {
  final record = rankings
      ?.where((entry) => entry.team.id == team)
      .firstOrNull
      ?.result;
  if (record == null) return null;
  final score = record.sortOrders.firstOrNull;
  final matches = record.matchesPlayed;
  return (
    rank: record.rank,
    rankingPoints: score == null || matches == null
        ? null
        : (score * matches).round(),
    rankingScore: score,
  );
}

class GamePackTeamCardStatistics extends ConsumerWidget {
  const GamePackTeamCardStatistics({
    super.key,
    required this.event,
    required this.team,
    required this.kind,
    required this.fallback,
    this.scrollable = false,
  });

  final String event;
  final String team;
  final GamePackTeamCardKind kind;
  final Widget fallback;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(gamePackEventAnalysisProvider(event));
    final analysis = latest.value;
    if (latest.hasError && analysis == null) {
      return const Text('Scouting metrics unavailable');
    }
    if (analysis == null) {
      return scrollable && latest.isLoading
          ? const Center(child: BearingsSpinner())
          : fallback;
    }
    final layout = analysis.analysis.definition.teamCards
        .where((card) => card.kind == kind)
        .firstOrNull;
    if (layout == null) return fallback;
    final blocks = layout.sections.expand((section) => section.blocks);
    final roster = blocks.any((block) => block.chart?.sharedScale == true)
        ? ref.watch(competitionTeamsProvider(event)).value?.items
        : null;
    final rank =
        blocks.any((block) => block.kind == GamePackCardBlockKind.eventRank)
        ? gamePackEventRank(
            ref.watch(competitionRankingsProvider(event)).value,
            team,
          )
        : null;
    final cache = _cardCaches[analysis] ??= _CardCache(analysis);
    final content = GamePackTeamCardContent(
      layout: layout,
      output: (output) => cache.value(team, output),
      rank: rank,
      sharedRange: roster == null
          ? null
          : (chart) => cache.shared(chart, roster),
    );
    return scrollable
        ? BearingsCardList(
            children: [
              if (analysis.offline)
                const ListTile(
                  leading: Icon(LucideIcons.cloudOff),
                  title: Text('Showing cached results'),
                ),
              content,
            ],
          )
        : content;
  }
}
