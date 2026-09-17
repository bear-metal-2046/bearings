import 'package:beariscope/models/honeycomb_enriched_event.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';

/// Honeycomb Nexus snapshot for the selected TBA event (`/events?event=&enrich=true`).
final enrichedCurrentEventProvider =
    FutureProvider<HoneycombEnrichedEvent?>((ref) async {
  final currentEventKey = ref.watch(currentEventProvider);
  final client = ref.watch(honeycombClientProvider);

  try {
    final response = await client.get<dynamic>(
      '/events',
      queryParams: {'event': currentEventKey, 'enrich': 'true'},
      cachePolicy: CachePolicy.networkFirst,
    );

    if (response is! Map) return null;
    return HoneycombEnrichedEvent.fromHoneycombJson(
      Map<String, dynamic>.from(response),
    );
  } catch (_) {
    return null;
  }
});
