import 'package:beariscope/models/up_next_match.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:core/core.dart' show EventStatusSnapshot;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/services.dart';

class UpNextList {
  const UpNextList({
    required this.matches,
    required this.source,
    this.eventOver = false,
    this.nexusProblem,
    this.eventContext,
  });

  final List<UpNextMatch> matches;
  final UpNextSource source;
  final bool eventOver;
  final String? nexusProblem;
  final EventStatusSnapshot? eventContext;
}

final upNextProvider = Provider.autoDispose<AsyncValue<UpNextList>>((ref) {
  final currentEventKey = ref.watch(currentEventProvider);
  return ref.watch(upNextFeedProvider(currentEventKey)).whenData((feed) {
    final alliances = feed.doubleElimination
        ? playoffAllianceNumbers(feed.allMatches)
        : const <String, int>{};
    final possible = feed.doubleElimination
        ? possiblePlayoffMatches(
            allMatches: feed.allMatches,
            upcoming: feed.matches,
            teamKey: bearMetalTeamKey,
          )
        : const <String, PlayoffOutcome>{};

    final matches = feed.matches.map((match) {
      int? allianceOf(List<String> teams) =>
          match.level == 'qm' ? null : allianceNumberFor(teams, alliances);

      return UpNextMatch(
        match: match,
        bracket: feed.doubleElimination ? bracketFor(match) : null,
        redAllianceNumber: allianceOf(match.redTeamKeys),
        blueAllianceNumber: allianceOf(match.blueTeamKeys),
        possibleOutcome: possible[match.key],
      );
    }).toList()..sort((a, b) => compareMatchesForUpNext(a.match, b.match));

    return UpNextList(
      matches: matches,
      source: feed.source,
      eventOver: feed.eventOver,
      nexusProblem: feed.nexusProblem,
      eventContext: feed.nexus,
    );
  });
});

int compareMatchesForUpNext(UpNextFeedMatch a, UpNextFeedMatch b) {
  final level = _levelRank(a.level).compareTo(_levelRank(b.level));
  if (level != 0) return level;
  final order = _sortNumber(a).compareTo(_sortNumber(b));
  return order == 0 ? a.key.compareTo(b.key) : order;
}

int _sortNumber(UpNextFeedMatch match) => switch (match.level) {
  'qm' || 'f' => match.matchNumber,
  'sf' => match.setNumber,
  _ => match.matchNumber,
};

int _levelRank(String level) => switch (level) {
  'qm' => 0,
  'sf' => 1,
  'f' => 2,
  _ => 3,
};
