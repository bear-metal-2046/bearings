// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report.dart';

// **************************************************************************
// _GroveGenerator
// **************************************************************************

Json _ScoutingReportToGroveJson(ScoutingReport value) => {
  "id": value.id,
  "timestamp": value.timestamp.toUtc().toIso8601String(),
  "data": value.data.map((key, item) => MapEntry(key, item)),
};
ScoutingReport _ScoutingReportFromGroveJson(Json json) => ScoutingReport(
  id: json["id"] as String,
  timestamp: DateTime.parse(json["timestamp"] as String),
  data: (json["data"] as Map).map((key, item) => MapEntry(key as String, item)),
);

final scoutingReportEntity = EntityDescriptor<ScoutingReport>(
  type: "scouting.report",
  version: 1,
  offlineMutable: true,

  encode: _ScoutingReportToGroveJson,
  decode: _ScoutingReportFromGroveJson,
);

abstract final class ScoutingReportFields {
  static const id = EntityField<ScoutingReport, String>("id");
}
