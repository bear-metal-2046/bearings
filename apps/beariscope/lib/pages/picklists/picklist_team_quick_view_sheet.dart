import 'package:beariscope/pages/gamepacks/team_card_content.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:core/core.dart'
    show GamePackTeamCardKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:ui/widgets/bearings_modal.dart';

class PicklistTeamQuickViewSheet extends ConsumerWidget {
  const PicklistTeamQuickViewSheet({super.key, required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(currentEventProvider);
    final canRead =
        ref.watch(permissionCheckerProvider)?.canReadGamePackAnalysis == true;
    return BearingsModal(
      title: 'Team ${team.number} — ${team.name}',
      size: BearingsModalSize.tall,
      scrolling: BearingsModalScrolling.content,
      actions: const [],
      primaryAction: BearingsModalPrimaryAction(
        label: 'Dive deeper',
        icon: LucideIcons.arrowUpRight,
        onPressed: () => BearingsModal.complete(context, true),
      ),
      content: canRead
          ? GamePackTeamCardStatistics(
              event: event,
              team: team.key,
              kind: GamePackTeamCardKind.details,
              scrollable: true,
              fallback: const Center(child: Text('No team details configured.')),
            )
          : const Text('GamePack observation access is required.'),
    );
  }
}
