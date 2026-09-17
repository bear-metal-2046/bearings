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
  final String? status;
  final bool highlighted;

  const UpNextMatchCard({
    super.key,
    required this.displayName,
    required this.matchKey,
    required this.time,
    this.status,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BeariscopeCard(
      title: displayName,
      subtitle: time,
      trailing: status == null
          ? null
          : _MatchStatusChip(status: status!, colorScheme: colorScheme),
      color: highlighted
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      onTap: () => context.push('/up_next/$matchKey'),
    );
  }
}

class _MatchStatusChip extends StatelessWidget {
  const _MatchStatusChip({required this.status, required this.colorScheme});

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
