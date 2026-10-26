import 'dart:math' as math;

import 'package:beariscope/pages/flash_cards/flash_card_animation.dart';
import 'package:beariscope/pages/flash_cards/flash_card_color.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/widgets/logo_badge.dart';
import 'package:beariscope/widgets/team_avatar.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

class FlashCard extends StatefulWidget {
  const FlashCard({
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
  State<FlashCard> createState() => _FlashCardState();
}

class _FlashCardState extends State<FlashCard>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController.unbounded(
    value: widget.flipped ? 1 : 0,
    vsync: this,
  );

  @override
  void didUpdateWidget(FlashCard oldWidget) {
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
          SpringSimulation(
            flashCardSpring,
            _turn.value,
            target,
            _turn.velocity,
          ),
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
