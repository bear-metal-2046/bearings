import 'package:grove/grove.dart';
import 'package:uuid/uuid.dart';

import '../../models/match_form_data.dart';

part 'report.g.dart';

/// Game-specific sections remain flexible. Identity, event and report metadata
/// are shared across Bearimetric, Beariscope and Honeycomb.
@GroveEntity('scouting.report', version: 1, offlineMutable: true)
class ScoutingReport {
  ScoutingReport({
    required this.id,
    required this.timestamp,
    required Json data,
  }) : data = cloneJson(data) {
    if (id.isEmpty || eventKey.isEmpty || kind.isEmpty || season < 1) {
      throw ArgumentError(
        'Scouting report requires ID, event, type and season',
      );
    }
  }
  factory ScoutingReport.fromPayload(
    Json data, {
    String? id,
    DateTime? timestamp,
  }) => ScoutingReport(
    id: id ?? const Uuid().v4(),
    timestamp: timestamp ?? DateTime.now(),
    data: data,
  );

  factory ScoutingReport.fromMatch(MatchFormData form) =>
      ScoutingReport.fromPayload(
        {...form.toJson(), 'sections': form.sections}..remove('id'),
        id: form.id,
        timestamp: form.lastModified,
      );

  MatchFormData toMatch() => MatchFormData.fromJson({
    ...data,
    'id': id,
    'lastModified': timestamp.toUtc().toIso8601String(),
  });

  final String id;
  final DateTime timestamp;
  final Json data;
  Json? get meta => data['meta'] is Map
      ? Map<String, dynamic>.from(data['meta'] as Map)
      : null;
  String get eventKey => meta?['event'] as String? ?? '';
  String get kind => meta?['type'] as String? ?? '';
  int get season => meta?['season'] as int? ?? 0;
  ScoutingReport copyWith({Json? data, DateTime? timestamp}) => ScoutingReport(
    id: id,
    data: data ?? this.data,
    timestamp: timestamp ?? this.timestamp,
  );
  Json toJson() => _ScoutingReportToGroveJson(this);
  factory ScoutingReport.fromJson(Json json) =>
      _ScoutingReportFromGroveJson(json);
  static const event = EntityField<ScoutingReport, String>('data.meta.event');
  static const reportType = EntityField<ScoutingReport, String>(
    'data.meta.type',
  );
}
