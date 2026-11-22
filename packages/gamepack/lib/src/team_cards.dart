import 'analysis.dart';
import 'forms.dart';
import 'graph.dart';
import 'value.dart';
import 'views.dart';

enum GamePackTeamCardKind {
  compact('Team Card'),
  details('Team Details');

  const GamePackTeamCardKind(this.label);
  final String label;
}

enum GamePackCardBlockKind {
  metrics('Metric row'),
  chips('Chips'),
  text('Text summary'),
  trend('Trend chart'),
  table('Table'),
  eventRank('Official event rank');

  const GamePackCardBlockKind(this.label);
  final String label;
}

enum GamePackCardTone { neutral, accent, info, positive, warning, danger }

enum GamePackCardMissing { dash, hide, showState }

enum GamePackCardMarkerIcon { alert, breakdown, defense, absent, star, flag }

class GamePackTeamCardLayout {
  GamePackTeamCardLayout({
    required this.kind,
    required List<GamePackCardSection> sections,
  }) : sections = List.unmodifiable(sections);

  final GamePackTeamCardKind kind;
  final List<GamePackCardSection> sections;

  factory GamePackTeamCardLayout.fromJson(Map<String, dynamic> json) =>
      GamePackTeamCardLayout(
        kind: GamePackTeamCardKind.values.byName(json['kind'] as String),
        sections: _read(json['sections'], GamePackCardSection.fromJson),
      );

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'sections': sections.map((section) => section.toJson()).toList(),
  };

  void validate(GamePackAnalysis analysis) {
    if (sections.isEmpty ||
        sections.length > 12 ||
        (kind == GamePackTeamCardKind.compact && sections.length != 1)) {
      throw FormatException('${kind.label} has an invalid number of sections.');
    }
    final sectionIds = <String>{};
    for (final section in sections) {
      validateGamePackIdentifier(section.id);
      if (!sectionIds.add(section.id))
        throw FormatException('Duplicate card section: ${section.id}.');
      if (section.title case final title?) validateGamePackLabel(title);
      if (section.blocks.isEmpty || section.blocks.length > 24) {
        throw FormatException(
          'Add 1–24 blocks to ${section.title ?? kind.label}.',
        );
      }
      final ids = <String>{};
      for (final block in section.blocks) {
        if (!ids.add(block.id))
          throw FormatException('Duplicate card block: ${block.id}.');
        if (kind == GamePackTeamCardKind.compact &&
            block.kind == GamePackCardBlockKind.table) {
          throw const FormatException('Tables belong in Team Details.');
        }
        block.validate(analysis);
      }
    }
  }
}

class GamePackCardSection {
  GamePackCardSection({
    required this.id,
    this.title,
    required List<GamePackCardBlock> blocks,
  }) : blocks = List.unmodifiable(blocks);

  final String id;
  final String? title;
  final List<GamePackCardBlock> blocks;

  factory GamePackCardSection.fromJson(Map<String, dynamic> json) =>
      GamePackCardSection(
        id: json['id'] as String,
        title: json['title'] as String?,
        blocks: _read(json['blocks'], GamePackCardBlock.fromJson),
      );

  Map<String, Object> toJson() => {
    'id': id,
    if (title case final title?) 'title': title,
    'blocks': blocks.map((block) => block.toJson()).toList(),
  };
}

class GamePackCardBlock {
  GamePackCardBlock({
    required this.id,
    required this.kind,
    this.title,
    List<GamePackCardMetric> metrics = const [],
    this.chart,
    this.table,
  }) : metrics = List.unmodifiable(metrics);

  final String id;
  final GamePackCardBlockKind kind;
  final String? title;
  final List<GamePackCardMetric> metrics;
  final GamePackCardChart? chart;
  final GamePackCardTable? table;

  factory GamePackCardBlock.fromJson(Map<String, dynamic> json) =>
      GamePackCardBlock(
        id: json['id'] as String,
        kind: GamePackCardBlockKind.values.byName(json['kind'] as String),
        title: json['title'] as String?,
        metrics: _read(json['metrics'], GamePackCardMetric.fromJson),
        chart: json['chart'] == null
            ? null
            : GamePackCardChart.fromJson(json['chart'] as Map<String, dynamic>),
        table: json['table'] == null
            ? null
            : GamePackCardTable.fromJson(json['table'] as Map<String, dynamic>),
      );

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    if (title case final title?) 'title': title,
    if (metrics.isNotEmpty)
      'metrics': metrics.map((metric) => metric.toJson()).toList(),
    if (chart case final chart?) 'chart': chart.toJson(),
    if (table case final table?) 'table': table.toJson(),
  };

  void validate(GamePackAnalysis analysis) {
    validateGamePackIdentifier(id);
    if (title case final title?) validateGamePackLabel(title);
    if (kind != GamePackCardBlockKind.table && table != null)
      throw const FormatException('Tables require a table block.');
    switch (kind) {
      case GamePackCardBlockKind.table:
        if (table == null || chart != null || metrics.isNotEmpty)
          throw const FormatException('Configure the table.');
        table!.validate(analysis, title ?? kind.label);

      case GamePackCardBlockKind.eventRank:
        if (chart != null || metrics.isNotEmpty)
          throw const FormatException(
            'Official event rank uses the competition standings.',
          );
      case GamePackCardBlockKind.trend:
        if (chart == null || metrics.isNotEmpty)
          throw const FormatException('Configure the trend chart.');
        chart!.validate(analysis, title ?? kind.label);
      case GamePackCardBlockKind.metrics:
      case GamePackCardBlockKind.chips:
      case GamePackCardBlockKind.text:
        final limit = kind == GamePackCardBlockKind.text ? 1 : 12;
        if (chart != null || metrics.isEmpty || metrics.length > limit) {
          throw FormatException('${kind.label} needs 1–$limit values.');
        }
        for (final metric in metrics) {
          metric.validate(
            analysis,
            allowFlag: kind == GamePackCardBlockKind.chips,
          );
        }
    }
  }
}

