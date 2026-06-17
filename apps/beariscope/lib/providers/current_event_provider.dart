import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:services/providers/api_provider.dart';

import 'shared_preferences_provider.dart';

part 'current_event_provider.g.dart';

@Riverpod(keepAlive: true)
class CurrentEvent extends _$CurrentEvent {
  static const _storageKey = 'current_event_key';
  static const _defaultEventKey = '2026wabon';

  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedKey = prefs.getString(_storageKey)?.trim();
    return savedKey == null || savedKey.isEmpty ? _defaultEventKey : savedKey;
  }

  Future<void> setEventKey(String? eventKey) async {
    final value = _normalizeEventKey(eventKey);
    state = value;
    await ref.read(sharedPreferencesProvider).setString(_storageKey, value);
  }

  String _normalizeEventKey(String? eventKey) {
    final trimmed = eventKey?.trim();
    return trimmed == null || trimmed.isEmpty ? _defaultEventKey : trimmed;
  }
}

final teamEventsProvider = FutureProvider<List<EventOption>>((ref) async {
  final client = ref.watch(honeycombClientProvider);
  final year = DateTime.now().year;
  final response = await client.get<List<dynamic>>(
    '/events',
    queryParams: {'team': 'frc2046', 'year': year, 'enrich': false},
    cachePolicy: CachePolicy.networkFirst,
  );

  final events = response
      .whereType<Map>()
      .map((raw) => Map<String, dynamic>.from(raw))
      .map(EventOption.fromJson)
      .toList();

  events.sort((a, b) {
    final aDate = a.startDate ?? DateTime(0);
    final bDate = b.startDate ?? DateTime(0);
    return aDate.compareTo(bDate);
  });

  return events;
});

class EventOption {
  static const int regional = 0;
  static const int district = 1;
  static const int districtCmp = 2;
  static const int cmpDivision = 3;
  static const int cmpFinals = 4;
  static const int districtCmpDivision = 5;
  static const int foc = 6;
  static const int remote = 7;
  static const int offseason = 99;
  static const int preseason = 100;
  static const int unlabeled = -1;

  final String key;
  final String name;
  final String shortName;
  final int eventType;
  final DateTime? startDate;

  const EventOption({
    required this.key,
    required this.name,
    required this.shortName,
    required this.eventType,
    this.startDate,
  });

  factory EventOption.current(String key) {
    return EventOption(
      key: key,
      name: key,
      shortName: key,
      eventType: unlabeled,
    );
  }

  factory EventOption.fromJson(Map<String, dynamic> json) {
    return EventOption(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Event',
      shortName:
          json['shortName']?.toString() ??
          json['name']?.toString() ??
          'Unknown Event',
      eventType: (json['eventType'] as num?)?.toInt() ?? unlabeled,
      startDate: () {
        final raw = json['startDate'] ?? json['start_date'];
        if (raw == null) return null;
        return DateTime.tryParse(raw.toString());
      }(),
    );
  }

  String get displayName => name.isEmpty ? key : name;

  String get displayShortName => shortName.isEmpty ? displayName : shortName;

  IconData get leadingIcon {
    switch (eventType) {
      case regional:
        return Symbols.public_rounded;
      case district:
        return Symbols.location_city_rounded;
      case districtCmpDivision:
        return Symbols.view_module_rounded;
      case districtCmp:
        return Symbols.stadium_rounded;
      case cmpDivision:
        return Symbols.view_module_rounded;
      case cmpFinals:
        return Symbols.trophy_rounded;
      case foc:
        return Symbols.groups_rounded;
      case remote:
        return Symbols.videocam_rounded;
      case offseason:
        return Symbols.beach_access_rounded;
      case preseason:
        return Symbols.rocket_launch_rounded;
      case unlabeled:
      default:
        return Symbols.help_rounded;
    }
  }
}

List<EventOption> eventPickerOptions(
  List<EventOption> events,
  String currentEventKey,
) {
  if (events.any((event) => event.key == currentEventKey)) {
    return events;
  }

  return [...events, EventOption.current(currentEventKey)];
}
