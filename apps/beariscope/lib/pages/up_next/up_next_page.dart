import 'dart:async';

import 'package:beariscope/models/match_nexus_info.dart';
import 'package:beariscope/models/up_next_match.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';
import 'package:beariscope/pages/up_next/up_next_widget.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/nexus_event_key_provider.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
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
  static const _refreshInterval = Duration(seconds: 45);

  _MatchFilter _filter = _MatchFilter.bearMetal;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!mounted) return;
      ref.invalidate(upNextProvider);
      ref.invalidate(upNextEventContextProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final schedule = ref.watch(upNextProvider);
    final eventContext = ref.watch(upNextEventContextProvider);
    final currentEventKey = ref.watch(currentEventProvider);

    Future<void> refreshSchedule() async {
      ref.invalidate(upNextProvider);
      ref.invalidate(upNextEventContextProvider);
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
              : matches.where((match) => match.includes2046).toList();

          return _MatchList(
            matches: filteredMatches,
            eventContext: eventContext.asData?.value,
            emptyMessage: 'No matches found. Is the schedule released?',
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
    required this.eventContext,
    required this.emptyMessage,
    required this.timeFormat,
    required this.onRefresh,
  });

  final List<UpNextMatch> matches;
  final UpNextEventContext? eventContext;
  final String emptyMessage;
  final DateFormat timeFormat;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (eventContext != null)
              _EventContextHeader(eventContext: eventContext!),
            SizedBox(height: 320, child: Center(child: Text(emptyMessage))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (eventContext != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _EventContextHeader(eventContext: eventContext!),
            ),
          ...matches.map((match) {
            final matchTime = match.displayTime;
            final timeLabel = matchTime == null
                ? 'Time TBD'
                : timeFormat.format(matchTime);

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: UpNextMatchCard(
                    matchKey: match.key,
                    displayName: match.displayName,
                    time: timeLabel,
                    status: match.queueStatus,
                    highlighted:
                        match.includes2046 &&
                        isActiveQueueStatus(match.queueStatus),
                  ),
                ),
              ),
            );
          }),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () {
                launchUrl(
                  Uri.parse('https://frc.nexus'),
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(LucideIcons.externalLink, size: 16),
              label: const Text('Queue data from FRC Nexus'),
            ),
          ),
        ],
      ),
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
      spacing: 12,
      children: [
        if (eventContext.nowQueuing != null)
          Card(
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.radio,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Now queuing: ${eventContext.nowQueuing}',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (eventContext.announcements.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.megaphone, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Announcements',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  ...eventContext.announcements.map(Text.new),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
