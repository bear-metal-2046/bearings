import 'package:material_ui/material_ui.dart';
import 'package:core/core.dart';
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:bearimetric/models/scouting_session.dart' show trainingEventKey;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bearimetric/custom_widgets/upload_status_indicator.dart';
import 'package:bearimetric/providers/scouting_providers.dart';
import 'package:ui/widgets/bearings_spinner.dart';

class MatchSelectPage extends ConsumerStatefulWidget {
  const MatchSelectPage({super.key});

  @override
  ConsumerState<MatchSelectPage> createState() => _MatchSelectPageState();
}

class _MatchSelectPageState extends ConsumerState<MatchSelectPage> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scoutingSessionProvider);

    if (session.event == null ||
        session.position == null ||
        session.scout == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/config');
      });
      return const Scaffold(body: Center(child: BearingsSpinner()));
    }

    final position = session.position!;
    final eventKey = session.event!.key;
    final permissions = ref.watch(permissionCheckerProvider);
    final training = eventKey == trainingEventKey;
    final source = training
        ? ref.watch(practiceScheduleProvider).value
        : eventKey;
    final canOpen =
        permissions?.hasPermission(gamePackReadPermission) == true &&
        (training ||
            permissions?.hasPermission(gamePackSubmitPermission) == true);
    final pack = source != null && canOpen
        ? ref.watch(
            training
                ? practiceGamePackProvider(source)
                : eventGamePackProvider(source),
          )
        : null;
    final form = position.isStrategy
        ? GamePackFormKind.strategy
        : GamePackFormKind.match;
    final definition = pack?.value?.definition;
    final packReady = definition?.formFor(form) != null;
    final packStatus = switch (pack) {
      _ when source == null => 'No event schedule is available for training.',
      _ when !canOpen => 'This device needs GamePack scouting access.',
      AsyncError() => 'Could not load the assigned GamePack.',
      AsyncLoading() when !packReady => 'Loading the assigned GamePack…',
      _ when definition == null =>
        training
            ? 'Assign a practice GamePack in Beariscope.'
            : 'Assign a GamePack to the event in Beariscope.',
      _ when !packReady =>
        'The assigned GamePack has no ${form.label.toLowerCase()} form.',
      _ => null,
    };

    final schedule = ref.watch(matchesProvider(eventKey));
    final matches =
        (schedule.value ?? [])
            .where((match) => canScoutMatch(match, position))
            .toList()
          ..sort(compareScoutingMatches);
    final requestedId = _selectedId ?? session.matchId;
    final selected = matches
        .where((match) => match.id == requestedId)
        .firstOrNull;
    final index = selected == null ? 0 : matches.indexOf(selected);
    final preview = matches.isEmpty ? null : matches[index];
    final chosen = selected ?? (requestedId == null ? preview : null);
    final team = preview?.teamNumberAt(position);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.go('/scout'),
        ),
        title: const Text('Select Match'),
        actionsPadding: EdgeInsets.only(right: 16),
        actions: const [UploadStatusIndicator()],
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                            session.event?.name ?? '',
                            style: Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          )
                          .animate()
                          .fadeIn(duration: 500.ms)
                          .slideY(
                            begin: -0.3,
                            end: 0,
                            duration: 500.ms,
                            curve: Curves.easeOut,
                          ),
                      const SizedBox(height: 8),
                      Text(
                            'Position: ${position.displayName}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          )
                          .animate()
                          .fadeIn(delay: 100.ms, duration: 500.ms)
                          .slideY(
                            begin: -0.2,
                            end: 0,
                            delay: 100.ms,
                            duration: 500.ms,
                            curve: Curves.easeOut,
                          ),
                      Text(
                            'Scout: ${session.scout?.name ?? "—"}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          )
                          .animate()
                          .fadeIn(delay: 150.ms, duration: 500.ms)
                          .slideY(
                            begin: -0.2,
                            end: 0,
                            delay: 150.ms,
                            duration: 500.ms,
                            curve: Curves.easeOut,
                          ),

                      const SizedBox(height: 16),
                      if (packStatus != null)
                        Text(packStatus, textAlign: TextAlign.center),
                      const SizedBox(height: 32),
                      if (schedule.isLoading && matches.isEmpty)
                        const BearingsSpinner()
                      else if (matches.isEmpty)
                        const Text('No downloaded matches for this position.')
                      else ...[
                        if (chosen == null)
                          const Text(
                            'The selected match is unavailable. Choose another match.',
                          ),
                        Text(
                          scoutingMatchLabel(preview!),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        if (team != null) Text('Team $team'),
                        if (matches.length > 1)
                          Slider(
                            value: index.toDouble(),
                            max: (matches.length - 1).toDouble(),
                            divisions: matches.length - 1,
                            label: scoutingMatchLabel(preview),
                            semanticFormatterCallback: (value) =>
                                scoutingMatchLabel(matches[value.round()]),
                            onChanged: (value) => setState(() {
                              _selectedId = matches[value.round()].id;
                            }),
                          ),
                        if (chosen == null)
                          TextButton(
                            onPressed: () =>
                                setState(() => _selectedId = preview.id),
                            child: Text(
                              'Select ${scoutingMatchLabel(preview)}',
                            ),
                          ),
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
                            onPressed: chosen != null && packReady
                                ? () {
                                    ref
                                        .read(scoutingSessionProvider.notifier)
                                        .selectMatch(chosen);
                                    context.go('/gamepack-match');
                                  }
                                : null,
                            icon: const Icon(LucideIcons.play),
                            label: const Text('Go'),
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
