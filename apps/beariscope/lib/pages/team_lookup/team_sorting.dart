import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/rankings_provider.dart';
import 'package:core/core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/widgets/bearings_popup_menu.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';

Iterable<GamePackTeamSort> teamSortMetrics(GamePackEventAnalysis? analysis) =>
    analysis?.analysis.definition.results.sorts ?? const [];

Iterable<GamePackTeamFilter> teamFilters(GamePackEventAnalysis? analysis) =>
    analysis?.analysis.definition.results.filters ?? const [];

GamePackValue teamListValue(
  GamePackAnalysisSession session,
  String team,
  GameGraphOutputRef field,
) {
  try {
    return session
        .evaluate(
          field,
          scope: GamePackScope(event: session.event, team: team),
        )
        .result;
  } on GameGraphLimitExceeded {
    return GamePackValue.unknown;
  }
}

bool teamPassesFilters(
  GamePackAnalysisSession session,
  String team,
  Iterable<GamePackTeamFilter> enabled,
) => enabled.every(
  (rule) => rule.matches(teamListValue(session, team, rule.output)),
);

class GamePackTeamFilterMenu extends StatelessWidget {
  const GamePackTeamFilterMenu({
    super.key,
    required this.filters,
    required this.enabled,
    required this.onChanged,
  });
  final Iterable<GamePackTeamFilter> filters;
  final Set<String> enabled;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => BearingsPopupMenu.icon(
    tooltip: 'Filter teams',
    icon: Icon(
      enabled.isEmpty ? LucideIcons.listFilter : LucideIcons.listFilterPlus,
    ),
    menuChildren: [
      for (final rule in filters)
        BearingsMenuItem(
          selected: enabled.contains(rule.id),
          onPressed: () => onChanged(
            enabled.contains(rule.id)
                ? ({...enabled}..remove(rule.id))
                : {...enabled, rule.id},
          ),
          child: Text(rule.label),
        ),
      if (enabled.isNotEmpty)
        BearingsMenuItem(
          onPressed: () => onChanged({}),
          child: const Text('Clear filters'),
        ),
    ],
  );
}

void sortTeams(
  List<Team> teams,
  TeamSort order,
  Map<int, TeamRanking> rankings,
) {
  teams.sort((a, b) {
    if (order.sort == TeamSortOptions.rank) {
      final left = rankings[a.number]?.rank;
      final right = rankings[b.number]?.rank;
      if (left == null && right != null) return 1;
      if (left != null && right == null) return -1;
      if (left != null && right != null && left != right) {
        final rankOrder = left.compareTo(right);
        return order.isAscending ? rankOrder : -rankOrder;
      }
      return a.number.compareTo(b.number);
    }
    return order.isAscending
        ? a.number.compareTo(b.number)
        : b.number.compareTo(a.number);
  });
}

Map<String, GamePackValue> sortTeamsByMetric(
  List<Team> teams,
  GamePackEventAnalysis analysis,
  GamePackTeamSort binding, {
  required bool ascending,
}) {
  final session = analysis.session(analysis.analysis.definition.analysis);
  final values = {
    for (final team in teams)
      team.key: teamListValue(session, team.key, binding.output),
  };
  teams.sort((a, b) {
    final order = compareGamePackTeamValues(
      values[a.key]!,
      values[b.key]!,
      ascending: ascending,
    );
    return order == 0 ? a.number.compareTo(b.number) : order;
  });
  return values;
}
