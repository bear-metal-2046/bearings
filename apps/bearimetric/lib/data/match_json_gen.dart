import 'dart:convert';

import 'package:core/core.dart' show MatchFormData;
import 'package:hive_ce_flutter/adapters.dart';
import 'package:bearimetric/data/local_data.dart';
import 'package:bearimetric/data/match_form_store.dart';
import 'package:bearimetric/data/ui_json_serialization.dart';
import 'package:bearimetric/models/scouting_session.dart';

typedef MatchIdentity = ({
  ScoutingEvent event,
  int matchNumber,
  ScoutPosition position,
  Scout scout,
});

String identityDataKey(MatchIdentity identity) {
  return "MATCH_${identity.event.key}_${identity.matchNumber}_${identity.position.name}_${identity.scout.name}";
}

// key without scouts
String matchBaseKey(MatchIdentity identity) {
  return "MATCH_${identity.event.key}_${identity.matchNumber}_${identity.position.name}";
}

String matchDataKey(MatchIdentity identity, String sectionId, String fieldId) {
  return "${matchBaseKey(identity)}_${sectionId}_$fieldId";
}

String matchTeamKey(MatchIdentity identity) => '${matchBaseKey(identity)}_team';

// name of the scout who last saved data
String matchScoutedByKey(MatchIdentity identity) =>
    '${matchBaseKey(identity)}_scoutedBy';

class SectionJsonData {
  final String sectionId;
  final Map<String, dynamic> fields;

  SectionJsonData({required this.sectionId, required this.fields});

