import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart' show CompetitionMedia;

final _decodedAvatars = Expando<Uint8List>();

extension CompetitionMediaDisplay on CompetitionMedia {
  bool includesTeam(String teamKey) => teams.any((team) => team.id == teamKey);

  bool get isAvatar => type == 'avatar';
  bool get isPhoto => type == 'imgur';
  bool get isChiefDelphiThread => type == 'cd-thread';
  bool get isCadRelease => type == 'onshape';
  bool get isYoutubeVideo => type == 'youtube';

  bool get hasRenderableMedia =>
      isPhoto || isChiefDelphiThread || isCadRelease || isYoutubeVideo;

  String? get title => switch (type) {
    'cd-thread' => _nonEmpty(details.threadTitle),
    'onshape' => _nonEmpty(details.modelName),
    'youtube' => _nonEmpty(details.title),
    _ => null,
  };

  String? get previewImageUrl {
    final preview = switch (type) {
      'cd-thread' => details.imageUrl,
      'onshape' => details.modelImage,
      _ => null,
    };
    return _nonEmpty(preview) ?? _nonEmpty(directUrl);
  }

  String? get openUrl => _nonEmpty(viewUrl) ?? _nonEmpty(directUrl);

  Uint8List? get avatarBytes {
    final encoded = _nonEmpty(details.avatarBase64);
    if (encoded == null) return null;

    try {
      return _decodedAvatars[details] ??= base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
