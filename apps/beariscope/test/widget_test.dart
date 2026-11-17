import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('team search matches name and number without matching key', () {
    final team = Team(
      key: 'frc2046',
      number: 2046,
      name: 'Bear Metal',
      website: null,
    );

    expect(teamMatchesSearch(team, 'bear'), isTrue);
    expect(teamMatchesSearch(team, '204'), isTrue);
    expect(teamMatchesSearch(team, 'FRC2046'), isFalse);
    expect(teamMatchesSearch(team, '  BEAR  '), isTrue);
    expect(teamMatchesSearch(team, 'bear-metal'), isTrue);
    expect(teamMatchesSearch(team, 'falcons'), isFalse);
    expect(teamMatchesSearch(team, ''), isTrue);
  });
}
