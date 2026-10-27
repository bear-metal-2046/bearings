import 'package:beariscope/pages/team_lookup/team_providers.dart';

/// Returns a photo rather than a team avatar, video thumbnail, or CAD preview.
String? flashCardPhoto(List<TeamMediaRecord> records, String teamKey) {
  final photos = records.where(
    (record) =>
        record.teamKeys.contains(teamKey) &&
        record.isPhoto &&
        record.previewImageUrl?.isNotEmpty == true,
  );
  for (final photo in photos) {
    if (photo.preferred) return photo.previewImageUrl;
  }
  return photos.firstOrNull?.previewImageUrl;
}
