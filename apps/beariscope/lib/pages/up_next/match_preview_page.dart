import 'package:beariscope/models/drive_team_note.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/drive_team_notes_provider.dart';
import 'package:beariscope/providers/match_preview_layout_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/widgets/team_card.dart';
import 'package:dots_indicator/dots_indicator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/providers/user_profile_provider.dart';
import 'package:ui/ui.dart';
import 'package:url_launcher/url_launcher.dart';

enum _TeamAction { switchLayout, openTba, openStatbotics, openYouTube }

final matchProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  matchKey,
) {
  return ref
      .watch(honeycombClientProvider)
      .get<Map<String, dynamic>>(
        '/matches?match=$matchKey',
        cachePolicy: CachePolicy.networkFirst,
      );
});

class DriveTeamMatchPreviewPage extends ConsumerStatefulWidget {
  final String matchKey;

  const DriveTeamMatchPreviewPage({super.key, required this.matchKey});

  @override
  ConsumerState<DriveTeamMatchPreviewPage> createState() =>
      _DriveTeamMatchPreviewPageState();
}

class _DriveTeamMatchPreviewPageState
    extends ConsumerState<DriveTeamMatchPreviewPage> {
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
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        appBar: AppBar(title: Text('Match ${widget.matchKey}')),
        body: Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(requestProvider),
            child: const Text('Retry'),
          ),
        ),
      ),
      data: (data) {
        String teamNumberFromKey(String teamKey) {
          return teamKey.replaceFirst(RegExp('^frc'), '');
        }

        void handleAction(
          BuildContext context,
          _TeamAction action,
          String key,
        ) {
          switch (action) {
            case _TeamAction.switchLayout:
              final nextLayout = scrollVertical
                  ? MatchPreviewLayout.horizontal
                  : MatchPreviewLayout.vertical;
              ref
                  .read(matchPreviewLayoutProvider.notifier)
                  .setLayout(nextLayout);
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
              key == 'null'
                  ? ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No video available')),
                    )
                  : launchUrl(
                      Uri.parse('https://www.youtube.com/watch?v=$key'),
                      mode: LaunchMode.externalApplication,
                    );
          }
        }

        final match = Map<String, dynamic>.from(data);
        final alliances = match['alliances'];
        final redTeams = alliances is Map && alliances['red'] is Map
            ? (alliances['red']['team_keys'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const <String>[]
            : const <String>[];
        final blueTeams = alliances is Map && alliances['blue'] is Map
            ? (alliances['blue']['team_keys'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const <String>[]
            : const <String>[];
        final cards = <({String teamKey, Color color})>[
          ...redTeams.map((teamKey) => (teamKey: teamKey, color: Colors.red)),
          ...blueTeams.map((teamKey) => (teamKey: teamKey, color: Colors.blue)),
        ];
        final compLevel = compLevelForMatch(match);
        final number = compLevel == 'sf'
            ? setNumberForMatch(match) ?? matchNumberForMatch(match)
            : matchNumberForMatch(match);
        final matchTitle = compLevel.isEmpty || number == null
            ? 'Match ${widget.matchKey}'
            : '${switch (compLevel) {
                'qm' => 'Qualification Match',
                'sf' => 'Semifinal Match',
                'f' => 'Final Match',
                _ => compLevel.toUpperCase(),
              }} $number';
        final matchVideos = (match['videos'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final video = matchVideos.firstWhere(
          (e) => e['type'] == 'youtube',
          orElse: () => <String, dynamic>{},
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(matchTitle),
            actions: [
              PopupMenuButton<_TeamAction>(
                icon: const Icon(LucideIcons.ellipsisVertical),
                tooltip: 'More options',
                onSelected: (action) =>
                    handleAction(context, action, video['key'].toString()),
                itemBuilder: (context) => [
                  if (MediaQuery.sizeOf(context).width <= 1100) ...[
                    PopupMenuItem(
                      value: _TeamAction.switchLayout,
                      child: ListTile(
                        leading: Icon(
                          scrollVertical
                              ? LucideIcons.galleryHorizontal
                              : LucideIcons.galleryVertical,
                        ),
                        title: Text(
                          scrollVertical
                              ? 'Switch to horizontal layout'
                              : 'Switch to vertical layout',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                  ],
                  const PopupMenuItem(
                    value: _TeamAction.openTba,
                    child: ListTile(
                      leading: Icon(LucideIcons.externalLink),
                      title: Text('Open in TBA'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: _TeamAction.openStatbotics,
                    child: ListTile(
                      leading: Icon(LucideIcons.externalLink),
                      title: Text('Open in Statbotics'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: _TeamAction.openYouTube,
                    child: ListTile(
                      leading: Icon(LucideIcons.externalLink),
                      title: Text('Watch Match Video'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (cards.isEmpty) {
                return const Center(child: Text('No teams available.'));
              }

              final width = constraints.maxWidth;
              final height = constraints.maxHeight;

              final labelStyle = Theme.of(context).textTheme.titleMedium
                  ?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  );

              Widget buildStyledCard(int index, {bool showLabel = false}) {
                const padding = 60.0;
                const gap = 10.0;
                final card = cards[index];
                final isRed = index < redTeams.length;
                final label = isRed ? 'Red Alliance' : 'Blue Alliance';
                final cardHeight =
                    ((height - padding * 2 - gap) / 2 - 8).clamp(0.0, double.infinity);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showLabel)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 0),
                        child: Text(
                          label,
                          style: labelStyle?.copyWith(color: Colors.white),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: TeamCard(
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
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: gap,
                      childAspectRatio:
                          (width - padding * 2 - gap * 2) /
                          3 /
                          ((height - padding * 2 - gap) / 2),
                    ),
                    itemCount: cards.length,
                    itemBuilder: (context, index) => buildStyledCard(index),
                  ),
                );
              }

              // horizontal fraction
              final cardWidth = (width - 16).clamp(0.0, 600.0);
              final hFraction = width > 0
                  ? (cardWidth / width).clamp(0.0, 1.0)
                  : 1.0;

              if (scrollVertical) {
                final canTakeNotes =
                    permissionChecker?.hasPermission(
                      PermissionKey.driveTeamUpload,
                    ) ??
                    false;
                final verticalFooterHeight = canTakeNotes ? 56.0 : 0.0;
                final verticalViewportHeight = (height - verticalFooterHeight)
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
                  _currentPageNotifier.value.round().clamp(0, cards.length - 1),
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
                    if (canTakeNotes)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: FilledButton(
                            onPressed: () {
                              final filteredRedTeams = redTeams
                                  .where(
                                    (teamKey) =>
                                        teamNumberFromKey(teamKey) != '2046',
                                  )
                                  .toList();
                              final filteredBlueTeams = blueTeams
                                  .where(
                                    (teamKey) =>
                                        teamNumberFromKey(teamKey) != '2046',
                                  )
                                  .toList();
                              showModalBottomSheet(
                                context: context,
                                showDragHandle: true,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (context) => _DriveTeamNotesSheet(
                                  matchKey: widget.matchKey,
                                  redAllianceTeamKeys: filteredRedTeams,
                                  blueAllianceTeamKeys: filteredBlueTeams,
                                ),
                              );
                            },
                            child: const Text('Take Notes'),
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
                _currentPageNotifier.value.round().clamp(0, cards.length - 1),
              );

              Widget buildDotsIndicator(double page) {
                return FlutterMaterialScope(
                  child: DotsIndicator(
                    dotsCount: cards.length,
                    position: page.clamp(0, cards.length - 1).toDouble(),
                    axis: scrollVertical ? Axis.vertical : Axis.horizontal,
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
                      builder: (context, page, _) => buildDotsIndicator(page),
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
                                    redTeams.length + blueTeams.length - 1,
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
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: TeamCard(
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
                  if (permissionChecker?.hasPermission(
                        PermissionKey.driveTeamUpload,
                      ) ??
                      false)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SizedBox(
                        width: 586,
                        child: FilledButton(
                          onPressed: () {
                            final filteredRedTeams = redTeams
                                .where(
                                  (teamKey) =>
                                      teamNumberFromKey(teamKey) != '2046',
                                )
                                .toList();
                            final filteredBlueTeams = blueTeams
                                .where(
                                  (teamKey) =>
                                      teamNumberFromKey(teamKey) != '2046',
                                )
                                .toList();
                            showModalBottomSheet(
                              context: context,
                              showDragHandle: true,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (context) => _DriveTeamNotesSheet(
                                matchKey: widget.matchKey,
                                redAllianceTeamKeys: filteredRedTeams,
                                blueAllianceTeamKeys: filteredBlueTeams,
                              ),
                            );
                          },
                          child: const Text('Take Notes'),
                        ),
                      ),
                    ),
                ],
              );
            },
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

class _DriveTeamNotesSheet extends ConsumerStatefulWidget {
  final String matchKey;
  final List<String> redAllianceTeamKeys;
  final List<String> blueAllianceTeamKeys;

  const _DriveTeamNotesSheet({
    required this.matchKey,
    required this.redAllianceTeamKeys,
    required this.blueAllianceTeamKeys,
  });

  @override
  ConsumerState<_DriveTeamNotesSheet> createState() =>
      _DriveTeamNotesSheetState();
}

class _DriveTeamNotesSheetState extends ConsumerState<_DriveTeamNotesSheet> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _existingIds = {};

  bool _initialized = false;
  bool _isSaving = false;

  Future<String> _resolveScoutedBy() async {
    final userInfo = await ref.read(userInfoProvider.future);
    final name = userInfo?.name?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return 'Unknown User';
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  //populates the controllers with existing notes
  void _initControllers(Map<int, DriveTeamNote> existingNotes) {
    if (_initialized) return;
    _initialized = true;

    final allTeamKeys = [
      ...widget.redAllianceTeamKeys,
      ...widget.blueAllianceTeamKeys,
    ];

    for (final teamKey in allTeamKeys) {
      final teamNumber = teamKey.replaceFirst(RegExp(r'^frc'), '');
      final teamNum = int.tryParse(teamNumber);
      final controller = TextEditingController();

      if (teamNum != null && existingNotes.containsKey(teamNum)) {
        final existing = existingNotes[teamNum]!;
        controller.text = existing.note;
        if (existing.id != null && existing.id!.isNotEmpty) {
          _existingIds[teamNumber] = existing.id!;
        }
      }

      _controllers[teamNumber] = controller;
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final authMe = await ref.read(authMeProvider.future);
      final eventKey = ref.read(currentEventProvider);

      final scoutedBy = await _resolveScoutedBy();
      final userId = authMe?.user.id ?? '';

      final entries = <Map<String, Object?>>[];
      for (final entry in _controllers.entries) {
        final text = entry.value.text.trim();
        if (text.isEmpty) continue;
        final teamNum = int.tryParse(entry.key) ?? 0;
        final note = DriveTeamNote(
          id: _existingIds[entry.key],
          matchKey: widget.matchKey,
          teamNumber: teamNum,
          note: text,
          scoutedBy: scoutedBy,
          userId: userId,
          eventKey: eventKey,
          season: 2026,
        );
        entries.add(note.toIngestEntry());
      }

      if (entries.isNotEmpty) {
        final client = ref.read(honeycombClientProvider);
        await client.post('/scout/ingest', data: {'entries': entries});
        // sync the local Hive cache so notes survive a page-exit and re-entry.
        await ref.read(scoutingDataProvider.notifier).refresh();
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save notes: $e')));
      }
    }
  }

  Widget _buildAllianceSection(
    ThemeData theme,
    String label,
    List<String> teamKeys,
  ) {
    if (teamKeys.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        for (final teamKey in teamKeys)
          Builder(
            builder: (context) {
              final teamNumber = teamKey.replaceFirst(RegExp(r'^frc'), '');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    teamNumber.isEmpty ? teamKey : teamNumber,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    controller: _controllers[teamNumber],
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Notes',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(myDriveTeamNotesProvider(widget.matchKey));
    final theme = Theme.of(context);

    return notesAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SizedBox(
        height: 200,
        child: Center(child: Text('Error loading notes: $e')),
      ),
      data: (existingNotes) {
        _initControllers(existingNotes);

        if (widget.redAllianceTeamKeys.isEmpty &&
            widget.blueAllianceTeamKeys.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Cannot load notes for this match.')),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAllianceSection(
                  theme,
                  'Red Alliance',
                  widget.redAllianceTeamKeys,
                ),
                _buildAllianceSection(
                  theme,
                  'Blue Alliance',
                  widget.blueAllianceTeamKeys,
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Notes'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
