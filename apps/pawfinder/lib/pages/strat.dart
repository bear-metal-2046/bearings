import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pawfinder/providers/scouting_flow_provider.dart';
import 'package:pawfinder/providers/scouting_providers.dart';
import 'package:pawfinder/store/strat_state.dart';

class StratPage extends ConsumerStatefulWidget {
  const StratPage({super.key});

  @override
  ConsumerState<StratPage> createState() => _StratPageState();
}

class _StratPageState extends ConsumerState<StratPage> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scoutingSessionProvider);
    final identity = ref
        .read(scoutingSessionProvider.notifier)
        .createMatchIdentity();

    // shouldn't ever never be null here since the route requires a configured session
    if (identity == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final strat = ref.watch(stratStateProvider(identity));
    final notifier = ref.read(stratStateProvider(identity).notifier);
    final allianceTeamsAsync = ref.watch(allianceTeamsForSessionProvider);
    final size = MediaQuery.sizeOf(context);

    // Re-init when the match changes and teams are already loaded.
    ref.listen(scoutingSessionProvider, (_, _) {
      final id = ref
          .read(scoutingSessionProvider.notifier)
          .createMatchIdentity();
      if (id == null) return;
      final teams = ref
          .read(allianceTeamsForSessionProvider)
          .maybeWhen(data: (v) => v, orElse: () => const <String>[]);
      if (teams.isEmpty) return;
      ref.read(stratStateProvider(id).notifier).initFromSchedule(teams);
    });

    // Re-init when teams arrive asynchronously for the current match.
    ref.listen<AsyncValue<List<String>>>(allianceTeamsForSessionProvider, (
      _,
      next,
    ) {
      final teams = next.maybeWhen(
        data: (v) => v,
        orElse: () => const <String>[],
      );
      if (teams.isEmpty) return;
      final id = ref
          .read(scoutingSessionProvider.notifier)
          .createMatchIdentity();
      if (id == null) return;
      ref.read(stratStateProvider(id).notifier).initFromSchedule(teams);
    });

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: size.width),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: allianceTeamsAsync.when(
                data: (teams) => Text(
                  teams.isNotEmpty
                      ? 'Match ${session.matchNumber ?? "?"} · Alliance: ${teams.join(", ")}'
                      : 'Match ${session.matchNumber ?? "?"}',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                loading: () => Text(
                  'Match ${session.matchNumber ?? "?"}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                error: (e, s) => Text(
                  'Match ${session.matchNumber ?? "?"}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),

            _RankingList(
              title: 'Driver Skill',
              teams: strat.driverSkill,
              onReorder: notifier.reorderDriverSkill,
            ),
            _RankingList(
              title: 'Defensive Resilience',
              teams: strat.defensiveResilience,
              onReorder: notifier.reorderDefensiveResilience,
            ),
            _RankingList(
              title: 'Defensive Skill',
              teams: strat.defensiveSkill,
              onReorder: notifier.reorderDefensiveSkill,
            ),

            _RankingList(
              title: 'Mechanical Stability',
              teams: strat.mechanicalStability,
              onReorder: notifier.reorderMechanicalStability,
            ),

            ElevatedButton(
              onPressed: notifier.incrementAutoHumanPlayer,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  side: BorderSide(color: Colors.white, width: 1.0),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Auto Human Player: ${strat.autoHumanPlayerScore}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 56,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.remove,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: notifier.decrementAutoHumanPlayer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: notifier.incrementTeleHumanPlayer,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  side: BorderSide(color: Colors.white, width: 1.0),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tele Human Player: ${strat.teleHumanPlayerScore}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 56,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.remove,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: notifier.decrementTeleHumanPlayer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: () {
                ref.read(scoutingFlowControllerProvider).nextMatch();
              },
              child: const Text('Next Match'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingList extends StatelessWidget {
  final String title;
  final List<String> teams;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _RankingList({
    required this.title,
    required this.teams,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title, textScaler: TextScaler.linear(2)),
        SizedBox(
          width: 400,
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: onReorder,
            children: [
              for (final item in teams)
                ListTile(
                  key: ValueKey(item),
                  title: Text(item),
                  trailing: const Icon(Icons.drag_handle),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
