/// Thresholds for accuracy coloring in exports.
/// Values represent deviation percentages (0.0-1.0) where:
/// - Below [good]: no color (accurate)
/// - [good] to [warning]: yellow (slight deviation)
/// - [warning] to [bad]: orange (moderate deviation)
/// - Above [bad]: red (significant deviation)
class ColorThresholds {
  final double good;
  final double warning;
  final double bad;

  const ColorThresholds({
    this.good = 0.10,
    this.warning = 0.20,
    this.bad = 0.30,
  });

  static const defaults = ColorThresholds();

  ColorThresholds copyWith({double? good, double? warning, double? bad}) {
    return ColorThresholds(
      good: good ?? this.good,
      warning: warning ?? this.warning,
      bad: bad ?? this.bad,
    );
  }
}

/// Thresholds for when to apply auto-correction scaling.
/// When scouted values deviate from TBA ground truth beyond these thresholds,
/// scaling factors are applied to normalize the data.
class CorrectionThresholds {
  /// Minimum deviation (0.0-1.0) before correction is applied.
  final double minDeviation;

  /// Maximum scalar multiplier allowed (e.g., 2.0 = at most 2x scaling).
  final double maxScalar;

  const CorrectionThresholds({this.minDeviation = 0.05, this.maxScalar = 2.0});

  static const defaults = CorrectionThresholds();

  CorrectionThresholds copyWith({double? minDeviation, double? maxScalar}) {
    return CorrectionThresholds(
      minDeviation: minDeviation ?? this.minDeviation,
      maxScalar: maxScalar ?? this.maxScalar,
    );
  }
}

/// Configuration for which worksheet types to include in the export.
class ExportSheets {
  final bool rawMatch;
  final bool processedMatch;
  final bool pitsRaw;
  final bool stratRaw;
  final bool stratZScore;
  final bool correctionTodoList;

  const ExportSheets({
    this.rawMatch = true,
    this.processedMatch = false,
    this.pitsRaw = false,
    this.stratRaw = false,
    this.stratZScore = false,
    this.correctionTodoList = false,
  });

  bool get hasAny =>
      rawMatch ||
      processedMatch ||
      pitsRaw ||
      stratRaw ||
      stratZScore ||
      correctionTodoList;

  bool get hasMatchData => rawMatch || processedMatch;

  bool get hasStratData => stratRaw || stratZScore;

  bool get hasPitsData => pitsRaw;

  ExportSheets copyWith({
    bool? rawMatch,
    bool? processedMatch,
    bool? pitsRaw,
    bool? stratRaw,
    bool? stratZScore,
    bool? correctionTodoList,
  }) {
    return ExportSheets(
      rawMatch: rawMatch ?? this.rawMatch,
      processedMatch: processedMatch ?? this.processedMatch,
      pitsRaw: pitsRaw ?? this.pitsRaw,
      stratRaw: stratRaw ?? this.stratRaw,
      stratZScore: stratZScore ?? this.stratZScore,
      correctionTodoList: correctionTodoList ?? this.correctionTodoList,
    );
  }
}

class ExportOptions {
  final int? matchFrom;
  final int? matchTo;
  final Set<int>? teamFilter;
  final bool includeNotes;
  final bool colorCodeAccuracy;
  final bool anonymizeScouters;
  final ExportSheets sheets;
  final ColorThresholds colorThresholds;
  final CorrectionThresholds correctionThresholds;
  final double incorrectDataThreshold;

  const ExportOptions({
    this.matchFrom,
    this.matchTo,
    this.teamFilter,
    this.includeNotes = true,
    this.colorCodeAccuracy = false,
    this.anonymizeScouters = false,
    this.sheets = const ExportSheets(),
    this.colorThresholds = const ColorThresholds(),
    this.correctionThresholds = const CorrectionThresholds(),
    this.incorrectDataThreshold = 0.20,
  });

  ExportOptions copyWith({
    int? matchFrom,
    int? matchTo,
    Set<int>? teamFilter,
    bool? includeNotes,
    bool? colorCodeAccuracy,
    bool? anonymizeScouters,
    ExportSheets? sheets,
    ColorThresholds? colorThresholds,
    CorrectionThresholds? correctionThresholds,
    double? incorrectDataThreshold,
  }) {
    return ExportOptions(
      matchFrom: matchFrom ?? this.matchFrom,
      matchTo: matchTo ?? this.matchTo,
      teamFilter: teamFilter ?? this.teamFilter,
      includeNotes: includeNotes ?? this.includeNotes,
      colorCodeAccuracy: colorCodeAccuracy ?? this.colorCodeAccuracy,
      anonymizeScouters: anonymizeScouters ?? this.anonymizeScouters,
      sheets: sheets ?? this.sheets,
      colorThresholds: colorThresholds ?? this.colorThresholds,
      correctionThresholds: correctionThresholds ?? this.correctionThresholds,
      incorrectDataThreshold:
          incorrectDataThreshold ?? this.incorrectDataThreshold,
    );
  }
}
