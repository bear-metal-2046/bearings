import 'package:beariscope/models/match_nexus_info.dart';
import 'package:beariscope/pages/up_next/up_next_provider.dart';

class UpNextMatch {
  final Map<String, dynamic> raw;
  final MatchNexusInfo? nexus;

  const UpNextMatch({required this.raw, this.nexus});

  factory UpNextMatch.fromMap(Map<String, dynamic> map) {
    return UpNextMatch(raw: map, nexus: MatchNexusInfo.fromMatchJson(map));
  }

  String get key => raw['key']?.toString() ?? '';

  String get displayName => matchDisplayName(raw);

  String? get queueStatus => nexus?.status;

  bool get includes2046 {
    final alliances = raw['alliances'] as Map?;
    if (alliances == null) return false;

    for (final alliance in alliances.values) {
      if (alliance is! Map) continue;
      final keys =
          (alliance['team_keys'] ?? alliance['teamKeys'] ?? alliance['teams'])
              as List?;
      if (keys != null && keys.any((k) => k?.toString() == 'frc2046')) {
        return true;
      }
    }
    return false;
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
