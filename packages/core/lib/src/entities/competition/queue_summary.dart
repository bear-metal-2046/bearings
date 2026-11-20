part of 'competition_entities.dart';

@GroveValue()
class QueueMatchSummary {
  const QueueMatchSummary({
    required this.label,
    required this.status,
    required this.played,
    this.estimatedQueueAt,
    this.estimatedStartAt,
  });

  final String label;
  final String status;
  final bool played;
  final DateTime? estimatedQueueAt;
  final DateTime? estimatedStartAt;
}

@GroveEntity('event_queue_summary', version: 1, serverManaged: true)
class EventQueueSummary {
  const EventQueueSummary({
    required this.id,
    required this.season,
    required this.event,
    this.dataAsOf,
    this.nowQueueing,
    this.nowQueueingName,
    this.matches = const {},
    this.pitMap,
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final DateTime? dataAsOf;
  final EntityRef<CompetitionMatch>? nowQueueing;
  final String? nowQueueingName;
  final Map<String, QueueMatchSummary> matches;
  final PitMap? pitMap;
}
