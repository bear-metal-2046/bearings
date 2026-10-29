import 'package:beariscope/models/tba_match_score.dart';
import 'package:beariscope/providers/youtube_video_metadata_provider.dart';
import 'package:beariscope/widgets/beariscope_modal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

final matchVideoLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Playable videos in source order, without duplicate or malformed links.
List<TbaMatchVideo> matchVideosForMatch(Map<String, dynamic>? match) {
  final entries = match?['videos'];
  if (entries is! List) return const [];
  final ids = <String>{};
  return [
    for (final entry in entries)
      if (entry is Map && entry['type'] == 'youtube')
        if (entry['key'] case final String key)
          if (isYoutubeVideoId(key.trim()) && ids.add(key.trim()))
            TbaMatchVideo(key: key.trim(), type: 'youtube'),
  ];
}

/// Opens a single video directly or lets the user choose between multiple
/// videos. Matches without playable videos do not open anything.
Future<void> openMatchVideo(
  BuildContext context, {
  required Map<String, dynamic>? match,
  String? matchTitle,
}) async {
  final videos = matchVideosForMatch(match);
  if (videos.isEmpty) return;
  final launchVideo = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(matchVideoLauncherProvider);

  Future<bool> open(TbaMatchVideo video) async {
    try {
      return await launchVideo(youtubeVideoUri(video.key));
    } catch (_) {
      // Keep the picker available if the operating system cannot open a link.
      return false;
    }
  }

  if (videos.length == 1) {
    final opened = await open(videos.single);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open match video.')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await BeariscopeModal.show<void>(
    context,
    builder: (_) =>
        _MatchVideoPicker(videos: videos, matchTitle: matchTitle, open: open),
  );
}

class _MatchVideoPicker extends StatefulWidget {
  const _MatchVideoPicker({
    required this.videos,
    required this.matchTitle,
    required this.open,
  });

  final List<TbaMatchVideo> videos;
  final String? matchTitle;
  final Future<bool> Function(TbaMatchVideo) open;

  @override
  State<_MatchVideoPicker> createState() => _MatchVideoPickerState();
}

class _MatchVideoPickerState extends State<_MatchVideoPicker> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _select(TbaMatchVideo video) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    final opened = await widget.open(video);
    if (!mounted) return;
    if (opened) {
      BeariscopeModal.complete(context);
    } else {
      setState(() {
        _opening = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => BeariscopeModal(
    title: 'Watch match video',
    actions: const [],
    canDismiss: !_opening,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.matchTitle case final String title) ...[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
        ],
        if (_failed) ...[
          Text(
            'Could not open match video. Try again.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        for (final (index, video) in widget.videos.indexed) ...[
          if (index > 0) const SizedBox(height: 12),
          _MatchVideoTile(
            video: video,
            onTap: _opening ? null : () => _select(video),
          ),
        ],
        const SizedBox(height: 4),
      ],
    ),
  );
}

class _MatchVideoTile extends ConsumerWidget {
  const _MatchVideoTile({required this.video, required this.onTap});

  final TbaMatchVideo video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(youtubeVideoMetadataProvider(video.key));
    final details = metadata.asData?.value;
    final theme = Theme.of(context);
    final thumbnail = AspectRatio(
      aspectRatio: 16 / 9,
      child: Image.network(
        'https://i.ytimg.com/vi/${video.key}/mqdefault.jpg',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(LucideIcons.video)),
        ),
      ),
    );
    final label = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            details?.title ??
                (metadata.isLoading
                    ? 'Loading video details…'
                    : 'YouTube video ${video.key}'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            details?.channelName ??
                (metadata.isLoading ? 'YouTube' : 'Channel unavailable'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('match-video-${video.key}'),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 400
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [thumbnail, label],
                )
              : Row(
                  children: [
                    SizedBox(width: 160, child: thumbnail),
                    Expanded(child: label),
                  ],
                ),
        ),
      ),
    );
  }
}
