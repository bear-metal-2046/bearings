import 'dart:convert';

import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PicklistLibraryNotifier extends Notifier<List<Picklist>> {
  static const storageKey = 'offline_picklists_v1';

  late String _eventKey;

  @override
  List<Picklist> build() {
    _eventKey = ref.watch(currentEventProvider);
    final picklists = _readAll()
        .where((item) => item.eventKey == _eventKey)
        .toList();
    picklists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return picklists;
  }

  Picklist create({required String title, List<String> teamKeys = const []}) {
    final now = DateTime.now();
    var id = '${now.microsecondsSinceEpoch}';
    while (state.any((item) => item.id == id)) {
      id = '${int.parse(id) + 1}';
    }
    final item = Picklist(
      id: id,
      eventKey: _eventKey,
      title: title.trim().isEmpty ? 'Untitled Picklist' : title.trim(),
      teamKeys: List.unmodifiable(teamKeys.toSet()),
      createdAt: now,
      updatedAt: now,
    );
    state = [item, ...state];
    _persist();
    return item;
  }

  void rename(String id, String title) {
    _update(
      id,
      (item) => item.copyWith(
        title: title.trim().isEmpty ? 'Untitled Picklist' : title.trim(),
      ),
    );
  }

  void setTeams(String id, List<String> teamKeys) {
    _update(
      id,
      (item) => item.copyWith(teamKeys: List.unmodifiable(teamKeys.toSet())),
    );
  }

  void addTeam(String id, String teamKey, {int? at}) {
    final item = state.where((picklist) => picklist.id == id).firstOrNull;
    if (item == null || item.teamKeys.contains(teamKey)) return;
    final updated = [...item.teamKeys];
    updated.insert((at ?? updated.length).clamp(0, updated.length), teamKey);
    setTeams(id, updated);
  }

  void removeTeam(String id, String teamKey) {
    final item = state.where((picklist) => picklist.id == id).firstOrNull;
    if (item == null) return;
    setTeams(id, [...item.teamKeys]..remove(teamKey));
  }

  Picklist? duplicate(String id) {
    final source = state.where((picklist) => picklist.id == id).firstOrNull;
    if (source == null) return null;
    return create(title: 'Copy of ${source.title}', teamKeys: source.teamKeys);
  }

  void delete(String id) {
    state = state.where((item) => item.id != id).toList(growable: false);
    _persist();
  }

  void _update(String id, Picklist Function(Picklist item) update) {
    final now = DateTime.now();
    var changed = false;
    state = state
        .map((item) {
          if (item.id != id) return item;
          changed = true;
          return update(item).copyWith(updatedAt: now);
        })
        .toList(growable: false);
    if (changed) _persist();
  }

  List<Picklist> _readAll() {
    final raw = ref.read(sharedPreferencesProvider).getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Picklist.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id.isNotEmpty && item.eventKey.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _persist() {
    final otherEvents = _readAll().where((item) => item.eventKey != _eventKey);
    final all = [
      ...otherEvents,
      ...state,
    ].map((item) => item.toJson()).toList();
    // SharedPreferences updates its in-memory cache synchronously before the
    // platform write completes, so every editor mutation is captured here.
    ref.read(sharedPreferencesProvider).setString(storageKey, jsonEncode(all));
  }
}

final picklistLibraryProvider =
    NotifierProvider<PicklistLibraryNotifier, List<Picklist>>(
      PicklistLibraryNotifier.new,
    );
