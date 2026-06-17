import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:pawfinder/data/local_data.dart';
import 'package:pawfinder/data/match_json_gen.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'strat_state.g.dart';

String stratStorageKey({
  required String eventKey,
  required int matchNumber,
  required String alliance,
}) => 'STRAT_${eventKey}_${matchNumber}_$alliance';

String stratStorageKeyForIdentity(MatchIdentity identity) => stratStorageKey(
  eventKey: identity.event.key,
  matchNumber: identity.matchNumber,
  alliance: identity.position.allianceKey,
);

String _stratScoutedByKey(MatchIdentity identity) =>
    '${stratStorageKeyForIdentity(identity)}_scoutedBy';

class StratFormData {
  const StratFormData({
    required this.id,
    required this.eventKey,
    required this.matchNumber,
    required this.alliance,
    required this.season,
    required this.configVersion,
    required this.lastModified,
    required this.state,
    this.scoutedBy,
  });

  final String id;
  final String eventKey;
  final int matchNumber;
  final String alliance;
  final int season;
  final int configVersion;
  final DateTime lastModified;
  final StratState state;
  final String? scoutedBy;

  factory StratFormData.blankForIdentity(
    MatchIdentity identity, {
    String? scoutedBy,
  }) {
    return StratFormData(
      id: const Uuid().v4(),
      eventKey: identity.event.key,
      matchNumber: identity.matchNumber,
      alliance: identity.position.allianceKey,
      season: identity.event.year,
      configVersion: 1,
      lastModified: DateTime.now().toUtc(),
      state: const StratState.empty(),
      scoutedBy: _sanitizeScoutName(scoutedBy),
    );
  }

  StratFormData copyWith({
    String? id,
    String? eventKey,
    int? matchNumber,
    String? alliance,
    int? season,
    int? configVersion,
    DateTime? lastModified,
    StratState? state,
    Object? scoutedBy = _noChange,
  }) {
    return StratFormData(
      id: id ?? this.id,
      eventKey: eventKey ?? this.eventKey,
      matchNumber: matchNumber ?? this.matchNumber,
      alliance: alliance ?? this.alliance,
      season: season ?? this.season,
      configVersion: configVersion ?? this.configVersion,
      lastModified: (lastModified ?? this.lastModified).toUtc(),
      state: state ?? this.state,
      scoutedBy: identical(scoutedBy, _noChange)
          ? this.scoutedBy
          : _sanitizeScoutName(scoutedBy as String?),
    );
  }

  Map<String, dynamic> toJson() {
    final meta = <String, dynamic>{
      'season': season,
      'version': configVersion,
      'type': 'strat',
      'event': eventKey,
      'matchNumber': matchNumber,
      'alliance': alliance,
    };
    final normalizedScout = _sanitizeScoutName(scoutedBy);
    if (normalizedScout != null) {
      meta['scoutedBy'] = normalizedScout;
    }

    return {
      'id': id,
      'meta': meta,
      'driverSkillRanking': state.driverSkill,
      'defensiveSkillRanking': state.defensiveSkill,
      'defensiveResilienceRanking': state.defensiveResilience,
      'mechanicalStabilityRanking': state.mechanicalStability,
      'autoHumanPlayerScore': state.autoHumanPlayerScore,
      'teleHumanPlayerScore': state.teleHumanPlayerScore,
    };
  }

  Map<String, dynamic> toStoredJson() {
    return {
      'id': id,
      'lastModified': lastModified.toUtc().toIso8601String(),
      'payload': toJson(),
    };
  }

