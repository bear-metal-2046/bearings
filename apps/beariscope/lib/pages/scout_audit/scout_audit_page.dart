import 'dart:convert';
import 'dart:math' as math;

import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/scout_audit/match_scouting_form_page.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_logic.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_preferences_provider.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_provider.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:core/core.dart' show ScoutPosition;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:services/providers/api_provider.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:url_launcher/url_launcher.dart';

class ScoutAuditPage extends ConsumerStatefulWidget {
  const ScoutAuditPage({super.key});

  @override
  ConsumerState<ScoutAuditPage> createState() => _ScoutAuditPageState();
}

class _ScoutAuditPageState extends ConsumerState<ScoutAuditPage> {
  @override
  Widget build(BuildContext context) {
    final controller = MainViewController.of(context);
    final threshold = ref.watch(scoutAuditIncorrectThresholdProvider);
    final snapshotAsync = ref.watch(scoutAuditSnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scout Audit'),
        leading: controller.isDesktop
            ? null
            : IconButton(
                icon: const Icon(Symbols.menu_rounded),
                onPressed: controller.openDrawer,
              ),
        actions: [
          IconButton(
            onPressed: () => _showManualScoutDialog(context),
            icon: const Icon(Symbols.add_rounded),
            tooltip: 'Manual Scout',
          ),
          IconButton(
            onPressed: () => _showThresholdDialog(context, threshold),
            icon: const Icon(Symbols.tune_rounded),
            tooltip: 'Adjust Threshold',
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.error_rounded,
                  size: 52,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'TBA cached data is unavailable',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Scout Audit needs cached match schedule and scores.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(cachedTbaMatchesProvider);
                    ref.invalidate(scoutAuditSnapshotProvider);
                  },
                  icon: const Icon(Symbols.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (snapshot) {
          if (snapshot.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.check_circle_rounded,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'All scouted data looks clean!',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          final allIssues = <_AuditIssueItem>[
            for (final issue in snapshot.incompleteMatches)
              _AuditIssueItem(
                type: ScoutAuditIssueType.incomplete,
                title: issue.entryType == ScoutAuditEntryType.strat
                    ? 'Match ${issue.matchNumber} (Strat)'
                    : 'Match ${issue.matchNumber}',
                subtitle: issue.entryType == ScoutAuditEntryType.strat
                    ? '${issue.scoutedCount}/${issue.expectedCount} alliances scouted'
                    : '${issue.scoutedCount}/${issue.expectedCount} teams scouted',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _IncompleteMatchDetailPage(
                      matchNumber: issue.matchNumber,
                      entryType: issue.entryType,
                    ),
                  ),
                ),
              ),
            for (final issue in snapshot.notInTba)
              _AuditIssueItem(
                type: ScoutAuditIssueType.notInTba,
                title: issue.entryType == ScoutAuditEntryType.strat
                    ? 'Match ${issue.matchNumber} (Strat)'
                    : 'Match ${issue.matchNumber}',
                subtitle: issue.entryType == ScoutAuditEntryType.strat
                    ? 'Strat · ${issue.positionLabel}'
                    : issue.teamNumber == null
                    ? issue.positionLabel
                    : '${issue.teamNumber} · ${issue.positionLabel}',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _NotInTbaDetailPage(
                      docId: issue.docId,
                      entryType: issue.entryType,
                    ),
                  ),
                ),
              ),
            for (final issue in snapshot.duplicates)
              _AuditIssueItem(
                type: ScoutAuditIssueType.duplicate,
                title: issue.entryType == ScoutAuditEntryType.strat
                    ? 'Match ${issue.matchNumber} (Strat)'
                    : 'Match ${issue.matchNumber}',
                subtitle: issue.entryType == ScoutAuditEntryType.strat
                    ? 'Strat · ${_allianceLabel(issue.alliance)}'
                    : issue.teamNumber == null
                    ? _posLabel(issue.pos)
                    : 'Team ${issue.teamNumber} · ${_posLabel(issue.pos)}',
                trailing: '${issue.entries.length} entries',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _DuplicateDetailPage(
                      matchNumber: issue.matchNumber,
                      entryType: issue.entryType,
                      pos: issue.pos,
                      alliance: issue.alliance,
                    ),
                  ),
                ),
              ),
            for (final issue in snapshot.incorrect)
              _AuditIssueItem(
                type: ScoutAuditIssueType.incorrect,
                title: 'Match ${issue.matchNumber}',
                subtitle:
                    '${(issue.deviation * 100).toStringAsFixed(0)}% off TBA · ${issue.teams.join(', ')}',
                trailing: issue.alliance == 'red' ? 'Red' : 'Blue',
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _IncorrectDataDetailPage(
                      matchNumber: issue.matchNumber,
                      alliance: issue.alliance,
                    ),
                  ),
                ),
              ),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSummaryCard(context, snapshot, threshold),
                      const SizedBox(height: 16),
                      for (final type in ScoutAuditIssueType.values) ...[
                        _buildIssueSectionHeader(
                          context,
                          type,
                          allIssues,
                          threshold,
                        ),
                        const SizedBox(height: 8),
                        ...allIssues
                            .where((i) => i.type == type)
                            .map(
                              (issue) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildIssueCard(context, issue),
                              ),
                            ),
                        if (allIssues.where((i) => i.type == type).isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              elevation: 0,
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No issues',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showManualScoutDialog(BuildContext context) async {
    final selection = await showDialog<_ManualScoutSelection>(
      context: context,
      builder: (_) => const _ManualScoutDialog(),
    );

    if (selection == null || !context.mounted || !mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MatchScoutingFormPage(
          eventKey: ref.read(currentEventProvider),
          matchNumber: selection.matchNumber,
          pos: selection.pos,
          teamNumber: selection.teamNumber,
        ),
      ),
    );

    if (saved == true) {
      ref.invalidate(scoutAuditSnapshotProvider);
    }
  }

  Widget _buildSummaryCard(
    BuildContext context,
    ScoutAuditSnapshot snapshot,
    double threshold,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalIssues =
        snapshot.incompleteMatches.length +
        snapshot.notInTba.length +
        snapshot.duplicates.length +
        snapshot.incorrect.length;

    return Card(
      color: colorScheme.primaryContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$totalIssues ${totalIssues == 1 ? 'Issue' : 'Issues'} Found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Incorrect Data Threshold: >${(threshold * 100).toStringAsFixed(0)}% deviation',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer.withAlpha(200),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssueSectionHeader(
    BuildContext context,
    ScoutAuditIssueType type,
    List<_AuditIssueItem> allIssues,
    double threshold,
  ) {
    final count = allIssues.where((i) => i.type == type).length;
    final colorScheme = Theme.of(context).colorScheme;

    String label;
    IconData icon;
    switch (type) {
      case ScoutAuditIssueType.incomplete:
        label = 'Incomplete Match';
        icon = Symbols.pending_rounded;
      case ScoutAuditIssueType.notInTba:
        label = 'Not in TBA';
        icon = Symbols.help_rounded;
      case ScoutAuditIssueType.duplicate:
        label = 'Duplicate';
        icon = Symbols.content_copy_rounded;
      case ScoutAuditIssueType.incorrect:
        label = 'Incorrect Data';
        icon = Symbols.warning_rounded;
    }

    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: count > 0
                ? colorScheme.errorContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: count > 0
                  ? colorScheme.onErrorContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIssueCard(BuildContext context, _AuditIssueItem issue) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: issue.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      issue.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (issue.trailing != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    issue.trailing!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (issue.onTap != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Symbols.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showThresholdDialog(
    BuildContext context,
    double threshold,
  ) async {
    var value = threshold;

    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Incorrect Data Threshold'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(value * 100).toStringAsFixed(0)}%'),
                const SizedBox(height: 8),
                SfSlider(
                  min: 0.05,
                  max: 1.0,
                  stepSize: 0.01,
                  value: value,
                  enableTooltip: true,
                  tooltipTextFormatterCallback: (actualValue, _) =>
                      '${(actualValue * 100).toStringAsFixed(0)}%',
                  onChanged: (dynamic next) {
                    setState(() => value = (next as double));
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (changed == true) {
      await ref
          .read(scoutAuditIncorrectThresholdProvider.notifier)
          .setThreshold(value);
      ref.invalidate(scoutAuditSnapshotProvider);
    }
  }
}

class _IncompleteMatchDetailPage extends ConsumerStatefulWidget {
  const _IncompleteMatchDetailPage({
    required this.matchNumber,
    required this.entryType,
  });

  final int matchNumber;
  final ScoutAuditEntryType entryType;

  @override
  ConsumerState<_IncompleteMatchDetailPage> createState() =>
      _IncompleteMatchDetailPageState();
}

class _IncompleteMatchDetailPageState
    extends ConsumerState<_IncompleteMatchDetailPage> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final eventKey = ref.watch(currentEventProvider);
    final snapshotAsync = ref.watch(scoutAuditSnapshotProvider);
    final docs =
        ref.watch(scoutingDataProvider).value ?? const <ScoutingDocument>[];
    final tbaMatchesAsync = ref.watch(cachedTbaMatchesProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isStrat = widget.entryType == ScoutAuditEntryType.strat;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isStrat
              ? 'Match ${widget.matchNumber} (Strat)'
              : 'Match ${widget.matchNumber}',
        ),
        actions: [
          IconButton(
            onPressed: () => _openMatchVideo(
              context,
              tbaMatchesAsync.asData?.value ?? const <Map<String, dynamic>>[],
              widget.matchNumber,
            ),
            icon: const Icon(Symbols.play_circle_rounded),
            tooltip: 'Watch Match Video',
          ),
          IconButton(
            onPressed: _working
                ? null
                : () => _confirmDeleteAllEntries(context, eventKey, docs),
            icon: const Icon(Symbols.delete_rounded),
            tooltip: 'Delete all entries',
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            'Unable to load issue state.',
            style: TextStyle(color: colorScheme.error),
          ),
        ),
        data: (snapshot) {
          final issue = snapshot.incompleteMatches
              .where(
                (i) =>
                    i.entryType == widget.entryType &&
                    i.matchNumber == widget.matchNumber,
              )
              .firstOrNull;

          if (issue == null || issue.missingSlots.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: colorScheme.secondaryContainer,
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Symbols.pending_rounded,
                                color: colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${issue.missingSlots.length} missing ${issue.entryType == ScoutAuditEntryType.strat ? (issue.missingSlots.length == 1 ? 'alliance' : 'alliances') : (issue.missingSlots.length == 1 ? 'position' : 'positions')}',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isStrat) ...[
                        const SizedBox(height: 12),
                        Card(
                          color: colorScheme.surfaceContainer,
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Strat scouting cannot be opened from Scout Audit. Scout the missing match on the original tablet or use the delete all entries button to resolve this issue.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      for (final slot in issue.missingSlots) ...[
                        Card(
                          color: colorScheme.surfaceContainer,
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: isStrat
                                ? null
                                : () => _openMatchForm(
                                    context,
                                    eventKey: eventKey,
                                    matchNumber: issue.matchNumber,
                                    slot: slot,
                                    docs: docs,
                                  ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isStrat
                                              ? _allianceLabel(slot.alliance)
                                              : 'Team ${slot.teamNumber}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          slot.label,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isStrat)
                                    Icon(
                                      Symbols.chevron_right_rounded,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openMatchForm(
    BuildContext context, {
    required String eventKey,
    required int matchNumber,
    required AuditSlot slot,
    required List<ScoutingDocument> docs,
  }) async {
    final existing = _latestDocFor(docs, matchNumber, slot.pos);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MatchScoutingFormPage(
          eventKey: eventKey,
          matchNumber: matchNumber,
          pos: slot.pos,
          teamNumber: slot.teamNumber,
          existing: existing,
        ),
      ),
    );

    if (saved == true) {
      ref.invalidate(scoutAuditSnapshotProvider);
    }
  }

  Future<void> _openMatchVideo(
    BuildContext context,
    List<Map<String, dynamic>> matches,
    int matchNumber,
  ) async {
    await _launchMatchVideo(
      context,
      ref.read(currentEventProvider),
      matches,
      matchNumber,
    );
  }

  Future<void> _confirmDeleteAllEntries(
    BuildContext context,
    String eventKey,
    List<ScoutingDocument> docs,
  ) async {
    final noun = widget.entryType == ScoutAuditEntryType.strat
        ? 'strat entries'
        : 'scouted entries';
    final confirmed = await _confirm(
      context,
      title: 'Delete all entries?',
      message: 'This will remove all $noun for match ${widget.matchNumber}.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;

    setState(() => _working = true);
    try {
      final client = ref.read(honeycombClientProvider);
      if (widget.entryType == ScoutAuditEntryType.strat) {
        final stratDocs = _stratDocsForMatch(
          docs,
          eventKey,
          widget.matchNumber,
        );
        for (final doc in stratDocs) {
          await client.delete('/scouting/${doc.id}?type=strat');
        }
      } else {
        final matchDocs = matchDocsForMatch(docs, eventKey, widget.matchNumber);
        for (final doc in matchDocs) {
          await client.delete('/scouting/${doc.id}?type=match');
        }
      }
      await ref.read(scoutingDataProvider.notifier).refresh();
      ref.invalidate(scoutAuditSnapshotProvider);
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!context.mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete entries: $error')),
      );
    }
  }
}

class _NotInTbaDetailPage extends ConsumerStatefulWidget {
  const _NotInTbaDetailPage({required this.docId, required this.entryType});

  final String docId;
  final ScoutAuditEntryType entryType;

  @override
  ConsumerState<_NotInTbaDetailPage> createState() =>
      _NotInTbaDetailPageState();
}

class _NotInTbaDetailPageState extends ConsumerState<_NotInTbaDetailPage> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final docs =
        ref.watch(scoutingDataProvider).value ?? const <ScoutingDocument>[];
    final doc = docs.where((d) => d.id == widget.docId).firstOrNull;
    final colorScheme = Theme.of(context).colorScheme;

    if (doc == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final match =
        TeamScoutingBundle.matchNumber(doc) ?? _matchNumberFromMeta(doc.meta);
    final team = TeamScoutingBundle.teamNumber(doc);
    final pos = widget.entryType == ScoutAuditEntryType.strat
        ? _allianceLabel(doc.meta?['alliance']?.toString())
        : _posLabel(_posOf(doc));

    return Scaffold(
      appBar: AppBar(title: const Text('Not in TBA')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: colorScheme.errorContainer,
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Symbols.help_rounded,
                            color: colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This entry doesn\'t match any TBA schedule',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: colorScheme.onErrorContainer,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: colorScheme.surfaceContainer,
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Match: ${match ?? 'Unknown'}'),
                          Text(
                            widget.entryType == ScoutAuditEntryType.strat
                                ? 'Type: Strat'
                                : 'Team: ${team ?? 'Unknown'}',
                          ),
                          Text('Position: $pos'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () => _deleteDoc(context, doc.id),
                    icon: const Icon(Symbols.delete_rounded),
                    label: const Text('Delete Entry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDoc(BuildContext context, String docId) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete entry?',
      message: 'This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;

    setState(() => _working = true);
    try {
      await ref
          .read(honeycombClientProvider)
          .delete(
            '/scouting/$docId?type=${widget.entryType == ScoutAuditEntryType.strat ? 'strat' : 'match'}',
          );
      await ref.read(scoutingDataProvider.notifier).refresh();
      ref.invalidate(scoutAuditSnapshotProvider);
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!context.mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete entry: $error')));
    }
  }
}

class _DuplicateDetailPage extends ConsumerStatefulWidget {
  const _DuplicateDetailPage({
    required this.matchNumber,
    required this.entryType,
    this.pos,
    this.alliance,
  });

  final int matchNumber;
  final ScoutAuditEntryType entryType;
  final int? pos;
  final String? alliance;

  @override
  ConsumerState<_DuplicateDetailPage> createState() =>
      _DuplicateDetailPageState();
}

class _DuplicateDetailPageState extends ConsumerState<_DuplicateDetailPage> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(scoutAuditSnapshotProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Duplicate Entries')),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            'Unable to load duplicate issue.',
            style: TextStyle(color: colorScheme.error),
          ),
        ),
        data: (snapshot) {
          final issue = snapshot.duplicates.where((d) {
            if (d.entryType != widget.entryType) return false;
            if (d.matchNumber != widget.matchNumber) return false;
            if (widget.entryType == ScoutAuditEntryType.strat) {
              return d.alliance == widget.alliance;
            }
            return d.pos == widget.pos;
          }).firstOrNull;

          if (issue == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          if (issue.identical) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          color: colorScheme.tertiaryContainer,
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Symbols.content_copy_rounded,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Match ${issue.matchNumber} · ${_duplicateIdentityLabel(issue)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onTertiaryContainer,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${issue.entries.length} identical entries found',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onTertiaryContainer
                                                  .withAlpha(200),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          color: colorScheme.surfaceContainer,
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'These entries contain identical data. Would you like to keep the most recent and delete the rest?',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _working
                              ? null
                              : () => _keepEntry(
                                  issue.entries.first,
                                  issue.entries,
                                ),
                          icon: const Icon(Symbols.check_rounded),
                          label: const Text('Keep Most Recent'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return _MergeConflictView(
            issue: issue,
            working: _working,
            onConfirmKeep: _confirmKeep,
          );
        },
      ),
    );
  }

  Future<void> _confirmKeep(
    ScoutingDocument selected,
    List<ScoutingDocument> all,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Keep this entry?',
      message: 'Keep this entry and delete the others?',
      confirmLabel: 'Keep',
    );
    if (!confirmed || !mounted) return;
    await _keepEntry(selected, all);
  }

  Future<void> _keepEntry(
    ScoutingDocument selected,
    List<ScoutingDocument> all,
  ) async {
    setState(() => _working = true);
    try {
      final client = ref.read(honeycombClientProvider);
      final deleteType = widget.entryType == ScoutAuditEntryType.strat
          ? 'strat'
          : 'match';
      for (final doc in all) {
        if (doc.id == selected.id) continue;
        await client.delete('/scouting/${doc.id}?type=$deleteType');
      }
      await ref.read(scoutingDataProvider.notifier).refresh();
      ref.invalidate(scoutAuditSnapshotProvider);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve duplicate: $error')),
      );
    }
  }
}

class _IncorrectDataDetailPage extends ConsumerStatefulWidget {
  const _IncorrectDataDetailPage({
    required this.matchNumber,
    required this.alliance,
  });

  final int matchNumber;
  final String alliance;

  @override
  ConsumerState<_IncorrectDataDetailPage> createState() =>
      _IncorrectDataDetailPageState();
}

class _IncorrectDataDetailPageState
    extends ConsumerState<_IncorrectDataDetailPage> {
  final _rescannedTeams = <int>{};

  @override
  Widget build(BuildContext context) {
    final eventKey = ref.watch(currentEventProvider);
    final threshold = ref.watch(scoutAuditIncorrectThresholdProvider);
    final snapshotAsync = ref.watch(scoutAuditSnapshotProvider);
    final docs =
        ref.watch(scoutingDataProvider).value ?? const <ScoutingDocument>[];
    final tbaMatchesAsync = ref.watch(cachedTbaMatchesProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isRed = widget.alliance == 'red';

    return Scaffold(
      appBar: AppBar(
        title: Text('Match ${widget.matchNumber}'),
        actions: [
          IconButton(
            onPressed: () => _launchMatchVideo(
              context,
              eventKey,
              tbaMatchesAsync.asData?.value ?? const <Map<String, dynamic>>[],
              widget.matchNumber,
            ),
            icon: const Icon(Symbols.play_circle_rounded),
            tooltip: 'Watch Match Video',
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text(
            'Unable to load incorrect-data issue.',
            style: TextStyle(color: colorScheme.error),
          ),
        ),
        data: (snapshot) {
          final metric = snapshot.metricFor(
            widget.matchNumber,
            widget.alliance,
          );
          if (metric == null) {
            return Center(
              child: Text(
                'Alliance metric unavailable.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            );
          }

          final ratio = (metric.deviation / threshold).clamp(0.0, 1.0);
          final looksGood = metric.deviation <= threshold;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: isRed
                            ? const Color(0xFFFFCDD2)
                            : const Color(0xFFBBDEFB),
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Symbols.warning_rounded,
                                color: isRed
                                    ? const Color(0xFFC62828)
                                    : const Color(0xFF1565C0),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${isRed ? 'Red' : 'Blue'} Alliance',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: isRed
                                                ? const Color(0xFFC62828)
                                                : const Color(0xFF1565C0),
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${(metric.deviation * 100).toStringAsFixed(0)}% deviation from TBA',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: isRed
                                                ? const Color(
                                                    0xFFC62828,
                                                  ).withAlpha(200)
                                                : const Color(
                                                    0xFF1565C0,
                                                  ).withAlpha(200),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: colorScheme.surfaceContainer,
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Scouted: ${metric.scoutedSum}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                  Text(
                                    'TBA: ${metric.tbaScore}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 10,
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  color: looksGood
                                      ? Colors.green
                                      : colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    looksGood
                                        ? Symbols.check_circle_rounded
                                        : Symbols.error_rounded,
                                    size: 16,
                                    color: looksGood
                                        ? Colors.green
                                        : colorScheme.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    looksGood
                                        ? 'Within threshold'
                                        : '${_rescannedTeams.length} team${_rescannedTeams.length == 1 ? '' : 's'} re-scouted',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Teams to re-scout',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final slot in metric.slots) ...[
                        Card(
                          color: colorScheme.surfaceContainer,
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _openRescout(
                              context,
                              eventKey: eventKey,
                              metric: metric,
                              slot: slot,
                              docs: docs,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  if (_rescannedTeams.contains(slot.teamNumber))
                                    Icon(
                                      Symbols.check_circle_rounded,
                                      color: Colors.green,
                                      size: 20,
                                    )
                                  else
                                    Icon(
                                      Symbols.edit_rounded,
                                      color: colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Team ${slot.teamNumber}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          slot.label,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Symbols.chevron_right_rounded,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRescout(
    BuildContext context, {
    required String eventKey,
    required AllianceMetric metric,
    required AuditSlot slot,
    required List<ScoutingDocument> docs,
  }) async {
    final existing = _latestDocFor(docs, metric.matchNumber, slot.pos);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MatchScoutingFormPage(
          eventKey: eventKey,
          matchNumber: metric.matchNumber,
          pos: slot.pos,
          teamNumber: slot.teamNumber,
          existing: existing,
        ),
      ),
    );

    if (saved == true) {
      setState(() => _rescannedTeams.add(slot.teamNumber));
      ref.invalidate(scoutAuditSnapshotProvider);
    }
  }
}

class _ManualScoutSelection {
  const _ManualScoutSelection({
    required this.matchNumber,
    required this.teamNumber,
    required this.pos,
  });

  final int matchNumber;
  final int teamNumber;
  final int pos;
}

class _ManualScoutDialog extends ConsumerStatefulWidget {
  const _ManualScoutDialog();

  @override
  ConsumerState<_ManualScoutDialog> createState() => _ManualScoutDialogState();
}

class _ManualScoutDialogState extends ConsumerState<_ManualScoutDialog> {
  final _matchController = TextEditingController();
  final _teamController = TextEditingController();

  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _matchController.dispose();
    _teamController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final matchNumber = int.tryParse(_matchController.text.trim());
    final teamNumber = int.tryParse(_teamController.text.trim());

    if (matchNumber == null || matchNumber <= 0) {
      setState(() => _errorText = 'Enter a valid match number.');
      return;
    }
    if (teamNumber == null || teamNumber <= 0) {
      setState(() => _errorText = 'Enter a valid team number.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final eventKey = ref.read(currentEventProvider);
      final matches = await ref.read(cachedTbaMatchesProvider.future);
      final docs = await ref.read(scoutingDataProvider.future);

      final match = findTbaMatchForNumber(matches, eventKey, matchNumber);
      if (match == null) {
        if (!mounted) return;
        setState(
          () => _errorText =
              'Match $matchNumber is not in the current event schedule.',
        );
        return;
      }

      final slot = findAuditSlotForTeamInMatch(match, teamNumber);
      if (slot == null) {
        if (!mounted) return;
        setState(
          () => _errorText =
              'Team $teamNumber did not play in match $matchNumber.',
        );
        return;
      }

      final alreadyScouted = docs.any((doc) {
        final meta = doc.meta;
        if (meta?['type']?.toString() != 'match' ||
            meta?['event']?.toString() != eventKey) {
          return false;
        }

        final parsedMatch = int.tryParse(
          doc.data['matchNumber']?.toString() ?? '',
        );
        final parsedTeam = TeamScoutingBundle.teamNumber(doc);
        return parsedMatch == matchNumber && parsedTeam == teamNumber;
      });

      if (alreadyScouted) {
        if (!mounted) return;
        setState(
          () => _errorText =
              'Team $teamNumber has already been scouted for match $matchNumber.',
        );
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        _ManualScoutSelection(
          matchNumber: matchNumber,
          teamNumber: teamNumber,
          pos: slot.pos,
        ),
      );
    } catch (error) {
      setState(
        () => _errorText = 'Unable to validate scouting request: $error',
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Manual Scout'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _matchController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Match number',
                hintText: 'e.g. 12',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _teamController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Team number',
                hintText: 'e.g. 2046',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Scout'),
        ),
      ],
    );
  }
}

class _AuditIssueItem {
  final ScoutAuditIssueType type;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  const _AuditIssueItem({
    required this.type,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(
            confirmLabel,
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
        ),
      ],
    ),
  );

  return confirmed == true;
}

Future<void> _launchMatchVideo(
  BuildContext context,
  String eventKey,
  List<Map<String, dynamic>> matches,
  int matchNumber,
) async {
  final match = findTbaMatchForNumber(matches, eventKey, matchNumber);
  final videoKey = match == null ? null : matchVideoKey(match);

  if (videoKey == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No match video is available.')),
      );
    }
    return;
  }

  await launchUrl(
    Uri.parse('https://www.youtube.com/watch?v=$videoKey'),
    mode: LaunchMode.externalApplication,
  );
}

ScoutingDocument? _latestDocFor(
  List<ScoutingDocument> docs,
  int matchNumber,
  int pos,
) {
  final candidates = docs.where((doc) {
    final meta = doc.meta;
    if (meta?['type']?.toString() != 'match') return false;
    final rawMatch = doc.data['matchNumber'];
    final rawPos = doc.data['pos'];
    final parsedMatch = rawMatch is int
        ? rawMatch
        : int.tryParse(rawMatch?.toString() ?? '');
    final parsedPos = rawPos is int
        ? rawPos
        : int.tryParse(rawPos?.toString() ?? '');
    return parsedMatch == matchNumber && parsedPos == pos;
  }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return candidates.firstOrNull;
}

List<ScoutingDocument> _stratDocsForMatch(
  List<ScoutingDocument> docs,
  String eventKey,
  int matchNumber,
) {
  return docs
      .where((doc) {
        final meta = doc.meta;
        if (meta?['type']?.toString() != 'strat') return false;
        if (meta?['event']?.toString() != eventKey) return false;
        return _matchNumberFromMeta(meta) == matchNumber;
      })
      .toList(growable: false);
}

int? _posOf(ScoutingDocument doc) {
  final raw = doc.data['pos'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '');
}

String _posLabel(int? pos) {
  final parsed = ScoutPosition.fromPosIndex(pos);
  return parsed?.displayName ?? 'Unknown Position';
}

String _allianceLabel(String? alliance) {
  return switch (alliance?.toLowerCase()) {
    'red' => 'Red Alliance',
    'blue' => 'Blue Alliance',
    _ => 'Unknown Alliance',
  };
}

int? _matchNumberFromMeta(Map<String, dynamic>? meta) {
  final raw = meta?['matchNumber'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '');
}

String _duplicateIdentityLabel(DuplicateIssue issue) {
  if (issue.entryType == ScoutAuditEntryType.strat) {
    return _allianceLabel(issue.alliance);
  }
  return _posLabel(issue.pos);
}

class _MergeConflictView extends StatefulWidget {
  const _MergeConflictView({
    required this.issue,
    required this.working,
    required this.onConfirmKeep,
  });

  final DuplicateIssue issue;
  final bool working;
  final Function(ScoutingDocument, List<ScoutingDocument>) onConfirmKeep;

  @override
  State<_MergeConflictView> createState() => _MergeConflictViewState();
}

class _MergeConflictViewState extends State<_MergeConflictView> {
  late Map<int, List<String>> _jsonLines;
  late List<ScrollController> _verticalControllers;
  bool _syncingVerticalScroll = false;

  @override
  void initState() {
    super.initState();
    _initializeJsonLines();
    _initializeScrollControllers();
  }

  @override
  void didUpdateWidget(covariant _MergeConflictView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.issue.entries.length != widget.issue.entries.length) {
      for (final controller in _verticalControllers) {
        controller.dispose();
      }
      _initializeJsonLines();
      _initializeScrollControllers();
    }
  }

  @override
  void dispose() {
    for (final controller in _verticalControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initializeJsonLines() {
    _jsonLines = {};

    for (var i = 0; i < widget.issue.entries.length; i++) {
      final doc = widget.issue.entries[i];
      final json = const JsonEncoder.withIndent('  ').convert(doc.data);
      _jsonLines[i] = json.split('\n');
    }
  }

  void _initializeScrollControllers() {
    _verticalControllers = List<ScrollController>.generate(
      widget.issue.entries.length,
      (index) {
        final controller = ScrollController();
        controller.addListener(() => _syncVerticalScroll(index));
        return controller;
      },
    );
  }

  void _syncVerticalScroll(int sourceIndex) {
    if (_syncingVerticalScroll || sourceIndex >= _verticalControllers.length) {
      return;
    }

    final source = _verticalControllers[sourceIndex];
    if (!source.hasClients) return;

    final sourceMaxExtent = source.position.maxScrollExtent;
    final sourcePixels = source.offset;
    final progress = sourceMaxExtent <= 0
        ? 0.0
        : sourcePixels / sourceMaxExtent;

    _syncingVerticalScroll = true;
    try {
      for (var i = 0; i < _verticalControllers.length; i++) {
        if (i == sourceIndex) continue;
        final target = _verticalControllers[i];
        if (!target.hasClients) continue;

        final targetMaxExtent = target.position.maxScrollExtent;
        final targetOffset = (progress * targetMaxExtent).clamp(
          0.0,
          targetMaxExtent,
        );
        if ((target.offset - targetOffset).abs() > 0.5) {
          target.jumpTo(targetOffset);
        }
      }
    } finally {
      _syncingVerticalScroll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final numEntries = widget.issue.entries.length;
    final maxLines = _jsonLines.values
        .map((lines) => lines.length)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        Container(
          color: colorScheme.primaryContainer.withAlpha(100),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Symbols.merge_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Match ${widget.issue.matchNumber} · ${_duplicateIdentityLabel(widget.issue)}',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$numEntries duplicate entries',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < numEntries; i++)
                    FilledButton.tonal(
                      onPressed: widget.working
                          ? null
                          : () => widget.onConfirmKeep(
                              widget.issue.entries[i],
                              widget.issue.entries,
                            ),
                      child: Text('Keep Entry ${i + 1}'),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const minColumnWidth = 420.0;
              const dividerWidth = 1.0;
              final widthPerColumn = math.max(
                minColumnWidth,
                (constraints.maxWidth - (numEntries - 1) * dividerWidth) /
                    numEntries,
              );
              final totalWidth =
                  (widthPerColumn * numEntries) +
                  (numEntries - 1) * dividerWidth;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (
                        var entryIdx = 0;
                        entryIdx < numEntries;
                        entryIdx++
                      ) ...[
                        SizedBox(
                          width: widthPerColumn,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                color: colorScheme.primaryContainer.withAlpha(
                                  100,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Text(
                                  'Entry ${entryIdx + 1}',
                                  style: textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  controller: _verticalControllers[entryIdx],
                                  padding: EdgeInsets.zero,
                                  itemCount: maxLines,
                                  itemBuilder: (context, lineIdx) {
                                    return _buildLineWidget(
                                      context,
                                      entryIdx,
                                      lineIdx,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (entryIdx < numEntries - 1)
                          Container(
                            width: dividerWidth,
                            color: colorScheme.outlineVariant,
                          ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLineWidget(BuildContext context, int entryIdx, int lineIdx) {
    final colorScheme = Theme.of(context).colorScheme;
    final lines = _jsonLines[entryIdx]!;

    if (lineIdx >= lines.length) {
      return Container(
        height: 20,
        color: colorScheme.surfaceContainerLowest.withAlpha(50),
      );
    }

    final line = lines[lineIdx];
    final isDifferent = _isLineDifferent(lineIdx);
    final bgColor = isDifferent
        ? colorScheme.tertiaryContainer.withAlpha(80)
        : null;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${lineIdx + 1}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withAlpha(150),
              ),
            ),
          ),
          Expanded(
            child: Text(
              line.isEmpty ? ' ' : line,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
                color: isDifferent
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant.withAlpha(180),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isLineDifferent(int lineIdx) {
    if (_jsonLines.length < 2) return false;

    String? firstLine;
    for (var i = 0; i < _jsonLines.length; i++) {
      final lines = _jsonLines[i]!;
      final line = lineIdx < lines.length ? lines[lineIdx] : '';

      if (firstLine == null) {
        firstLine = line;
      } else if (line != firstLine) {
        return true;
      }
    }
    return false;
  }
}
