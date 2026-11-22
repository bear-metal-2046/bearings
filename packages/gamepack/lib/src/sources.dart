import 'forms.dart';
import 'value.dart';

/// Fields supplied by the app when evaluating a team, match, or event view.
final gamePackContextType = GamePackType.record({
  'event': GamePackType.text,
  'match': GamePackType.text,
  'team': GamePackType.text,
  'alliance': GamePackType.text,
  'station': GamePackType.integer,
});

Map<String, GamePackType> gamePackSourceTypes(Iterable<GamePackField> fields) {
  final observation = GamePackType.record({
    'id': GamePackType.text,
    'event': GamePackType.text,
    'match': GamePackType.text,
    'team': GamePackType.text,
    'alliance': GamePackType.text,
    'station': GamePackType.integer,
    'form': GamePackType.text,
    'kind': GamePackType.text,
    'release': GamePackType.text,
    'scout': GamePackType.text,
    'author': GamePackType.text,
    'captured_at': GamePackType.integer,
    'supersedes': GamePackType.text,
    'retracted': GamePackType.boolean,
    'answers': GamePackType.record({
      for (final field in fields) field.id: field.type,
    }),
  });
  final tba = GamePackType.record({
    'id': GamePackType.text,
    'event': GamePackType.text,
    'match': GamePackType.text,
    'sequence': GamePackType.integer,
    'observed_at': GamePackType.integer,
    'payload': GamePackType.json,
  });
  return {
    'context': gamePackContextType,
    'observations': GamePackType.list(observation),
    'observation_history': GamePackType.list(observation),
    'tba': GamePackType.list(tba),
    'tba_history': GamePackType.list(tba),
  };
}

class GamePackScope {
  const GamePackScope({
    required this.event,
    this.match,
    this.team,
    this.alliance,
    this.station,
  });

  final String event;
  final String? match;
  final String? team;
  final String? alliance;
  final int? station;

  GamePackValue toValue() => GamePackValue.of({
    'event': event,
    if (match case final value?) 'match': value,
    if (team case final value?) 'team': value,
    if (alliance case final value?) 'alliance': value,
    if (station case final value?) 'station': value,
  });
}
