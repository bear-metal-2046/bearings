part of 'competition_entities.dart';

@GroveValue()
class AwardRecipient {
  const AwardRecipient({this.team, this.person});

  final EntityRef<CompetitionTeam>? team;
  final String? person;
}

@GroveEntity('award', version: 1, serverManaged: true)
class EventAward {
  const EventAward({
    required this.id,
    required this.season,
    required this.event,
    required this.type,
    required this.name,
    this.recipients = const [],
  });

  final String id;
  final int season;
  final EntityRef<CompetitionEvent> event;
  final int type;
  final String name;
  final List<AwardRecipient> recipients;
}
