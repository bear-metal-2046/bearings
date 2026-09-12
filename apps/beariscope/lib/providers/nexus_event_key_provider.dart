import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolves the current TBA event key to the Nexus-normalized [EventOption.firstKey].
final nexusEventKeyProvider = FutureProvider<String?>((ref) async {
  final tbaEventKey = ref.watch(currentEventProvider);
  final allEvents = await ref.watch(teamEventsProvider.future);

  for (final event in allEvents) {
    if (event.key == tbaEventKey) {
      return event.firstKey;
    }
  }

  return null;
});
