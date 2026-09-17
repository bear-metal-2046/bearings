import 'dart:async';
import 'dart:convert';

import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_sync.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:services/providers/user_profile_provider.dart';

class PicklistLibraryNotifier extends Notifier<List<Picklist>> {
  static const storageKey = 'offline_picklists_v1';

  String? _eventKey;
  bool _remoteRefreshStarted = false;
  final Map<String, PicklistSyncSession> _sessions = {};
  final Map<String, Future<void>> _pendingRemoteCreates = {};
  final Map<String, Picklist> _pendingPatches = {};
  final Set<String> _patching = {};
  int _generation = 0;
  int _refreshVersion = 0;

  @override
  List<Picklist> build() {
    // Re-run when login or /auth/me permissions finish loading so a page that
    // opened offline can upgrade to live collaboration without navigation.
    ref.watch(authStatusProvider);
    ref.watch(permissionCheckerProvider);
    // Profile refreshes should update presence without rebuilding CRDT sessions.
    ref.listen(userInfoProvider, (_, next) {
      final user = next.asData?.value;
      if (user == null) return;
      for (final session in _sessions.values) {
        session.presence.updateProfile(_presenceProfile(user));
      }
    });

    final nextEventKey = ref.watch(currentEventProvider);
    if (_eventKey != null && _eventKey != nextEventKey) {
      for (final session in _sessions.values) {
        session.dispose();
      }
      _sessions.clear();
      _remoteRefreshStarted = false;
    }
    _eventKey = nextEventKey;

    final canReadRemotely = _canReadRemotely;
    if (!canReadRemotely && _sessions.isNotEmpty) {
      for (final session in _sessions.values) {
        session.dispose();
      }
      _sessions.clear();
    }
    if (!canReadRemotely) _remoteRefreshStarted = false;

    final generation = ++_generation;
    ref.onDispose(() {
      _generation++;
      _remoteRefreshStarted = false;
      _pendingPatches.clear();
      for (final session in _sessions.values) {
        session.dispose();
      }
      _sessions.clear();
      _pendingRemoteCreates.clear();
    });

    final picklists = _readAll()
        .where((item) => item.eventKey == _eventKey)
        .toList();
    picklists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (!_remoteRefreshStarted && canReadRemotely) {
      _remoteRefreshStarted = true;

      Future.microtask(() {
        if (ref.mounted && generation == _generation) unawaited(refresh());
      });
    }
    return picklists;
  }

  /// Refreshes the server-backed picklist projection while leaving local-only
  /// picklists available when offline.
  Future<void> refresh() async {
    if (!_canReadRemotely) {
      return;
    }

    await _refreshFromServer();
  }

  Picklist create({
    required String title,
    String? emoji,
    List<String> teamKeys = const [],
    PicklistMode mode = PicklistMode.offline,
  }) {
    if (mode == PicklistMode.multiplayer && !_canManageRemotely) {
      throw StateError('Multiplayer picklists require editing permission');
    }
    final now = DateTime.now();
    var id = '${now.microsecondsSinceEpoch}';
    while (state.any((item) => item.id == id)) {
      id = '${int.parse(id) + 1}';
    }
    final item = Picklist(
      id: id,
      eventKey: _eventKey!,
      title: title.trim().isEmpty ? 'Untitled Picklist' : title.trim(),
      emoji: emoji ?? randomPicklistEmoji(),
      teamKeys: List.unmodifiable(teamKeys.toSet()),
      createdAt: now,
      updatedAt: now,
      mode: mode,
    );

    state = [item, ...state];
    _persist();
    if (item.mode == PicklistMode.multiplayer && _canManageRemotely) {
      final ready = _createOnServer(item);
      _pendingRemoteCreates[item.id] = ready;
      unawaited(
        ready.whenComplete(() => _pendingRemoteCreates.remove(item.id)),
      );
    }
    return item;
  }

  /// Starts a live CRDT session for the editor. It is intentionally safe to
  /// call repeatedly from a widget build.
  PicklistSyncSession? open(String id) {
    if (!_canReadRemotely) {
      return null;
    }
    if (_sessions.containsKey(id)) return _sessions[id];
    final item = state.where((picklist) => picklist.id == id).firstOrNull;
    if (item == null) {
      return null;
    }
    if (item.mode != PicklistMode.multiplayer) {
      return null;
    }
    final remoteReady = _pendingRemoteCreates[id];

    final session = PicklistSyncSession(
      initial: item,
      preferences: ref.read(sharedPreferencesProvider),
      client: ref.read(honeycombClientProvider),
      remoteEnabled: true,
      remoteWritable: _canManageRemotely,
      remoteReady: remoteReady,
      onProjectionChanged: (updated) {
        if (ref.mounted) _replaceFromSession(updated);
      },
      onDeleted: () {
        if (ref.mounted) _removeLocal(id);
      },
      profile: _presenceProfile(ref.read(userInfoProvider).asData?.value),
    );
    _sessions[id] = session;
    unawaited(session.start());
    return session;
  }

