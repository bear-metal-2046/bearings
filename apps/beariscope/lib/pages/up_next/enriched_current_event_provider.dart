import 'package:beariscope/models/honeycomb_enriched_event.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/services.dart';

/// Honeycomb Nexus snapshot for the selected TBA event (`/events?event=&enrich=true`).
///
/// Shares [nexusEventStatusProvider] with Up Next, so it polls the same request
/// and its failures are logged there. Mapping the [AsyncValue] directly keeps
/// polls as refreshes, so watchers keep showing the previous data meanwhile.
final enrichedCurrentEventProvider =
    Provider.autoDispose<AsyncValue<HoneycombEnrichedEvent?>>((ref) {
      final currentEventKey = ref.watch(currentEventProvider);
      return ref
          .watch(nexusEventStatusProvider(currentEventKey))
          .whenData(
            (result) => switch (result) {
              NexusAvailable(:final status) =>
                HoneycombEnrichedEvent.fromNexusStatus(status),
              _ => null,
            },
          );
    });
