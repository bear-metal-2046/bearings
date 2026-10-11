import 'package:beariscope/models/match_nexus_info.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';
import 'package:core/core.dart';
import 'package:services/services.dart';

const bearMetalTeamKey = 'frc2046';

class UpNextMatch {
  final Map<String, dynamic> raw;
  final MatchNexusInfo? nexus;

  /// Double-elimination bracket details, for playoff matches at events that
  /// use that bracket.
  final DoubleEliminationMatch? bracket;
  final int? redAllianceNumber;
  final int? blueAllianceNumber;

  /// Set when Bear Metal is not in this match yet but would be with this
  /// result.
  final PlayoffOutcome? possibleOutcome;

  const UpNextMatch({
    required this.raw,
    this.nexus,
    this.bracket,
    this.redAllianceNumber,
    this.blueAllianceNumber,
    this.possibleOutcome,
  });

  factory UpNextMatch.fromMap(
    Map<String, dynamic> map, {
    MatchNexusInfo? nexus,
    DoubleEliminationMatch? bracket,
    int? redAllianceNumber,
    int? blueAllianceNumber,
    PlayoffOutcome? possibleOutcome,
  }) {
    return UpNextMatch(
      raw: map,
      nexus: nexus ?? MatchNexusInfo.fromMatchJson(map),
      bracket: bracket,
      redAllianceNumber: redAllianceNumber,
      blueAllianceNumber: blueAllianceNumber,
      possibleOutcome: possibleOutcome,
    );
  }

  String get key => raw['key']?.toString() ?? '';

  String get displayName => matchDisplayName(raw);

  /// The Nexus label, such as "Playoff 5", or a name built from the match key.
  String get title {
    final label = nexus?.label;
    if (label != null) return label;
    if (bracket != null) return 'Playoff ${bracket!.number}';
    return displayName;
  }

  String? get queueStatus => nexus?.status;

  List<String> get redTeamKeys => _teamKeys('red');

  List<String> get blueTeamKeys => _teamKeys('blue');

  bool get includes2046 =>
      redTeamKeys.contains(bearMetalTeamKey) ||
      blueTeamKeys.contains(bearMetalTeamKey);

  List<String> _teamKeys(String color) {
    final alliances = raw['alliances'];
    if (alliances is! Map) return const [];
    final alliance = alliances[color];
    if (alliance is! Map) return const [];
    final keys =
        (alliance['team_keys'] ?? alliance['teamKeys'] ?? alliance['teams'])
            as List?;
    return keys?.map((key) => key.toString()).toList() ?? const [];
  }

  DateTime? get displayTime {
    final nexusTime = nexus?.displayTime;
    if (nexus != null &&
        isActiveQueueStatus(nexus!.status) &&
        nexusTime != null) {
      return nexusTime;
    }

    return _predictedTimeFromTba(raw) ?? nexusTime;
  }
}

DateTime? _predictedTimeFromTba(Map<String, dynamic> match) {
  final value = match['predictedTime'] ?? match['predicted_time'];
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  if (value is num) {
    final seconds = value.toInt();
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  return null;
}