class GamePackCardTable {
  GamePackCardTable({
    required this.output,
    required Map<String, String> columns,
  }) : columns = Map.unmodifiable(columns);

  final GameGraphOutputRef output;
  final Map<String, String> columns;

  factory GamePackCardTable.fromJson(Map<String, dynamic> json) =>
      GamePackCardTable(
        output: readGamePackResult(json),
        columns: (json['columns'] as Map<String, dynamic>)
            .cast<String, String>(),
      );
  Map<String, Object> toJson() => {
    ...writeGamePackResult(output),
    'columns': columns,
  };
  static bool supports(GamePackType type) =>
      GamePackCardChart.columns(type).isNotEmpty;

  void validate(GamePackAnalysis analysis, String label) {
    final type = validateGamePackViewOutput(
      analysis,
      output,
      label,
      scope: GamePackGrain.team,
    );
    final fields = GamePackCardChart.columns(type);
    if (columns.isEmpty ||
        columns.length > 12 ||
        !columns.keys.every(fields.containsKey)) {
      throw FormatException('Choose 1–12 table columns for $label.');
    }
    for (final heading in columns.values) {
      validateGamePackLabel(heading);
    }
  }
}

class GamePackCardMetric {
  const GamePackCardMetric({
    required this.label,
    required this.output,
    this.decimals,
    this.prefix = '',
    this.suffix = '',
    this.tone = GamePackCardTone.neutral,
    this.missing = GamePackCardMissing.dash,
    this.onlyWhenTrue = false,
  });

  final String label;
  final GameGraphOutputRef output;
  final int? decimals;
  final String prefix;
  final String suffix;
  final GamePackCardTone tone;
  final GamePackCardMissing missing;
  final bool onlyWhenTrue;

  factory GamePackCardMetric.fromJson(Map<String, dynamic> json) =>
      GamePackCardMetric(
        label: json['label'] as String,
        output: readGamePackResult(json),
        decimals: json['decimals'] as int?,
        prefix: json['prefix'] as String? ?? '',
        suffix: json['suffix'] as String? ?? '',
        tone: GamePackCardTone.values.byName(
          json['tone'] as String? ?? 'neutral',
        ),
        missing: GamePackCardMissing.values.byName(
          json['missing'] as String? ?? 'dash',
        ),
        onlyWhenTrue: json['onlyWhenTrue'] == true,
      );

  Map<String, Object> toJson() => {
    'label': label,
    ...writeGamePackResult(output),
    if (decimals case final decimals?) 'decimals': decimals,
    if (prefix.isNotEmpty) 'prefix': prefix,
    if (suffix.isNotEmpty) 'suffix': suffix,
    if (tone != GamePackCardTone.neutral) 'tone': tone.name,
    if (missing != GamePackCardMissing.dash) 'missing': missing.name,
    if (onlyWhenTrue) 'onlyWhenTrue': true,
  };

  static bool supports(GamePackType type) => switch (type.kind) {
    GamePackTypeKind.boolean ||
    GamePackTypeKind.integer ||
    GamePackTypeKind.number ||
    GamePackTypeKind.text => true,
    _ => false,
  };

  void validate(GamePackAnalysis analysis, {required bool allowFlag}) {
    validateGamePackLabel(label);
    final type = validateGamePackViewOutput(
      analysis,
      output,
      label,
      scope: GamePackGrain.team,
    );
    if (!supports(type))
      throw FormatException('$label needs a number, text, or yes/no output.');
    if (decimals case final digits?) {
      if (!GamePackType.number.accepts(type) || digits < 0 || digits > 6) {
        throw FormatException(
          '$label needs a numeric output and 0–6 decimal places.',
        );
      }
    }
    if (prefix.length > 24 || suffix.length > 24)
      throw FormatException('Shorten the units for $label.');
    if (onlyWhenTrue && (!allowFlag || type != GamePackType.boolean)) {
      throw FormatException(
        '$label needs a yes/no output to appear only when true.',
      );
    }
  }
}

class GamePackCardChart {
  GamePackCardChart({
    required this.output,
    required this.x,
    required List<GamePackCardSeries> series,
    List<GamePackCardMarker> markers = const [],
    this.sharedScale = false,
    this.minimumPoints = 1,
  }) : series = List.unmodifiable(series),
       markers = List.unmodifiable(markers);

