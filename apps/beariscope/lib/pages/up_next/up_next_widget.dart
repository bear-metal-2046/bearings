import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class UpNextMatchCard extends StatelessWidget {
  final String displayName;
  final String matchKey;
  final String time;

  const UpNextMatchCard({
    super.key,
    required this.displayName,
    required this.matchKey,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return BeariscopeCard(
      title: displayName,
      subtitle: time,
      onTap: () => context.push('/up_next/$matchKey'),
    );
  }
}

class NexusMatchCard extends StatelessWidget {
  final String label;
  final String time;
  final String? status;
  final bool includes2046;

  const NexusMatchCard({
    super.key,
    required this.label,
    required this.time,
    this.status,
    this.includes2046 = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BeariscopeCard(
      title: label,
      subtitle: time,
      trailing: status == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(colorScheme, status!).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status!,
                style: TextStyle(
                  color: _statusColor(colorScheme, status!),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
      color: includes2046
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
    );
  }

  Color _statusColor(ColorScheme colorScheme, String status) {
    return switch (status) {
      'Now queuing' => colorScheme.primary,
      'On deck' => colorScheme.tertiary,
      'On field' => colorScheme.secondary,
      _ => colorScheme.onSurfaceVariant,
    };
  }
}

class UpNextEventCard extends ConsumerWidget {
  final String eventKey;
  final String name;
  final String dateLabel;

  const UpNextEventCard({
    super.key,
    required this.eventKey,
    required this.name,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BeariscopeCard(
      title: name,
      subtitle: dateLabel,
      trailing: Icon(LucideIcons.externalLink, size: 20),
      onTap: () async {
        final uri = ref.tbaWebsiteUri('/event/$eventKey');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Could not open TBA')));
          }
        }
      },
    );
  }
}
