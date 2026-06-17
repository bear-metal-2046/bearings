import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:beariscope/providers/tba_preferences_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
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
      trailing: Icon(Symbols.open_in_new_rounded, size: 20),
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
