import 'package:grove/grove.dart';

import '../entities/competition/competition_entities.dart';

/// Parse the pit geometry returned by both competition APIs.
PitMap parsePitMap(Json map) => PitMap(
  size: _vector(map['size'] as Json),
  pits: _mapElements(map['pits']),
  areas: _mapElements(map['areas']),
  labels: _mapElements(map['labels']),
  arrows: _mapElements(map['arrows']),
  walls: _mapElements(map['walls']),
);

Map<String, PitMapElement> _mapElements(Object? data) =>
    (data as Json? ?? const {}).map((key, value) {
      final item = value as Json;
      return MapEntry(
        key,
        PitMapElement(
          position: _vector(item['position'] as Json),
          size: _vector(item['size'] as Json),
          angle: (item['angle'] as num?)?.toDouble(),
          team: parsePitTeam(item['team_key'] ?? item['team']),
          label: item['label'] as String?,
          arrowType: item['type'] as String?,
        ),
      );
    });

EntityRef<CompetitionTeam>? parsePitTeam(Object? team) {
  if (team == null) return null;
  final key = team.toString().trim();
  if (key.isEmpty) return null;
  return EntityRef(key.startsWith('frc') ? key : 'frc$key');
}

PitMapPoint _vector(Json item) => PitMapPoint(
  x: (item['x'] as num).toDouble(),
  y: (item['y'] as num).toDouble(),
);
