import 'package:core/core.dart' show ScoutingReport;

/// A drive team scouting note for a single opponent team in a specific match.
class DriveTeamNote {
  /// The document ID used for upsert. Null when not yet submitted to the
  /// backend (i.e. a new note that hasn't been saved yet).
  final String? id;

  /// Full TBA match key, e.g. `'2026wabon_qm3'`.
  final String matchKey;

  /// The team number being scouted.
  final int teamNumber;

  /// The note text.
  final String note;

  /// Display name of the submitting user.
  final String scoutedBy;

  /// Auth0 user ID of the submitting user.
  /// Used to scope the match preview view to only the current user's notes.
  final String userId;

  /// TBA event key.
  final String eventKey;

  /// Season year.
  final int season;

  const DriveTeamNote({
    required this.id,
    required this.matchKey,
    required this.teamNumber,
    required this.note,
    required this.scoutedBy,
    required this.userId,
    required this.eventKey,
    required this.season,
  });

  /// Game-specific data carried by a Grove scouting report.
  Map<String, dynamic> toPayload() {
    return {
      'meta': {
        'type': 'drive_team',
        'version': 1,
        'season': season,
        'event': eventKey,
        'scoutedBy': scoutedBy,
        'userId': userId,
        'matchKey': matchKey,
      },
      'teamNumber': teamNumber,
      'note': note,
    };
  }

  /// Reconstructs a [DriveTeamNote] from a raw [ScoutingReport].
  factory DriveTeamNote.fromScoutingDocument(ScoutingReport doc) {
    final meta = doc.meta ?? {};
    final tn = doc.data['teamNumber'];
    final teamNumber = tn is int
        ? tn
        : tn is double
        ? tn.toInt()
        : tn is String
        ? int.tryParse(tn) ?? 0
        : 0;

    return DriveTeamNote(
      id: doc.id.isNotEmpty ? doc.id : null,
      matchKey: meta['matchKey']?.toString() ?? '',
      teamNumber: teamNumber,
      note: doc.data['note']?.toString() ?? '',
      scoutedBy: meta['scoutedBy']?.toString() ?? '',
      userId: meta['userId']?.toString() ?? '',
      eventKey: meta['event']?.toString() ?? '',
      season: (meta['season'] as num?)?.toInt() ?? 2026,
    );
  }
}
