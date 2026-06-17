import 'dart:convert';
import 'dart:typed_data';

import 'package:beariscope/providers/current_event_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';

final searchControllerProvider = Provider((ref) => TextEditingController());
final searchFocusNodeProvider = Provider((ref) => FocusNode());

class TeamSort {
  TeamSortOptions sort = TeamSortOptions.teamNumber;
  bool isAscending = true;

  TeamSort(this.sort, this.isAscending);
}

enum TeamSortOptions { teamNumber, rank, custom, defense, noShow, brokeDown }

extension TeamSortLabel on TeamSortOptions {
  String get label => switch (this) {
    TeamSortOptions.teamNumber => 'Team #',
    TeamSortOptions.rank => 'Rank',
    TeamSortOptions.custom => 'Total #',
    TeamSortOptions.defense => 'Played Defense',
    TeamSortOptions.noShow => 'No Shows',
    TeamSortOptions.brokeDown => 'Breakdowns',
  };
}

class TeamSortNotifier extends Notifier<TeamSort> {
  @override
  TeamSort build() => TeamSort(TeamSortOptions.teamNumber, true);

  void setSort(TeamSortOptions sort, bool isAscending) =>
      state = TeamSort(sort, isAscending);

  TeamSortOptions getSort() => state.sort;

  bool getIsAscending() => state.isAscending;
}

final teamSortProvider = NotifierProvider<TeamSortNotifier, TeamSort>(
  () => TeamSortNotifier(),
);

List<Map<String, dynamic>> _toStringKeyMaps(List<dynamic> data) {
  return data
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Uint8List? _decodeBase64Image(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  try {
    return Uint8List.fromList(base64Decode(trimmed));
  } on FormatException {
    return null;
  }
}

final teamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final selectedEvent = ref.watch(currentEventProvider);
  final client = ref.watch(honeycombClientProvider);

  final teamData = await client.get<List<dynamic>>(
    '/teams',
    queryParams: {'event': selectedEvent},
    cachePolicy: CachePolicy.networkFirst,
  );

  return _toStringKeyMaps(teamData);
});

class TeamMediaRecord {
  final String foreignKey;
  final String type;
  final bool preferred;
  final List<String> teamKeys;
  final Map<String, dynamic> details;
  final String? directUrl;
  final String? viewUrl;
  final Uint8List? base64Image;

  const TeamMediaRecord({
    required this.foreignKey,
    required this.type,
    required this.preferred,
    required this.teamKeys,
    required this.details,
    required this.directUrl,
    required this.viewUrl,
    required this.base64Image,
  });

  factory TeamMediaRecord.fromJson(Map<String, dynamic> json) {
    final details = json['details'];
    final detailsMap = details is Map
        ? Map<String, dynamic>.from(details)
        : const <String, dynamic>{};
    final teamKeys = (json['team_keys'] as List<dynamic>? ?? const [])
        .map((teamKey) => teamKey.toString())
        .where((teamKey) => teamKey.isNotEmpty)
        .toList();

    return TeamMediaRecord(
      foreignKey: json['foreign_key']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      preferred: json['preferred'] == true,
      teamKeys: teamKeys,
      details: detailsMap,
      directUrl: _cleanString(json['direct_url']),
      viewUrl: _cleanString(json['view_url']),
      base64Image: _decodeBase64Image(detailsMap['base64Image']?.toString()),
    );
  }

  static String? _cleanString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  bool get isAvatar => type == 'avatar';

  bool get isPhoto => type == 'imgur' || type == 'instagram-image';

  bool get isChiefDelphiThread => type == 'cd-thread';

  bool get isCadRelease => type == 'onshape';

  bool get isYoutubeVideo => type == 'youtube';

  bool get hasRenderableMedia =>
      isPhoto || isChiefDelphiThread || isCadRelease || isYoutubeVideo;

  String? get title => switch (type) {
    'cd-thread' => _cleanString(details['thread_title']),
    'onshape' => _cleanString(details['model_name']),
    'youtube' =>
      _cleanString(details['title']) ??
          _cleanString(details['video_title']) ??
          _cleanString(details['name']),
    _ => null,
  };

  String? get previewImageUrl => switch (type) {
    'cd-thread' => _cleanString(details['image_url']) ?? directUrl,
    'onshape' => _cleanString(details['model_image']) ?? directUrl,
    'youtube' => directUrl,
    'imgur' => directUrl,
    _ => directUrl,
  };

  String? get openUrl => viewUrl ?? directUrl;
}

final eventTeamMediaProvider = FutureProvider<List<TeamMediaRecord>>((
  ref,
) async {
  final selectedEvent = ref.watch(currentEventProvider);
  final client = ref.watch(honeycombClientProvider);

  final response = await client.get<List<dynamic>>(
    '/event/$selectedEvent/team_media',
    cachePolicy: CachePolicy.networkFirst,
  );

  return response
      .whereType<Map>()
      .map((item) => TeamMediaRecord.fromJson(Map<String, dynamic>.from(item)))
      .toList();
});

final teamMediaProvider = FutureProvider.family<List<TeamMediaRecord>, int>((
  ref,
  teamNumber,
) async {
  final records = await ref.watch(eventTeamMediaProvider.future);
  final teamKey = 'frc$teamNumber';
  return records.where((record) => record.teamKeys.contains(teamKey)).toList();
});
