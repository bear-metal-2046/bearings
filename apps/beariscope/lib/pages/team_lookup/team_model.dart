import 'package:core/core.dart';

/// Opaque team colors supplied by Honeycomb's FRC Colors integration.
class TeamColors {
  const TeamColors({required this.primaryArgb, this.secondaryArgb});

  final int primaryArgb;
  final int? secondaryArgb;

  static TeamColors? fromJson(Object? value) {
    if (value is! Map) return null;
    final primary = _parseHex(value['primaryHex']);
    if (primary == null) return null;
    return TeamColors(
      primaryArgb: primary,
      secondaryArgb: _parseHex(value['secondaryHex']),
    );
  }

  static int? _parseHex(Object? value) {
    if (value is! String) return null;
    var hex = value.trim().replaceFirst(RegExp(r'^#'), '');
    if (!RegExp(r'^(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(hex)) {
      return null;
    }
    if (hex.length == 3) {
      hex = hex.split('').map((digit) => '$digit$digit').join();
    }
    return 0xff000000 | int.parse(hex, radix: 16);
  }
}

class Team {
  final String key;
  final int number;
  final String name;
  final String? website;
  final TeamColors? colors;

  Team({
    required this.key,
    required this.number,
    required this.name,
    required this.website,
    this.colors,
  });

  factory Team.fromCompetition(CompetitionTeam team) => Team(
    key: team.id,
    number: team.number,
    name: team.nickname ?? team.name ?? 'Unknown Team',
    website: _cleanString(team.website),
  );

  static String? _cleanString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return Uri.parse(text).host.contains('firstinspires.org') ? null : text;
  }
}

//FIXED punctuation :)
String _normalize(String input) {
  return input.replaceAll(RegExp(r'\W'), '').toLowerCase();
}

bool teamMatchesSearch(Team team, String query) {
  final cleanQuery = _normalize(query).trim();
  if (cleanQuery.isEmpty) return true;

  final cleanName = _normalize(team.name);
  final teamNumber = team.number.toString();

  return cleanName.contains(cleanQuery) || teamNumber.contains(cleanQuery);
}
