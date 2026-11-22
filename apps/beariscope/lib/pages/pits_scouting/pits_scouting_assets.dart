import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_card.dart';

class PitsScoutingTeamCard extends StatelessWidget {
  final String teamName;
  final int teamNumber;
  final bool scouted;
  final bool statusKnown;
  final String? scouterName;
  final VoidCallback? onTap;

  const PitsScoutingTeamCard({
    super.key,
    required this.teamName,
    required this.teamNumber,
    required this.scouted,
    required this.statusKnown,
    this.scouterName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = !statusKnown
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : scouted
        ? Colors.green
        : Colors.red;

    return BearingsCard(
      title: teamName,
      subtitle: '$teamNumber',
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            !statusKnown
                ? 'Scouting status unavailable'
                : scouted
                ? 'Scouted'
                : 'Not Scouted',
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
          if (scouterName != null)
            Text(
              'by $scouterName',
              style: TextStyle(color: statusColor, fontSize: 12),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
