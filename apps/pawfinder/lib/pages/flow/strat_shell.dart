import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pawfinder/custom_widgets/upload_status_indicator.dart';
import 'package:pawfinder/providers/scouting_flow_provider.dart';
import 'package:pawfinder/providers/scouting_providers.dart';

class StratShell extends ConsumerWidget {
  final Widget child;

  const StratShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(scoutingSessionProvider);
    final notifier = ref.read(scoutingSessionProvider.notifier);
    final flow = ref.read(scoutingFlowControllerProvider);
    final matchNumber = session.matchNumber ?? 0;

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
        title: Row(
          children: [
            Text('Match $matchNumber'),
            const VerticalDivider(),
            Text(session.position?.displayName ?? 'Strategy'),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: UploadStatusIndicator(),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: 'Previous Match',
                onPressed: matchNumber > 1 ? () => flow.previousMatch() : null,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: 'Next Match',
                onPressed: () async {
                  if (flow.shouldWarnForRapidNextMatchTaps()) {
                    final shouldContinue = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Next Match Spam'),
                        content: const Text(
                          'Please do not spam the next match button. Every time you advance a match, it uploads it. By spamming you are uploading multiple empty matches which messes with the data.)',
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
                },
              ),
            ],
          ),
        ],
      ),
      body: child,
    );
  }
}