  factory SectionJsonData.fromJson(Map<String, dynamic> json) {
    return SectionJsonData(
      sectionId: json['sectionId'],
      fields: Map<String, dynamic>.from(json['fields'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {'sectionId': sectionId, 'fields': fields};
}

@Deprecated('use MatchFormData and MatchFormStore instead')
class MetaJsonData {
  final int season;
  final int version;
  final String type;
  final String event;
  final String scoutedBy;

  MetaJsonData({
    required this.season,
    required this.version,
    required this.type,
    required this.event,
    required this.scoutedBy,
  });

  factory MetaJsonData.fromJson(Map<String, dynamic> json) {
    return MetaJsonData(
      season: json['season'],
      version: json['version'],
      type: json['type'],
      event: json['event']?.toString() ?? '',
      scoutedBy: json['scoutedBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'season': season,
    'version': version,
    'type': type,
    'event': event,
    'scoutedBy': scoutedBy,
  };
}

@Deprecated('use MatchFormData and MatchFormStore instead')
class MatchJsonData {
  final MetaJsonData meta;
  final int? teamNumber;
  final int matchNumber;
  final int pos;
  final List<SectionJsonData> sections;

  MatchJsonData({
    required this.meta,
    required this.matchNumber,
    required this.pos,
    required this.sections,
    this.teamNumber,
  });

  factory MatchJsonData.fromJson(Map<String, dynamic> json) {
    return MatchJsonData(
      meta: MetaJsonData.fromJson(json['meta']),
      teamNumber: json['teamNumber'] as int?,
      matchNumber: (json['matchNumber'] as int?) ?? 0,
      pos: (json['pos'] as int?) ?? 0,
      sections: (json['sections'] as List)
          .map((e) => SectionJsonData.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'meta': meta.toJson(),
      'matchNumber': matchNumber,
      'pos': pos,
      'sections': sections.map((e) => e.toJson()).toList(),
    };
    if (teamNumber != null) map['teamNumber'] = teamNumber;
    return map;
  }
}

@Deprecated('use MatchFormData and MatchFormStore instead')
// legacy read helper used by existing upload flow before full migration
SectionJsonData generateSectionJsonHive(PageConfig config, MatchIdentity info) {
  final section = SectionJsonData(sectionId: config.sectionId, fields: {});
  final box = Hive.box(boxKey);

  for (final data in config.components) {
    final key = matchDataKey(info, config.sectionId, data.fieldId);
    section.fields[data.fieldId] = box.get(key) ?? 0;
  }

  return section;
}

@Deprecated('use MatchFormData and MatchFormStore instead')
MetaJsonData generateMetaJsonHive(Meta config, MatchIdentity info) {
  // keep the name of the scout who last saved data
  final storedScout = Hive.box(boxKey).get(matchScoutedByKey(info)) as String?;
  return MetaJsonData(
    season: config.season,
    type: config.type,
    version: config.version,
    event: info.event.key,
    scoutedBy: storedScout ?? info.scout.name,
  );
}

@Deprecated('use MatchFormData and MatchFormStore instead')
// reads from new one-document storage when available, falls back to legacy keys
MatchJsonData generateMatchJsonHive(MatchConfig config, MatchIdentity info) {
  final store = MatchFormStore();
  final stored = store.load(
    info.event.key,
    info.matchNumber,
    info.position.posIndex,
  );
  if (stored != null) {
    return _toLegacyMatchJson(stored);
  }

  final box = Hive.box(boxKey);
  final rawTeam = box.get(matchTeamKey(info));
  final teamNumber = rawTeam is int ? rawTeam : null;

  return MatchJsonData(
    meta: generateMetaJsonHive(config.meta, info),
    teamNumber: teamNumber,
    matchNumber: info.matchNumber,
    pos: info.position.posIndex,
    sections: config.pages
        .map((e) => generateSectionJsonHive(e, info))
        .toList(),
  );
}

@Deprecated('use MatchFormData and MatchFormStore instead')
// compatibility: store full document under one key
void loadMatchJsonToHive(MatchJsonData data, MatchIdentity info) {
  final store = MatchFormStore();
  store.save(_toMatchFormData(data, info, store));
}

@Deprecated('use MatchFormData and MatchFormStore instead')
// compatibility: store full document under one key
void insertMatchJsonToHive(MatchJsonData data, MatchIdentity info) {
  final store = MatchFormStore();
  store.save(_toMatchFormData(data, info, store));
}

@Deprecated('use MatchFormData and MatchFormStore instead')
MatchJsonData? getMatchJsonFromHive(MatchIdentity info) {
  final store = MatchFormStore();
  final stored = store.load(
    info.event.key,
    info.matchNumber,
    info.position.posIndex,
  );
  if (stored != null) return _toLegacyMatchJson(stored);

  // legacy compatibility while old callers still exist
  final jsonRaw = Hive.box(boxKey).get('${matchBaseKey(info)}_JSON') as String?;
  if (jsonRaw == null) return null;
  try {
    return MatchJsonData.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonRaw) as Map),
    );
  } catch (_) {
    return null;
  }
}

MatchJsonData _toLegacyMatchJson(MatchFormData data) {
  return MatchJsonData(
    meta: MetaJsonData(
      season: data.season,
      version: data.configVersion,
      type: 'match',
      event: data.eventKey,
      scoutedBy: data.scoutedBy ?? '',
    ),
    teamNumber: data.teamNumber,
    matchNumber: data.matchNumber,
    pos: data.pos,
    sections: data.sections.entries
        .map(
          (entry) => SectionJsonData(
            sectionId: entry.key,
            fields: Map<String, dynamic>.from(entry.value),
          ),
        )
        .toList(),
  );
}

MatchFormData _toMatchFormData(
  MatchJsonData data,
  MatchIdentity info,
  MatchFormStore store,
) {
  final existing = store.load(
    info.event.key,
    info.matchNumber,
    info.position.posIndex,
  );
  final sections = <String, Map<String, dynamic>>{
    for (final section in data.sections)
      section.sectionId: Map<String, dynamic>.from(section.fields),
  };

  if (existing != null) {
    return existing.copyWith(
      season: data.meta.season,
      configVersion: data.meta.version,
      teamNumber: data.teamNumber,
      scoutedBy: data.meta.scoutedBy,
      sections: sections,
    );
  }

  return MatchFormData.blank(
    eventKey: data.meta.event.isEmpty ? info.event.key : data.meta.event,
    matchNumber: data.matchNumber,
    pos: data.pos,
    season: data.meta.season,
    configVersion: data.meta.version,
    teamNumber: data.teamNumber,
    scoutedBy: data.meta.scoutedBy,
  ).copyWith(sections: sections);
}
