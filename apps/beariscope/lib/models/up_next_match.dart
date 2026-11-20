import 'package:core/core.dart';
import 'package:services/services.dart';

const bearMetalTeamKey = 'frc2046';

class UpNextMatch {
  final UpNextFeedMatch match;

  QueueMatch? get nexus => match.nexus;

  /// Double-elimination bracket details, for playoff matches at events that
  /// use that bracket.
  final DoubleEliminationMatch? bracket;
  final int? redAllianceNumber;
  final int? blueAllianceNumber;

  /// Set when Bear Metal is not in this match yet but would be with this
  /// result.
  final PlayoffOutcome? possibleOutcome;

  const UpNextMatch({
    required this.match,
    this.bracket,
    this.redAllianceNumber,
    this.blueAllianceNumber,
    this.possibleOutcome,
  });

  String get key => match.key;

  String get displayName => switch (match.level) {
    'qm' => 'Qualification Match ${match.matchNumber}',
    'sf' => 'Semifinal Match ${match.setNumber}',
    'f' => 'Final Match ${match.matchNumber}',
    '' => key,
    final level => '$level ${match.matchNumber}',
  };

  /// The Nexus label, such as "Playoff 5", or a name built from the match key.
  String get title {
    final label = nexus?.label;
    if (label != null) return label;
    if (bracket != null) return 'Playoff ${bracket!.number}';
    return displayName;
  }

  String? get queueStatus => nexus?.status;

  List<String> get redTeamKeys => match.redTeamKeys;

  List<String> get blueTeamKeys => match.blueTeamKeys;

  bool get includes2046 =>
      redTeamKeys.contains(bearMetalTeamKey) ||
      blueTeamKeys.contains(bearMetalTeamKey);

  DateTime? get displayTime {
    final times = nexus?.times;
    final nexusTime =
        times?.estimatedQueueTime ??
        times?.actualQueueTime ??
        times?.estimatedStartTime ??
        times?.estimatedOnDeckTime;
    if (isActiveQueueStatus(queueStatus) && nexusTime != null) {
      return nexusTime.toLocal();
    }
    return (match.predictedAt ?? nexusTime)?.toLocal();
  }
}

const activeNexusQueueStatuses = {
  'Queuing soon',
  'Now queuing',
  'On deck',
  'On field',
};

bool isActiveQueueStatus(String? status) {
  if (status == null) return false;
  return activeNexusQueueStatuses.contains(status);
}
