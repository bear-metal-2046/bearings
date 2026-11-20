import 'package:core/core.dart' show CompetitionEvent;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/competition_provider.dart';

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

final teamEventsProvider = Provider<AsyncValue<List<EventOption>>>((ref) {
  final year = DateTime.now().year;
  return ref
      .watch(competitionEventsProvider((year: year, team: 'frc2046')))
      .whenData((response) {
        final events = response.map(EventOption.fromCompetition).toList();

        events.sort((a, b) {
          final aDate = a.startDate ?? DateTime(0);
          final bDate = b.startDate ?? DateTime(0);
          return aDate.compareTo(bDate);
        });

        return events;
      });
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

  static const Map<String, String> _eventNameReplacements = {
    'District Championship': 'DCMP',
    'State Championship': 'State CMP',
    'Provincial Championship': 'PCMP',
    "Girl's Generation": "Girl's Gen",

    'Pacific Northwest FIRST': 'PNW',
    'FIRST in Michigan': 'FIM',
    'FIRST in Texas': 'FIT',
    'FIRST Indiana': 'FIN',
    'FIRST Mid-Atlantic': 'FMA',
    'FIRST North Carolina': 'FNC',
    'FIRST South Carolina': 'FSC',
    'FIRST Wisconsin': 'WIN',
    'New England FIRST': 'NE',
    'Peachtree': 'PCH',
    'FIRST Ontario': 'ONT',
    'FIRST Israel': 'ISR',

    'PNW District': 'PNW',
    'FIM District': 'FIM',
    'FIT District': 'FIT',
    'FCH District': 'FCH',
    'FIN District': 'FIN',
    'FMA District': 'FMA',
    'FNC District': 'FNC',
    'FSC District': 'FSC',
    'WIN District': 'WIN',
    'NE District': 'NE',
    'PCH District': 'PCH',
    'ONT District': 'ONT',
    'ISR District': 'ISR',
  };

  static String _normalizeApostrophes(String text) {
    return text.replaceAll(RegExp('[’‘‛ʻʼ`]'), "'");
  }

  static String? _shortenEventName(String name) {
    var text = _normalizeApostrophes(name)
        .replaceAll(RegExp(r'\s+presented.*$', caseSensitive: false), '');

    text = text.replaceAll(
      RegExp(r"Girl'?s Generation", caseSensitive: false),
      "Girl's Gen",
    );

    for (final entry in _eventNameReplacements.entries) {
      text = text.replaceAll(
        RegExp(
          RegExp.escape(_normalizeApostrophes(entry.key)),
          caseSensitive: false,
        ),
        entry.value,
      );
    }

    text = text.trim();
    return text.isEmpty || text == name ? null : text;
  }

  final String key;
  final String firstKey;
  final String name;
  final String shortName;
  final int eventType;
  final DateTime? startDate;

  const EventOption({
    required this.key,
    required this.firstKey,
    required this.name,
    required this.shortName,
    required this.eventType,
    this.startDate,
  });

  factory EventOption.current(String key) {
    return EventOption(
      key: key,
      name: key,
      firstKey: key,
      shortName: key,
      eventType: unlabeled,
    );
  }

  factory EventOption.fromCompetition(CompetitionEvent event) {
    final key = event.id;
    final name = event.name.trim();
    final firstCode = event.firstEventCode;
    final upstreamShortName = event.shortName?.trim() ?? '';
    return EventOption(
      key: key,
      firstKey: firstCode == null
          ? key
          : '${event.season}${firstCode.toLowerCase()}',
      name: name.isNotEmpty ? name : key,
      shortName:
          _shortenEventName(name) ??
          (upstreamShortName.isNotEmpty
              ? upstreamShortName
              : name.isNotEmpty
              ? name
              : key),
      eventType: event.eventType ?? unlabeled,
      startDate: event.startDate,
    );
  }

  IconData get leadingIcon {
    final name = this.name.toLowerCase();

    // PNW events
    if (name.contains('clackamas')) {
      return LucideIcons.factory;
    }
    if (name.contains('kentridge')) {
      return LucideIcons.zap;
    }
    if (name.contains('auburn')) {
      return LucideIcons.chessKnight;
    }
    if (name.contains('wilsonville')) {
      return LucideIcons.cat;
    }
    if (name.contains('sundome') || name.contains('sun dome')) {
      return LucideIcons.sun;
    }
    if (name.contains('sammamish')) {
      return LucideIcons.bird;
    }
    if (name.contains('oregon state fair')) {
      return LucideIcons.ferrisWheel;
    }
    if (name.contains('bonney lake')) {
      return LucideIcons.waves;
    }
    if (name.contains('glacier peak')) {
      return LucideIcons.mountainSnow;
    }

    // Worlds divisions
    if (name.contains('archimedes')) {
      return LucideIcons.pi;
    }

    if (name.contains('curie')) {
      return LucideIcons.radiation;
    }

    if (name.contains('daly')) {
      return LucideIcons.flaskConical;
    }

    if (name.contains('galileo')) {
      return LucideIcons.telescope;
    }

    if (name.contains('hopper')) {
      return LucideIcons.bug;
    }

    if (name.contains('johnson')) {
      return LucideIcons.rocket;
    }

    if (name.contains('milstein')) {
      return LucideIcons.biohazard;
    }

    if (name.contains('newton')) {
      return LucideIcons.apple;
    }

    // FIM
    if (name.contains('dte')) {
      return LucideIcons.solarPanel;
    }
    if (name.contains('consumers')) {
      return LucideIcons.zap;
    }
    if (name.contains('hemlock')) {
      return LucideIcons.microchip;
    }
    if (name.contains('aptiv')) {
      return LucideIcons.factory;
    }

    // FIT
    if (name.contains('mercury')) {
      return LucideIcons.globe;
    }
    if (name.contains('apollo')) {
      return LucideIcons.sparkles;
    }

    // NE
    if (name.contains('burns')) {
      return LucideIcons.bookMarked;
    }
    if (name.contains('newsom')) {
      return LucideIcons.amphora;
    }

    // ONT
    if (name.contains('technology')) {
      return LucideIcons.cpu;
    }

    if (name.contains('science')) {
      return LucideIcons.atom;
    }

    // Other
    if (name.contains('chezy')) {
      return LucideIcons.hamburger;
    }
    if (name.contains('bordie')) {
      return LucideIcons.bird;
    }
    if (name.contains('block party')) {
      return LucideIcons.cuboid;
    }
    if (name.contains('girl') && name.contains('gen')) {
      return LucideIcons.venus;
    }
    if (name.contains('stormsurge')) {
      return LucideIcons.cloudLightning;
    }

    switch (eventType) {
      case regional:
        return LucideIcons.earth;
      case district:
        return LucideIcons.building2;
      case districtCmpDivision:
        return LucideIcons.grid3x2;
      case districtCmp:
        return LucideIcons.trophy;
      case cmpDivision:
        return LucideIcons.grid3x2;
      case cmpFinals:
        return LucideIcons.brain;
      case foc:
        return LucideIcons.users;
      case remote:
        return LucideIcons.video;
      case offseason:
        return LucideIcons.balloon;
      case preseason:
        return LucideIcons.sprout;
      case unlabeled:
      default:
        return LucideIcons.circleQuestionMark;
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
