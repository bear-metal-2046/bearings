import 'package:beariscope/models/match_nexus_info.dart';
import 'package:beariscope/models/up_next_match.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';
import 'package:beariscope/pages/up_next/up_next_widget.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/nexus_event_key_provider.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:beariscope/widgets/beariscope_status_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:services/services.dart';
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
      ref.invalidate(nexusEventStatusProvider(currentEventKey));
      ref.invalidate(scheduleMatchesProvider(currentEventKey));
      ref.invalidate(teamEventsProvider);
      try {
        await ref.read(upNextProvider.future);
      } catch (error) {
        debugPrint('Up Next: refresh failed for $currentEventKey: $error');
      }
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
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Error fetching schedule: $err')),
        data: (upNext) {
          final filteredMatches = _filter == _MatchFilter.all
              ? upNext.matches
              : upNext.matches.where((match) => match.includes2046).toList();
          return _MatchList(
            matches: filteredMatches,
            source: upNext.source,
            nexusProblem: upNext.nexusProblem,
            eventContext: upNext.eventContext,
            timeFormat: UpNextPage.timeFormat,
            onRefresh: refreshSchedule,
          );
        },
      ),
    );
  }

  Future<void> _handleAction(
    _EventAction action,
    String eventKey,
    WidgetRef ref,
  ) async {
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
        final nexusEventKey =
            await ref.read(nexusEventKeyProvider.future) ?? eventKey;
        launchUrl(
          Uri.parse(
            'https://frc.nexus/en/event/$nexusEventKey/team/2046/matches',
          ),
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

class _MatchList extends StatelessWidget {
  const _MatchList({
    required this.matches,
    required this.source,
    required this.nexusProblem,
    required this.eventContext,
    required this.timeFormat,
    required this.onRefresh,
  });

  final List<UpNextMatch> matches;
  final UpNextSource source;
  final String? nexusProblem;
  final UpNextEventContext? eventContext;
  final DateFormat timeFormat;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (eventContext != null)
        _EventContextHeader(eventContext: eventContext!),
      _SourceLine(source: source, nexusProblem: nexusProblem),
      if (matches.isEmpty)
        const SizedBox(
          height: 320,
          child: BeariscopeStatusView(
            icon: LucideIcons.calendar,
            title: 'No matches found',
            subtitle: 'Is the schedule released?',
          ),
        )
      else
        ...matches.map((match) {
          final matchTime = match.displayTime;
          final timeLabel = matchTime == null
              ? 'Time TBD'
              : timeFormat.format(matchTime);

          return UpNextMatchCard(
            matchKey: match.key,
            displayName: match.displayName,
            time: timeLabel,
            status: match.queueStatus,
            highlighted:
                match.includes2046 && isActiveQueueStatus(match.queueStatus),
          );
        }),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: BeariscopeCardList(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        spacing: 8,
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.source, required this.nexusProblem});

  final UpNextSource source;
  final String? nexusProblem;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colorScheme.onSurfaceVariant);
    final isNexus = source == UpNextSource.nexus;

    final line = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        spacing: 6,
        children: [
          Icon(
            isNexus ? LucideIcons.radio : LucideIcons.calendar,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: Text(
              isNexus
                  ? 'Live from FRC Nexus'
                  : 'Schedule; Nexus unavailable: $nexusProblem',
              style: style,
            ),
          ),
        ],
      ),
    );

    if (!isNexus) return line;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => launchUrl(
        Uri.parse('https://frc.nexus'),
        mode: LaunchMode.externalApplication,
      ),
      child: line,
    );
  }
}

class _EventContextHeader extends StatelessWidget {
  const _EventContextHeader({required this.eventContext});

  final UpNextEventContext eventContext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (eventContext.nowQueuing != null)
          BeariscopeCard(
            title: 'Now queuing: ${eventContext.nowQueuing}',
            color: colorScheme.primaryContainer,
            leading: Icon(
              LucideIcons.radio,
              color: colorScheme.onPrimaryContainer,
            ),
            titleStyle: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (eventContext.announcements.isNotEmpty)
          BeariscopeCard(
            title: 'Announcements',
            subtitle: eventContext.announcements.join('\n'),
            leading: const Icon(LucideIcons.megaphone, size: 18),
          ),
      ],
    );
  }
}
