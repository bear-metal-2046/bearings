import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/grove_provider.dart';

const _nexusFreshness = Duration(minutes: 2);

/// The outcome of asking Honeycomb for an event's Nexus data.
sealed class NexusFetchResult {
  const NexusFetchResult();

  /// Why there is no usable Nexus data, or null when Nexus data is available.
  String? get problem;
}

final class NexusAvailable extends NexusFetchResult {
  const NexusAvailable(this.status);

  final EventStatusSnapshot status;

  @override
  String? get problem => null;
}

final class NexusEmpty extends NexusFetchResult {
  const NexusEmpty([this.status]);

  final EventStatusSnapshot? status;

  @override
  String get problem => 'The server returned no Nexus data for this event';
}

final class NexusFailed extends NexusFetchResult {
  const NexusFailed(this.message);

  final String message;

  @override
  String get problem => message;
}

/// Observe the direct Nexus feed for a TBA event. Re-evaluate locally when the
/// snapshot ages out so Up Next falls back even if Grove has gone quiet.
final nexusEventStatusProvider = Provider.autoDispose
    .family<AsyncValue<NexusFetchResult>, String>((ref, eventKey) {
      final event = ref.watch(competitionEventProvider(eventKey));
      // Offseason and demo events can be addressed by their Nexus key.
      final metadata = event.when(
        data: AsyncData<CompetitionEvent?>.new,
        error: (error, stack) => error is GroveException
            ? const AsyncData<CompetitionEvent?>(null)
            : AsyncError<CompetitionEvent?>(error, stack),
        loading: AsyncLoading<CompetitionEvent?>.new,
      );
      final status = metadata.flatMap((event) {
        final key = nexusEventKey(eventKey, event?.firstEventCode);
        final grove = ref.watch(bearingsGroveProvider);
        final query = grove.query<EventStatusSnapshot>().byId(key);
        return ref.watch(groveQueryProvider(query)).whenData((result) {
          final snapshot = result.requireAvailable().items.singleOrNull;
          if (snapshot == null) return const NexusEmpty();
          final remaining = snapshot.dataAsOfTime
              .add(_nexusFreshness)
              .difference(DateTime.now());
          if (remaining <= Duration.zero) {
            return const NexusFailed('Nexus event status is stale');
          }
          final timer = Timer(remaining, ref.invalidateSelf);
          ref.onDispose(timer.cancel);
          return snapshot.hasData
              ? NexusAvailable(snapshot)
              : NexusEmpty(snapshot);
        });
      });
      return status.when(
        data: AsyncData<NexusFetchResult>.new,
        error: (error, _) =>
            AsyncData(NexusFailed('Could not load Nexus data: $error')),
        loading: AsyncLoading<NexusFetchResult>.new,
      );
    });

Future<void> refreshNexusStatus(
  ProviderContainer container,
  String eventKey,
) async {
  final event = container.read(competitionEventProvider(eventKey)).value;
  final key = nexusEventKey(eventKey, event?.firstEventCode);
  final grove = container.read(bearingsGroveProvider);
  await grove.query<EventStatusSnapshot>().byId(key).result();
}
