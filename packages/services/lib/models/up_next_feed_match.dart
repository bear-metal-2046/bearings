import 'package:core/core.dart';

/// A match from the live queue or the competition schedule.
class UpNextFeedMatch {
  UpNextFeedMatch.scheduled(CompetitionMatch match)
    : key = match.id,
      schedule = match,
      nexus = null,
      _nexusRef = null;

  UpNextFeedMatch.queued(this.key, QueueMatch match, NexusMatchRef ref)
    : schedule = null,
      nexus = match,
      _nexusRef = ref;

  final String key;
  final CompetitionMatch? schedule;
  final QueueMatch? nexus;
  final NexusMatchRef? _nexusRef;

  String get level => _nexusRef?.compLevel ?? schedule!.level;
  int get matchNumber => _nexusRef?.matchNumber ?? schedule!.matchNumber;
  int get setNumber => _nexusRef?.setNumber ?? schedule!.setNumber;

  late final List<String> redTeamKeys =
      nexus?.redTeamKeys ?? _teamKeys(schedule?.red);
  late final List<String> blueTeamKeys =
      nexus?.blueTeamKeys ?? _teamKeys(schedule?.blue);

  DateTime? get predictedAt =>
      schedule?.predictedAt ??
      nexus?.times.estimatedStartTime ??
      nexus?.times.scheduledStartTime;

  static List<String> _teamKeys(CompetitionAlliance? alliance) => [
    for (final team in alliance?.teams ?? const []) team.id,
  ];
}
