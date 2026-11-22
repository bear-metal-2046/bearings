import 'analysis.dart';
import 'graph.dart';
import 'value.dart';

/// Verify that a view can resolve its output from the app's scope.
GamePackType validateGamePackViewOutput(
  GamePackAnalysis analysis,
  GameGraphOutputRef output,
  String label, {
  GamePackGrain? scope,
}) {
  final info = analysis.resultInfo(output);
  if (info.grain case final grain?
      when scope != null && !scope.canRead(grain)) {
    throw FormatException(
      '$label requires ${grain.label.toLowerCase()} context.',
    );
  }
  return info.type;
}