  static StratFormData fromStoredJson(
    Map<String, dynamic> stored, {
    required String fallbackEventKey,
    required int fallbackMatchNumber,
    required String fallbackAlliance,
    required int fallbackSeason,
    String? fallbackScout,
  }) {
    final payloadRaw = stored['payload'];
    final payload = payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : stored;
    final metaRaw = payload['meta'];
    final meta = metaRaw is Map ? Map<String, dynamic>.from(metaRaw) : const {};

    final normalizedAlliance = _normalizeAlliance(
      meta['alliance']?.toString() ?? fallbackAlliance,
    );

    return StratFormData(
      id:
          stored['id']?.toString() ??
          payload['id']?.toString() ??
          const Uuid().v4(),
      eventKey: meta['event']?.toString() ?? fallbackEventKey,
      matchNumber:
          _asInt(meta['matchNumber']) ??
          _asInt(payload['matchNumber']) ??
          fallbackMatchNumber,
      alliance: normalizedAlliance,
      season: _asInt(meta['season']) ?? fallbackSeason,
      configVersion: _asInt(meta['version']) ?? 1,
      lastModified:
          _asDateTime(stored['lastModified']) ?? DateTime.now().toUtc(),
      scoutedBy: _sanitizeScoutName(
        meta['scoutedBy']?.toString() ?? fallbackScout,
      ),
      state: _stratStateFromPayload(payload),
    );
  }
}

class _DecodedStratRecord {
  const _DecodedStratRecord({required this.data});

  final StratFormData data;
}

StratFormData? loadStratFormDataForIdentity(MatchIdentity identity) {
  final box = Hive.box(boxKey);
  final key = stratStorageKeyForIdentity(identity);
  final fallbackScout = _storedScoutName(
    box,
    key,
    fallback: identity.scout.name,
  );

  final raw = box.get(key);
  if (raw is! String) return null;

  final decoded = _decodeStratRaw(
    raw,
    eventKey: identity.event.key,
    matchNumber: identity.matchNumber,
    alliance: identity.position.allianceKey,
    season: identity.event.year,
    fallbackScout: fallbackScout,
  );
  return decoded?.data;
}

StratFormData? loadStratFormDataById(String id) {
  if (id.isEmpty) return null;
  final box = Hive.box(boxKey);

  for (final dynamic rawKey in box.keys) {
    if (rawKey is! String) continue;
    if (!rawKey.startsWith('STRAT_') || rawKey.endsWith('_scoutedBy')) {
      continue;
    }

    final parsedKey = _parseStratStorageKey(rawKey);
    if (parsedKey == null) continue;

    final raw = box.get(rawKey);
    if (raw is! String) continue;

    final decoded = _decodeStratRaw(
      raw,
      eventKey: parsedKey.eventKey,
      matchNumber: parsedKey.matchNumber,
      alliance: parsedKey.alliance,
      season: _seasonFromEventKey(parsedKey.eventKey),
      fallbackScout: _storedScoutName(box, rawKey),
    );
    if (decoded == null) continue;
    if (decoded.data.id == id) return decoded.data;
  }

  return null;
}

_DecodedStratRecord? _decodeStratRaw(
  String raw, {
  required String eventKey,
  required int matchNumber,
  required String alliance,
  required int season,
  String? fallbackScout,
}) {
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }

  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);

  if (map['payload'] is Map || map['meta'] is Map) {
    return _DecodedStratRecord(
      data: StratFormData.fromStoredJson(
        map,
        fallbackEventKey: eventKey,
        fallbackMatchNumber: matchNumber,
        fallbackAlliance: alliance,
        fallbackSeason: season,
        fallbackScout: fallbackScout,
      ),
    );
  }

  return null;
}

({String eventKey, int matchNumber, String alliance})? _parseStratStorageKey(
  String key,
) {
  if (!key.startsWith('STRAT_')) return null;
  final body = key.substring('STRAT_'.length);
  final last = body.lastIndexOf('_');
  if (last <= 0) return null;
  final secondLast = body.lastIndexOf('_', last - 1);
  if (secondLast <= 0) return null;

  final eventKey = body.substring(0, secondLast);
  final matchNumber = int.tryParse(body.substring(secondLast + 1, last));
  final alliance = _normalizeAlliance(body.substring(last + 1));

  if (eventKey.isEmpty || matchNumber == null) return null;
  return (eventKey: eventKey, matchNumber: matchNumber, alliance: alliance);
}

