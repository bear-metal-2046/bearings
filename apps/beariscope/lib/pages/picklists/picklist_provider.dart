import 'dart:async';
import 'dart:convert';

import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_presence.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:uuid/uuid.dart';

final sharedPicklistsProvider =
    Provider<AsyncValue<QueryResult<GrovePicklist>>?>((ref) {
      final authenticated =
          ref.watch(authStatusProvider) == AuthStatus.authenticated;
      final access = ref.watch(permissionCheckerProvider);
      if (!authenticated ||
          !(access?.hasPermission(PermissionKey.picklistsRead) ?? false)) {
        return null;
      }
      final grove = ref.watch(bearingsGroveProvider);
      final event = ref.watch(currentEventProvider);
      return ref.watch(
        groveQueryProvider(
          grove.query<GrovePicklist>().where(
            GrovePicklistFields.eventKey.equals(event),
          ),
        ),
      );
    });

final sharedPicklistsOfflineProvider = Provider<bool>((ref) {
  return ref.watch(sharedPicklistsProvider)?.value?.offline ?? false;
});

class PicklistLibraryNotifier extends Notifier<List<Picklist>> {
  static const storageKey = 'offline_picklists_v1';
  late String _eventKey;
  late Grove _grove;
  final _presence = <String, PicklistPresence>{};
  final _shared = <String, Picklist>{};
  late List<Picklist> _local;

  @override
  List<Picklist> build() {
    _eventKey = ref.watch(currentEventProvider);
    _grove = ref.watch(bearingsGroveProvider);
    _local = _readLocal();
    ref.onDispose(() {
      for (final room in _presence.values) {
        room.dispose();
      }
      _presence.clear();
      _shared.clear();
    });
    _setShared(ref.read(sharedPicklistsProvider));
    ref.listen(sharedPicklistsProvider, (_, next) {
      _setShared(next);
      state = _library();
    });
    ref.listen(permissionCheckerProvider, (_, _) => state = _library());
    return _library();
  }

  void _setShared(AsyncValue<QueryResult<GrovePicklist>>? result) {
    final records = result?.hasError == true
        ? const <GrovePicklist>[]
        : result?.value?.items ?? const [];
    _shared
      ..clear()
      ..addEntries(
        records.map(
          (record) => MapEntry(record.id, Picklist.fromGrove(record)),
        ),
      );
    for (final id in _presence.keys.toList()) {
      if (!_shared.containsKey(id)) close(id);
    }
  }

  List<Picklist> _library() => [
    ..._local.where((picklist) => picklist.eventKey == _eventKey),
    ..._shared.values,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<Picklist> create({
    required String title,
    String? emoji,
    List<String> teamKeys = const [],
    PicklistMode mode = PicklistMode.offline,
  }) async {
    if (mode == PicklistMode.multiplayer) _requireEditing();
    final now = DateTime.now();
    final id = const Uuid().v4();
    final name = _title(title);
    final icon = emoji ?? randomPicklistEmoji();
    if (mode == PicklistMode.multiplayer) {
      final grove = _grove;
      final record = await grove.create(
        GrovePicklist(
          id: id,
          eventKey: _eventKey,
          title: name,
          emoji: icon,
          createdAt: now,
          updatedAt: now,
        ).replaceTeams(teamKeys, at: now),
      );
      return Picklist.fromGrove(record);
    }

    final picklist = Picklist(
      id: id,
      eventKey: _eventKey,
      title: name,
      emoji: icon,
      teamKeys: List.unmodifiable(teamKeys.toSet()),
      createdAt: now,
      updatedAt: now,
    );
    _local = [picklist, ..._local];
    await _saveLocal();
    return picklist;
  }

  PicklistPresence? open(String id) {
    if (!_shared.containsKey(id) || !_canReadRemotely) return null;
    return _presence.putIfAbsent(
      id,
      () => PicklistPresence(_grove.watchPresence<GrovePicklist>(id)),
    );
  }

  void close(String id) => _presence.remove(id)?.dispose();

  Future<void> customize(String id, {String? title, String? emoji}) async {
    if (title == null && emoji == null) return;
    final now = DateTime.now();
    final name = title == null ? null : _title(title);
    if (_shared.containsKey(id)) {
      _requireEditing();
      await _grove.update<GrovePicklist>(
        id,
        (record) => record.customize(title: name, emoji: emoji, at: now),
      );
    } else {
      await _editLocal(
        id,
        (item) => item.copyWith(title: name, emoji: emoji, updatedAt: now),
      );
    }
  }

  Future<void> setTeams(
    String id,
    List<String> teamKeys, {
    Picklist? basedOn,
  }) async {
    final now = DateTime.now();
    final base = basedOn?.shared ?? _shared[id]?.shared;
    if (base != null) {
      _requireEditing();
      await _grove.update<GrovePicklist>(
        id,
        (record) => record.replaceTeams(teamKeys, at: now),
        basedOn: base,
      );
    } else {
      await _editLocal(
        id,
        (item) => item.copyWith(
          teamKeys: List.unmodifiable(teamKeys.toSet()),
          updatedAt: now,
        ),
      );
    }
  }

  Future<Picklist?> duplicate(String id, {PicklistMode? mode}) async {
    final source = state.where((picklist) => picklist.id == id).firstOrNull;
    if (source == null || !canEdit(source)) return null;
    return create(
      title: 'Copy of ${source.title}',
      emoji: source.emoji,
      teamKeys: source.teamKeys,
      mode: mode ?? source.mode,
    );
  }

  Future<void> delete(String id) async {
    if (_shared.containsKey(id)) {
      _requireEditing();
      await _grove.delete<GrovePicklist>(id);
      return;
    }
    if (!_local.any((item) => item.id == id)) return;
    _local = _local.where((item) => item.id != id).toList();
    await _saveLocal();
  }

  Future<void> _editLocal(String id, Picklist Function(Picklist) edit) async {
    if (!_local.any((item) => item.id == id)) return;
    _local = [
      for (final item in _local)
        if (item.id == id) edit(item) else item,
    ];
    await _saveLocal();
  }

  Future<void> _saveLocal() async {
    state = _library();
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          storageKey,
          jsonEncode(_local.map((item) => item.toJson()).toList()),
        );
  }

  bool canEdit(Picklist item) =>
      item.mode == PicklistMode.offline ||
      (_canManageRemotely && !ref.read(sharedPicklistsOfflineProvider));

  void _requireEditing() {
    if (!_canManageRemotely) {
      throw StateError('Multiplayer picklists require editing permission');
    }
    if (ref.read(sharedPicklistsOfflineProvider)) throw const GroveOffline();
  }

  bool get _canReadRemotely =>
      ref.read(authStatusProvider) == AuthStatus.authenticated &&
      (ref
              .read(permissionCheckerProvider)
              ?.hasPermission(PermissionKey.picklistsRead) ??
          false);

  bool get _canManageRemotely =>
      _canReadRemotely &&
      (ref
              .read(permissionCheckerProvider)
              ?.hasPermission(PermissionKey.picklistsManage) ??
          false);

  List<Picklist> _readLocal() {
    final raw = ref.read(sharedPreferencesProvider).getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => Picklist.fromJson(Map<String, dynamic>.from(item)))
          .where(
            (item) =>
                item.mode == PicklistMode.offline &&
                item.id.isNotEmpty &&
                item.eventKey.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _title(String value) =>
      value.trim().isEmpty ? 'Untitled Picklist' : value.trim();
}

final picklistLibraryProvider =
    NotifierProvider<PicklistLibraryNotifier, List<Picklist>>(
      PicklistLibraryNotifier.new,
    );
