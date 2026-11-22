import 'package:beariscope/pages/gamepacks/match_observations_page.dart';
import 'package:beariscope/utils/match_video_opener.dart';
import 'package:beariscope/providers/match_preview_layout_provider.dart';
import 'package:core/core.dart'
    show
        CompetitionMatch,
        GamePackFormKind,
        gamePackReadPermission,
        gamePackSubmitPermission;
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/widgets/team_card.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/ui.dart';
import 'package:url_launcher/url_launcher.dart';

enum _TeamAction {
  switchLayout,
  copyStrategyMessage,
  openTba,
  openStatbotics,
  openYouTube,
}

final matchProvider = Provider.autoDispose
    .family<AsyncValue<CompetitionMatch>, String>(
      (ref, matchKey) => ref
          .watch(competitionMatchProvider(matchKey))
          .whenData(
            (match) =>
                match ?? (throw StateError('Match $matchKey was not found')),
          ),
    );

class MatchPreviewPage extends ConsumerStatefulWidget {
  final String matchKey;

  const MatchPreviewPage({super.key, required this.matchKey});

  @override
  ConsumerState<MatchPreviewPage> createState() => _MatchPreviewPageState();
}

class _MatchPreviewPageState extends ConsumerState<MatchPreviewPage> {
  final ValueNotifier<double> _currentPageNotifier = ValueNotifier(0.0);
  PageController? _pageController;

