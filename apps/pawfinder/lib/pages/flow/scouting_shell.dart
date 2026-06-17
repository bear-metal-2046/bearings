import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:pawfinder/custom_widgets/upload_status_indicator.dart';
import 'package:pawfinder/data/local_data.dart';
import 'package:pawfinder/data/match_json_gen.dart';
import 'package:pawfinder/providers/app_provider.dart';
import 'package:pawfinder/providers/scouting_flow_provider.dart';
import 'package:pawfinder/providers/scouting_providers.dart';

class ScoutingShell extends ConsumerStatefulWidget {
  final Widget child;

  const ScoutingShell({super.key, required this.child});

  @override
  ConsumerState<ScoutingShell> createState() => _ScoutingShellState();
}

class _ScoutingShellState extends ConsumerState<ScoutingShell> {
  bool _shouldFlashTele = true; // controls the flashing state

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scoutingSessionProvider);
    final notifier = ref.read(scoutingSessionProvider.notifier);
    final matchNumber = session.matchNumber ?? 0;
    final position = session.position;
    final event = session.event;

    final upcomingMatchOptions =
        event != null && position != null && !position.isStrategy
        ? ref
              .watch(matchesProvider(event.key))
              .maybeWhen(
                data: (matches) =>
                    matches.where((m) => m.matchNumber != matchNumber).map((m) {
                      final rawTeam = m.teamNumberAt(position);
                      final team = rawTeam == '???' ? '—' : rawTeam;
                      return _UpcomingMatchOption(
                        matchNumber: m.matchNumber,
                        label: 'Match ${m.matchNumber} · Team $team',
                      );
                    }).toList(),
                orElse: () => const <_UpcomingMatchOption>[],
              )
        : const <_UpcomingMatchOption>[];

    // always contains the correct team even when navigating via prev/next.
    ref.listen<AsyncValue<int?>>(teamNumberForSessionProvider, (_, next) {
      final team = next.when(
        data: (t) => t,
        loading: () => null,
        error: (_, _) => null,
      );
      if (team == null) return;
      final identity = notifier.createMatchIdentity();
      if (identity == null) return;
      Hive.box(boxKey).put(matchTeamKey(identity), team);
    });

    final teamAsync = ref.watch(teamNumberForSessionProvider);
    final teamLabel = teamAsync.maybeWhen(
      data: (t) => t != null ? ' · $t' : '',
      orElse: () => '',
    );
    final positionLabel = position?.displayName ?? '';
    final matchMetaLabel = '$positionLabel$teamLabel';
    final dropdownFontSize = (MediaQuery.sizeOf(context).width / 30)
        .clamp(20.0, 24.0)
        .toDouble();
    final dropdownLabel = matchMetaLabel.isEmpty
        ? 'Match $matchNumber'
        : 'Match $matchNumber · $matchMetaLabel';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Exit to Scout Selection',
          onPressed: () async {
            final shouldExit = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Exit Scouting'),
                content: const Text(
                  'Are you sure you want to exit this match?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Exit'),
                  ),
                ],
              ),
            );
            if (shouldExit ?? false) {
              notifier.exitToScoutSelect();
              if (context.mounted) {
                context.go('/scout');
              }
            }
          },
        ),

        title: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            isDense: true,
            isExpanded: true,
            value: null,
            hint: Text(
              dropdownLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: dropdownFontSize),
            ),
            icon: const Icon(Icons.arrow_drop_down),
            onChanged: upcomingMatchOptions.isEmpty
                ? null
                : (selectedMatch) {
                    if (selectedMatch == null) return;
                    final flow = ref.read(scoutingFlowControllerProvider);
                    flow.markCurrentMatchForUpload();
                    flow.markCurrentStratForUpload();
                    notifier.setMatchNumber(selectedMatch);
                    context.go('/match/auto');
                  },
            items: upcomingMatchOptions
                .map(
                  (option) => DropdownMenuItem<int>(
                    value: option.matchNumber,
                    child: Text(option.label),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4, left: 8),
            child: UploadStatusIndicator(),
          ),
          const LightSwitch(),
          IconButton(
            icon: const Icon(Icons.skip_previous),
            tooltip: 'Previous Match',
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: () {
              ref.read(scoutingFlowControllerProvider).previousMatch();
              context.go('/match/auto');
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: 'Next Match',
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints.tightFor(width: 36, height: 36),
            onPressed: () async {
              final flow = ref.read(scoutingFlowControllerProvider);
              if (flow.shouldWarnForRapidNextMatchTaps()) {
                final shouldContinue = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Next Match Spam'),
                    content: const Text(
                      'Please do not spam the next match button. Every time you advance a match, it uploads it. By spamming you are uploading multiple empty matches which messes with the data. Use the dropdown instead (click the Match # • Color # • #### title bar)',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                );
                if (!(shouldContinue ?? false)) return;
              }

              flow.nextMatch();
              if (context.mounted) {
                context.go('/match/auto');
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex(context),
        indicatorColor: Theme.of(context).colorScheme.primary,

        onDestinationSelected: (index) {
          setState(() {
            if (index == 1) {
              _shouldFlashTele = false;
            }
          });
          switch (index) {
            case 0:
              context.go('/match/auto');
              break;
            case 1:
              context.go('/match/tele');
              break;
            case 2:
              context.go('/match/end');
              break;
          }
        },
        destinations: [
          NavigationDestination(icon: Icon(Icons.bolt), label: 'Auto'),
          NavigationDestination(
            icon: _shouldFlashTele
                ? Flash(
                    infinite: true,
                    delay: const Duration(seconds: 20),
                    child: const Icon(Icons.stacked_bar_chart_sharp),
                  )
                : const Icon(Icons.stacked_bar_chart_sharp),
            label: 'Tele',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_array),
            label: 'Post-Match',
          ),
        ],
      ),
    );
  }

  int _currentTabIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.contains('/tele')) return 1;
    if (location.contains('/end')) return 2;
    return 0;
  }
}

class _UpcomingMatchOption {
  final int matchNumber;
  final String label;

  const _UpcomingMatchOption({required this.matchNumber, required this.label});
}

class LightSwitch extends ConsumerWidget {
  const LightSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = ref.watch(brightnessNotifierProvider);
    final isDark = brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      isSelected: isDark,
      tooltip: isDark ? 'Use light theme' : 'Use dark theme',
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      color: scheme.onSurfaceVariant,
      selectedIcon: Icon(Icons.dark_mode, color: scheme.primary),
      icon: const Icon(Icons.light_mode_outlined),
      onPressed: () {
        ref.read(brightnessNotifierProvider.notifier).changeBrightness(!isDark);
      },
    );
  }
}
