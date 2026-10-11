import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';

const nexusPollInterval = Duration(seconds: 15);

/// The outcome of asking Honeycomb for an event's Nexus data.
sealed class NexusFetchResult {
  const NexusFetchResult();

  /// Why there is no usable Nexus data, or null when Nexus data is available.
  String? get problem;
}

final class NexusAvailable extends NexusFetchResult {
  const NexusAvailable(this.status);

  final NexusEventStatus status;

  @override
  String? get problem => null;
}

final class NexusEmpty extends NexusFetchResult {
  const NexusEmpty([this.status]);

  final NexusEventStatus? status;

  @override
  String get problem => 'Honeycomb returned no Nexus data for this event';
}

final class NexusFailed extends NexusFetchResult {
  const NexusFailed(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String get problem => message;
}

/// Nexus data for a TBA event key, refetched every [nexusPollInterval] while
/// something is listening.
final nexusEventStatusProvider = FutureProvider.autoDispose
    .family<NexusFetchResult, String>(fetchNexusEventStatus);

/// The default body of [nexusEventStatusProvider], public so overrides can
/// fall back to it.
Future<NexusFetchResult> fetchNexusEventStatus(Ref ref, String eventKey) {
  final timer = Timer(nexusPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  return loadNexusEventStatus(ref.watch(honeycombClientProvider), eventKey);
}

Future<NexusFetchResult> loadNexusEventStatus(
  HoneycombClient client,
  String eventKey,
) async {
  final Object? response;
  try {
    response = await client.get<dynamic>(
      '/events',
      queryParams: {'event': eventKey, 'enrich': 'true'},
      cachePolicy: CachePolicy.networkFirst,
    );
  } on HoneycombApiException catch (error) {
    final code = error.statusCode;
    final message = code == 401 || code == 403
        ? 'Not allowed to read event data (needs external.read, HTTP $code)'
        : 'Honeycomb /events failed (HTTP $code)';
    debugPrint('Nexus: $message for $eventKey: $error');
    return NexusFailed(message, statusCode: code);
  } catch (error) {
    debugPrint('Nexus: request for $eventKey failed: $error');
    return NexusFailed('Could not load Nexus data: $error');
  }

  return parseNexusEventResponse(eventKey, response);
}

NexusFetchResult parseNexusEventResponse(String eventKey, Object? response) {
  final event = switch (response) {
    Map() => Map<String, dynamic>.from(response),
    List() =>
      response
          .whereType<Map>()
          .map((event) => Map<String, dynamic>.from(event))
          .where((event) => event['key']?.toString() == eventKey)
          .firstOrNull,
    _ => null,
  };
  if (event == null) {
    debugPrint(
      'Nexus: /events response for $eventKey had no matching event '
      '(${response.runtimeType})',
    );
    return NexusFailed('Honeycomb returned no event for $eventKey');
  }

  final status = NexusEventStatus.fromHoneycombEvent(event);
  for (final warning in status.parseWarnings) {
    debugPrint('Nexus: $eventKey $warning');
  }

  if (!status.hasData) {
    debugPrint(
      'Nexus: no Nexus data for $eventKey. The event may not use Nexus, or '
      'Honeycomb dropped the Nexus response.',
    );
    return NexusEmpty(status);
  }
  return NexusAvailable(status);
}
