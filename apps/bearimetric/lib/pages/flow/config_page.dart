import 'package:material_ui/material_ui.dart';
import 'package:core/core.dart'
    show
        CompetitionMatch,
        GamePackFormKind,
        gamePackReadPermission,
        gamePackSubmitPermission;
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bearimetric/custom_widgets/upload_status_indicator.dart';
import 'package:bearimetric/models/scouting_session.dart';
import 'package:bearimetric/pages/flow/about_page.dart';
import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:ui/widgets/bearings_spinner.dart';

class ConfigPage extends ConsumerStatefulWidget {
  const ConfigPage({super.key});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  ScoutingEventSelection? _selectedEvent;
  ScoutPosition? _selectedPosition;
  final _customKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = ref.read(scoutingSessionProvider);
      if (mounted) {
        setState(() {
          _selectedEvent = session.event;
          _selectedPosition = session.position;
        });
      }
    });
  }

  @override
  void dispose() {
    _customKeyController.dispose();
    super.dispose();
  }

  void _applyCustomKey() {
    final raw = _customKeyController.text.trim();
    if (raw.isEmpty) return;

    final year = raw.length >= 4
        ? (int.tryParse(raw.substring(0, 4)) ?? DateTime.now().year)
        : DateTime.now().year;

    final customEvent = ScoutingEventSelection(key: raw, name: raw, year: year);
    setState(() => _selectedEvent = customEvent);
    ref.read(scoutingSessionProvider.notifier).setEvent(customEvent);
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);

    final practiceSchedule = ref.watch(practiceScheduleProvider).value;
    final hasTrainingSource = practiceSchedule != null;
    final canContinue =
        _selectedEvent != null &&
        _selectedPosition != null &&
        (_selectedEvent!.key != trainingEventKey || hasTrainingSource);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Comp and Position'),
        actionsPadding: EdgeInsets.only(right: 8),
        actions: [
          const UploadStatusIndicator(),
          const SizedBox(width: 5),
          IconButton(
            icon: const Icon(LucideIcons.info),
            tooltip: 'About',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            tooltip: 'Settings',
            onPressed: () => context.push('/config/settings'),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                            'Position',
                            style: Theme.of(context).textTheme.titleMedium,
                          )
                          .animate()
                          .fadeIn(duration: 500.ms)
                          .slideX(begin: -0.2, end: 0, duration: 500.ms),
                      const SizedBox(height: 8),
                      _PositionSelector(
                            selected: _selectedPosition,
                            onChanged: (pos) {
                              setState(() => _selectedPosition = pos);
                              ref
                                  .read(scoutingSessionProvider.notifier)
                                  .setPosition(pos);
                            },
                          )
                          .animate()
                          .fadeIn(delay: 100.ms, duration: 500.ms)
                          .slideY(
                            begin: 0.2,
                            end: 0,
                            delay: 100.ms,
                            duration: 500.ms,
                          ),

                      const SizedBox(height: 32),

                      Text(
                            'Competition',
                            style: Theme.of(context).textTheme.titleMedium,
                          )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 500.ms)
                          .slideX(
                            begin: -0.2,
                            end: 0,
                            delay: 200.ms,
                            duration: 500.ms,
                          ),
                      const SizedBox(height: 8),
                      eventsAsync.when(
                        data: (events) {
                          final trainingEvent = !hasTrainingSource
                              ? null
                              : ScoutingEventSelection(
                                  key: trainingEventKey,
                                  name: 'Training (no uploads)',
                                  year:
                                      int.tryParse(
                                        practiceSchedule.characters
                                            .take(4)
                                            .toString(),
                                      ) ??
                                      DateTime.now().year,
                                );
                          // Ensure displayEvents has unique event keys and, if we
                          // need to include a custom/previously-selected event,
                          // prepend it only once. This prevents multiple
                          // DropdownMenuItems from comparing equal and tripping the
                          // Dropdown assertion.
                          final combined = <ScoutingEventSelection>[
                            if (_selectedEvent != null &&
                                !events.any((e) => e.id == _selectedEvent!.key))
                              _selectedEvent!,
                            ...events.map(
                              ScoutingEventSelection.fromCompetition,
                            ),
                          ];

                          if (trainingEvent != null) {
                            combined.add(trainingEvent);
                          }

                          final displayEvents = <ScoutingEventSelection>[];
                          final seenKeys = <String>{};
                          for (final e in combined) {
                            if (seenKeys.add(e.key)) displayEvents.add(e);
                          }

                          // Pick the instance from displayEvents that matches the
                          // selected event by key so the Dropdown has exactly one
                          // matching item instance.
                          ScoutingEventSelection? initialValue;
                          if (_selectedEvent != null) {
                            try {
                              initialValue = displayEvents.firstWhere(
                                (e) => e.key == _selectedEvent!.key,
                              );
                            } catch (_) {
                              initialValue = null;
                            }
                          }

                          return DropdownButtonFormField<
                                ScoutingEventSelection
                              >(
                                initialValue: initialValue,
                                padding: EdgeInsets.all(4),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  ),
                                  hintText: 'Select a competition',
                                ),
                                items: displayEvents
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (event) {
                                  setState(() => _selectedEvent = event);
                                  if (event != null) {
                                    ref
                                        .read(scoutingSessionProvider.notifier)
                                        .setEvent(event);
                                  }
                                },
                              )
                              .animate()
                              .fadeIn(delay: 300.ms, duration: 500.ms)
                              .slideY(
                                begin: 0.2,
                                end: 0,
                                delay: 300.ms,
                                duration: 500.ms,
                              );
                        },
                        loading: () => const LinearProgressIndicator(),
                        error: (err, _) => _ErrorRetry(
                          message: 'Failed to load competitions',
                          onRetry: () => retryCompetitionEvents(
                            ProviderScope.containerOf(context, listen: false),
                            (year: DateTime.now().year, team: 'frc2046'),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Text(
                            'Or enter event key manually',
                            style: Theme.of(context).textTheme.titleMedium,
                          )
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 500.ms)
                          .slideX(
                            begin: -0.2,
                            end: 0,
                            delay: 400.ms,
                            duration: 500.ms,
                          ),
                      const SizedBox(height: 8),
                      Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _customKeyController,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                    hintText: 'e.g. 2026waahs',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                  ),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _applyCustomKey(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: _applyCustomKey,
                                child: const Text('Apply'),
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(delay: 500.ms, duration: 500.ms)
                          .slideY(
                            begin: 0.2,
                            end: 0,
                            delay: 500.ms,
                            duration: 500.ms,
                          ),

                      if (_selectedEvent != null) ...[
                        const SizedBox(height: 16),
                        if (_selectedEvent?.key == trainingEventKey)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Training uses the configured practice schedule when available. '
                              'Scouting records stay on this device and are not uploaded.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        _ScheduleDownloadTile(
                          key: ValueKey((
                            _selectedEvent!.key,
                            _selectedPosition,
                          )),
                          eventKey: _selectedEvent!.key,
                          position: _selectedPosition,
                        ).animate().fadeIn(delay: 500.ms, duration: 300.ms),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(32.0),
                child:
                    SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            style: ButtonStyle(
                              backgroundColor: canContinue
                                  ? WidgetStateProperty.all(
                                      Theme.of(context).colorScheme.primary,
                                    )
                                  : WidgetStateProperty.all(
                                      Theme.of(context).colorScheme.surface,
                                    ),
                            ),
                            onPressed: canContinue
                                ? () {
                                    final notifier = ref.read(
                                      scoutingSessionProvider.notifier,
                                    );
                                    notifier.setEvent(_selectedEvent!);
                                    notifier.setPosition(_selectedPosition!);
                                    context.go('/scout');
                                  }
                                : null,
                            icon: const Icon(LucideIcons.arrowRight),
                            label: const Text('Next'),
                          ),
                        )
                        .animate()
                        .fadeIn(delay: 600.ms, duration: 500.ms)
                        .slideY(
                          begin: 0.3,
                          end: 0,
                          delay: 600.ms,
                          duration: 500.ms,
                          curve: Curves.easeOut,
                        )
                        .shimmer(
                          delay: 1200.ms,
                          duration: 1500.ms,
                          color: Colors.white24,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionSelector extends StatelessWidget {
  final ScoutPosition? selected;
  final ValueChanged<ScoutPosition> onChanged;

  const _PositionSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _allianceRow(
          context,
          label: 'Red Alliance',
          color: Colors.red,
          positions: [
            ScoutPosition.red1,
            ScoutPosition.red2,
            ScoutPosition.red3,
            ScoutPosition.redStrat,
          ],
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 8),
        _allianceRow(
          context,
          label: 'Blue Alliance',
          color: Colors.blue,
          positions: [
            ScoutPosition.blue1,
            ScoutPosition.blue2,
            ScoutPosition.blue3,
            ScoutPosition.blueStrat,
          ],
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _allianceRow(
    BuildContext context, {
    required String label,
    required Color color,
    required List<ScoutPosition> positions,
    required ColorScheme colorScheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ScoutPosition>(
            segments: positions.map((pos) {
              return ButtonSegment<ScoutPosition>(
                value: pos,
                label: Text(pos.displayName),
              );
            }).toList(),
            selected: selected != null && positions.contains(selected)
                ? {selected!}
                : {},
            emptySelectionAllowed: true,
            onSelectionChanged: (Set<ScoutPosition> selection) {
              if (selection.isNotEmpty) {
                onChanged(selection.first);
              }
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return color.withValues(alpha: 0.3);
                }
                return colorScheme.surface;
              }),
              foregroundColor: WidgetStateProperty.resolveWith<Color>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.selected)) {
                  return colorScheme.onSurface;
                }
                return colorScheme.onSurface.withValues(alpha: 0.7);
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleDownloadTile extends ConsumerStatefulWidget {
  final String eventKey;
  final ScoutPosition? position;

  const _ScheduleDownloadTile({
    super.key,
    required this.eventKey,
    required this.position,
  });

  @override
  ConsumerState<_ScheduleDownloadTile> createState() =>
      _ScheduleDownloadTileState();
}

class _ScheduleDownloadTileState extends ConsumerState<_ScheduleDownloadTile> {
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final event = widget.eventKey == trainingEventKey
          ? await waitForValue(container, practiceScheduleProvider)
          : widget.eventKey;
      if (event == null) {
        throw StateError('Choose a practice event in Beariscope first.');
      }
      if (!mounted) return;
      final result = await ref.read(competitionProvider).matchResults(event);
      final matches = result.requireAvailable().items;
      if (!_hasSchedule(matches) || result.offline) {
        throw StateError('Connect to download a schedule for this position.');
      }
      retryCompetitionMatches(container, event);
      if (!mounted) return;
      final pack = await waitForValue(
        container,
        widget.eventKey == trainingEventKey
            ? practiceGamePackProvider(event)
            : eventGamePackProvider(event),
      );
      if (pack == null ||
          !_hasForm(pack.definition.forms.map((form) => form.kind))) {
        throw StateError(
          'Assign a GamePack with the required form in Beariscope.',
        );
      }
      if (!mounted) return;
      final grove = ref.read(bearingsGroveProvider);
      final roster = await scoutRosterQuery(grove).result();
      if (roster.requireAvailable().items.isEmpty || roster.offline) {
        throw StateError('Connect to download a scout roster.');
      }
      if (mounted) ref.invalidate(groveQueryProvider(scoutRosterQuery(grove)));
      final access = await waitForValue(container, groveAccessProvider);
      final permissions = access
          ?.requireAvailable()
          .items
          .singleOrNull
          ?.permissions;
      if (!_hasAccess(permissions)) {
        throw StateError('This device needs GamePack scouting access.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event ready for offline scouting'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  bool _hasAccess(Set<String>? permissions) =>
      permissions?.contains(gamePackReadPermission) == true &&
      (widget.eventKey == trainingEventKey ||
          permissions?.contains(gamePackSubmitPermission) == true);

  bool _hasSchedule(Iterable<CompetitionMatch> matches) {
    final position = widget.position;
    return position == null
        ? matches.isNotEmpty
        : matches.any((match) => canScoutMatch(match, position));
  }

  bool _hasForm(Iterable<GamePackFormKind> forms) => widget.position == null
      ? forms.any(
          (kind) =>
              kind == GamePackFormKind.match ||
              kind == GamePackFormKind.strategy,
        )
      : forms.contains(
          widget.position!.isStrategy
              ? GamePackFormKind.strategy
              : GamePackFormKind.match,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final training = widget.eventKey == trainingEventKey;
    final event = training
        ? ref.watch(practiceScheduleProvider).value
        : widget.eventKey;
    final eligibleMatches = ref.watch(matchesProvider(widget.eventKey));
    final pack = event == null
        ? null
        : ref.watch(
            training
                ? practiceGamePackProvider(event)
                : eventGamePackProvider(event),
          );
    final roster = ref.watch(scoutRosterProvider);
    final hasSchedule = _hasSchedule(eligibleMatches.value ?? []);
    final hasForm = _hasForm(
      pack?.value?.definition.forms.map((form) => form.kind) ?? [],
    );
    final hasRoster = roster.value?.isNotEmpty == true;
    final hasAccess = _hasAccess(
      ref.watch(permissionCheckerProvider)?.permissions,
    );
    final loaded = hasSchedule && hasForm && hasRoster && hasAccess;
    final missing = [
      if (!hasSchedule) 'schedule',
      if (!hasForm) 'GamePack form',
      if (!hasRoster) 'scout roster',
      if (!hasAccess) 'scouting access',
    ];
    final statusText = loaded
        ? 'Ready for offline scouting'
        : 'Missing ${missing.join(', ')}';

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Icon(
          loaded ? LucideIcons.cloudCheck : LucideIcons.cloudOff,
          size: 18,
          color: loaded ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        Text(statusText, style: theme.textTheme.bodySmall),
        _downloading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: BearingsSpinner(strokeWidth: 2),
              )
            : OutlinedButton.icon(
                onPressed: _download,
                icon: const Icon(LucideIcons.download, size: 16),
                label: const Text('Prepare for offline'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
              ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(LucideIcons.refreshCw),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
