import 'dart:convert';

import 'package:core/core.dart';
import 'package:hive_ce/hive.dart';
import 'package:bearimetric/data/local_data.dart';

class MatchFormStore {
  static String keyFor(String eventKey, int matchNumber, int pos) {
    return 'match:$eventKey:$matchNumber:$pos';
  }

  MatchFormData? load(String eventKey, int matchNumber, int pos) {
    final raw = Hive.box(boxKey).get(keyFor(eventKey, matchNumber, pos));
    if (raw is! String) return null;
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final payload = decoded['payload'];
      if (payload is Map) {
        final data = MatchFormData.fromJson(Map<String, dynamic>.from(payload));
        final storedId = decoded['id']?.toString();
        return data.copyWith(
          id: storedId != null && storedId.isNotEmpty ? storedId : data.id,
          lastModified:
              DateTime.tryParse(decoded['lastModified']?.toString() ?? '') ??
              data.lastModified,
        );
      }

      return MatchFormData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  void save(MatchFormData data) {
    Hive.box(boxKey).put(
      keyFor(data.eventKey, data.matchNumber, data.pos),
      jsonEncode(data.toStoredJson()),
    );
  }
}
