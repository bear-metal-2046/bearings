import 'package:beariscope/models/nexus_live_status.dart';
import 'package:beariscope/providers/nexus_event_key_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';

final nexusLiveProvider = FutureProvider<NexusLiveStatus?>((ref) async {
  final eventKey = await ref.watch(nexusEventKeyProvider.future);
  if (eventKey == null || eventKey.isEmpty) return null;

  try {
    final client = ref.watch(honeycombClientProvider);
    final response = await client.get<Map<String, dynamic>>(
      '/nexus/live',
      queryParams: {'event': eventKey},
      cachePolicy: CachePolicy.networkFirst,
    );

    return NexusLiveStatus.fromJson(response);
  } catch (_) {
    return null;
  }
});
