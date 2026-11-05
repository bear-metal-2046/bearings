import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

bool isYoutubeVideoId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value);

Uri youtubeVideoUri(String videoId) =>
    Uri.https('www.youtube.com', '/watch', {'v': videoId});

String? youtubeVideoIdFromUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments;
  final String? id;
  if (host == 'youtu.be') {
    id = segments.firstOrNull;
  } else if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
    id =
        uri.queryParameters['v'] ??
        (segments.length >= 2 &&
                ['shorts', 'embed', 'live'].contains(segments.first)
            ? segments[1]
            : null);
  } else {
    return null;
  }
  return id != null && isYoutubeVideoId(id) ? id : null;
}

class YoutubeVideoMetadata {
  const YoutubeVideoMetadata({this.title, this.channelName});

  final String? title;
  final String? channelName;

  factory YoutubeVideoMetadata.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return YoutubeVideoMetadata(
      title: text('title'),
      channelName: text('author_name'),
    );
  }
}

final youtubeMetadataClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Share successful lookups between match videos and team media. Failed
/// requests can retry when the video is next displayed.
final youtubeVideoMetadataProvider = FutureProvider.autoDispose
    .family<YoutubeVideoMetadata?, String>((ref, videoId) async {
      if (!isYoutubeVideoId(videoId)) return null;
      final client = ref.watch(youtubeMetadataClientProvider);
      try {
        final response = await client
            .get(
              Uri.https('www.youtube.com', '/oembed', {
                'url': youtubeVideoUri(videoId).toString(),
                'format': 'json',
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return null;
        final json = jsonDecode(response.body);
        if (json is! Map<String, dynamic>) return null;
        final metadata = YoutubeVideoMetadata.fromJson(json);
        if (ref.mounted &&
            (metadata.title != null || metadata.channelName != null)) {
          ref.keepAlive();
        }
        return metadata;
      } catch (_) {
        return null;
      }
    });
