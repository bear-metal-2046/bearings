import 'package:beariscope/models/match_nexus_info.dart';
import 'package:beariscope/models/up_next_match.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// An Up Next match that expands, like FRC Nexus, to show queue times,
/// bracket details, and teams, with a button to open the match preview.
class UpNextMatchCard extends StatefulWidget {
  const UpNextMatchCard({
    super.key,
    required this.match,
    required this.now,
    this.onFieldNow = false,
    this.initiallyExpanded = false,
  });

  final UpNextMatch match;
  final DateTime now;

  /// Shows the collapsed card as "X is on field now".
  final bool onFieldNow;
  final bool initiallyExpanded;

  @override
  State<UpNextMatchCard> createState() => _UpNextMatchCardState();
}

class _UpNextMatchCardState extends State<UpNextMatchCard> {
  late bool _expanded;

  String get _storageId => 'up_next_expanded_${widget.match.key}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _expanded =
        PageStorage.maybeOf(context)?.readState(context, identifier: _storageId)
            as bool? ??
        widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    PageStorage.maybeOf(context)
        ?.writeState(context, _expanded, identifier: _storageId);
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final highlighted =
        match.includes2046 && isActiveQueueStatus(match.queueStatus);

    return Card(
      color: highlighted
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                spacing: 8,
                children: [
                  if (widget.onFieldNow)
                    Icon(
                      LucideIcons.play,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  Expanded(
                    flex: 3,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: match.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.onFieldNow)
                                const TextSpan(text: ' is on field now'),
                            ],
                          ),
                          style: textTheme.titleMedium,
                        ),
                        if (match.possibleOutcome != null)
                          _OutcomeTag(outcome: match.possibleOutcome!),
                      ],
                    ),
                  ),
                  if (!widget.onFieldNow)
                    Flexible(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _Summary(match: match, now: widget.now),
                      ),
                    ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(LucideIcons.chevronDown, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _expanded
                ? _MatchDetails(match: match, now: widget.now)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The right side of a collapsed card: the live status, or when it queues.
class _Summary extends StatelessWidget {
  const _Summary({required this.match, required this.now});

  final UpNextMatch match;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final status = match.queueStatus;
    if (status != null && status != 'Queuing soon') {
      return _MatchStatusChip(
        status: status,
        colorScheme: Theme.of(context).colorScheme,
      );
    }

    final queueTime = match.nexus?.estimatedQueueTime;
    final text = queueTime != null && queueTime.isAfter(now)
        ? 'Queuing ${_fromNow(queueTime, now)}'
        : switch (match.displayTime) {
            final time? when time.isAfter(now) => _fromNow(time, now),
            final time? => _clock(time),
            null => 'Time TBD',
          };
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium,
      textAlign: TextAlign.end,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _MatchDetails extends StatelessWidget {
  const _MatchDetails({required this.match, required this.now});

  final UpNextMatch match;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final nexus = match.nexus;
    final bracket = match.bracket;

    final lines = <(IconData, String)>[
      if (bracket != null)
        (
          LucideIcons.mapPin,
          'Round ${bracket.round} - '
              '${bracket.bracket == PlayoffBracket.upper ? 'Upper' : 'Lower'} '
              'bracket - Match ${bracket.number}',
        ),
      if (bracket != null)
        (
          LucideIcons.logOut,
          'Winner advances to ${_slotLabel(bracket.winnerTo)}',
        ),
      if (bracket?.loserTo != null)
        (
          LucideIcons.cornerRightDown,
          'Loser moves to ${_slotLabel(bracket!.loserTo!)}',
        ),
      if (bracket?.loserPlace != null)
        (LucideIcons.x, 'Loser places ${bracket!.loserPlace}'),
      if (nexus?.replayOf != null)
        (LucideIcons.rotateCcw, 'Replay of ${nexus!.replayOf}'),
      ?_statusLine(),
      if (nexus?.scheduledStartTime != null)
        (
          LucideIcons.calendar,
          'Originally scheduled to start @ '
              '${_clock(nexus!.scheduledStartTime!)}',
        )
      else if (match.displayTime != null)
        (
          LucideIcons.calendar,
          'Expected to start @ ${_clock(match.displayTime!)}',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (lines.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                for (final (icon, text) in lines)
                  Row(
                    spacing: 10,
                    children: [
                      Icon(icon, size: 18),
                      Expanded(child: Text(text)),
                    ],
                  ),
              ],
            ),
          _AllianceGrid(match: match),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: () => context.push('/up_next/${match.key}'),
              icon: const Icon(LucideIcons.eye, size: 18),
              label: const Text('Match preview'),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String)? _statusLine() {
    final nexus = match.nexus;
    if (nexus == null) return null;
    final since = switch (nexus.status) {
      'On field' => nexus.actualOnFieldTime,
      'On deck' => nexus.actualOnDeckTime,
      'Now queuing' => nexus.actualQueueTime,
      _ => null,
    };
    if (since != null) {
      return (LucideIcons.clock, '${nexus.status} ${_ago(since, now)}');
    }

    final (verb, time) = switch (nexus.estimatedQueueTime) {
      final queue? when queue.isAfter(now) => ('Queuing', queue),
      _ => ('Starting', nexus.estimatedStartTime),
    };
    if (time == null || !time.isAfter(now)) return null;
    return (
      LucideIcons.clock,
      '$verb ${_fromNow(time, now)} (${_clock(time)})',
    );
  }
}

class _AllianceGrid extends StatelessWidget {
  const _AllianceGrid({required this.match});

  final UpNextMatch match;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget side(String color, int? alliance, List<String> teamKeys) {
      final isRed = color == 'red';
      final background = isRed
          ? Colors.red.withValues(alpha: 0.18)
          : Colors.blue.withValues(alpha: 0.18);
      return Expanded(
        child: Column(
          spacing: 4,
          children: [
            Text(
              alliance != null
                  ? 'Alliance $alliance'
                  : isRed
                  ? 'Red'
                  : 'Blue',
              style: textTheme.titleSmall,
            ),
            Container(
              color: background,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: teamKeys.isEmpty
                    ? [
                        const Expanded(
                          child: Text('TBD', textAlign: TextAlign.center),
                        ),
                      ]
                    : [
                        for (final team in teamKeys)
                          Expanded(
                            child: Text(
                              team.replaceFirst('frc', ''),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: team == bearMetalTeamKey
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                          ),
                      ],
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        side('red', match.redAllianceNumber, match.redTeamKeys),
        side('blue', match.blueAllianceNumber, match.blueTeamKeys),
      ],
    );
  }
}

/// A break between matches, from Nexus's `breakAfter`.
class UpNextBreakRow extends StatelessWidget {
  const UpNextBreakRow({super.key, required this.name, required this.after});

  final String name;
  final String after;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              name,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text('After $after', style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _OutcomeTag extends StatelessWidget {
  const _OutcomeTag({required this.outcome});

  final PlayoffOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        outcome == PlayoffOutcome.win ? 'If you win' : 'If you lose',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

String _slotLabel(PlayoffSlot slot) {
  final side = slot.red ? 'red' : 'blue';
  return slot.isFinals ? 'the Finals ($side)' : 'Playoff ${slot.match} ($side)';
}

String _clock(DateTime time) => DateFormat.jm().format(time);

/// "~48 mins" or "~1 hr 5 mins" until [time].
String _fromNow(DateTime time, DateTime now) {
  final minutes = time.difference(now).inMinutes;
  if (minutes < 1) return 'now';
  if (minutes < 60) return '~$minutes min${minutes == 1 ? '' : 's'}';
  if (minutes >= 12 * 60) return DateFormat("EEE 'at' h:mm a").format(time);
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return '~$hours hr${rest == 0 ? '' : ' $rest min${rest == 1 ? '' : 's'}'}';
}

/// "2 minutes ago" since [time].
String _ago(DateTime time, DateTime now) {
  final minutes = now.difference(time).inMinutes;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes minute${minutes == 1 ? '' : 's'} ago';
  final hours = minutes ~/ 60;
  return '$hours hour${hours == 1 ? '' : 's'} ago';
}

class _MatchStatusChip extends StatelessWidget {
  const _MatchStatusChip({required this.status, required this.colorScheme});

  final String status;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Now queuing' => colorScheme.primary,
      'On deck' => colorScheme.tertiary,
      'On field' => colorScheme.secondary,
      _ => colorScheme.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class UpNextEventCard extends ConsumerWidget {
  final String eventKey;
  final String name;
  final String dateLabel;

  const UpNextEventCard({
    super.key,
    required this.eventKey,
    required this.name,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BeariscopeCard(
      title: name,
      subtitle: dateLabel,
      trailing: Icon(LucideIcons.externalLink, size: 20),
      onTap: () async {
        final uri = ref.tbaWebsiteUri('/event/$eventKey');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Could not open TBA')));
          }
        }
      },
    );
  }
}
