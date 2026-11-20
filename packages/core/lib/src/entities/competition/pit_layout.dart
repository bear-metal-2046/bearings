part of 'competition_entities.dart';

@GroveValue()
class PitMapPoint {
  const PitMapPoint({required this.x, required this.y});

  final double x;
  final double y;
}

@GroveValue()
class PitMapElement {
  const PitMapElement({
    required this.position,
    required this.size,
    this.angle,
    this.team,
    this.label,
    this.arrowType,
  });

  final PitMapPoint position;
  final PitMapPoint size;
  final double? angle;
  final EntityRef<CompetitionTeam>? team;
  final String? label;
  final String? arrowType;
}

@GroveValue()
class PitMap {
  const PitMap({
    required this.size,
    this.pits = const {},
    this.areas = const {},
    this.labels = const {},
    this.arrows = const {},
    this.walls = const {},
  });

  final PitMapPoint size;
  final Map<String, PitMapElement> pits;
  final Map<String, PitMapElement> areas;
  final Map<String, PitMapElement> labels;
  final Map<String, PitMapElement> arrows;
  final Map<String, PitMapElement> walls;
}

@GroveValue()
class PitGeometry {
  const PitGeometry({required this.position, required this.size, this.angle});

  final PitMapPoint position;
  final PitMapPoint size;
  final double? angle;
}

@GroveValue()
class Pit {
  const Pit({this.geometry, this.team});

  final PitGeometry? geometry;
  final EntityRef<CompetitionTeam>? team;
}

@GroveValue()
class PitMapBackground {
  const PitMapBackground({
    required this.size,
    this.areas = const {},
    this.labels = const {},
    this.arrows = const {},
    this.walls = const {},
  });

  final PitMapPoint size;
  final Map<String, PitMapElement> areas;
  final Map<String, PitMapElement> labels;
  final Map<String, PitMapElement> arrows;
  final Map<String, PitMapElement> walls;
}

/// An event's pits, keyed by address, and its optional map background.
@GroveEntity('pit_layout', version: 1, serverManaged: true)
class PitLayout {
  const PitLayout({required this.id, this.map, this.pits = const {}});

  final String id;
  final PitMapBackground? map;
  final Map<String, Pit> pits;
}
