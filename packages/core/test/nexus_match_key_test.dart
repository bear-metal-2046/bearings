import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('nexusLabelToMatchKey', () {
    test('maps qualifications', () {
      expect(
        nexusLabelToMatchKey('2026new', 'Qualification 12'),
        '2026new_qm12',
      );
      expect(nexusLabelToMatchKey('2026new', 'qualification 1'), '2026new_qm1');
    });

    test('maps replays to the original match key', () {
      expect(
        nexusLabelToMatchKey('2026new', 'Qualification 24 Replay'),
        '2026new_qm24',
      );
      expect(parseNexusMatchLabel('Qualification 24 Replay')?.isReplay, isTrue);
    });

    test('maps playoffs to double-elimination semifinal sets', () {
      expect(nexusLabelToMatchKey('2026new', 'Playoff 8'), '2026new_sf8m1');
      expect(nexusLabelToMatchKey('2026new', 'Playoff 13'), '2026new_sf13m1');
      expect(nexusLabelToMatchKey('2026new', 'Semifinal 2'), '2026new_sf2m1');
    });

    test('maps finals to set 1 match numbers', () {
      expect(nexusLabelToMatchKey('2026new', 'Final 1'), '2026new_f1m1');
      expect(nexusLabelToMatchKey('2026new', 'Final 3'), '2026new_f1m3');
    });

    test('returns null for practice matches', () {
      expect(nexusLabelToMatchKey('2026new', 'Practice 3'), isNull);
      expect(parseNexusMatchLabel('Practice 3')?.isPractice, isTrue);
    });

    test('returns null for unknown or empty input', () {
      expect(nexusLabelToMatchKey('2026new', null), isNull);
      expect(nexusLabelToMatchKey('2026new', ''), isNull);
      expect(nexusLabelToMatchKey('2026new', 'Qualification'), isNull);
      expect(nexusLabelToMatchKey('2026new', 'Match 12'), isNull);
      expect(nexusLabelToMatchKey('2026new', 'Qualification 12 Extra'), isNull);
      expect(nexusLabelToMatchKey('', 'Qualification 12'), isNull);
    });
  });
}
