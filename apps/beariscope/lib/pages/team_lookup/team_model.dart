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

  factory Team.fromJson(Map<String, dynamic> json) {
    // extract number (try multiple field names and types)
    dynamic numberRaw =
        json['team_number'] ?? json['teamNumber'] ?? json['number'];
    int number = 0;
    if (numberRaw is int) {
      number = numberRaw;
    } else if (numberRaw is String) {
      number = int.tryParse(numberRaw) ?? 0;
    }

    // extract key (try multiple names, or generate from number)
    String? keyRaw = (json['team_key'] ?? json['team'] ?? json['key'])
        ?.toString();
    String key = (keyRaw != null && keyRaw.isNotEmpty) ? keyRaw : 'frc$number';

    // extract name
    String name =
        (json['nickname'] ??
                json['team_name'] ??
                json['name'] ??
                'Unknown Team')
            .toString();

    final website = _cleanString(json['website']);

    return Team(
      key: key,
      number: number,
      name: name,
      website: website,
      colors: TeamColors.fromJson(json['colors']),
    );
  }

  static String? _cleanString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return Uri.parse(text).host.contains('firstinspires.org') ? null : text;
  }
}

bool teamMatchesSearch(Team team, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;

  return team.name.toLowerCase().contains(normalizedQuery) ||
      team.number.toString().contains(normalizedQuery) ||
      team.key.toLowerCase().contains(normalizedQuery);
}