  @override
  void dispose() {
    _pageController?.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  void _updatePageController(double fraction, int initialPage) {
    if (_pageController != null &&
        (_pageController!.viewportFraction - fraction).abs() < 0.001) {
      return;
    }
    _pageController?.dispose();
    _pageController = PageController(
      initialPage: initialPage,
      viewportFraction: fraction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final requestProvider = matchProvider(widget.matchKey);
    final matchAsync = ref.watch(requestProvider);
    final permissionChecker = ref.watch(permissionCheckerProvider);
    final matchPreviewLayout = ref.watch(matchPreviewLayoutProvider);
    final scrollVertical = matchPreviewLayout == MatchPreviewLayout.vertical;

    return matchAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text('Match ${widget.matchKey}')),
        body: const Center(child: BearingsSpinner()),
      ),
      error: (err, stack) => Scaffold(
        appBar: AppBar(title: Text('Match ${widget.matchKey}')),
        body: BearingsStatusView(
          icon: LucideIcons.circleAlert,
          iconColor: Theme.of(context).colorScheme.error,
          title: 'Match unavailable',
          subtitle: 'Error loading match data: $err',
          action: FilledButton.icon(
            onPressed: () => retryCompetitionMatch(
              ProviderScope.containerOf(context, listen: false),
              widget.matchKey,
            ),
            icon: const Icon(LucideIcons.rotateCw),
            label: const Text('Retry'),
          ),
        ),
      ),
      data: (match) {
        final assignment =
            permissionChecker?.hasPermission(gamePackReadPermission) == true
            ? ref.watch(eventGamePackProvider(match.event.id)).value
            : null;
        final capture = assignment;
        final canAddObservation =
            capture?.definition.formFor(GamePackFormKind.observation) != null &&
            permissionChecker?.hasPermission(gamePackSubmitPermission) == true;
        final wideLayout = MediaQuery.sizeOf(context).width > 1100;

        final redTeams = <String>[
          for (final team in match.red?.teams ?? []) team.id,
        ];
        final blueTeams = <String>[
          for (final team in match.blue?.teams ?? []) team.id,
        ];
        final cards = <({String teamKey, Color color})>[
          ...redTeams.map((teamKey) => (teamKey: teamKey, color: Colors.red)),
          ...blueTeams.map((teamKey) => (teamKey: teamKey, color: Colors.blue)),
        ];
        final compLevel = match.level;
        final number = compLevel == 'sf' ? match.setNumber : match.matchNumber;
        final matchTitle = compLevel.isEmpty || number <= 0
            ? 'Match ${widget.matchKey}'
            : '${switch (compLevel) {
                'qm' => 'Qualification Match',
                'sf' => 'Semifinal Match',
                'f' => 'Final Match',
                _ => compLevel.toUpperCase(),
              }} $number';
        void addObservation() {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => GamePackMatchObservationsPage(
                match: match,
                release: capture!,
              ),
            ),
          );
        }

        Future<void> handleAction(
          BuildContext context,
          _TeamAction action,
        ) async {
          switch (action) {
            case _TeamAction.switchLayout:
              final nextLayout = scrollVertical
                  ? MatchPreviewLayout.horizontal
                  : MatchPreviewLayout.vertical;
              ref
                  .read(matchPreviewLayoutProvider.notifier)
                  .setLayout(nextLayout);
            case _TeamAction.copyStrategyMessage:
              final message = matchStrategyMessage(
                matchLabel: compLevel == 'qm' && number > 0
                    ? 'Match $number'
                    : matchTitle,
                redTeams: redTeams,
                blueTeams: blueTeams,
              );
              try {
                await Clipboard.setData(ClipboardData(text: message));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Match strategy message copied'),
                  ),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to copy message')),
                );
              }
            case _TeamAction.openTba:
              launchUrl(
                ref.tbaWebsiteUri('/match/${widget.matchKey}'),
                mode: LaunchMode.externalApplication,
              );
            case _TeamAction.openStatbotics:
              launchUrl(
                Uri.parse('https://www.statbotics.io/match/${widget.matchKey}'),
                mode: LaunchMode.externalApplication,
              );
            case _TeamAction.openYouTube:
              openMatchVideo(context, match: match, matchTitle: matchTitle);
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(matchTitle),
            actions: [
              if (wideLayout && canAddObservation)
                IconButton(
                  icon: const Icon(LucideIcons.messageSquarePlus),
                  tooltip: 'Add observation',
                  onPressed: addObservation,
                ),
              BearingsPopupMenu.overflow(
                tooltip: 'More options',
                menuChildren: [
                  if (!wideLayout) ...[
                    BearingsMenuItem(
                      onPressed: () =>
                          handleAction(context, _TeamAction.switchLayout),
                      leadingIcon: Icon(
                        scrollVertical
                            ? LucideIcons.galleryHorizontal
                            : LucideIcons.galleryVertical,
                      ),
                      child: Text(
                        scrollVertical
                            ? 'Switch to horizontal layout'
                            : 'Switch to vertical layout',
                      ),
                    ),
                    const Divider(height: 16),
                  ],
                  BearingsMenuItem(
                    onPressed: () =>
                        handleAction(context, _TeamAction.copyStrategyMessage),
                    leadingIcon: const Icon(LucideIcons.copy),
                    child: const Text('Copy match strategy message'),
                  ),
                  BearingsMenuItem(
                    onPressed: () =>
                        handleAction(context, _TeamAction.openYouTube),
                    leadingIcon: const Icon(LucideIcons.squarePlay),
                    child: const Text('Watch match video'),
                  ),
                  const Divider(height: 16),
                  BearingsMenuItem(
                    onPressed: () => handleAction(context, _TeamAction.openTba),
                    leadingIcon: const Icon(LucideIcons.externalLink),
                    child: const Text('Open in TBA'),
                  ),
                  BearingsMenuItem(
                    onPressed: () =>
                        handleAction(context, _TeamAction.openStatbotics),
                    leadingIcon: const Icon(LucideIcons.externalLink),
                    child: const Text('Open in Statbotics'),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (cards.isEmpty) {
                      return const BearingsStatusView(
                        icon: LucideIcons.users,
                        title: 'No teams available',
                        subtitle: 'This match does not have any team data yet.',
                      );
                    }

                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;

                    final labelStyle = Theme.of(context).textTheme.titleMedium
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        );

                    Widget buildStyledCard(
                      int index, {
                      bool showLabel = false,
                    }) {
                      const padding = 60.0;
                      const gap = 10.0;
                      final card = cards[index];
                      final isRed = index < redTeams.length;
                      final label = isRed ? 'Red Alliance' : 'Blue Alliance';
                      final cardHeight = ((height - padding * 2 - gap) / 2 - 8)
                          .clamp(0.0, double.infinity);

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showLabel)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 0,
                              ),
                              child: Text(
                                label,
                                style: labelStyle?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: TeamCard(
                                eventKey: match.event.id,
                                teamKey: card.teamKey,
                                allianceColor: card.color,
                                height: cardHeight,
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    if (width > 1100) {
                      const padding = 60.0;
                      const gap = 10.0;
                      return Padding(
                        padding: const EdgeInsets.all(padding),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: gap,
                                mainAxisSpacing: gap,
                                childAspectRatio:
                                    (width - padding * 2 - gap * 2) /
                                    3 /
                                    ((height - padding * 2 - gap) / 2),
                              ),
                          itemCount: cards.length,
                          itemBuilder: (context, index) =>
                              buildStyledCard(index),
                        ),
                      );
                    }

                    // horizontal fraction
                    final cardWidth = (width - 16).clamp(0.0, 600.0);
                    final hFraction = width > 0
                        ? (cardWidth / width).clamp(0.0, 1.0)
                        : 1.0;

                    if (scrollVertical) {
                      final verticalFooterHeight = canAddObservation
                          ? 56.0
                          : 0.0;
                      final verticalViewportHeight =
                          (height - verticalFooterHeight)
                              .clamp(0.0, height)
                              .toDouble();
                      final verticalPageHeight = (verticalViewportHeight - 16)
                          .clamp(0.0, verticalViewportHeight)
                          .toDouble();
                      final verticalFraction = verticalViewportHeight > 0
                          ? (verticalPageHeight / verticalViewportHeight).clamp(
                              0.0,
                              1.0,
                            )
                          : 1.0;

                      _updatePageController(
                        verticalFraction,
                        _currentPageNotifier.value.round().clamp(
                          0,
                          cards.length - 1,
                        ),
                      );

                      const horizontalPadding = 16.0;
                      const verticalPadding = 8.0;
                      final verticalCardHeight =
                          (verticalPageHeight - verticalPadding * 2)
                              .clamp(0.0, double.infinity)
                              .toDouble();

                      return Column(
                        children: [
                          Expanded(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollUpdateNotification &&
                                    _pageController?.hasClients == true) {
                                  _currentPageNotifier.value =
                                      _pageController?.page ?? 0.0;
                                }
                                return false;
                              },
                              child: PageView.builder(
                                controller: _pageController,
                                scrollDirection: Axis.vertical,
                                itemCount: cards.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: horizontalPadding,
                                      vertical: verticalPadding,
                                    ),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: TeamCard(
                                        eventKey: match.event.id,
                                        teamKey: cards[index].teamKey,
                                        allianceColor: cards[index].color,
                                        height: verticalCardHeight,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          if (canAddObservation)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: SizedBox(
                                width: double.infinity,
                                height: 40,
                                child: FilledButton(
                                  onPressed: addObservation,
                                  child: const Text('Add observation'),
                                ),
                              ),
                            ),
                        ],
                      );
                    }

                    final stride = width * hFraction;
                    final contentLeftEdge = (width - cardWidth) / 2.0 + 8.0;

                    _updatePageController(
                      hFraction,
                      _currentPageNotifier.value.round().clamp(
                        0,
                        cards.length - 1,
                      ),
                    );

                    Widget buildDotsIndicator(double page) {
                      return FlutterMaterialScope(
                        child: DotsIndicator(
                          dotsCount: cards.length,
                          position: page.clamp(0, cards.length - 1).toDouble(),
                          axis: scrollVertical
                              ? Axis.vertical
                              : Axis.horizontal,
                          onTap: (position) {
                            _pageController?.animateToPage(
                              position.toInt(),
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            );
                          },
                          decorator: DotsDecorator(
                            activeColor: Theme.of(context).colorScheme.primary,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            colors: cards
                                .map((c) => c.color.withValues(alpha: 0.4))
                                .toList(),
                            activeColors: cards.map((c) => c.color).toList(),
                            spacing: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            size: const Size.square(8.0),
                            activeSize: const Size(24.0, 8.0),
                            activeShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                          ),
                        ),
                      );
                    }

                    Widget dots = cards.length > 1
                        ? ValueListenableBuilder<double>(
                            valueListenable: _currentPageNotifier,
                            builder: (context, page, _) =>
                                buildDotsIndicator(page),
                          )
                        : const SizedBox.shrink();

                    // horizontal layout
                    return Column(
                      children: [
                        SizedBox(
                          height: 40,
                          width: double.infinity,
                          child: ValueListenableBuilder<double>(
                            valueListenable: _currentPageNotifier,
                            builder: (context, page, _) {
                              return Stack(
                                children: [
                                  if (redTeams.isNotEmpty)
                                    _buildStickyLabel(
                                      context: context,
                                      label: 'Red Alliance',
                                      groupStartIndex: 0,
                                      groupEndIndex: redTeams.length - 1,
                                      page: page,
                                      stride: stride,
                                      cardWidth: cardWidth,
                                      baseOffset: contentLeftEdge,
                                      style: labelStyle,
                                    ),
                                  if (blueTeams.isNotEmpty)
                                    _buildStickyLabel(
                                      context: context,
                                      label: 'Blue Alliance',
                                      groupStartIndex: redTeams.length,
                                      groupEndIndex:
                                          redTeams.length +
                                          blueTeams.length -
                                          1,
                                      page: page,
                                      stride: stride,
                                      cardWidth: cardWidth,
                                      baseOffset: contentLeftEdge,
                                      style: labelStyle,
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollUpdateNotification &&
                                  _pageController?.hasClients == true) {
                                _currentPageNotifier.value =
                                    _pageController?.page ?? 0.0;
                              }
                              return false;
                            },
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: cards.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: TeamCard(
                                    eventKey: match.event.id,
                                    teamKey: cards[index].teamKey,
                                    allianceColor: cards[index].color,
                                    height: constraints.maxHeight,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        dots,
                        if (canAddObservation)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SizedBox(
                              width: 586,
                              child: FilledButton(
                                onPressed: addObservation,
                                child: const Text('Add observation'),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStickyLabel({
    required BuildContext context,
    required String label,
    required int groupStartIndex,
    required int groupEndIndex,
    required double page,
    required double stride,
    required double cardWidth,
    required double baseOffset,
    required TextStyle? style,
  }) {
    final double boxLeft = baseOffset + (groupStartIndex - page) * stride;
    final double boxRight =
        baseOffset + (groupEndIndex - page) * stride + cardWidth - 16;

    const double stickyTarget = 16.0;

    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
    )..layout();

    final double labelWidth = textPainter.width;

    double x = boxLeft;

    if (x < stickyTarget) {
      x = stickyTarget;
    }

    if (x + labelWidth > boxRight) {
      x = boxRight - labelWidth;
    }

    return Positioned(
      left: x,
      child: Text(label, style: style),
    );
  }
}

/// Formats a strategy message from 2046's perspective when playing, or by
/// alliance color otherwise.
String matchStrategyMessage({
  required String matchLabel,
  required List<String> redTeams,
  required List<String> blueTeams,
}) {
  final onBlue = blueTeams.contains('frc2046');
  final playing = onBlue || redTeams.contains('frc2046');
  String teamLine(String key) => '${key.replaceFirst(RegExp('^frc'), '')} - ';
  if (!playing) {
    return [
      '$matchLabel:',
      '',
      'Red:',
      ...redTeams.map(teamLine),
      '',
      'Blue:',
      ...blueTeams.map(teamLine),
    ].join('\n');
  }
  final partners = onBlue ? blueTeams : redTeams;
  final opponents = onBlue ? redTeams : blueTeams;

  return [
    '$matchLabel:',
    '',
    'Against:',
    ...opponents.map(teamLine),
    '',
    'With:',
    ...partners.where((key) => key != 'frc2046').map(teamLine),
  ].join('\n');
}
