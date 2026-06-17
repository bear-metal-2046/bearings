import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pawfinder/custom_widgets/upload_status_indicator.dart';
import 'package:pawfinder/models/scouting_session.dart';
import 'package:pawfinder/pages/flow/about_page.dart';
import 'package:pawfinder/providers/scouting_providers.dart';
import 'package:pawfinder/services/scout_sync_service.dart';

class ConfigPage extends ConsumerStatefulWidget {
  const ConfigPage({super.key});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  ScoutingEvent? _selectedEvent;
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

    final customEvent = ScoutingEvent(key: raw, name: raw, year: year);
    setState(() => _selectedEvent = customEvent);
    ref.read(scoutingSessionProvider.notifier).setEvent(customEvent);
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Comp and Position'),
        actionsPadding: EdgeInsets.only(right: 8),
        actions: [
          const UploadStatusIndicator(),
          const SizedBox(width: 5),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
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
                          // Ensure displayEvents has unique event keys and, if we
                          // need to include a custom/previously-selected event,
                          // prepend it only once. This prevents multiple
                          // DropdownMenuItems from comparing equal and tripping the
                          // Dropdown assertion.
                          final combined =
                              (_selectedEvent != null &&
                                  !events.any(
                                    (e) => e.key == _selectedEvent!.key,
                                  ))
                              ? [_selectedEvent!, ...events]
                              : events;

                          final displayEvents = <ScoutingEvent>[];
                          final seenKeys = <String>{};
                          for (final e in combined) {
                            if (seenKeys.add(e.key)) displayEvents.add(e);
                          }

                          // Pick the instance from displayEvents that matches the
                          // selected event by key so the Dropdown has exactly one
                          // matching item instance.
                          ScoutingEvent? initialValue;
                          if (_selectedEvent != null) {
                            try {
                              initialValue = displayEvents.firstWhere(
                                (e) => e.key == _selectedEvent!.key,
                              );
                            } catch (_) {
                              initialValue = null;
                            }
                          }

                          return DropdownButtonFormField<ScoutingEvent>(
                                initialValue: initialValue,
                                padding: EdgeInsets.all(4),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
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
                          onRetry: () => ref.invalidate(eventsProvider),
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
                        _ScheduleDownloadTile(
                          eventKey: _selectedEvent!.key,
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
                              backgroundColor:
                                  _selectedEvent != null &&
                                      _selectedPosition != null
                                  ? WidgetStateProperty.all(
                                      Theme.of(context).colorScheme.primary,
                                    )
                                  : WidgetStateProperty.all(
                                      Theme.of(context).colorScheme.surface,
                                    ),
                            ),
                            onPressed:
                                _selectedEvent != null &&
                                    _selectedPosition != null
                                ? () {
                                    final notifier = ref.read(
                                      scoutingSessionProvider.notifier,
                                    );
                                    notifier.setEvent(_selectedEvent!);
                                    notifier.setPosition(_selectedPosition!);
                                    context.go('/scout');
                                  }
                                : null,
                            icon: const Icon(Icons.arrow_forward),
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

  const _ScheduleDownloadTile({required this.eventKey});

  @override
  ConsumerState<_ScheduleDownloadTile> createState() =>
      _ScheduleDownloadTileState();
}

class _ScheduleDownloadTileState extends ConsumerState<_ScheduleDownloadTile> {
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      ref.invalidate(matchesProvider(widget.eventKey));
      await ref.read(matchesProvider(widget.eventKey).future);
      await ref.read(scoutSyncServiceProvider).syncDownEvent(widget.eventKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule refreshed and scouting synced'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchesAsync = ref.watch(matchesProvider(widget.eventKey));
    final loaded = matchesAsync.asData != null;
    final statusText = matchesAsync.when(
      data: (matches) => '${matches.length} matches loaded',
      loading: () => 'Loading schedule…',
      error: (_, _) => 'No schedule',
    );

    return Row(
      children: [
        Icon(
          loaded ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          size: 18,
          color: loaded ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        const SizedBox(width: 8),
        Text(statusText, style: theme.textTheme.bodySmall),
        const Spacer(),
        _downloading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Refresh schedule'),
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
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
