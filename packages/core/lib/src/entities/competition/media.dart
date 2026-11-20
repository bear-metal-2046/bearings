part of 'competition_entities.dart';

@GroveValue()
class MediaDetails {
  const MediaDetails({
    this.avatarBase64,
    this.modelCreated,
    this.modelDescription,
    this.modelImage,
    this.modelName,
    this.title,
    this.caption,
    this.webUri,
    this.imageUrl,
    this.mediumImageUrl,
    this.smallImageUrl,
    this.imagePartial,
    this.coverUrl,
    this.mediumCoverUrl,
    this.smallCoverUrl,
    this.imageCount,
    this.threadTitle,
  });

  final String? avatarBase64;
  final DateTime? modelCreated;
  final String? modelDescription;
  final String? modelImage;
  final String? modelName;
  final String? title;
  final String? caption;
  final String? webUri;
  final String? imageUrl;
  final String? mediumImageUrl;
  final String? smallImageUrl;
  final String? imagePartial;
  final String? coverUrl;
  final String? mediumCoverUrl;
  final String? smallCoverUrl;
  final int? imageCount;
  final String? threadTitle;
}

@GroveEntity('media', version: 1, serverManaged: true)
class CompetitionMedia {
  const CompetitionMedia({
    required this.id,
    this.season,
    this.event,
    this.team,
    this.teams = const [],
    required this.rosterMedia,
    this.tag,
    required this.type,
    required this.foreignKey,
    required this.preferred,
    this.directUrl,
    this.viewUrl,
    required this.details,
  });

  final String id;
  final int? season;
  final EntityRef<CompetitionEvent>? event;
  final EntityRef<CompetitionTeam>? team;
  final List<EntityRef<CompetitionTeam>> teams;
  final bool rosterMedia;
  final String? tag;
  final String type;
  final String foreignKey;
  final bool preferred;
  final String? directUrl;
  final String? viewUrl;
  final MediaDetails details;
}

@GroveEntity('media_tag', version: 1, serverManaged: true)
class MediaTag {
  const MediaTag({required this.id, required this.name});

  final String id;
  final String name;
}
