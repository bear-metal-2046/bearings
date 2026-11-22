import 'package:material_ui/material_ui.dart';
import 'package:core/core.dart'
    show GamePackFormKind, gamePackReadPermission, gamePackSubmitPermission;
import 'package:services/providers/gamepack_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:bearimetric/models/scouting_session.dart' show trainingEventKey;
import 'package:flutter/services.dart';
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
  final _matchNumberController = TextEditingController(text: '1');
  int? _matchNumber = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = ref.read(scoutingSessionProvider);
      if (mounted && session.matchNumber != null) {
        setState(() {
          _matchNumber = session.matchNumber;
          _matchNumberController.text = session.matchNumber.toString();
        });
      }
    });
  }

  @override
  void dispose() {
    _matchNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scoutingSessionProvider);
    final teamAsync = ref.watch(teamNumberForSessionProvider);

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
        ? ref.watch(eventsProvider).value?.firstOrNull?.id
        : eventKey;
    final canOpen =
        permissions?.hasPermission(gamePackReadPermission) == true &&
        (training ||
            permissions?.hasPermission(gamePackSubmitPermission) == true);
    final pack = source != null && canOpen
        ? ref.watch(eventGamePackProvider(source))
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
        'Assign a published GamePack to the event in Beariscope.',
      _ when !packReady =>
        'The assigned GamePack has no ${form.label.toLowerCase()} form.',
      _ => null,
    };

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
                      teamAsync.when(
                        data: (team) =>
                            Text(
                                  team != null ? 'Team: $team' : 'Team: —',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: team != null
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : null,
                                      ),
                                )
                                .animate()
                                .fadeIn(delay: 200.ms, duration: 500.ms)
                                .slideY(
                                  begin: -0.2,
                                  end: 0,
                                  delay: 200.ms,
                                  duration: 500.ms,
                                  curve: Curves.easeOut,
                                ),
                        loading: () => const SizedBox(
                          height: 24,
                          width: 24,
                          child: BearingsSpinner(strokeWidth: 2),
                        ),
                        error: (_, _) => Text(
                          'Team: —',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),

                      const SizedBox(height: 32),

                      Text(
                            'Match Number',
                            style: Theme.of(context).textTheme.titleLarge,
                          )
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 500.ms)
                          .slideY(
                            begin: 0.2,
                            end: 0,
                            delay: 400.ms,
                            duration: 500.ms,
                          ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: TextField(
                              controller: _matchNumberController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                hintText: 'Match number',
                                prefixIcon: IconButton(
                                  icon: const Icon(LucideIcons.minus),
                                  onPressed: () {
                                    final current =
                                        int.tryParse(
                                          _matchNumberController.text,
                                        ) ??
                                        1;
                                    if (current > 1) {
                                      _matchNumberController.text =
                                          (current - 1).toString();
                                      setState(
                                        () => _matchNumber = current - 1,
                                      );
                                      ref
                                          .read(
                                            scoutingSessionProvider.notifier,
                                          )
                                          .setMatchNumber(current - 1);
                                    }
                                  },
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(LucideIcons.plus),
                                  onPressed: () {
                                    final current =
                                        int.tryParse(
                                          _matchNumberController.text,
                                        ) ??
                                        1;
                                    _matchNumberController.text = (current + 1)
                                        .toString();
                                    setState(() => _matchNumber = current + 1);
                                    ref
                                        .read(scoutingSessionProvider.notifier)
                                        .setMatchNumber(current + 1);
                                  },
                                ),
                              ),
                              onChanged: (value) {
                                final parsed = int.tryParse(value);
                                setState(() {
                                  _matchNumber = parsed;
                                });
                                if (parsed != null && parsed > 0) {
                                  ref
                                      .read(scoutingSessionProvider.notifier)
                                      .setMatchNumber(parsed);
                                }
                              },
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 500.ms, duration: 500.ms)
                          .slideY(
                            begin: 0.2,
                            end: 0,
                            delay: 500.ms,
                            duration: 500.ms,
                          ),
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
                            onPressed:
                                _matchNumber != null &&
                                    _matchNumber! > 0 &&
                                    packReady
                                ? () {
                                    ref
                                        .read(scoutingSessionProvider.notifier)
                                        .setMatchNumber(_matchNumber!);

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
