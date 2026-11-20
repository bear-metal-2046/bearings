import 'package:services/providers/grove_provider.dart';
import 'package:grove/grove.dart';
import 'package:beariscope/models/drive_team_note.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final myDriveTeamNotesProvider = Provider.autoDispose
    .family<AsyncValue<Map<int, DriveTeamNote>>, String>(
      (ref, matchKey) => ref.watch(groveSubjectProvider).flatMap((subject) {
        if (subject == null) return const AsyncData({});
        return watchScoutingReports(
          ref,
          'drive_team',
          matchKey: matchKey,
          subject: subject,
        ).whenData((reports) {
          final notes = reports.map(DriveTeamNote.fromScoutingDocument);
          return {for (final note in notes) note.teamNumber: note};
        });
      }),
    );
