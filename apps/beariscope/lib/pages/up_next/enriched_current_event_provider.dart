import 'package:beariscope/models/honeycomb_enriched_event.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';

/// Honeycomb Nexus snapshot for the selected TBA event (`/events?event=&enrich=true`).
final enrichedCurrentEventProvider = FutureProvider<HoneycombEnrichedEvent?>((
  ref,
) async {
  final currentEventKey = ref.watch(currentEventProvider);
  final client = ref.watch(honeycombClientProvider);

  try {
    final response = await client.get<dynamic>(
      '/events',
      queryParams: {'event': currentEventKey, 'enrich': 'true'},
      cachePolicy: CachePolicy.networkFirst,
    );

    final eventJson = switch (response) {
      Map() => Map<String, dynamic>.from(response),
      List() =>
        response
            .whereType<Map>()
            .map((event) => Map<String, dynamic>.from(event))
            .where(
              (event) =>
                  event['key']?.toString() == currentEventKey ||
                  event['eventKey']?.toString() == currentEventKey ||
                  event['event_key']?.toString() == currentEventKey,
            )
            .firstOrNull,
      _ => null,
    };
    if (eventJson == null) return null;
    return HoneycombEnrichedEvent.fromHoneycombJson(eventJson);
  } catch (_) {
    return null;
  }
});
