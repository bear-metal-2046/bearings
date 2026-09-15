import 'package:beariscope/models/match_nexus_info.dart';
import 'package:beariscope/pages/up_next/up_next_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MatchNexusDetails extends StatelessWidget {
  const MatchNexusDetails({super.key, required this.match});

  final Map<String, dynamic> match;

  @override
  Widget build(BuildContext context) {
    final nexus = MatchNexusInfo.fromMatchJson(match);
    if (nexus == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final rows = <({String label, DateTime? time})>[
      (label: 'Estimated queue', time: nexus.estimatedQueueTime),
      (label: 'On deck', time: nexus.estimatedOnDeckTime),
      (label: 'On field', time: nexus.estimatedOnFieldTime),
      (label: 'Estimated start', time: nexus.estimatedStartTime),
    ].where((row) => row.time != null).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.clock3, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Nexus queue',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (nexus.status != null) ...[
                        const Spacer(),
                        _StatusChip(status: nexus.status!, colorScheme: colorScheme),
                      ],
                    ],
                  ),
                  if (nexus.label != null) Text(nexus.label!),
                  ...rows.map(
                    (row) => Text(
                      '${row.label}: ${UpNextPage.timeFormat.format(row.time!)}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.colorScheme});

  final String status;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Now queuing' => colorScheme.primary,
      'On deck' => colorScheme.tertiary,
      'On field' => colorScheme.secondary,
      _ => colorScheme.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