  Map<String, dynamic> _presenceProfile(UserInfo? user) => {
    'id': ref.read(authMeProvider).value?.user.id,
    'name': user?.name ?? 'Teammate',
    'avatarUrl': user?.pictureUrl,
  };

  void close(String id) => _sessions.remove(id)?.dispose();

  void _removeLocal(String id) {
    _refreshVersion++;
    close(id);
    _pendingPatches.remove(id);
    state = state.where((item) => item.id != id).toList(growable: false);
    _persist();
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .remove('${PicklistSyncSession.storagePrefix}$id'),
    );
  }

  void customize(String id, {String? title, String? emoji}) {
    if (title == null && emoji == null) return;
    _update(
      id,
      (item) => item.copyWith(
        title: title == null
            ? null
            : (title.trim().isEmpty ? 'Untitled Picklist' : title.trim()),
        emoji: emoji,
      ),
    );
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

  Picklist? duplicate(String id, {PicklistMode? mode, String? title}) {
    final source = state.where((picklist) => picklist.id == id).firstOrNull;
    if (source == null || !canEdit(source)) {
      return null;
    }

    return create(
      title: title ?? 'Copy of ${source.title}',
      emoji: source.emoji,
      teamKeys: source.teamKeys,
      mode: mode ?? source.mode,
    );
  }

  void delete(String id) {
    final item = state.where((picklist) => picklist.id == id).firstOrNull;
    if (item == null) {
      return;
    }

    if (item.mode == PicklistMode.multiplayer && !_canManageRemotely) return;
    final remoteCreate = _pendingRemoteCreates[id];
    _removeLocal(id);
    if (item.mode == PicklistMode.multiplayer && _canManageRemotely) {
      unawaited(_deleteOnServer(id, afterCreate: remoteCreate));
    }
  }

  void _update(String id, Picklist Function(Picklist item) update) {
    final previous = state.where((item) => item.id == id).firstOrNull;
    if (previous == null) {
      return;
    }
    if (previous.mode == PicklistMode.multiplayer && !_canManageRemotely) {
      return;
    }

    final now = DateTime.now();
    var changed = false;
    state = state
        .map((item) {
          if (item.id != id) return item;
          changed = true;
          return update(item).copyWith(updatedAt: now);
        })
        .toList(growable: false);
    if (!changed) return;

    final updated = state.firstWhere((item) => item.id == id);

    _persist();
    final session = _sessions[id] ?? open(id);
    if (session != null) {
      if (updated.title != previous.title) session.setTitle(updated.title);
      if (updated.emoji != previous.emoji) session.setEmoji(updated.emoji);
      if (!_sameList(updated.teamKeys, previous.teamKeys)) {
        session.setTeams(updated.teamKeys);
      }
    }
    if (updated.mode == PicklistMode.multiplayer && _canManageRemotely) {
      _queuePatch(updated);
    }
  }

  void _replaceFromSession(Picklist updated) {
    final previous = state.where((item) => item.id == updated.id).firstOrNull;
    if (previous == null ||
        (previous.title == updated.title &&
            previous.emoji == updated.emoji &&
            _sameList(previous.teamKeys, updated.teamKeys))) {
      return;
    }
    var found = false;
    state = state
        .map((item) {
          if (item.id != updated.id) return item;
          found = true;
          return updated;
        })
        .toList(growable: false);
    if (!found) {
      return;
    }

    _persist();
    if (updated.mode == PicklistMode.multiplayer && _canManageRemotely) {
      _queuePatch(updated);
    }
  }

  Future<void> _refreshFromServer() async {
    final eventKey = _eventKey;
    final generation = _generation;
    final version = ++_refreshVersion;
    final knownIds = state.map((item) => item.id).toSet();
    final creatingIds = _pendingRemoteCreates.keys.toSet();
    try {
      final response = await ref
          .read(honeycombClientProvider)
          .get<List<dynamic>>(
            '/picklists',
            queryParams: {'eventKey': eventKey},
            cachePolicy: CachePolicy.networkOnly,
          );
      if (!ref.mounted ||
          generation != _generation ||
          version != _refreshVersion) {
        return;
      }
      final remote = response
          .whereType<Map>()
          .map(
            (raw) => Picklist.fromJson(
              Map<String, dynamic>.from(raw),
              defaultMode: PicklistMode.multiplayer,
            ),
          )
          .where((item) => item.id.isNotEmpty && item.eventKey == _eventKey)
          .toList();

      final localById = {for (final item in state) item.id: item};
      final merged = [
        ...remote,
        for (final item in state)
          if (!remote.any((remoteItem) => remoteItem.id == item.id) &&
              (item.mode == PicklistMode.offline ||
                  creatingIds.contains(item.id) ||
                  _pendingRemoteCreates.containsKey(item.id) ||
                  !knownIds.contains(item.id)))
            item,
      ];
      // A currently-open editor gets its authoritative projection from the
      // CRDT session, not a potentially stale list-page projection.
      for (final id in _sessions.keys) {
        final local = localById[id];
        if (local == null) continue;
        final index = merged.indexWhere((item) => item.id == id);
        if (index >= 0) merged[index] = local;
      }
      final retained = merged.map((item) => item.id).toSet();
      for (final id in localById.keys.where((id) => !retained.contains(id))) {
        close(id);
        _pendingPatches.remove(id);
        unawaited(
          ref
              .read(sharedPreferencesProvider)
              .remove('${PicklistSyncSession.storagePrefix}$id'),
        );
      }
      merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = List.unmodifiable(merged);

      _persist();
    } catch (_) {
      // Keep the local library available when the remote refresh fails.
    }
  }

  Future<void> _createOnServer(Picklist item) async {
    try {
      await ref
          .read(honeycombClientProvider)
          .post<Map<String, dynamic>>('/picklists', data: item.toJson());
    } catch (_) {
      // The failed remote create is represented locally as an offline copy.
      if (ref.mounted && _eventKey == item.eventKey) {
        close(item.id);
        state = [
          for (final current in state)
            if (current.id == item.id)
              current.copyWith(mode: PicklistMode.offline)
            else
              current,
        ];
        _persist();
      }
    }
  }

  void _queuePatch(Picklist item) {
    _pendingPatches[item.id] = item;
    if (_patching.add(item.id)) unawaited(_flushPatches(item.id));
  }

  Future<void> _flushPatches(String id) async {
    final client = ref.read(honeycombClientProvider);
    final generation = _generation;
    try {
      await _pendingRemoteCreates[id];
      while (ref.mounted &&
          generation == _generation &&
          _pendingPatches.containsKey(id)) {
        final item = _pendingPatches.remove(id)!;
        if (!state.any(
          (value) => value.id == id && value.mode == PicklistMode.multiplayer,
        )) {
          break;
        }
        await client.patch<Map<String, dynamic>>(
          '/picklists/$id',
          data: {
            'title': item.title,
            'emoji': item.emoji,
            'teamKeys': item.teamKeys,
          },
        );
      }
    } on HoneycombApiException catch (error) {
      if (ref.mounted && generation == _generation && error.statusCode == 404) {
        _removeLocal(id);
      }
    } catch (_) {
      // Remote projection errors are non-fatal; retain the local state.
    } finally {
      _patching.remove(id);
    }
  }

  Future<void> _deleteOnServer(String id, {Future<void>? afterCreate}) async {
    try {
      await afterCreate;
      await ref.read(honeycombClientProvider).delete('/picklists/$id');
    } catch (_) {
      // The local deletion has already completed; remote cleanup is best effort.
    }
  }

  bool canEdit(Picklist item) =>
      item.mode == PicklistMode.offline || _canManageRemotely;

  bool get _isAuthenticated =>
      ref.read(authStatusProvider) == AuthStatus.authenticated;

  bool get _canReadRemotely =>
      _isAuthenticated &&
      (ref
              .read(permissionCheckerProvider)
              ?.hasPermission(PermissionKey.picklistsRead) ??
          false);

  bool get _canManageRemotely =>
      _isAuthenticated &&
      (ref
              .read(permissionCheckerProvider)
              ?.hasPermission(PermissionKey.picklistsManage) ??
          false);

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

    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(storageKey, jsonEncode(all)),
    );
  }

  static bool _sameList(List<String> left, List<String> right) =>
      left.length == right.length &&
      left.indexed.every((entry) => entry.$2 == right[entry.$1]);
}

final picklistLibraryProvider =
    NotifierProvider<PicklistLibraryNotifier, List<Picklist>>(
      PicklistLibraryNotifier.new,
    );
