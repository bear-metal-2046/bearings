/// A Nexus match label parsed into TBA match key parts.
class NexusMatchRef {
  const NexusMatchRef({
    required this.compLevel,
    required this.setNumber,
    required this.matchNumber,
    this.isReplay = false,
  });

  /// TBA comp level: `pm`, `qm`, `sf`, or `f`.
  final String compLevel;
  final int setNumber;
  final int matchNumber;
  final bool isReplay;

  bool get isPractice => compLevel == 'pm';
}

final _nexusLabelPattern = RegExp(
  r'^(practice|qualification|playoff|semifinal|final)\s+(\d+)(\s+replay)?$',
  caseSensitive: false,
);

/// Parses Nexus labels such as `Qualification 24`, `Qualification 24 Replay`,
/// `Playoff 8`, `Final 1`, and `Practice 3`.
///
/// Playoffs assume the double-elimination format TBA has used since 2023:
/// `Playoff N` is semifinal set N, match 1.
NexusMatchRef? parseNexusMatchLabel(String? label) {
  final match = _nexusLabelPattern.firstMatch(label?.trim() ?? '');
  if (match == null) return null;

  final number = int.parse(match.group(2)!);
  final isReplay = match.group(3) != null;

  return switch (match.group(1)!.toLowerCase()) {
    'practice' => NexusMatchRef(
      compLevel: 'pm',
      setNumber: 1,
      matchNumber: number,
      isReplay: isReplay,
    ),
    'qualification' => NexusMatchRef(
      compLevel: 'qm',
      setNumber: 1,
      matchNumber: number,
      isReplay: isReplay,
    ),
    'final' => NexusMatchRef(
      compLevel: 'f',
      setNumber: 1,
      matchNumber: number,
      isReplay: isReplay,
    ),
    _ => NexusMatchRef(
      compLevel: 'sf',
      setNumber: number,
      matchNumber: 1,
      isReplay: isReplay,
    ),
  };
}

/// Builds the TBA match key for [ref], or null for practice matches, which
/// TBA does not publish.
String? matchKeyForNexusRef(String eventKey, NexusMatchRef ref) {
  final event = eventKey.trim();
  if (event.isEmpty) return null;

  return switch (ref.compLevel) {
    'qm' => '${event}_qm${ref.matchNumber}',
    'sf' ||
    'f' => '${event}_${ref.compLevel}${ref.setNumber}m${ref.matchNumber}',
    _ => null,
  };
}

/// Converts a Nexus label into a TBA match key, for example
/// `Qualification 12` at `2026new` becomes `2026new_qm12`.
String? nexusLabelToMatchKey(String eventKey, String? label) {
  final ref = parseNexusMatchLabel(label);
  if (ref == null) return null;
  return matchKeyForNexusRef(eventKey, ref);
}
