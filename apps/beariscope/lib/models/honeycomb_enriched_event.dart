import 'package:beariscope/models/match_nexus_info.dart';
import 'package:core/core.dart';

/// Honeycomb `GET /events?event=…&enrich=true` — TBA event plus Nexus live snapshot.
class HoneycombEnrichedEvent {
  final UpNextEventContext? context;
  final List<MatchNexusInfo> nexusMatches;

  const HoneycombEnrichedEvent({
    required this.context,
    required this.nexusMatches,
  });

  static HoneycombEnrichedEvent? fromNexusStatus(NexusEventStatus status) {
    final nexusMatches = status.matches
        .map((match) => MatchNexusInfo.fromNexusMap(match.toJson()))
        .whereType<MatchNexusInfo>()
        .toList();
    final context = UpNextEventContext.fromNexusStatus(status);

    if (context == null && nexusMatches.isEmpty) return null;

    return HoneycombEnrichedEvent(context: context, nexusMatches: nexusMatches);
  }
}
