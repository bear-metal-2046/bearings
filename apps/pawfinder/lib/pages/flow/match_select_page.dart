import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:pawfinder/custom_widgets/upload_status_indicator.dart';
import 'package:pawfinder/data/local_data.dart';
import 'package:pawfinder/data/match_json_gen.dart';
import 'package:pawfinder/providers/scouting_providers.dart';

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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final position = session.position!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
                      teamAsync.when(
                        data: (team) =>
                            Text(
                                  team != null ? 'Team: $team' : 'Team: —',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: team != null
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                                  icon: const Icon(Icons.remove),
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
                                  icon: const Icon(Icons.add),
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
                            onPressed: _matchNumber != null && _matchNumber! > 0
                                ? () {
                                    ref
                                        .read(scoutingSessionProvider.notifier)
                                        .setMatchNumber(_matchNumber!);

                                    final identity = ref
                                        .read(scoutingSessionProvider.notifier)
                                        .createMatchIdentity();
                                    if (identity != null) {
                                      final team = teamAsync.when(
                                        data: (t) => t,
                                        loading: () => null,
                                        error: (_, _) => null,
                                      );
                                      if (team != null) {
                                        Hive.box(
                                          boxKey,
                                        ).put(matchTeamKey(identity), team);
                                      }
                                    }

                                    if (position.isStrategy) {
                                      context.go('/strat');
                                    } else {
                                      context.go('/match/auto');
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.play_arrow),
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
