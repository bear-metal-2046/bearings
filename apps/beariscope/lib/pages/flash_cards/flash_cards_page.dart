import 'dart:math' as math;

import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

/// Returns a photo rather than a team avatar, video thumbnail, or CAD preview.
String? flashCardPhoto(List<TeamMediaRecord> records, String teamKey) {
  final photos = records.where(
    (record) =>
        record.teamKeys.contains(teamKey) &&
        record.isPhoto &&
        record.previewImageUrl?.isNotEmpty == true,
  );
  for (final photo in photos) {
    if (photo.preferred) return photo.previewImageUrl;
  }
  return photos.firstOrNull?.previewImageUrl;
}

class FlashCardsPage extends ConsumerWidget {
  const FlashCardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventKey = ref.watch(currentEventProvider);
    final teamsAsync = ref.watch(teamsProvider);
    final controller = MainViewController.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flash Cards'),
        leading: controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                tooltip: 'Open navigation',
                onPressed: controller.openDrawer,
              ),
      ),
      body: teamsAsync.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => BeariscopeStatusView(
          icon: LucideIcons.circleAlert,
          title: 'Teams unavailable',
          subtitle: 'Could not load teams for $eventKey.',
          action: FilledButton(
            onPressed: () => ref.invalidate(teamsProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (rawTeams) {
          final byNumber = <int, Team>{};
          for (final raw in rawTeams) {
            final team = Team.fromJson(raw);
            if (team.number > 0) byNumber[team.number] = team;
          }
          final teams = byNumber.values.toList()
            ..sort((a, b) => a.number.compareTo(b.number));
          if (teams.isEmpty) {
            return const BeariscopeStatusView(
              icon: LucideIcons.layers,
              title: 'No teams in this event',
              subtitle: 'Select another event from the navigation menu.',
            );
          }

          // Media is optional: slow or unavailable photos never block studying.
          final media =
              ref.watch(eventTeamMediaProvider).asData?.value ??
              const <TeamMediaRecord>[];
          return _FlashCardDeck(
            key: ValueKey(
              '$eventKey:${teams.map((team) => team.key).join(",")}',
            ),
            eventKey: eventKey,
            teams: teams,
            media: media,
          );
        },
      ),
    );
  }
}

class _FlashCardDeck extends StatefulWidget {
  const _FlashCardDeck({
    super.key,
    required this.eventKey,
    required this.teams,
    required this.media,
  });

  final String eventKey;
  final List<Team> teams;
  final List<TeamMediaRecord> media;

  @override
  State<_FlashCardDeck> createState() => _FlashCardDeckState();
}

class _FlashCardDeckState extends State<_FlashCardDeck> {
  final _pages = PageController();
  int _index = 0;
  int _revision = 0;
  bool _nameFirst = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.teams.length) return;
    _pages.animateToPage(
      index,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardHeight = (MediaQuery.sizeOf(context).height - 360).clamp(
      220.0,
      460.0,
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Text('Event: ${widget.eventKey}'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  children: [
                    const Text('Show first'),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Number')),
                        ButtonSegment(value: true, label: Text('Name')),
                      ],
                      selected: {_nameFirst},
                      onSelectionChanged: (value) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _nameFirst = value.single;
                          _revision++;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: cardHeight,
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: widget.teams.length,
                    onPageChanged: (index) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _index = index;
                        _revision++;
                      });
                    },
                    itemBuilder: (context, index) {
                      final team = widget.teams[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _FlashCard(
                          key: ValueKey('${team.key}:$_revision'),
                          team: team,
                          nameFirst: _nameFirst,
                          photoUrl: flashCardPhoto(widget.media, team.key),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Previous card',
                      onPressed: _index == 0 ? null : () => _goTo(_index - 1),
                      icon: const Icon(LucideIcons.chevronLeft),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Semantics(
                        liveRegion: true,
                        child: Text('${_index + 1} / ${widget.teams.length}'),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Next card',
                      onPressed: _index == widget.teams.length - 1
                          ? null
                          : () => _goTo(_index + 1),
                      icon: const Icon(LucideIcons.chevronRight),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (_index + 1) / widget.teams.length,
                  semanticsLabel: 'Deck progress',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tap a card to flip it. Swipe to change teams.',
                  textAlign: TextAlign.center,
                ),
                if (_index == widget.teams.length - 1 && _index > 0)
                  TextButton.icon(
                    onPressed: () => _goTo(0),
                    icon: const Icon(LucideIcons.rotateCcw),
                    label: const Text('Study again'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlashCard extends StatefulWidget {
  const _FlashCard({
    super.key,
    required this.team,
    required this.nameFirst,
    required this.photoUrl,
  });

  final Team team;
  final bool nameFirst;
  final String? photoUrl;

  @override
  State<_FlashCard> createState() => _FlashCardState();
}

class _FlashCardState extends State<_FlashCard> {
  bool _flipped = false;

  void _flip() {
    HapticFeedback.lightImpact();
    setState(() => _flipped = !_flipped);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _flipped ? math.pi : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      builder: (context, angle, _) {
        final back = angle > math.pi / 2;
        final showName = widget.nameFirst != back;
        final hasPhoto = !showName && widget.photoUrl != null;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .001)
            ..rotateY(angle),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(back ? math.pi : 0),
            child: Semantics(
              button: true,
              label: showName ? widget.team.name : '${widget.team.number}',
              hint: 'Flip card',
              onTap: _flip,
              excludeSemantics: true,
              child: Material(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _flip,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasPhoto) ...[
                        Image.network(
                          widget.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black54),
                        ),
                      ],
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            showName
                                ? widget.team.name
                                : '${widget.team.number}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: showName ? 36 : 64,
                              fontWeight: FontWeight.bold,
                              color: hasPhoto ? Colors.white : colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
