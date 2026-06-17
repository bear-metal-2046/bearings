import 'dart:async';
import 'dart:convert';

import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:beariscope/pages/team_lookup/tabs/media_save_helper.dart';
import 'package:beariscope/pages/team_lookup/tabs/scouting_tab_widgets.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

class MediaTab extends ConsumerStatefulWidget {
  final int teamNumber;
  final String? teamWebsite;

  const MediaTab({super.key, required this.teamNumber, this.teamWebsite});

  @override
  ConsumerState<MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends ConsumerState<MediaTab> {
  late final ValueNotifier<String?> _activeUrlNotifier;

  @override
  void initState() {
    super.initState();
    _activeUrlNotifier = ValueNotifier<String?>(null);
  }

  @override
  void dispose() {
    _activeUrlNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(teamMediaProvider(widget.teamNumber));
    final websiteUri = _normalizeWebsiteUri(widget.teamWebsite);
    final websiteMetadataFuture = websiteUri == null
        ? null
        : WebsiteMetadataProvider.metadataForUrl(websiteUri);

    return mediaAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (media) {
        final sections = _MediaSections.fromRecords(
          media.where((record) => !record.isAvatar),
        );

        if (sections.isEmpty && websiteMetadataFuture == null) {
          return const Center(child: Text('No media recorded for this team.'));
        }

        if (sections.isEmpty && websiteMetadataFuture != null) {
          return FutureBuilder<WebsiteMetadata?>(
            future: websiteMetadataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              final metadata = snapshot.data;
              if (metadata == null) {
                return const Center(
                  child: Text('No media recorded for this team.'),
                );
              }

              return BeariscopeCardList(
                spacing: 0,
                children: [
                  _TeamWebsiteSection(uri: websiteUri!, metadata: metadata),
                ],
              );
            },
          );
        }

        return BeariscopeCardList(
          spacing: 0,
          children: [
            if (sections.photos.isNotEmpty) ...[
              const ScoutingSectionHeader(
                icon: Symbols.photo_library_rounded,
                title: 'Photos',
              ),
              const SizedBox(height: 12),
              _PhotoGrid(
                photos: sections.photos,
                activeUrlNotifier: _activeUrlNotifier,
              ),
              const SizedBox(height: 12),
            ],
            if (sections.chiefDelphiThreads.isNotEmpty) ...[
              const ScoutingSectionHeader(
                icon: Symbols.forum_rounded,
                title: 'Chief Delphi Threads',
              ),
              const SizedBox(height: 12),
              ...sections.chiefDelphiThreads.map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MediaLinkCard(record: record),
                ),
              ),
            ],
            if (sections.cadReleases.isNotEmpty) ...[
              const ScoutingSectionHeader(
                icon: Symbols.view_in_ar_rounded,
                title: 'CAD Files',
              ),
              const SizedBox(height: 12),
              ...sections.cadReleases.map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MediaLinkCard(record: record),
                ),
              ),
            ],
            if (sections.youtubeVideos.isNotEmpty) ...[
              const ScoutingSectionHeader(
                icon: Symbols.video_library_rounded,
                title: 'Videos',
              ),
              const SizedBox(height: 12),
              ...sections.youtubeVideos.map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MediaLinkCard(record: record),
                ),
              ),
            ],
            if (websiteUri != null && websiteMetadataFuture != null) ...[
              _TeamWebsiteSectionLoader(
                uri: websiteUri,
                metadataFuture: websiteMetadataFuture,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TeamWebsiteSectionLoader extends StatelessWidget {
  final Uri uri;
  final Future<WebsiteMetadata?> metadataFuture;

  const _TeamWebsiteSectionLoader({
    required this.uri,
    required this.metadataFuture,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WebsiteMetadata?>(
      future: metadataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.data == null) {
          return const SizedBox.shrink();
        }

        return _TeamWebsiteSection(uri: uri, metadata: snapshot.data!);
      },
    );
  }
}

class _TeamWebsiteSection extends StatelessWidget {
  final Uri uri;
  final WebsiteMetadata metadata;

  const _TeamWebsiteSection({required this.uri, required this.metadata});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title =
        _cleanWebsiteTitle(metadata.title) ??
        (uri.host.isNotEmpty ? uri.host : uri.toString());

    return Column(
      children: [
        const ScoutingSectionHeader(
          icon: Symbols.public_rounded,
          title: 'Team Website',
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _MediaLinkCard._openUri(context, uri),
          child: Ink(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  _WebsiteFavicon(
                    faviconUrl: metadata.faviconUrl,
                    fallbackColor: scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          uri.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.open_in_new_rounded),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _WebsiteFavicon extends StatelessWidget {
  final Uri? faviconUrl;
  final Color fallbackColor;

  const _WebsiteFavicon({
    required this.faviconUrl,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final favicon = faviconUrl;
    if (favicon == null) {
      return Icon(Symbols.public_rounded, color: fallbackColor);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 24,
        height: 24,
        child: Image.network(
          favicon.toString(),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Symbols.public_rounded, color: fallbackColor),
        ),
      ),
    );
  }
}

class _MediaSections {
  final List<TeamMediaRecord> photos;
  final List<TeamMediaRecord> chiefDelphiThreads;
  final List<TeamMediaRecord> cadReleases;
  final List<TeamMediaRecord> youtubeVideos;

  const _MediaSections({
    required this.photos,
    required this.chiefDelphiThreads,
    required this.cadReleases,
    required this.youtubeVideos,
  });

  factory _MediaSections.fromRecords(Iterable<TeamMediaRecord> records) {
    final photos = <TeamMediaRecord>[];
    final chiefDelphiThreads = <TeamMediaRecord>[];
    final cadReleases = <TeamMediaRecord>[];
    final youtubeVideos = <TeamMediaRecord>[];

    for (final record in records) {
      if (!record.hasRenderableMedia) continue;

      if (record.isPhoto && record.previewImageUrl?.isNotEmpty == true) {
        photos.add(record);
      } else if (record.isChiefDelphiThread &&
          record.openUrl?.isNotEmpty == true) {
        chiefDelphiThreads.add(record);
      } else if (record.isCadRelease && record.openUrl?.isNotEmpty == true) {
        cadReleases.add(record);
      } else if (record.isYoutubeVideo && record.openUrl?.isNotEmpty == true) {
        youtubeVideos.add(record);
      }
    }

    return _MediaSections(
      photos: photos,
      chiefDelphiThreads: chiefDelphiThreads,
      cadReleases: cadReleases,
      youtubeVideos: youtubeVideos,
    );
  }

  bool get isEmpty =>
      photos.isEmpty &&
      chiefDelphiThreads.isEmpty &&
      cadReleases.isEmpty &&
      youtubeVideos.isEmpty;
}

String? _cleanWebsiteTitle(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

class WebsiteMetadata {
  final String? title;
  final Uri? faviconUrl;

  const WebsiteMetadata({required this.title, required this.faviconUrl});
}

class WebsiteMetadataProvider {
  static final Map<String, Future<WebsiteMetadata?>> _cache = {};

  static Future<WebsiteMetadata?> metadataForUrl(Uri url) {
    return _cache.putIfAbsent(url.toString(), () => _fetchMetadata(url));
  }

  static Future<WebsiteMetadata?> _fetchMetadata(Uri url) async {
    try {
      final response = await http
          .get(
            url,
            headers: const {'Accept': 'text/html,application/xhtml+xml'},
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode < 200 || response.statusCode >= 400) {
        return null;
      }

      final body = response.body;
      return WebsiteMetadata(
        title: _extractTitle(body),
        faviconUrl: _extractFaviconUrl(body, url) ?? _fallbackFavicon(url),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _extractTitle(String html) {
    final titleMatch = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final title = _decodeHtmlEntities(titleMatch?.group(1));
    if (title != null && title.isNotEmpty) return title;

    for (final pattern in [
      r'''<meta[^>]*property=["']og:title["'][^>]*content=["'](.*?)["']''',
      r'''<meta[^>]*name=["']twitter:title["'][^>]*content=["'](.*?)["']''',
    ]) {
      final match = RegExp(
        pattern,
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html);
      final metaTitle = _decodeHtmlEntities(match?.group(1));
      if (metaTitle != null && metaTitle.isNotEmpty) return metaTitle;
    }

    return null;
  }

  static Uri? _extractFaviconUrl(String html, Uri baseUrl) {
    final linkTags = RegExp(
      r'<link\b[^>]*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html);

    for (final match in linkTags) {
      final tag = match.group(0) ?? '';
      final rel = _extractAttribute(tag, 'rel')?.toLowerCase() ?? '';
      if (!rel.contains('icon') && !rel.contains('shortcut icon')) continue;

      final href = _extractAttribute(tag, 'href');
      if (href == null || href.isEmpty) continue;

      final resolved = baseUrl.resolve(href);
      if (resolved.scheme == 'http' || resolved.scheme == 'https') {
        return resolved;
      }
    }

    return null;
  }

  static Uri _fallbackFavicon(Uri url) => url.resolve('/favicon.ico');

  static String? _extractAttribute(String tag, String attribute) {
    final match = RegExp(
      '$attribute\\s*=\\s*["\']([^"\']+)["\']',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(tag);
    return match?.group(1);
  }

  static String? _decodeHtmlEntities(String? value) {
    if (value == null) return null;

    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }
}

Uri? _normalizeWebsiteUri(String? website) {
  final value = website?.trim();
  if (value == null || value.isEmpty) return null;

  final parsed = Uri.tryParse(value);
  if (parsed == null) return null;

  if (parsed.hasScheme) return parsed;

  return Uri.tryParse('https://$value');
}

class _PhotoGrid extends StatelessWidget {
  final List<TeamMediaRecord> photos;
  final ValueNotifier<String?> activeUrlNotifier;

  const _PhotoGrid({required this.photos, required this.activeUrlNotifier});

  @override
  Widget build(BuildContext context) {
    final urls = photos.map((e) => e.previewImageUrl!).toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final url = urls[index];

        return ValueListenableBuilder<String?>(
          valueListenable: activeUrlNotifier,
          builder: (context, activeUrl, _) {
            final isViewerOpen = activeUrl != null;
            final isViewingThis = activeUrl == url;
            final shouldBeHero = !isViewerOpen || isViewingThis;

            Widget imageContent = ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _NetworkImageWithSkeleton(url: url, fit: BoxFit.cover),
            );

            if (shouldBeHero) {
              imageContent = Hero(tag: url, child: imageContent);
            }

            return GestureDetector(
              onTap: () async {
                activeUrlNotifier.value = url;
                await Navigator.of(context, rootNavigator: true).push(
                  PageRouteBuilder(
                    opaque: false,
                    transitionDuration: const Duration(milliseconds: 300),
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        _FullscreenImageViewer(
                          urls: urls,
                          initialIndex: index,
                          activeUrlNotifier: activeUrlNotifier,
                        ),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) =>
                            FadeTransition(opacity: animation, child: child),
                  ),
                );
                activeUrlNotifier.value = null;
              },
              child: Opacity(
                opacity: isViewingThis ? 0.0 : 1.0,
                child: imageContent,
              ),
            );
          },
        );
      },
    );
  }
}

class _MediaLinkCard extends StatelessWidget {
  final TeamMediaRecord record;

  const _MediaLinkCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final openUrl = record.openUrl;

    final subtitleText = switch (record.type) {
      'cd-thread' => 'Chief Delphi Thread',
      'onshape' => 'Onshape CAD File',
      'youtube' => 'YouTube Video',
      _ => record.type,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: openUrl == null ? null : () => _openUrl(context, openUrl),
      child: Ink(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Faded Background Image Layer
              if (record.previewImageUrl != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.3,
                    child: _NetworkImageWithSkeleton(
                      url: record.previewImageUrl!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              // Content Layer
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTitle(context),
                          const SizedBox(height: 4),
                          Text(
                            subtitleText,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (openUrl != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.open_in_new_rounded),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);

    final fallback = switch (record.type) {
      'cd-thread' => 'Chief Delphi thread',
      'onshape' => 'CAD release',
      'youtube' => 'YouTube video',
      _ => 'Media item',
    };

    final defaultTitle = record.title ?? fallback;

    if (record.type == 'youtube' && record.openUrl != null) {
      return FutureBuilder<String?>(
        future: YoutubeTitleProvider.titleForUrl(record.openUrl!),
        builder: (context, snapshot) {
          final resolved = snapshot.data?.trim();
          final displayTitle = (resolved != null && resolved.isNotEmpty)
              ? resolved
              : defaultTitle;

          return Text(
            displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        },
      );
    }

    return Text(
      defaultTitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open media link')),
        );
      }
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open media link')),
      );
    }
  }

  static Future<void> _openUri(BuildContext context, Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open website')));
    }
  }
}

class YoutubeTitleProvider {
  static final Map<String, Future<String?>> _cache = {};

  static Future<String?> titleForUrl(String url) {
    return _cache.putIfAbsent(url, () => _fetchTitle(url));
  }

  static Future<String?> _fetchTitle(String url) async {
    final videoId = _extractVideoId(url);
    if (videoId == null) return null;

    final response = await http.get(
      Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json',
      ),
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    if (json is Map<String, dynamic>) {
      return json['title']?.toString().trim();
    }
    return null;
  }

  static String? _extractVideoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }

    final videoId = uri.queryParameters['v'];
    if (videoId != null && videoId.isNotEmpty) return videoId;

    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments.first == 'shorts') {
      return segments[1];
    }

    return null;
  }
}

class _FullscreenImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final ValueNotifier<String?> activeUrlNotifier;

  const _FullscreenImageViewer({
    required this.urls,
    required this.initialIndex,
    required this.activeUrlNotifier,
  });

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late final FocusNode _keyboardFocusNode;
  late int _currentIndex;
  double _dragOffset = 0;
  double _currentScale = 1.0;

  late final AnimationController _snapController;
  late Animation<double> _snapAnimation;

  static const double _dismissScaleThreshold = 1.02;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _keyboardFocusNode = FocusNode(
      debugLabel: 'FullscreenImageViewerKeyboardFocus',
    );

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _snapAnimation = const AlwaysStoppedAnimation(0);
    _snapController.addListener(() {
      setState(() {
        _dragOffset = _snapAnimation.value;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_keyboardFocusNode.hasFocus) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _snapController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goToPreviousImage() {
    if (_currentIndex <= 0) return;
    _pageController.animateToPage(
      _currentIndex - 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToNextImage() {
    if (_currentIndex >= widget.urls.length - 1) return;
    _pageController.animateToPage(
      _currentIndex + 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _handleKeyboard(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (_currentScale > _dismissScaleThreshold) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goToPreviousImage();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goToNextImage();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_snapController.isAnimating) _snapController.stop();
    setState(() => _dragOffset += details.delta.dy);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 100 ||
        (details.primaryVelocity?.abs() ?? 0) > 500) {
      Navigator.of(context).pop();
    } else {
      _animateDragOffsetToZero();
    }
  }

  void _animateDragOffsetToZero() {
    _snapAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController.forward(from: 0);
  }

  void _handleScaleChanged(double scale) {
    if (_currentScale == scale) return;
    setState(() => _currentScale = scale);
  }

  void _handleVerticalOverscroll(double delta) {
    if (_snapController.isAnimating) _snapController.stop();
    setState(() => _dragOffset += delta);
  }

  void _handleHorizontalOverscroll(double delta) {
    if (_pageController.hasClients) {
      _pageController.position.jumpTo(_pageController.position.pixels - delta);
    }
  }

  void _handleOverscrollEnd(Offset velocity) {
    if (_dragOffset.abs() > 0) {
      if (_dragOffset.abs() > 100 || velocity.dy.abs() > 500) {
        Navigator.of(context).pop();
      } else {
        _animateDragOffsetToZero();
      }
    }

    if (_pageController.hasClients) {
      final double currentPage =
          _pageController.page ?? _currentIndex.toDouble();
      int targetPage = currentPage.round();

      if (velocity.dx < -500 && currentPage < widget.urls.length - 1) {
        targetPage = currentPage.ceil();
      } else if (velocity.dx > 500 && currentPage > 0) {
        targetPage = currentPage.floor();
      } else {
        if (currentPage > _currentIndex + 0.2) {
          targetPage = _currentIndex + 1;
        } else if (currentPage < _currentIndex - 0.2) {
          targetPage = _currentIndex - 1;
        }
      }

      targetPage = targetPage.clamp(0, widget.urls.length - 1);

      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dragFraction = (_dragOffset.abs() / 300).clamp(0.0, 1.0);
    final backgroundOpacity = 1.0 - dragFraction;
    final scale = 1.0 - (dragFraction * 0.15);
    final canDismiss = _currentScale <= _dismissScaleThreshold;

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyboard,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: backgroundOpacity),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white.withValues(alpha: backgroundOpacity),
          elevation: 0,
          centerTitle: true,
          title: Text(
            '${_currentIndex + 1} / ${widget.urls.length}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: backgroundOpacity),
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'share') {
                  await _shareCurrentImage(widget.urls[_currentIndex]);
                } else if (value == 'open') {
                  final uri = Uri.parse(widget.urls[_currentIndex]);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open image')),
                      );
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: const [
                      Icon(Icons.ios_share_rounded),
                      SizedBox(width: 12),
                      Text('Share'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'open',
                  child: Row(
                    children: const [
                      Icon(Icons.open_in_new_rounded),
                      SizedBox(width: 12),
                      Text('Open in Browser'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: canDismiss ? _handleDragUpdate : null,
          onVerticalDragEnd: canDismiss ? _handleDragEnd : null,
          child: Transform.scale(
            scale: scale,
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: PageView.builder(
                controller: _pageController,
                physics: canDismiss
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: widget.urls.length,
                onPageChanged: (i) {
                  setState(() {
                    _currentIndex = i;
                    _dragOffset = 0;
                    _currentScale = 1.0;
                  });
                  widget.activeUrlNotifier.value = widget.urls[i];
                },
                itemBuilder: (context, index) {
                  final url = widget.urls[index];
                  final image = _NetworkImageWithSkeleton(
                    url: url,
                    fit: BoxFit.contain,
                  );

                  return _ZoomablePhotoPage(
                    url: url,
                    image: image,
                    isCurrent: index == _currentIndex,
                    onScaleChanged: index == _currentIndex
                        ? _handleScaleChanged
                        : null,
                    onVerticalOverscroll: index == _currentIndex
                        ? _handleVerticalOverscroll
                        : null,
                    onHorizontalOverscroll: index == _currentIndex
                        ? _handleHorizontalOverscroll
                        : null,
                    onOverscrollEnd: index == _currentIndex
                        ? _handleOverscrollEnd
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareCurrentImage(String url) async {
    final imgurId = url.split('/').last.split('.').first;
    final filename = '$imgurId.jpg';
    final bytes = await _fetchImageBytes(url);
    if (!mounted) return;
    await shareOrSaveImage(context, bytes, filename);
  }

  Future<Uint8List> _fetchImageBytes(String url) async {
    final bundle = NetworkAssetBundle(Uri.parse(url));
    final data = await bundle.load(url);
    return data.buffer.asUint8List();
  }
}

class _ZoomablePhotoPage extends StatefulWidget {
  final String url;
  final Widget image;
  final bool isCurrent;
  final ValueChanged<double>? onScaleChanged;
  final ValueChanged<double>? onVerticalOverscroll;
  final ValueChanged<double>? onHorizontalOverscroll;
  final ValueChanged<Offset>? onOverscrollEnd;

  const _ZoomablePhotoPage({
    required this.url,
    required this.image,
    required this.isCurrent,
    this.onScaleChanged,
    this.onVerticalOverscroll,
    this.onHorizontalOverscroll,
    this.onOverscrollEnd,
  });

  @override
  State<_ZoomablePhotoPage> createState() => _ZoomablePhotoPageState();
}

class _ZoomablePhotoPageState extends State<_ZoomablePhotoPage> {
  late final TransformationController _controller;
  double _lastScale = 1.0;
  Matrix4 _previousMatrix = Matrix4.identity();
  Axis? _overscrollAxis;
  Timer? _scrollEndTimer;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
  }

  @override
  void dispose() {
    _scrollEndTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    _previousMatrix = _controller.value.clone();
    _overscrollAxis = null;
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    final scale = _controller.value.getMaxScaleOnAxis();
    if ((scale - _lastScale).abs() >= 0.001) {
      _lastScale = scale;
      widget.onScaleChanged?.call(scale);
    }

    if (details.scale != 1.0 || scale <= 1.0) {
      _previousMatrix = _controller.value.clone();
      return;
    }

    _processDeltaBridge(details.focalPointDelta);
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    final scale = _controller.value.getMaxScaleOnAxis();
    if (scale <= 1.01) {
      _controller.value = Matrix4.identity();
      _lastScale = 1.0;
      widget.onScaleChanged?.call(1.0);
    }

    if (_overscrollAxis != null) {
      widget.onOverscrollEnd?.call(details.velocity.pixelsPerSecond);
      _overscrollAxis = null;
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final scale = _controller.value.getMaxScaleOnAxis();
      if (scale <= 1.0) return;

      final trackpadFocalDelta = Offset(
        -event.scrollDelta.dx,
        -event.scrollDelta.dy,
      );
      _processDeltaBridge(trackpadFocalDelta);

      _scrollEndTimer?.cancel();
      _scrollEndTimer = Timer(const Duration(milliseconds: 150), () {
        if (_overscrollAxis != null) {
          widget.onOverscrollEnd?.call(Offset.zero);
          _overscrollAxis = null;
        }
      });
    }
  }

  void _processDeltaBridge(Offset fingerDelta) {
    final currentMatrix = _controller.value;
    final double dx = currentMatrix.row0[3] - _previousMatrix.row0[3];
    final double dy = currentMatrix.row1[3] - _previousMatrix.row1[3];

    if (_overscrollAxis == null) {
      final hitX = fingerDelta.dx.abs() > 0.5 && dx.abs() < 0.1;
      final hitY = fingerDelta.dy.abs() > 0.5 && dy.abs() < 0.1;

      if (hitX && hitY) {
        _overscrollAxis = fingerDelta.dx.abs() > fingerDelta.dy.abs()
            ? Axis.horizontal
            : Axis.vertical;
      } else if (hitX) {
        _overscrollAxis = Axis.horizontal;
      } else if (hitY) {
        _overscrollAxis = Axis.vertical;
      }
    }

    if (_overscrollAxis == Axis.vertical &&
        fingerDelta.dy.abs() > 0.5 &&
        dy.abs() < 0.1) {
      widget.onVerticalOverscroll?.call(fingerDelta.dy);
    } else if (_overscrollAxis == Axis.horizontal &&
        fingerDelta.dx.abs() > 0.5 &&
        dx.abs() < 0.1) {
      widget.onHorizontalOverscroll?.call(fingerDelta.dx);
    }

    _previousMatrix = currentMatrix.clone();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: Center(
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1.0,
          maxScale: 5.0,
          panEnabled: widget.isCurrent,
          scaleEnabled: true,
          clipBehavior: Clip.none,
          onInteractionStart: _handleInteractionStart,
          onInteractionUpdate: _handleInteractionUpdate,
          onInteractionEnd: _handleInteractionEnd,
          child: widget.isCurrent
              ? Hero(tag: widget.url, child: widget.image)
              : widget.image,
        ),
      ),
    );
  }
}

class _NetworkImageWithSkeleton extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const _NetworkImageWithSkeleton({required this.url, required this.fit});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const _PulseSkeleton();
      },
      errorBuilder: (context, error, stackTrace) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PulseSkeleton extends StatefulWidget {
  const _PulseSkeleton();

  @override
  State<_PulseSkeleton> createState() => _PulseSkeletonState();
}

class _PulseSkeletonState extends State<_PulseSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5 + (_controller.value * 0.2),
        ),
      ),
    );
  }
}
