import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_card.dart';

import 'observation_list.dart';
import 'observation_page.dart';

class GamePackMatchObservationsPage extends ConsumerWidget {
  const GamePackMatchObservationsPage({
    super.key,
    required this.match,
    required this.release,
  });

  final CompetitionMatch match;
  final GamePackRelease release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = release.definition.formFor(GamePackFormKind.observation)!;
    final canRead =
        ref.watch(permissionCheckerProvider)?.canReadGamePackAnalysis == true;
    final history = canRead
        ? ref.watch(activeGamePackObservationsProvider(match.event.id))
        : const AsyncData(<GamePackObservation>[]);
    final recorded = (history.value ?? const <GamePackObservation>[])
        .where(
          (row) =>
              row.release.id == release.id &&
              row.match?.id == match.id &&
              row.formId == form.id,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Match observations')),
      body: BearingsCardList(
        children: [
          for (final (label, alliance) in [
            ('Red alliance', match.red),
            ('Blue alliance', match.blue),
          ])
            if (alliance != null && alliance.teams.isNotEmpty) ...[
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              for (final team in alliance.teams)
                BearingsCard(
                  title: 'Team ${team.id.replaceFirst('frc', '')}',
                  trailing: const Icon(LucideIcons.messageSquarePlus),
                  onTap: () async {
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => GamePackObservationPage(
                          title:
                              'Observation · ${team.id.replaceFirst('frc', '')}',
                          event: match.event.id,
                          release: release,
                          kind: form.kind,
                          match: match.id,
                          team: team.id,
                        ),
                      ),
                    );
                    if (saved == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Observation saved')),
                      );
                    }
                  },
                ),
            ],
          if (recorded.isNotEmpty) ...[
            Text(
              'Recorded observations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final row in recorded)
              GamePackObservationCard(observation: row, release: release),
          ],
        ],
      ),
    );
  }
}