  final GameGraphOutputRef output;
  final String x;
  final List<GamePackCardSeries> series;
  final List<GamePackCardMarker> markers;
  final bool sharedScale;
  final int minimumPoints;

  factory GamePackCardChart.fromJson(Map<String, dynamic> json) =>
      GamePackCardChart(
        output: readGamePackResult(json),
        x: json['x'] as String,
        series: _read(json['series'], GamePackCardSeries.fromJson),
        markers: _read(json['markers'], GamePackCardMarker.fromJson),
        sharedScale: json['sharedScale'] == true,
        minimumPoints: json['minimumPoints'] as int? ?? 1,
      );

  Map<String, Object> toJson() => {
    ...writeGamePackResult(output),
    'x': x,
    'series': series.map((line) => line.toJson()).toList(),
    if (markers.isNotEmpty)
      'markers': markers.map((marker) => marker.toJson()).toList(),
    if (sharedScale) 'sharedScale': true,
    if (minimumPoints != 1) 'minimumPoints': minimumPoints,
  };

  static Map<String, GamePackType> columns(GamePackType type) {
    if (type.kind != GamePackTypeKind.list ||
        type.element!.kind != GamePackTypeKind.record) {
      return const {};
    }
    final result = <String, GamePackType>{};
    void collect(GamePackType record, String prefix) {
      for (final entry in record.fields.entries) {
        final path = '$prefix${entry.key}';
        if (entry.value.kind == GamePackTypeKind.record) {
          collect(entry.value, '$path.');
        } else {
          result[path] = entry.value;
        }
      }
    }

    collect(type.element!, '');
    return result;
  }

  static bool supportsX(GamePackType type) =>
      type == GamePackType.text || GamePackType.number.accepts(type);

  static bool supports(GamePackType type) {
    final fields = columns(type);
    return fields.entries.any(
      (x) =>
          supportsX(x.value) &&
          fields.entries.any(
            (y) => y.key != x.key && GamePackType.number.accepts(y.value),
          ),
    );
  }

  void validate(GamePackAnalysis analysis, String label) {
    final fields = columns(
      validateGamePackViewOutput(
        analysis,
        output,
        label,
        scope: GamePackGrain.team,
      ),
    );
    final xType = fields[x];
    if (xType == null || !supportsX(xType))
      throw FormatException('$label needs a text or numeric x-axis field.');
    if (series.isEmpty ||
        series.length > 8 ||
        markers.length > 8 ||
        minimumPoints < 1 ||
        minimumPoints > 20) {
      throw FormatException(
        '$label has invalid series, markers, or minimum points.',
      );
    }
    final seriesFields = <String>{};
    for (final line in series) {
      validateGamePackLabel(line.label);
      final type = fields[line.field];
      if (type == null ||
          !GamePackType.number.accepts(type) ||
          line.field == x ||
          !seriesFields.add(line.field)) {
        throw FormatException('${line.label} needs a distinct numeric field.');
      }
    }
    final markerFields = <String>{};
    for (final marker in markers) {
      validateGamePackLabel(marker.label);
      if (fields[marker.field] != GamePackType.boolean ||
          !markerFields.add(marker.field)) {
        throw FormatException('${marker.label} needs a distinct yes/no field.');
      }
    }
  }
}

class GamePackCardSeries {
  const GamePackCardSeries({
    required this.field,
    required this.label,
    this.tone = GamePackCardTone.accent,
  });
  final String field;
  final String label;
  final GamePackCardTone tone;

  factory GamePackCardSeries.fromJson(Map<String, dynamic> json) =>
      GamePackCardSeries(
        field: json['field'] as String,
        label: json['label'] as String,
        tone: GamePackCardTone.values.byName(
          json['tone'] as String? ?? 'accent',
        ),
      );

  Map<String, Object> toJson() => {
    'field': field,
    'label': label,
    'tone': tone.name,
  };
}

class GamePackCardMarker {
  const GamePackCardMarker({
    required this.field,
    required this.label,
    this.icon = GamePackCardMarkerIcon.flag,
    this.tone = GamePackCardTone.neutral,
  });
  final String field;
  final String label;
  final GamePackCardMarkerIcon icon;
  final GamePackCardTone tone;

  factory GamePackCardMarker.fromJson(Map<String, dynamic> json) =>
      GamePackCardMarker(
        field: json['field'] as String,
        label: json['label'] as String,
        icon: GamePackCardMarkerIcon.values.byName(
          json['icon'] as String? ?? 'flag',
        ),
        tone: GamePackCardTone.values.byName(
          json['tone'] as String? ?? 'neutral',
        ),
      );

  Map<String, Object> toJson() => {
    'field': field,
    'label': label,
    'icon': icon.name,
    'tone': tone.name,
  };
}

List<T> _read<T>(Object? raw, T Function(Map<String, dynamic>) decode) =>
    (raw as List<dynamic>? ?? const [])
        .map((item) => decode(item as Map<String, dynamic>))
        .toList();
