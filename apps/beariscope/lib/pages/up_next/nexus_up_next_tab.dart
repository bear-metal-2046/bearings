import 'dart:async';

import 'package:beariscope/models/nexus_live_status.dart';
import 'package:beariscope/pages/up_next/nexus_live_provider.dart';
import 'package:beariscope/pages/up_next/nexus_match_utils.dart';
import 'package:beariscope/pages/up_next/up_next_page.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';
import 'package:beariscope/pages/up_next/up_next_widget.dart';
import 'package:beariscope/providers/nexus_event_key_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

enum NexusMatchFilter { all, bearMetal }

class NexusUpNextTab extends ConsumerStatefulWidget {
  const NexusUpNextTab({super.key, required this.isActive});

  final bool isActive;

  @override
  ConsumerState<NexusUpNextTab> createState() => _NexusUpNextTabState();
}

class _NexusUpNextTabState extends ConsumerState<NexusUpNextTab> {
  static const _refreshInterval = Duration(seconds: 45);

  NexusMatchFilter _filter = NexusMatchFilter.bearMetal;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _startRefreshTimer();
    }
  }

  @override
  void didUpdateWidget(covariant NexusUpNextTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive && !oldWidget.isActive) {
      ref.invalidate(nexusLiveProvider);
      _startRefreshTimer();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopRefreshTimer();
    }
  }

  @override
  void dispose() {
    _stopRefreshTimer();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!mounted || !widget.isActive) return;
      ref.invalidate(nexusLiveProvider);
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final nexusLive = ref.watch(nexusLiveProvider);
    final schedule = ref.watch(upNextProvider);
    final nexusEventKey = ref.watch(nexusEventKeyProvider);
    final scheduleMatches = schedule.asData?.value ?? const <Map<String, dynamic>>[];

    Future<void> refreshNexus() async {
      ref.invalidate(nexusLiveProvider);
      ref.invalidate(nexusEventKeyProvider);
      try {
        await ref.read(nexusLiveProvider.future);
      } catch (_) {}
    }

    return nexusLive.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _NexusMessageView(
        message: 'Error loading Nexus data: $err',
        onRefresh: refreshNexus,
      ),
      data: (status) {
        if (status == null) {
          return _NexusUnavailableView(
            nexusEventKey: nexusEventKey.asData?.value,
            onRefresh: refreshNexus,
          );
        }

        final filteredMatches = _filter == NexusMatchFilter.all
            ? status.matches
            : status.matches.where((match) => match.includesTeam(2046)).toList();

        if (filteredMatches.isEmpty) {
          return _NexusMessageView(
            message: status.matches.isEmpty
                ? 'No Nexus matches scheduled yet.'
                : 'No 2046 matches found in the Nexus queue.',
            onRefresh: refreshNexus,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (status.announcements.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _AnnouncementsBanner(
                      announcements: status.announcements,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (status.nowQueuing != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _NowQueuingBanner(label: status.nowQueuing!),
                  ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: refreshNexus,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (status.announcements.isNotEmpty) ...[
                _AnnouncementsBanner(announcements: status.announcements),
                const SizedBox(height: 12),
              ],
              if (status.nowQueuing != null) ...[
                _NowQueuingBanner(label: status.nowQueuing!),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Updated ${UpNextPage.timeFormat.format(status.dataAsOfTime)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  PopupMenuButton<NexusMatchFilter>(
                    icon: Icon(
                      _filter == NexusMatchFilter.bearMetal
                          ? LucideIcons.funnel
                          : LucideIcons.funnelX,
                      color: _filter == NexusMatchFilter.bearMetal
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    tooltip: 'Filter matches',
                    onSelected: (value) => setState(() => _filter = value),
                    itemBuilder: (context) => [
                      _filterMenuItem(
                        value: NexusMatchFilter.all,
                        label: 'All Matches',
                        current: _filter,
                      ),
                      _filterMenuItem(
                        value: NexusMatchFilter.bearMetal,
                        label: 'Just 2046',
                        current: _filter,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...filteredMatches.map((match) {
                final time = match.times.displayTime;
                final timeLabel = time == null
                    ? 'Time TBD'
                    : UpNextPage.timeFormat.format(time);
                final matchKey = tbaMatchKeyForNexusMatch(
                  match,
                  scheduleMatches,
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: NexusMatchCard(
                        label: match.label,
                        time: timeLabel,
                        status: match.status,
                        includes2046: match.includesTeam(2046),
                        onTap: matchKey == null
                            ? null
                            : () => context.push('/up_next/$matchKey'),
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
                  label: const Text('Data from FRC Nexus'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

PopupMenuItem<NexusMatchFilter> _filterMenuItem({
  required NexusMatchFilter value,
  required String label,
  required NexusMatchFilter current,
}) {
  return PopupMenuItem<NexusMatchFilter>(
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

class _NowQueuingBanner extends StatelessWidget {
  const _NowQueuingBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(LucideIcons.radio, color: colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Now queuing: $label',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementsBanner extends StatelessWidget {
  const _AnnouncementsBanner({required this.announcements});

  final List<NexusAnnouncement> announcements;

  @override
  Widget build(BuildContext context) {
    return Card(
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
            ...announcements.map(
              (announcement) => Text(announcement.message),
            ),
          ],
        ),
      ),
    );
  }
}

class _NexusMessageView extends StatelessWidget {
  const _NexusMessageView({
    required this.message,
    required this.onRefresh,
    this.header,
  });

  final String message;
  final Future<void> Function() onRefresh;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ?header,
          SizedBox(height: 320, child: Center(child: Text(message))),
        ],
      ),
    );
  }
}

class _NexusUnavailableView extends StatelessWidget {
  const _NexusUnavailableView({
    required this.nexusEventKey,
    required this.onRefresh,
  });

  final String? nexusEventKey;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 320,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    const Text(
                      'Nexus live data is unavailable for this event.',
                      textAlign: TextAlign.center,
                    ),
                    const Text(
                      'Live queue times are only available for events using Nexus queuing.',
                      textAlign: TextAlign.center,
                    ),
                    if (nexusEventKey != null)
                      FilledButton.icon(
                        onPressed: () {
                          launchUrl(
                            Uri.parse(
                              'https://frc.nexus/en/event/$nexusEventKey/team/2046/matches',
                            ),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(LucideIcons.externalLink),
                        label: const Text('Open in Nexus'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
