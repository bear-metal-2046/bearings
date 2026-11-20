import 'package:beariscope/utils/competition_media_display.dart';
import 'package:core/core.dart' show CompetitionMedia;

/// Returns a photo rather than a team avatar, video thumbnail, or CAD preview.
String? flashCardPhoto(List<CompetitionMedia> records) {
  final photos = records.where(
    (record) => record.isPhoto && record.previewImageUrl != null,
  );
  for (final photo in photos) {
    if (photo.preferred) return photo.previewImageUrl;
  }
  return photos.firstOrNull?.previewImageUrl;
}