String? _storedScoutName(Box<dynamic> box, String key, {String? fallback}) {
  final stored = box.get('${key}_scoutedBy')?.toString();
  return _sanitizeScoutName(stored ?? fallback);
}

int _seasonFromEventKey(String eventKey) {
  if (eventKey.length < 4) return DateTime.now().year;
  return int.tryParse(eventKey.substring(0, 4)) ?? DateTime.now().year;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

String _normalizeAlliance(String? alliance) {
  final normalized = alliance?.toLowerCase().trim();
  return normalized == 'blue' ? 'blue' : 'red';
}

String? _sanitizeScoutName(String? scoutName) {
  final trimmed = scoutName?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

StratState _stratStateFromPayload(Map<String, dynamic> payload) {
  return StratState.fromJson({
    'driverSkill': _asStringList(payload['driverSkillRanking']),
    'defensiveSkill': _asStringList(payload['defensiveSkillRanking']),
    'defensiveResilience': _asStringList(payload['defensiveResilienceRanking']),
    'mechanicalStability': _asStringList(payload['mechanicalStabilityRanking']),
    'autoHumanPlayerScore':
        (payload['autoHumanPlayerScore'] as num?)?.toInt() ?? 0,
    'teleHumanPlayerScore':
        (payload['teleHumanPlayerScore'] as num?)?.toInt() ?? 0,
  });
}

List<String> _asStringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((entry) => entry.toString()).toList(growable: false);
}

const Object _noChange = Object();

class StratState {
  final List<String> driverSkill;
  final List<String> defensiveSkill;
  final List<String> defensiveResilience;
  final List<String> mechanicalStability;
  final int autoHumanPlayerScore;
  final int teleHumanPlayerScore;

  const StratState({
    required this.driverSkill,
    required this.defensiveSkill,
    required this.defensiveResilience,
    required this.mechanicalStability,
    required this.autoHumanPlayerScore,
    required this.teleHumanPlayerScore,
  });

  // empty state for a match that hasn't been filled in yet
  const StratState.empty()
    : driverSkill = const [],
      defensiveSkill = const [],
      defensiveResilience = const [],
      mechanicalStability = const [],
      autoHumanPlayerScore = 0,
      teleHumanPlayerScore = 0;

  StratState copyWith({
    List<String>? driverSkill,
    List<String>? defensiveSkill,
    List<String>? defensiveResilience,
    List<String>? mechanicalStability,
    int? autoHumanPlayerScore,
    int? teleHumanPlayerScore,
  }) => StratState(
    driverSkill: driverSkill ?? this.driverSkill,
    defensiveSkill: defensiveSkill ?? this.defensiveSkill,
    defensiveResilience: defensiveResilience ?? this.defensiveResilience,
    mechanicalStability: mechanicalStability ?? this.mechanicalStability,
    autoHumanPlayerScore: autoHumanPlayerScore ?? this.autoHumanPlayerScore,
    teleHumanPlayerScore: teleHumanPlayerScore ?? this.teleHumanPlayerScore,
  );

  Map<String, dynamic> toJson() => {
    'driverSkill': driverSkill,
    'defensiveSkill': defensiveSkill,
    'defensiveResilience': defensiveResilience,
    'mechanicalStability': mechanicalStability,
    'autoHumanPlayerScore': autoHumanPlayerScore,
    'teleHumanPlayerScore': teleHumanPlayerScore,
  };

  factory StratState.fromJson(Map<String, dynamic> json) => StratState(
    driverSkill: List<String>.from(json['driverSkill'] ?? []),
    defensiveSkill: List<String>.from(json['defensiveSkill'] ?? []),
    defensiveResilience: List<String>.from(json['defensiveResilience'] ?? []),
    mechanicalStability: List<String>.from(json['mechanicalStability'] ?? []),
    autoHumanPlayerScore: (json['autoHumanPlayerScore'] as num?)?.toInt() ?? 0,
    teleHumanPlayerScore: (json['teleHumanPlayerScore'] as num?)?.toInt() ?? 0,
  );
}

// one notifier per match identity — reads/writes to hive on every change
// using keepAlive so the data doesn't get reset while the scout is still on the strat page
@Riverpod(keepAlive: true)
class StratStateNotifier extends _$StratStateNotifier {
  late StratFormData _document;

  @override
  StratState build(MatchIdentity identity) {
    final loaded = loadStratFormDataForIdentity(identity);
    if (loaded != null) {
      _document = loaded;
      return loaded.state;
    }

    _document = StratFormData.blankForIdentity(
      identity,
      scoutedBy: identity.scout.name,
    );
    return _document.state;
  }

  void _save() {
    final box = Hive.box(boxKey);
    final now = DateTime.now().toUtc();
    final scoutedBy = _sanitizeScoutName(identity.scout.name);

    _document = _document.copyWith(
      state: state,
      scoutedBy: scoutedBy,
      lastModified: now,
      eventKey: identity.event.key,
      matchNumber: identity.matchNumber,
      alliance: identity.position.allianceKey,
      season: identity.event.year,
      configVersion: 1,
    );

    box.put(
      stratStorageKeyForIdentity(identity),
      jsonEncode(_document.toStoredJson()),
    );
    if (scoutedBy != null && scoutedBy.isNotEmpty) {
      box.put(_stratScoutedByKey(identity), scoutedBy);
    }
  }

  // populate lists from the schedule if they're still empty (new match)
  void initFromSchedule(List<String> teams) {
    if (teams.isEmpty || state.driverSkill.isNotEmpty) return;
    state = state.copyWith(
      driverSkill: List.from(teams),
      defensiveSkill: List.from(teams),
      defensiveResilience: List.from(teams),
      mechanicalStability: List.from(teams),
    );
    _save();
  }

  void _handleReorder(
    List<String> currentList,
    int oldIndex,
    int newIndex,
    Function(List<String>) updateState,
  ) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final list = List<String>.from(currentList);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    updateState(list);
    _save();
  }

  void reorderDriverSkill(int oldIndex, int newIndex) {
    _handleReorder(state.driverSkill, oldIndex, newIndex, (newList) {
      state = state.copyWith(driverSkill: newList);
    });
  }

  void reorderDefensiveSkill(int oldIndex, int newIndex) {
    _handleReorder(state.defensiveSkill, oldIndex, newIndex, (newList) {
      state = state.copyWith(defensiveSkill: newList);
    });
  }

  void reorderDefensiveResilience(int oldIndex, int newIndex) {
    _handleReorder(state.defensiveResilience, oldIndex, newIndex, (newList) {
      state = state.copyWith(defensiveResilience: newList);
    });
  }

  void reorderMechanicalStability(int oldIndex, int newIndex) {
    _handleReorder(state.mechanicalStability, oldIndex, newIndex, (newList) {
      state = state.copyWith(mechanicalStability: newList);
    });
  }

  void incrementAutoHumanPlayer() {
    state = state.copyWith(
      autoHumanPlayerScore: state.autoHumanPlayerScore + 1,
    );
    _save();
  }

  void decrementAutoHumanPlayer() {
    if (state.autoHumanPlayerScore <= 0) return;
    state = state.copyWith(
      autoHumanPlayerScore: state.autoHumanPlayerScore - 1,
    );
    _save();
  }

  void incrementTeleHumanPlayer() {
    state = state.copyWith(
      teleHumanPlayerScore: state.teleHumanPlayerScore + 1,
    );
    _save();
  }

  void decrementTeleHumanPlayer() {
    if (state.teleHumanPlayerScore <= 0) return;
    state = state.copyWith(
      teleHumanPlayerScore: state.teleHumanPlayerScore - 1,
    );
    _save();
  }
}
