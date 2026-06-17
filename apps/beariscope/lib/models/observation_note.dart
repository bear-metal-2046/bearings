import 'package:beariscope/models/scouting_document.dart';

/// A team-scoped observation note that is always inserted as a new record.
class ObservationNote {
  /// Optional document ID used for future upsert support.
  final String? id;

  /// The team being observed.
  final int teamNumber;

  /// The observation text.
  final String note;

  /// Display name of the submitting user.
  final String scoutedBy;

  /// Auth0 user ID of the submitting user.
  final String userId;

  /// TBA event key.
  final String eventKey;

  /// Season year.
  final int season;

  const ObservationNote({
    this.id,
    required this.teamNumber,
    required this.note,
    required this.scoutedBy,
    required this.userId,
    required this.eventKey,
    required this.season,
  });

  /// Converts this note into an ingest entry payload for `POST /scout/ingest`.
  Map<String, Object?> toIngestEntry() {
    return {
      'meta': {
        'type': 'observation',
        'version': 1,
        'season': season,
        'event': eventKey,
        'scoutedBy': scoutedBy,
        'userId': userId,
        if (id != null && id!.isNotEmpty) 'existingId': id,
      },
      'teamNumber': teamNumber,
      'note': note,
    };
  }

  /// Reconstructs an [ObservationNote] from a raw [ScoutingDocument].
  factory ObservationNote.fromScoutingDocument(ScoutingDocument doc) {
    final meta = doc.meta ?? {};
    final tn = doc.data['teamNumber'];
    final teamNumber = tn is int
        ? tn
        : tn is double
        ? tn.toInt()
        : tn is String
        ? int.tryParse(tn) ?? 0
        : 0;

    return ObservationNote(
      id: doc.id.isNotEmpty ? doc.id : null,
      teamNumber: teamNumber,
      note: doc.data['note']?.toString() ?? '',
      scoutedBy: meta['scoutedBy']?.toString() ?? '',
      userId: meta['userId']?.toString() ?? '',
      eventKey: meta['event']?.toString() ?? '',
      season: (meta['season'] as num?)?.toInt() ?? 2026,
    );
  }
}
