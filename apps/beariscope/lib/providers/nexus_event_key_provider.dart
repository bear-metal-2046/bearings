import 'package:beariscope/providers/current_event_provider.dart';
import 'package:core/core.dart' show nexusEventKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/competition_provider.dart';

/// Resolves the current TBA event key to the key Nexus uses for official events.
final nexusEventKeyProvider = Provider<AsyncValue<String?>>((ref) {
  final key = ref.watch(currentEventProvider);
  if (key.length < 4) return const AsyncData(null);
  return ref
      .watch(competitionEventProvider(key))
      .whenData((event) => nexusEventKey(key, event?.firstEventCode));
});
