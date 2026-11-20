import 'package:core/core.dart' show ScoutingReport;
import 'package:beariscope/models/match_field_ids.dart';

class ProcessedScoutingDoc {
  final ScoutingReport raw;
  final double autoFuelScalar;
  final double teleFuelScalar;
  final double? autoFuelAccuracy;
  final double? teleFuelAccuracy;
  final int autoHumanPlayerScore;
  final int teleHumanPlayerScore;

  const ProcessedScoutingDoc({
    required this.raw,
    this.autoFuelScalar = 1.0,
    this.teleFuelScalar = 1.0,
    this.autoFuelAccuracy,
    this.teleFuelAccuracy,
    this.autoHumanPlayerScore = 0,
    this.teleHumanPlayerScore = 0,
  });

  int get totalHumanPlayerScore => autoHumanPlayerScore + teleHumanPlayerScore;

  double? accuracyForSection(String sectionId) {
    switch (sectionId) {
      case kSectionAuto:
        return autoFuelAccuracy;
      case kSectionTele:
        return teleFuelAccuracy;
      default:
        return null;
    }
  }

  bool get isScaled =>
      (autoFuelScalar - 1.0).abs() > 0.01 ||
      (teleFuelScalar - 1.0).abs() > 0.01;
}
