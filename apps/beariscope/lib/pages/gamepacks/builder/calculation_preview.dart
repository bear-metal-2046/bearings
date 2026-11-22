import 'package:core/core.dart';

import 'design.dart';

String summarizeCalculationValue(GamePackValue value, [int depth = 0]) {
  if (!value.isKnown) {
    return switch (value.state) {
      GamePackValueState.missing => 'Missing',
      GamePackValueState.unknown => 'Unknown',
      GamePackValueState.notApplicable => 'Not applicable',
      _ => value.toString(),
    };
  }
  final data = value.data;
  return switch (data) {
    true => 'Yes',
    false => 'No',
    final String text =>
      text.isEmpty ? 'Empty text' : _short(text.replaceAll('\n', ' '), 96),
    final num number => number.toString().replaceFirst(RegExp(r'\.0$'), ''),
    final Map<String, GamePackValue> fields when depth > 0 =>
      '${fields.length} fields',
    final Map<String, GamePackValue> fields =>
      fields.isEmpty
          ? 'Empty record'
          : _short(
              [
                for (final entry in fields.entries.take(4))
                  '${gamePackKeyLabel(entry.key)} ${summarizeCalculationValue(entry.value, depth + 1)}',
                if (fields.length > 4) '…',
              ].join(' · '),
              180,
            ),
    final List<GamePackValue> items =>
      items.isEmpty
          ? 'Empty list'
          : depth > 0 || items.first.data is Map
          ? '${items.length} ${items.first.data is Map ? 'records' : 'items'}'
          : _short(
              [
                for (final entry in items.take(4))
                  summarizeCalculationValue(entry, depth + 1),
                if (items.length > 4) '…',
              ].join(' · '),
              140,
            ),
    GamePackDistribution(:final values) =>
      'Distribution · ${values.length} outcomes',
    _ => _short(value.toString(), 120),
  };
}

String _short(String value, int maximum) =>
    value.length > maximum ? '${value.substring(0, maximum - 1)}…' : value;
