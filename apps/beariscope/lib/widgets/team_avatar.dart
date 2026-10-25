import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:flutter/widgets.dart';

/// Embedded avatars match the team card's source and avoid a network request.
/// Within each source type, preferred avatars come first; URLs are fallbacks.
List<ImageProvider> teamAvatarImages(
  List<TeamMediaRecord> records,
  String teamKey,
) {
  final avatars = records.where(
    (record) => record.isAvatar && record.teamKeys.contains(teamKey),
  );
  final ordered = [
    ...avatars.where((record) => record.preferred),
    ...avatars.where((record) => !record.preferred),
  ];
  return [
    for (final avatar in ordered)
      if (avatar.base64Image?.isNotEmpty == true)
        MemoryImage(avatar.base64Image!),
    for (final avatar in ordered)
      if (avatar.previewImageUrl?.isNotEmpty == true)
        NetworkImage(avatar.previewImageUrl!),
  ];
}

/// Tries the next avatar when a stored image or URL cannot be decoded/loaded.
class TeamAvatarImage extends StatelessWidget {
  const TeamAvatarImage({
    super.key,
    required this.images,
    required this.width,
    required this.height,
    this.loadedBuilder,
    this.fallbackBuilder,
  });

  final List<ImageProvider> images;
  final double width;
  final double height;
  final Widget Function(BuildContext, Widget, ImageProvider)? loadedBuilder;
  final WidgetBuilder? fallbackBuilder;

  @override
  Widget build(BuildContext context) => _image(context, 0);

  Widget _image(BuildContext context, int index) {
    if (index == images.length) {
      return fallbackBuilder?.call(context) ?? const SizedBox.shrink();
    }
    return Image(
      key: ValueKey(images[index]),
      image: images[index],
      width: width,
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      frameBuilder: loadedBuilder == null
          ? null
          : (context, child, frame, _) => frame == null
                ? const SizedBox.shrink()
                : loadedBuilder!(context, child, images[index]),
      errorBuilder: (context, _, _) => _image(context, index + 1),
    );
  }
}
