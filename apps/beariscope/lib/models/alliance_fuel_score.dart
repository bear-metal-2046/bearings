/// Reads the season's fuel breakdown from a competition alliance.
({int auto, int tele}) readAllianceFuelScore(Map<String, dynamic>? breakdown) {
  final hub = breakdown?['hubScore'];
  final source = hub is Map ? hub : breakdown;
  return (
    auto: _readCount(source, const [
      'autoCount',
      'autoFuelScored',
      'autoFuelCount',
    ]),
    tele: _readCount(source, const [
      'teleopCount',
      'teleFuelScored',
      'teleopFuelScored',
      'teleopFuelCount',
    ]),
  );
}

int _readCount(Map<Object?, Object?>? source, List<String> keys) {
  for (final key in keys) {
    final value = source?[key];
    final number = value is String ? num.tryParse(value) : value;
    if (number is num && number.isFinite) return number.toInt();
  }
  return 0;
}
