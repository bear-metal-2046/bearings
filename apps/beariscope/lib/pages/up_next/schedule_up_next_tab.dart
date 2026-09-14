import 'package:beariscope/models/nexus_live_status.dart';
import 'package:beariscope/pages/up_next/nexus_live_provider.dart';
import 'package:beariscope/pages/up_next/nexus_match_utils.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';
import 'package:beariscope/pages/up_next/up_next_widget.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum ScheduleMatchFilter { all, bearMetal }

class ScheduleUpNextTab extends ConsumerStatefulWidget {
  const ScheduleUpNextTab({
    super.key,
    required this.timeFormat,
  });

  final DateFormat timeFormat;

  @override
  ConsumerState<ScheduleUpNextTab> createState() => _ScheduleUpNextTabState();
}

class _ScheduleUpNextTabState extends ConsumerState<ScheduleUpNextTab> {
  ScheduleMatchFilter _filter = ScheduleMatchFilter.bearMetal;

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(upNextProvider);
    final nexusLive = ref.watch(nexusLiveProvider);
    final liveStatus = nexusLive.asData?.value;

    Future<void> refreshSchedule() async {
      ref.invalidate(upNextProvider);
      ref.invalidate(nexusLiveProvider);
      ref.invalidate(teamEventsProvider);
      try {
        await ref.read(upNextProvider.future);
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<ScheduleMatchFilter>(
            icon: Icon(
              _filter == ScheduleMatchFilter.bearMetal
                  ? LucideIcons.funnel
                  : LucideIcons.funnelX,
              color: _filter == ScheduleMatchFilter.bearMetal
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter matches',
            onSelected: (value) => setState(() => _filter = value),
            itemBuilder: (context) => [
              _filterMenuItem(
                value: ScheduleMatchFilter.all,
                label: 'All Matches',
                current: _filter,
              ),
              _filterMenuItem(
                value: ScheduleMatchFilter.bearMetal,
                label: 'Just 2046',
                current: _filter,
              ),
            ],
          ),
        ),
        Expanded(
          child: schedule.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) =>
                Center(child: Text('Error fetching schedule: $err')),
            data: (matches) {
              final filteredMatches = _filter == ScheduleMatchFilter.all
                  ? matches
                  : matches.where(_is2046Match).toList();

              return _MatchList(
                matches: filteredMatches,
                liveStatus: liveStatus,
                emptyMessage: 'No matches found. Is the schedule released?',
                timeFormat: widget.timeFormat,
                onRefresh: refreshSchedule,
              );
            },
          ),
        ),
      ],
    );
  }
}

PopupMenuItem<ScheduleMatchFilter> _filterMenuItem({
  required ScheduleMatchFilter value,
  required String label,
  required ScheduleMatchFilter current,
}) {
  return PopupMenuItem<ScheduleMatchFilter>(
    value: value,
    child: Row(
      children: [
        SizedBox(
          width: 32,
          child: current == value
              ? const Icon(LucideIcons.check, size: 20)
              : null,
        ),
        Text(label),
      ],
    ),
  );
}

bool _is2046Match(Map<String, dynamic> match) {
  final alliances = match['alliances'] as Map?;
  if (alliances == null) return false;

  for (final alliance in alliances.values) {
    if (alliance is! Map) continue;
    final keys =
        (alliance['team_keys'] ?? alliance['teamKeys'] ?? alliance['teams'])
            as List?;
    if (keys != null && keys.any((k) => k?.toString() == 'frc2046')) {
      return true;
    }
  }

  return false;
}

class _MatchList extends StatelessWidget {
  final List<Map<String, dynamic>> matches;
  final NexusLiveStatus? liveStatus;
  final String emptyMessage;
  final DateFormat timeFormat;
  final Future<void> Function() onRefresh;

  const _MatchList({
    required this.matches,
    this.liveStatus,
    required this.emptyMessage,
    required this.timeFormat,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 320, child: Center(child: Text(emptyMessage))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: BeariscopeCardList(
        children: matches.map((match) {
          final nexusMatch = nexusMatchForScheduleMatch(match, liveStatus);
          final matchTime = resolveScheduleMatchTime(match, nexusMatch);
          final timeLabel = matchTime == null
              ? 'Time TBD'
              : timeFormat.format(matchTime);

          return UpNextMatchCard(
            matchKey: match['key']?.toString() ?? '',
            displayName: matchDisplayName(match),
            time: timeLabel,
            status: nexusMatch?.status,
          );
        }).toList(),
      ),
    );
  }
}

