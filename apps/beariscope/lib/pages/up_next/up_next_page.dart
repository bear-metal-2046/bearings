import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';
import 'package:beariscope/pages/up_next/up_next_widget.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

enum _MatchFilter { all, bearMetal }

enum _EventAction { openTba, openStatbotics, openNexus, openFrcEvents }

class UpNextPage extends ConsumerStatefulWidget {
  const UpNextPage({super.key});

  static final DateFormat timeFormat = DateFormat("EEEE, MMM d 'at' h:mm a");

  @override
  ConsumerState<UpNextPage> createState() => _UpNextPageState();
}

class _UpNextPageState extends ConsumerState<UpNextPage> {
  _MatchFilter _filter = _MatchFilter.bearMetal;

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final schedule = ref.watch(upNextProvider);
    final currentEventKey = ref.watch(currentEventProvider);

    Future<void> refreshSchedule() async {
      ref.invalidate(upNextProvider);
      ref.invalidate(teamEventsProvider);
      try {
        await ref.read(upNextProvider.future);
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Up Next'),
        leading: controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.menu),
                onPressed: controller.openDrawer,
              ),
        actions: [
          PopupMenuButton<_MatchFilter>(
            icon: Icon(
              _filter == _MatchFilter.bearMetal
                  ? LucideIcons.funnel
                  : LucideIcons.funnelX,
              color: _filter == _MatchFilter.bearMetal
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter matches',
            onSelected: (value) => setState(() => _filter = value),
            itemBuilder: (context) => [
              _filterMenuItem(
                value: _MatchFilter.all,
                label: 'All Matches',
                current: _filter,
              ),
              _filterMenuItem(
                value: _MatchFilter.bearMetal,
                label: 'Just 2046',
                current: _filter,
              ),
            ],
          ),
          PopupMenuButton<_EventAction>(
            icon: const Icon(LucideIcons.ellipsisVertical),
            tooltip: 'More options',
            onSelected: (action) => _handleAction(action, currentEventKey, ref),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _EventAction.openTba,
                child: ListTile(
                  leading: Icon(LucideIcons.externalLink),
                  title: Text('View Event in TBA'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _EventAction.openStatbotics,
                child: ListTile(
                  leading: Icon(LucideIcons.externalLink),
                  title: Text('View Event in Statbotics'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _EventAction.openFrcEvents,
                child: ListTile(
                  leading: Icon(LucideIcons.externalLink),
                  title: Text('View Event in FIRST Events'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _EventAction.openNexus,
                child: ListTile(
                  leading: Icon(LucideIcons.externalLink),
                  title: Text('Open Schedule in Nexus'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: schedule.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Error fetching schedule: $err')),
        data: (matches) {
          final filteredMatches = _filter == _MatchFilter.all
              ? matches
              : matches.where(_is2046Match).toList();

          return _MatchList(
            matches: filteredMatches,
            emptyMessage: 'No matches found. Is the schedule released?',
            timeFormat: UpNextPage.timeFormat,
            onRefresh: refreshSchedule,
          );
        },
      ),
    );
  }

  void _handleAction(_EventAction action, String eventKey, WidgetRef ref) {
    switch (action) {
      case _EventAction.openTba:
        launchUrl(
          ref.tbaWebsiteUri('/event/$eventKey'),
          mode: LaunchMode.externalApplication,
        );
      case _EventAction.openStatbotics:
        launchUrl(
          Uri.parse('https://www.statbotics.io/event/$eventKey'),
          mode: LaunchMode.externalApplication,
        );
      case _EventAction.openNexus:
        launchUrl(
          Uri.parse('https://frc.nexus/en/event/$eventKey/team/2046/matches'),
          mode: LaunchMode.externalApplication,
        );
      case _EventAction.openFrcEvents:
        launchUrl(
          Uri.parse(
            'https://frc-events.firstinspires.org/${eventKey.substring(0, 4)}/${eventKey.substring(4)}',
          ),
          mode: LaunchMode.externalApplication,
        );
    }
  }
}

PopupMenuItem<_MatchFilter> _filterMenuItem({
  required _MatchFilter value,
  required String label,
  required _MatchFilter current,
}) {
  return PopupMenuItem<_MatchFilter>(
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
  final String emptyMessage;
  final DateFormat timeFormat;
  final Future<void> Function() onRefresh;

  const _MatchList({
    required this.matches,
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
          final matchTime = _parseMatchTime(match);
          final timeLabel = matchTime == null
              ? 'Time TBD'
              : timeFormat.format(matchTime);

          return UpNextMatchCard(
            matchKey: match['key']?.toString() ?? '',
            displayName: matchDisplayName(match),
            time: timeLabel,
          );
        }).toList(),
      ),
    );
  }
}

DateTime? _parseMatchTime(Map<String, dynamic> match) {
  final value = match['predictedTime'] ?? match['predicted_time'];
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  return null;
}
