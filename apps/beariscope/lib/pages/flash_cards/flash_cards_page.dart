import 'dart:async';
import 'dart:math' as math;

import 'package:beariscope/pages/flash_cards/flash_card_color.dart';
import 'package:beariscope/pages/flash_cards/flash_card_options_sheet.dart';
import 'package:beariscope/pages/flash_cards/flash_card_progress.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:beariscope/widgets/logo_badge.dart';
import 'package:beariscope/widgets/team_avatar.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stupid_simple_sheet/stupid_simple_sheet.dart';

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

class FlashCardsPage extends ConsumerStatefulWidget {
  const FlashCardsPage({super.key});

  @override
  ConsumerState<FlashCardsPage> createState() => _FlashCardsPageState();
}

class _FlashCardsPageState extends ConsumerState<FlashCardsPage> {
  late final FlashCardStore _store;
  late FlashCardOptions _options;
  int _resetGeneration = 0;

  @override
  void initState() {
    super.initState();
    _store = FlashCardStore(ref.read(sharedPreferencesProvider));
    _options = _store.readOptions();
  }

  final _studyFocus = FocusNode(debugLabel: 'Flash cards');

  @override
  void dispose() {
    _studyFocus.dispose();
    super.dispose();
  }

  Future<void> _showOptions() async {
    await Navigator.of(context).push<void>(
      StupidSimpleSheetRoute(
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
        child: FlashCardOptionsSheet(
          options: _options,
          onReset: () {
            final event = ref.read(currentEventProvider);
            unawaited(_store.saveProgress(event, const FlashCardProgress()));
            setState(() => _resetGeneration++);
          },
          onChanged: (options) {
            if (mounted) setState(() => _options = options);
            unawaited(_store.saveOptions(options));
          },
        ),
      ),
    );
    if (mounted && _studyFocus.context != null) _studyFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final eventKey = ref.watch(currentEventProvider);
    final teamsAsync = ref.watch(teamsProvider);
    final controller = MainViewController.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flash Cards'),
        actions: [
          IconButton(
            tooltip: 'Flash card options',
            onPressed: _showOptions,
            icon: const Icon(LucideIcons.slidersHorizontal),
          ),
        ],
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
            key: ValueKey(eventKey),
            eventKey: eventKey,
            resetGeneration: _resetGeneration,
            store: _store,
            teams: teams,
            media: media,
            options: _options,
            focusNode: _studyFocus,
          );
        },
      ),
    );
  }
}

class _FlashCardDeck extends StatefulWidget {
  const _FlashCardDeck({
    super.key,
    required this.teams,
    required this.media,
    required this.options,
    required this.focusNode,
    required this.eventKey,
    required this.resetGeneration,
    required this.store,
  });

  final List<Team> teams;
  final List<TeamMediaRecord> media;
  final FlashCardOptions options;
  final FocusNode focusNode;
  final String eventKey;
  final int resetGeneration;
  final FlashCardStore store;

  @override
  State<_FlashCardDeck> createState() => _FlashCardDeckState();
}

// Flutter's duration/bounce spring uses the same model as SwiftUI's spring.
final _cardSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 420),
  bounce: .18,
);

/// The next card can take input once the outgoing card and shadow clear the
/// viewport. Waiting for a pixel-based spring to fully settle adds a long tail.
class _CardExitSimulation extends SpringSimulation {
  _CardExitSimulation({
    required double position,
    required double velocity,
    required bool known,
    required this.cardWidth,
    required this.cardHeight,
    required this.viewportWidth,
  }) : _direction = known ? 1 : -1,
       super(
         _cardSpring,
         position,
         (known ? 1 : -1) *
             (viewportWidth / 2 + cardWidth * .7 + cardHeight * .08 + 24),
         velocity,
       );

  final double cardWidth;
  final double cardHeight;
  final double viewportWidth;
  final int _direction;

  @override
  bool isDone(double time) {
    final position = super.x(time);
    final angle = position / cardWidth * .12;
    final halfWidth =
        (cardWidth * math.cos(angle).abs() +
            cardHeight * math.sin(angle).abs()) /
        2;
    return position * _direction >= viewportWidth / 2 + halfWidth + 24 ||
        super.isDone(time);
  }
}

