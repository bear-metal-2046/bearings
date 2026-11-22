import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_modal.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_card.dart';
import 'package:ui/widgets/bearings_spinner.dart';
import 'package:ui/widgets/bearings_status_view.dart';
import 'package:uuid/uuid.dart';

import '../gamepacks/observation_list.dart';
import '../gamepacks/observation_page.dart';
import '../main_view.dart';

class GamePackAuditPage extends ConsumerStatefulWidget {
  const GamePackAuditPage({
    super.key,
    required this.event,
    required this.release,
  });

  final String event;
  final GamePack release;

  @override
  ConsumerState<GamePackAuditPage> createState() => _GamePackAuditPageState();
}

class _GamePackAuditPageState extends ConsumerState<GamePackAuditPage> {
  final _query = TextEditingController();
  String _search = '';
  String? _retracting;
  bool _showHistory = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _retract(GamePackObservation row) async {
    String reason = '';
    final confirmed = await BearingsModal.show<bool>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => BearingsModal(
          title: 'Retract observation?',
          actions: const [],
          primaryAction: BearingsModalPrimaryAction(
            label: 'Retract',
            icon: LucideIcons.undo2,
            enabled: reason.isNotEmpty,
            onPressed: () => BearingsModal.complete(context, true),
          ),
          content: TextField(
            autofocus: true,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Retraction reason'),
            onChanged: (value) => setDialogState(() => reason = value.trim()),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted || _retracting != null) return;
    setState(() => _retracting = row.id);
    try {
      await ref
          .read(bearingsGroveProvider)
          .create(
            GamePackObservation(
              id: const Uuid().v4(),
              event: row.event,
              gamePack: row.gamePack,
              team: row.team,
              match: row.match,
              station: row.station,
              scout: row.scout,
              form: row.formId,
              capturedAt: DateTime.now().toUtc(),
              answers: const {},
              supersedes: EntityRef(row.id),
              retracted: true,
              reason: reason,
            ),
            allowOffline: false,
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Observation retracted')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Retraction failed. $error')));
      }
    } finally {
      if (mounted) setState(() => _retracting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final main = MainViewController.of(context);
    final permission = ref.watch(permissionCheckerProvider);
    final canCorrect =
        permission?.hasPermission(gamePackCorrectPermission) == true;
    final canSubmit =
        permission?.hasPermission(gamePackSubmitPermission) == true;
    final history = ref.watch(gamePackObservationHistoryProvider(widget.event));
    final records = history.whenData(
      (snapshot) => snapshot.requireAvailable().items,
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Audit'),
          leading: main.isDesktop
              ? null
              : IconButton(
                  icon: const Icon(LucideIcons.menu),
                  onPressed: main.openDrawer,
                ),
          actions: [
            if (canSubmit &&
                widget.release.definition.formFor(GamePackFormKind.match) !=
                    null)
              IconButton(
                tooltip: 'Manual Scout',
                icon: const Icon(LucideIcons.plus),
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => _ManualGamePackScout(
                          event: widget.event,
                          release: widget.release,
                        ),
                      ),
                    ),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Coverage'),
              Tab(text: 'Observations'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Builder(
              builder: (context) => _ScoutingCoverage(
                event: widget.event,
                release: widget.release,
                onOpen: (match) {
                  _query.text = match;
                  setState(() => _search = match.toLowerCase());
                  DefaultTabController.of(context).animateTo(1);
                },
              ),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      labelText: 'Find team, match, or record',
                      prefixIcon: Icon(LucideIcons.search),
                    ),
                    onChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Show corrections and original records'),
                  value: _showHistory,
                  onChanged: (value) => setState(() => _showHistory = value),
                ),
                Expanded(
                  child: records.when(
                    loading: () => const Center(child: BearingsSpinner()),
                    error: (error, _) => BearingsStatusView(
                      icon: LucideIcons.circleAlert,
                      title: 'Audit unavailable',
                      subtitle: '$error',
                    ),
                    data: (rows) {
                      final all = rows
                          .where((row) => row.gamePack.id == widget.release.id)
                          .toList();
                      final active = activeGamePackObservations(all)
                          .map((row) => row.id)
                          .toSet();
                      final visible =
                          all
                              .where(
                                (row) =>
                                    (_showHistory || active.contains(row.id)) &&
                                    (_search.isEmpty ||
                                        [
                                          row.id,
                                          row.team?.id,
                                          row.match?.id,
                                          row.scout?.id,
                                        ].nonNulls.any(
                                          (value) => value
                                              .toLowerCase()
                                              .contains(_search),
                                        )),
                              )
                              .toList()
                            ..sort((a, b) {
                              final byTime = b.capturedAt.compareTo(
                                a.capturedAt,
                              );
                              return byTime == 0
                                  ? b.id.compareTo(a.id)
                                  : byTime;
                            });
                      if (visible.isEmpty) {
                        return const BearingsStatusView(
                          icon: LucideIcons.clipboardList,
                          title: 'No matching observations',
                        );
                      }
                      return BearingsCardList(
                        children: [
                          if (history.value?.offline == true)
                            const ListTile(
                              leading: Icon(LucideIcons.cloudOff),
                              title: Text('Showing cached observations'),
                            ),
                          for (final row in visible)
                            GamePackObservationCard(
                              key: ValueKey(row.id),
                              observation: row,
                              release: widget.release,
                              actions: [
                                if (canCorrect && active.contains(row.id)) ...[
                                  OutlinedButton(
                                    onPressed: _retracting != null
                                        ? null
                                        : () =>
                                              Navigator.of(
                                                context,
                                                rootNavigator: true,
                                              ).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      GamePackObservationPage(
                                                        title: 'Correct observation',
                                                        event: widget.event,
                                                        release: widget.release,
                                                        kind: widget
                                                            .release
                                                            .definition
                                                            .formById(
                                                              row.formId,
                                                            )
                                                            .kind,
                                                        previous: row,
                                                      ),
                                                ),
                                              ),
                                    child: const Text('Correct'),
                                  ),
                                  TextButton(
                                    onPressed: _retracting != null
                                        ? null
                                        : () => _retract(row),
                                    child: const Text('Retract'),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoutingCoverage extends ConsumerWidget {
  const _ScoutingCoverage({
    required this.event,
    required this.release,
    required this.onOpen,
  });

  final String event;
  final GamePack release;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKinds = {
      for (final form in release.definition.forms)
        if ([
          GamePackFormKind.match,
          GamePackFormKind.strategy,
        ].contains(form.kind))
          form.id: form.kind,
    };
    final schedule = ref.watch(competitionMatchesProvider(event));
    final observations = ref.watch(activeGamePackObservationsProvider(event));
    return schedule
        .flatMap(
          (result) => observations.whenData(
            (all) => (
              result.requireAvailable().items,
              all.where(
                (row) =>
                    row.gamePack.id == release.id &&
                    formKinds.containsKey(row.formId) &&
                    row.match != null,
              ),
            ),
          ),
        )
        .when(
          loading: () => const Center(child: BearingsSpinner()),
          error: (error, _) => BearingsStatusView(
            icon: LucideIcons.circleAlert,
            title: 'Coverage unavailable',
            subtitle: '$error',
          ),
          data: (data) {
            final (matches, rows) = data;
            final matchById = {for (final match in matches) match.id: match};
            final reported = <(String, int?), List<GamePackObservation>>{};
            final furthest = <GamePackFormKind, int>{};
            for (final row in rows) {
              final matchId = row.match!.id;
              reported.putIfAbsent((matchId, row.station), () => []).add(row);
              final match = matchById[matchId];
              if (match == null || match.level != 'qm') continue;
              final kind = formKinds[row.formId]!;
              if (match.matchNumber > (furthest[kind] ?? 0)) {
                furthest[kind] = match.matchNumber;
              }
            }
            final cards = <Widget>[];
            for (final match
                in matches
                    .where((match) => match.level == 'qm' && !match.practice)
                    .toList()
                  ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber))) {
              final missing = <String>[];
              for (final position in ScoutPosition.values) {
                final kind = position.isStrategy
                    ? GamePackFormKind.strategy
                    : GamePackFormKind.match;
                if (match.matchNumber > (furthest[kind] ?? 0)) continue;
                final teams =
                    (position.isRed ? match.red : match.blue)?.teams ?? [];
                if (teams.isEmpty || position.allianceIndex >= teams.length) {
                  continue;
                }
                if (!reported.containsKey((match.id, position.posIndex))) {
                  missing.add(position.displayName);
                }
              }
              if (missing.isNotEmpty) {
                cards.add(
                  BearingsCard(
                    title: 'Missing submissions · QM${match.matchNumber}',
                    subtitle: missing.join(', '),
                    onTap: () => onOpen(match.id),
                  ),
                );
              }
            }
            for (final entry in reported.entries) {
              final (match, station) = entry.key;
              final position = ScoutPosition.fromPosIndex(station)?.displayName;
              final label = [match, ?position].join(' · ');
              if (entry.value.length > 1) {
                final documents = entry.value;
                final differ = documents
                    .skip(1)
                    .any(
                      (row) =>
                          canonicalJson(row.answers) !=
                          canonicalJson(documents.first.answers),
                    );
                cards.add(
                  BearingsCard(
                    title: 'Duplicate submissions · $label',
                    subtitle:
                        '${documents.length} records · ${differ ? 'different answers' : 'matching answers'}',
                    onTap: () => onOpen(match),
                  ),
                );
              }
              if (!matchById.containsKey(match)) {
                cards.add(
                  BearingsCard(
                    title: 'Match missing from schedule · $label',
                    onTap: () => onOpen(match),
                  ),
                );
              }
            }
            if (cards.isEmpty) {
              return const BearingsStatusView(
                icon: LucideIcons.clipboardCheck,
                title: 'No coverage issues',
              );
            }
            return BearingsCardList(children: cards);
          },
        );
  }
}

class _ManualGamePackScout extends ConsumerStatefulWidget {
  const _ManualGamePackScout({required this.event, required this.release});

  final String event;
  final GamePack release;

  @override
  ConsumerState<_ManualGamePackScout> createState() =>
      _ManualGamePackScoutState();
}

class _ManualGamePackScoutState extends ConsumerState<_ManualGamePackScout> {
  CompetitionMatch? _match;
  ScoutPosition? _position;

  @override
  Widget build(BuildContext context) {
    final matches = ref
        .watch(competitionMatchesProvider(widget.event))
        .whenData(
          (result) => result
              .requireAvailable()
              .items
              .where((match) => !match.practice)
              .toList(),
        );
    final match = _match;
    List<EntityRef<CompetitionTeam>> teams(ScoutPosition position) =>
        (position.isRed ? match?.red : match?.blue)?.teams ?? [];
    final positions = ScoutPosition.values
        .where(
          (position) =>
              !position.isStrategy &&
              position.allianceIndex < teams(position).length,
        )
        .toList();
    final position = _position;
    return Scaffold(
      appBar: AppBar(title: const Text('Manual Scout')),
      body: matches.when(
        loading: () => const Center(child: BearingsSpinner()),
        error: (error, _) => BearingsStatusView(
          icon: LucideIcons.circleAlert,
          title: 'Schedule unavailable',
          subtitle: '$error',
        ),
        data: (schedule) => BearingsCardList(
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: match?.id,
              decoration: const InputDecoration(labelText: 'Match'),
              items: [
                for (final match in schedule)
                  DropdownMenuItem(value: match.id, child: Text(match.id)),
              ],
              onChanged: (id) => setState(() {
                _match = schedule.where((match) => match.id == id).firstOrNull;
                _position = null;
              }),
            ),
            DropdownButtonFormField<ScoutPosition>(
              key: ValueKey(match?.id),
              decoration: const InputDecoration(labelText: 'Station'),
              items: [
                for (final position in positions)
                  DropdownMenuItem(
                    value: position,
                    child: Text(position.displayName),
                  ),
              ],
              onChanged: match == null
                  ? null
                  : (choice) => setState(() => _position = choice),
            ),
            FilledButton(
              onPressed: match == null || position == null
                  ? null
                  : () async {
                      final team = teams(position)[position.allianceIndex];
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => GamePackObservationPage(
                            title: 'Scout ${team.id}',
                            event: widget.event,
                            release: widget.release,
                            kind: GamePackFormKind.match,
                            match: match.id,
                            station: position.posIndex,
                            team: team.id,
                            roster: teams(position)
                                .map((team) => team.id)
                                .toList(),
                          ),
                        ),
                      );
                      if (saved == true && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
              child: const Text('Open scouting form'),
            ),
          ],
        ),
      ),
    );
  }
}
