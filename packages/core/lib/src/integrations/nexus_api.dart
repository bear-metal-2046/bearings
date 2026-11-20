import 'package:grove/grove.dart';

import '../entities/competition/competition_entities.dart';
import 'pit_map.dart';

final _nexusKeyPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');
bool isNexusEventKey(String key) => _nexusKeyPattern.hasMatch(key);

String nexusEventKey(String eventKey, String? firstEventCode) =>
    firstEventCode == null || firstEventCode.isEmpty || eventKey.length < 4
    ? eventKey
    : '${eventKey.substring(0, 4)}${firstEventCode.toLowerCase()}';

DateTime? _nexusTimestamp(Object? value) => value is num && value.isFinite
    ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true)
    : null;

EventStatusSnapshot parseNexusEventSnapshot(Json data) {
  final id = data['eventKey'];
  final timestamp = _nexusTimestamp(data['dataAsOfTime']);
  final matches = data['matches'];
  if (id is! String ||
      !isNexusEventKey(id) ||
      timestamp == null ||
      matches is! List) {
    throw const FormatException('Invalid Nexus event status');
  }
  final nowQueuing = data['nowQueuing']?.toString().trim();
  return EventStatusSnapshot(
    id: id,
    dataAsOfTime: timestamp,
    nowQueuing: nowQueuing == null || nowQueuing.isEmpty ? null : nowQueuing,
    matches: matches.cast<Json>().map(QueueMatch.fromJson).toList(),
    announcements: (data['announcements'] as List? ?? const [])
        .cast<Json>()
        .map(
          (item) => EventAnnouncement(
            id: item['id'] as String?,
            text: item['announcement'] as String,
            postedAt: _nexusTimestamp(item['postedTime']),
          ),
        )
        .toList(),
    partsRequests: (data['partsRequests'] as List? ?? const [])
        .cast<Json>()
        .map(
          (item) => EventPartsRequest(
            id: item['id'] as String?,
            parts: item['parts'] as String,
            requestedByTeam: item['requestedByTeam'] as String,
            postedAt: _nexusTimestamp(item['postedTime']),
          ),
        )
        .toList(),
  );
}

PitMap parseNexusPitMap(Json data) => parsePitMap(data);

PitLayout parseNexusPitLayout(String event, {Json? map, Json? addresses}) {
  final geometry = map == null ? null : parseNexusPitMap(map);
  final pits = <String, Pit>{};
  final assignedTeams = <String>{};

  // Reserve both the address and team before falling back to embedded teams.
  for (final entry in (addresses ?? const <String, Object?>{}).entries) {
    final team = parsePitTeam(entry.key);
    if (team == null) continue;
    pits[entry.value as String] = Pit(team: team);
    assignedTeams.add(team.id);
  }

  for (final entry
      in (geometry?.pits ?? const <String, PitMapElement>{}).entries) {
    final address = entry.key;
    final element = entry.value;
    var team = pits[address]?.team;
    final embedded = element.team;
    if (team == null && embedded != null && assignedTeams.add(embedded.id)) {
      team = embedded;
    }
    pits[address] = Pit(
      geometry: PitGeometry(
        position: element.position,
        size: element.size,
        angle: element.angle,
      ),
      team: team,
    );
  }

  return PitLayout(
    id: event,
    map: geometry == null
        ? null
        : PitMapBackground(
            size: geometry.size,
            areas: geometry.areas,
            labels: geometry.labels,
            arrows: geometry.arrows,
            walls: geometry.walls,
          ),
    pits: pits,
  );
}