class _FlashCardDeckState extends State<_FlashCardDeck>
    with SingleTickerProviderStateMixin {
  late FlashCardProgress _progress;
  FlashCardProgress? _pending;
  late final _swipe = AnimationController.unbounded(vsync: this);
  bool _sorting = false;
  int _sortEpoch = 0;
  bool _mediaPreloadScheduled = false;
  bool _saveFailed = false;
  double _cardWidth = 300;
  double _cardHeight = 500;
  double _deckWidth = 320;
  List<String> get _teamKeys => widget.teams.map((team) => team.key).toList();
  Team _team(String key) => widget.teams.firstWhere((team) => team.key == key);
  int get _knownCount =>
      widget.teams.where((team) => _progress.ratings[team.key] == true).length;
  int get _learningCount => widget.teams.length - _knownCount;

  @override
  void initState() {
    super.initState();
    final saved = widget.store.readProgress(widget.eventKey);
    _progress = saved.order.isEmpty && saved.ratings.isEmpty
        ? saved.round(_teamKeys, widget.options.shuffled)
        : saved.reconcile(_teamKeys);
    _persist(_progress);
  }

  void _persist(FlashCardProgress progress) {
    unawaited(
      widget.store.saveProgress(widget.eventKey, progress).then<void>((saved) {
        if (!saved) {
          _saveError();
        } else {
          _saveFailed = false;
        }
      }, onError: (Object _, StackTrace _) => _saveError()),
    );
  }

  void _saveError() {
    if (!mounted || _saveFailed) return;
    _saveFailed = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Progress could not be saved.')),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMediaPreload();
  }

  @override
  void didUpdateWidget(_FlashCardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetGeneration != widget.resetGeneration) {
      _resetProgress();
      return;
    }
    _progress = _progress.reconcile(_teamKeys);
    if (_pending != null) {
      _pending = _pending!.reconcile(_teamKeys);
      if (oldWidget.options.shuffled != widget.options.shuffled) {
        _pending = _pending!.round(_teamKeys, widget.options.shuffled);
      }
      _persist(_pending!);
      _scheduleMediaPreload();
      return;
    }
    if (oldWidget.options.shuffled != widget.options.shuffled) {
      _startRound();
    } else if (oldWidget.options.nameFirst != widget.options.nameFirst &&
        _progress.flipped) {
      _progress = _progress.turn();
    }
    _persist(_progress);
    _scheduleMediaPreload();
  }

  void _scheduleMediaPreload() {
    if (_mediaPreloadScheduled) return;
    _mediaPreloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mediaPreloadScheduled = false;
      if (!mounted) return;
      for (
        var index = math.max(0, _progress.index - 1);
        index <= math.min(_progress.order.length - 1, _progress.index + 1);
        index++
      ) {
        final team = _team(_progress.order[index]);
        final url = widget.options.showPhotos
            ? flashCardPhoto(widget.media, team.key)
            : null;
        if (url != null) {
          unawaited(
            precacheImage(NetworkImage(url), context, onError: (_, _) {}),
          );
        }
        final logos = teamAvatarImages(widget.media, 'frc${team.number}');
        if (logos.isNotEmpty) {
          unawaited(
            loadLogoBadgeBackground(
              logos.first,
              createLocalImageConfiguration(context),
            ),
          );
        }
      }
    });
  }

  void _flip() {
    if (_sorting || _progress.complete || _swipe.value.abs() > 1) return;
    HapticFeedback.lightImpact();
    setState(() => _progress = _progress.turn());
    _persist(_progress);
  }

  Future<void> _rate(bool known, {double velocity = 0}) async {
    if (_sorting || _progress.complete) return;
    final epoch = ++_sortEpoch;
    _pending = _progress.rate(known);
    // Persist the user's decision before the exit animation, even if they leave.
    _persist(_pending!);
    HapticFeedback.selectionClick();
    setState(() => _sorting = true);
    if (!MediaQuery.disableAnimationsOf(context)) {
      try {
        await _swipe
            .animateWith(
              _CardExitSimulation(
                position: _swipe.value,
                velocity: velocity,
                known: known,
                cardWidth: _cardWidth,
                cardHeight: _cardHeight,
                viewportWidth: _deckWidth,
              ),
            )
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || epoch != _sortEpoch) return;
    setState(() {
      _progress = _pending!.reconcile(_teamKeys);
      _pending = null;
      _sorting = false;
      _swipe.value = 0;
    });
    _persist(_progress);
    _scheduleMediaPreload();
  }

  void _undo() {
    if (_sorting || _progress.history.isEmpty) return;
    _swipe.stop();
    _swipe.value = 0;
    HapticFeedback.selectionClick();
    setState(() => _progress = _progress.undo());
    _persist(_progress);
    _scheduleMediaPreload();
  }

  void _startRound() {
    if (_sorting) return;
    _swipe.stop();
    _swipe.value = 0;
    setState(
      () => _progress = _progress.round(_teamKeys, widget.options.shuffled),
    );
    _persist(_progress);
    _scheduleMediaPreload();
  }

  void _resetProgress() {
    _sortEpoch++;
    _swipe.stop();
    setState(() {
      _pending = null;
      _sorting = false;
      _swipe.value = 0;
      _progress = _progress.reset(_teamKeys, widget.options.shuffled);
    });
    _persist(_progress);
    _scheduleMediaPreload();
  }

  Future<void> _settle() async {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _swipe.value = 0;
      return;
    }
    try {
      await _swipe
          .animateWith(SpringSimulation(_cardSpring, _swipe.value, 0, 0))
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted && !_sorting) _swipe.value = 0;
  }

  void _endSwipe(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final distance = _swipe.value;
    if (distance.abs() >= _cardWidth * .24 ||
        (distance.abs() > 24 &&
            velocity.abs() > 900 &&
            velocity.sign == distance.sign)) {
      _rate(distance > 0, velocity: velocity);
    } else {
      _settle();
    }
  }

  @override
  void dispose() {
    _swipe.dispose();
    super.dispose();
  }

  Widget _card(String key, {required bool active}) {
    final team = _team(key);
    return _FlashCard(
      key: ValueKey('flash-card-$key'),
      team: team,
      nameFirst: widget.options.nameFirst,
      logoImages: teamAvatarImages(widget.media, 'frc${team.number}'),
      flipped: active && _progress.flipped,
      active: active,
      onFlip: _flip,
      onLearning: active && !_sorting ? () => _rate(false) : null,
      onKnown: active && !_sorting ? () => _rate(true) : null,
      photoUrl: widget.options.showPhotos
          ? flashCardPhoto(widget.media, team.key)
          : null,
    );
  }

  Widget _completion() {
    final title = _learningCount == 0 ? 'All known' : 'Round complete';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleCheck,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            if (_learningCount > 0) ...[
              FilledButton(
                onPressed: _startRound,
                child: const Text('Study again'),
              ),
              TextButton(
                onPressed: _resetProgress,
                child: const Text('Reset progress'),
              ),
            ] else
              FilledButton(
                onPressed: _resetProgress,
                child: const Text('Reset progress'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _deck(BoxConstraints constraints, bool reduceMotion) {
    final padding = constraints.maxHeight < 400 ? 8.0 : 16.0;
    final height = math.min(
      560.0,
      math.max(24.0, constraints.maxHeight - padding * 2),
    );
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SizedBox(
            key: const ValueKey('flash-card-deck'),
            height: height,
            child: LayoutBuilder(
              builder: (context, bounds) {
                _cardWidth = bounds.maxWidth * .94 - 8;
                _cardHeight = height - 16;
                _deckWidth = bounds.maxWidth;
                return GestureDetector(
                  onHorizontalDragStart: _sorting ? null : (_) => _swipe.stop(),
                  onHorizontalDragUpdate: _sorting
                      ? null
                      : (details) => _swipe.value += details.delta.dx,
                  onHorizontalDragEnd: _sorting ? null : _endSwipe,
                  onHorizontalDragCancel: _sorting ? null : _settle,
                  child: AnimatedBuilder(
                    animation: _swipe,
                    builder: (context, _) {
                      final amount = (_swipe.value.abs() / _cardWidth).clamp(
                        0.0,
                        1.0,
                      );
                      final known = _swipe.value > 0;
                      return ClipRect(
                        clipBehavior: _swipe.value == 0
                            ? Clip.none
                            : Clip.hardEdge,
                        clipper: const _DeckSwipeClipper(),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (amount > 0 &&
                                _progress.index + 1 < _progress.order.length)
                              Positioned(
                                left: (bounds.maxWidth - _cardWidth) / 2,
                                top: 8,
                                width: _cardWidth,
                                height: height - 16,
                                child: ExcludeSemantics(
                                  child: IgnorePointer(
                                    child: Transform.scale(
                                      scale: reduceMotion
                                          ? 1
                                          : .94 + .06 * amount,
                                      child: _card(
                                        _progress.order[_progress.index + 1],
                                        active: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              left: (bounds.maxWidth - _cardWidth) / 2,
                              top: 8,
                              width: _cardWidth,
                              height: height - 16,
                              child: Transform.translate(
                                offset: Offset(_swipe.value, 0),
                                child: Transform.rotate(
                                  angle: reduceMotion
                                      ? 0
                                      : _swipe.value / _cardWidth * .12,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    fit: StackFit.expand,
                                    children: [
                                      _card(_progress.current!, active: true),
                                      if (amount > .03)
                                        IgnorePointer(
                                          child: ExcludeSemantics(
                                            child: Opacity(
                                              opacity: (amount * 3).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                              child: Align(
                                                alignment: known
                                                    ? Alignment.topLeft
                                                    : Alignment.topRight,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    24,
                                                  ),
                                                  child: Material(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .surface,
                                                    elevation: 2,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 16,
                                                            vertical: 10,
                                                          ),
                                                      child: Text(
                                                        known
                                                            ? 'Know'
                                                            : 'Still learning',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final canRate = !_sorting && !_progress.complete;
    final navigation = Row(
      key: const ValueKey('flash-card-controls'),
      textDirection: TextDirection.ltr,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!_progress.complete)
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('mark-learning'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: canRate ? () => _rate(false) : null,
              icon: const Icon(LucideIcons.chevronLeft, size: 18),
              label: const Text(
                'Still learning',
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: IconButton(
            tooltip: 'Undo last sort',
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: !_sorting && _progress.history.isNotEmpty ? _undo : null,
            icon: const Icon(LucideIcons.undo2),
          ),
        ),
        if (!_progress.complete)
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('mark-known'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: canRate ? () => _rate(true) : null,
              icon: const Icon(LucideIcons.chevronRight, size: 18),
              label: const Text('Know', maxLines: 2),
            ),
          ),
      ],
    );
    return Focus(
      focusNode: widget.focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || !node.hasPrimaryFocus) {
          return KeyEventResult.ignored;
        }
        if ((HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed) &&
            event.logicalKey == LogicalKeyboardKey.keyZ) {
          _undo();
        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _rate(true);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _rate(false);
        } else if (event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          _flip();
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: LinearProgressIndicator(
                    key: const ValueKey('flash-card-round-progress'),
                    value: _progress.order.isEmpty
                        ? 0
                        : _progress.index / _progress.order.length,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(3),
                    semanticsLabel:
                        'Round progress, ${_progress.index} of ${_progress.order.length} cards',
                  ),
                ),
              ),
            ),
            Expanded(
              child: _progress.complete
                  ? _completion()
                  : LayoutBuilder(
                      builder: (context, constraints) =>
                          _deck(constraints, reduceMotion),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: navigation,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Horizontal sorting stays contained while a stationary flip remains unclipped.
class _DeckSwipeClipper extends CustomClipper<Rect> {
  const _DeckSwipeClipper();
  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -size.height, size.width, size.height * 2);
  @override
  bool shouldReclip(_DeckSwipeClipper oldClipper) => false;
}

class _FlashCard extends StatefulWidget {
  const _FlashCard({
    super.key,
    required this.team,
    required this.nameFirst,
    required this.photoUrl,
    required this.logoImages,
    required this.flipped,
    required this.active,
    required this.onFlip,
    this.onLearning,
    this.onKnown,
  });

  final Team team;
  final bool nameFirst;
  final String? photoUrl;
  final List<ImageProvider> logoImages;
  final bool flipped;
  final bool active;
  final VoidCallback onFlip;
  final VoidCallback? onLearning;
  final VoidCallback? onKnown;

  @override
  State<_FlashCard> createState() => _FlashCardState();
}

class _FlashCardState extends State<_FlashCard>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController.unbounded(
    value: widget.flipped ? 1 : 0,
    vsync: this,
  );

  @override
  void didUpdateWidget(_FlashCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nameFirst != widget.nameFirst ||
        oldWidget.active != widget.active) {
      _turn.value = widget.flipped ? 1 : 0;
    } else if (oldWidget.flipped != widget.flipped) {
      final target = widget.flipped ? 1.0 : 0.0;
      if (MediaQuery.disableAnimationsOf(context)) {
        _turn.value = target;
      } else {
        // Preserve velocity when a tap reverses a flip in flight.
        _turn.animateWith(
          SpringSimulation(_cardSpring, _turn.value, target, _turn.velocity),
        );
      }
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final teamColors = widget.team.colors;
    final cardBackground = teamColors == null
        ? colors.primaryContainer
        : flashCardColor(teamColors);
    final cardForeground = teamColors == null
        ? colors.onPrimaryContainer
        : (cardBackground.computeLuminance() > .179
              ? Colors.black
              : Colors.white);
    return AnimatedBuilder(
      animation: _turn,
      builder: (context, _) {
        final angle = _turn.value * math.pi;
        final back = _turn.value > .5;
        final showName = widget.nameFirst != back;
        final hasPhoto = !showName && widget.photoUrl != null;
        final foreground = hasPhoto ? Colors.white : cardForeground;
        final content = Text(
          showName ? widget.team.name : '${widget.team.number}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: showName ? 36 : 76,
            height: 1.08,
            letterSpacing: showName ? -1 : -3,
            fontWeight: FontWeight.w800,
            color: foreground,
            shadows: hasPhoto
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: .45),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        );
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0008)
            ..rotateY(angle),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(back ? math.pi : 0),
            child: Semantics(
              container: true,
              button: true,
              label: showName ? widget.team.name : '${widget.team.number}',
              hint: back
                  ? 'Show prompt'
                  : 'Reveal ${widget.nameFirst ? 'number' : 'name'}',
              onTap: widget.onFlip,
              customSemanticsActions: {
                if (widget.onLearning != null)
                  const CustomSemanticsAction(label: 'Still learning'):
                      widget.onLearning!,
                if (widget.onKnown != null)
                  const CustomSemanticsAction(label: 'Know'): widget.onKnown!,
              },
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: .12),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: .05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: cardBackground,
                  borderRadius: BorderRadius.circular(28),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onFlip,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasPhoto)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    widget.photoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0x52000000),
                                          Color(0x6B000000),
                                          Color(0x9E000000),
                                        ],
                                        stops: [0, .5, 1],
                                      ),
                                    ),
                                  ),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        center: Alignment(0, -.1),
                                        radius: 1.05,
                                        colors: [
                                          Colors.transparent,
                                          Color(0x47000000),
                                        ],
                                        stops: [.3, 1],
                                      ),
                                    ),
                                  ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: .12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        LayoutBuilder(
                          builder: (context, cardBounds) {
                            final compact = cardBounds.maxHeight < 200;
                            return Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 16 : 24,
                                vertical: compact
                                    ? 10
                                    : (back && widget.logoImages.isNotEmpty
                                          ? 24
                                          : 40),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final answer = showName && !compact
                                      ? SingleChildScrollView(child: content)
                                      : FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: constraints.maxWidth,
                                            ),
                                            child: content,
                                          ),
                                        );
                                  return Center(
                                    child: back && widget.logoImages.isNotEmpty
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _FlashCardLogo(
                                                images: widget.logoImages,
                                                size:
                                                    (constraints.maxHeight *
                                                            .38)
                                                        .clamp(32.0, 96.0),
                                              ),
                                              Flexible(child: answer),
                                            ],
                                          )
                                        : answer,
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
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

class _FlashCardLogo extends StatelessWidget {
  const _FlashCardLogo({required this.images, required this.size});

  final List<ImageProvider> images;
  final double size;

  @override
  Widget build(BuildContext context) {
    final inset = size < 64 ? 6.0 : 12.0;
    return TeamAvatarImage(
      images: images,
      width: size - inset * 2,
      height: size - inset * 2,
      // Keep the answer centered when a logo is missing, loading, or invalid.
      loadedBuilder: (context, child, image) {
        return Padding(
          padding: EdgeInsets.only(bottom: size < 64 ? 8 : 20),
          child: LogoBadge(image: image, inset: inset, child: child),
        );
      },
    );
  }
}
