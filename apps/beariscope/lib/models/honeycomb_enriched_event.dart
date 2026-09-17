import 'package:beariscope/models/match_nexus_info.dart';

/// Honeycomb `GET /events?event=…&enrich=true` — TBA event plus Nexus live snapshot.
class HoneycombEnrichedEvent {
  final UpNextEventContext? context;
  final List<MatchNexusInfo> nexusMatches;

  const HoneycombEnrichedEvent({
    required this.context,
    required this.nexusMatches,
  });

  static HoneycombEnrichedEvent? fromHoneycombJson(Map<String, dynamic> json) {
    final nexusMatches = _parseNexusMatches(json['matches']);
    final context = UpNextEventContext.fromEventJson(json);

    if (context == null && nexusMatches.isEmpty) return null;

    return HoneycombEnrichedEvent(
      context: context,
      nexusMatches: nexusMatches,
    );
  }
}

List<MatchNexusInfo> _parseNexusMatches(Object? value) {
  if (value is! List) return const [];

  return value
      .whereType<Map>()
      .map((raw) => MatchNexusInfo.fromNexusMap(Map<String, dynamic>.from(raw)))
      .whereType<MatchNexusInfo>()
      .toList();
}
