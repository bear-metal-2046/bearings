import 'dart:async';
import 'dart:convert';

import 'package:beariscope/pages/picklists/azure_web_pubsub_transport.dart';
import 'package:beariscope/pages/picklists/picklist_model.dart';
import 'package:beariscope/pages/picklists/picklist_presence.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/foundation.dart';
import 'package:services/providers/api_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef PicklistProjectionChanged = void Function(Picklist picklist);

class PicklistSyncSession {
  static const storagePrefix = 'picklist_crdt_v1_';
  static const _restoreOrigin = Object();
  final Picklist initial;
  final SharedPreferences preferences;
  final HoneycombClient client;
  final bool remoteEnabled;
  final bool remoteWritable;
  final Future<void>? remoteReady;
  final PicklistProjectionChanged onProjectionChanged;
  final VoidCallback? onDeleted;
  late final CRDTDocument document;
  late final CRDTRegisterHandler<String> _title;
  late final CRDTRegisterHandler<String> _emoji;
  late final CRDTFugueMovableListHandler<String> _teams;
  late final PicklistPresence presence;
  StreamSubscription<void>? _updatesSubscription;
  StreamSubscription<Change>? _localChangesSubscription;
  StreamSubscription<Message>? _messagesSubscription;
  WebSocketRelayClient? _relay;
  Timer? _recoveryTimer;
  Future<void>? _startFuture;
  Future<void> _lastStorageWrite = Future<void>.value();
  final List<String> _pendingChanges = [];
  Completer<void>? _pendingDrained;
  bool _connectingRemote = false;
  bool _started = false;
  bool _disposed = false;
  String? _pendingTitle;
  String? _pendingEmoji;
  List<String>? _pendingTeams;

  PicklistSyncSession({
    required this.initial,
    required this.preferences,
    required this.client,
    required this.remoteEnabled,
    required this.remoteWritable,
    this.remoteReady,
    required this.onProjectionChanged,
    this.onDeleted,
    Map<String, dynamic> profile = const {},
  }) {
    document = CRDTDocument(documentId: initial.id);
    _title = CRDTRegisterHandler<String>(
      document,
      'title',
      handlerType: 'beariscope.picklist.title',
    );
    _emoji = CRDTRegisterHandler<String>(
      document,
      'emoji',
      handlerType: 'beariscope.picklist.emoji',
    );
    _teams = CRDTFugueMovableListHandler<String>(
      document,
      'teams',
      handlerType: 'beariscope.picklist.teams',
    );
    presence = PicklistPresence(
      documentId: initial.id,
      peerId: document.peerId.toString(),
      profile: profile,
    );
  }

  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    _restoreLocalState();
    _updatesSubscription = document.updates.listen((_) {
      if (_disposed) return;
      onProjectionChanged(_projection());
      unawaited(_persistLocalState());
    });
    if (remoteEnabled && remoteWritable) {
      _localChangesSubscription = document.localChanges.listen((change) {
        if (_disposed) return;
        _pendingChanges.add(base64Encode(change.toBytes()));
        unawaited(_persistLocalState());
      });
    }
    if (remoteEnabled) {
      try {
        await remoteReady;
        if (_disposed) return;
        await _connectRemote();
      } catch (_) {
        // Realtime sync is best effort; continue with the local projection.
      }
      if (_disposed) return;
      _recoveryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_disposed) return;
        final relay = _relay;
        if (relay == null) {
          unawaited(_connectRemote().catchError((_) {}));
        } else if (relay.connectionStatusValue == ConnectionStatus.error) {
          unawaited(relay.connect());
        }
      });
    }
    if (_disposed) return;
    // Readers must never seed an empty remote document or replay local edits.
    if (!remoteEnabled || remoteWritable) {
      if (document.isEmpty) {
        document.runInTransaction(() {
          _title.set(_pendingTitle ?? initial.title);
          _emoji.set(_pendingEmoji ?? initial.emoji);
          _replaceTeamsNow(_pendingTeams ?? initial.teamKeys);
        });
      } else {
        if (_pendingEmoji != null) _emoji.set(_pendingEmoji!);
        if (_pendingTitle != null) _setTitleNow(_pendingTitle!);
        if (_pendingTeams != null) _replaceTeamsNow(_pendingTeams!);
      }
    }
    _pendingTitle = null;
    _pendingEmoji = null;
    _pendingTeams = null;
    _started = true;
    onProjectionChanged(_projection());
    await _persistLocalState();
  }

  Future<void> _connectRemote() async {
    if (_connectingRemote || _relay != null || _disposed) return;
    _connectingRemote = true;
    try {
      var firstUrl = await _negotiateRemoteUrl();
      if (_disposed) return;
      final relay = WebSocketRelayClient.test(
        url: firstUrl,
        document: document,
        author: document.peerId,
        transportFactory: () => Transport.create(
          AzureWebPubSubTransportConnector(
            () async {
              if (_disposed) throw StateError('Picklist session closed');
              final url = firstUrl;
              if (url.isNotEmpty) {
                firstUrl = '';
                return url;
              }
              return _negotiateRemoteUrl();
            },
            presence: presence,
            isDisposed: () => _disposed,
          ),
        ),
        maxReconnectAttempts: 20,
      );
      _relay = relay;
      if (remoteWritable) {
        for (final encoded in _pendingChanges) {
          await relay.sendChange(Change.fromBytes(base64Decode(encoded)));
        }
      }
      _messagesSubscription = relay.messages.listen((message) {
        if (message is RelayAckMessage && message.documentId == initial.id) {
          final acknowledged = message.count.clamp(0, _pendingChanges.length);
          _pendingChanges.removeRange(0, acknowledged);
          if (_pendingChanges.isEmpty &&
              !(_pendingDrained?.isCompleted ?? true)) {
            _pendingDrained!.complete();
          }
          unawaited(_persistLocalState());
        }
        final data = message.toJson();
        if (data['code'] == 'not_found' && !_disposed) onDeleted?.call();
      });
      await relay.connect();
    } on HoneycombApiException catch (error) {
      if (error.statusCode == 404) {
        if (!_disposed) onDeleted?.call();
        return;
      }
      rethrow;
    } finally {
      _connectingRemote = false;
    }
  }

  Future<String> _negotiateRemoteUrl() async {
    final response = await client.get<Map<String, dynamic>>(
      '/picklists/realtime/negotiate',
      queryParams: {'picklistId': initial.id},
      cachePolicy: CachePolicy.networkOnly,
    );
    final url = response['url']?.toString();
    if (url == null || url.isEmpty) {
      throw StateError('Realtime negotiation returned no URL');
    }
    return url;
  }

  bool get hasPendingChanges => _pendingChanges.isNotEmpty;

  /// Used by short-lived list-page edits before closing their relay session.
  /// A timeout leaves the edits in local storage for a later retry.
  Future<void> waitForPendingChanges(Duration timeout) async {
    await start();
    await Future<void>.delayed(Duration.zero);
    if (_disposed || _pendingChanges.isEmpty) return;
    final drained = _pendingDrained ??= Completer<void>();
    if (_pendingChanges.isEmpty && !drained.isCompleted) drained.complete();
    try {
      await drained.future.timeout(timeout);
    } on TimeoutException {
      // Pending changes stay persisted and will be retried on the next open.
    } finally {
      if (identical(_pendingDrained, drained)) _pendingDrained = null;
    }
  }

  void setTitle(String value) {
    if (_disposed || (remoteEnabled && !remoteWritable)) return;
    if (_started) {
      _setTitleNow(value);
    } else {
      _pendingTitle = value;
    }
  }

  void setEmoji(String value) {
    if (_disposed || (remoteEnabled && !remoteWritable)) return;
    if (_started) {
      if (_emoji.value != value) _emoji.set(value);
    } else {
      _pendingEmoji = value;
    }
  }

  void setTeams(List<String> values) {
    if (_disposed || (remoteEnabled && !remoteWritable)) return;
    if (_started) {
      _replaceTeamsNow(values);
    } else {
      _pendingTeams = List.of(values);
    }
  }

  void _setTitleNow(String value) {
    if (_title.value != value) _title.set(value);
  }

  void _replaceTeamsNow(List<String> values) =>
      replacePicklistTeams(document, _teams, values);

  Picklist _projection() => initial.copyWith(
    title: _title.value ?? initial.title,
    emoji: _emoji.value ?? initial.emoji,
    teamKeys: document.isEmpty
        ? initial.teamKeys
        : List.unmodifiable(_teams.value),
    updatedAt: DateTime.now(),
  );

  void _restoreLocalState() {
    final raw = preferences.getString('$storagePrefix${initial.id}');
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map;
      final changes = (decoded['changes'] as List)
          .cast<String>()
          .map((encoded) => Change.fromBytes(base64Decode(encoded)))
          .toList();
      document.importChanges(changes, origin: _restoreOrigin);
      _pendingChanges.addAll(
        (decoded['pendingChanges'] as List? ?? const []).cast<String>(),
      );
    } catch (error) {
      debugPrint('Ignoring corrupt picklist cache: $error');
    }
  }

  Future<void> _persistLocalState() async {
    if (_disposed || document.isEmpty) return;
    final payload = jsonEncode({
      'changes': [
        for (final change in document.exportChanges())
          base64Encode(change.toBytes()),
      ],
      'pendingChanges': List<String>.of(_pendingChanges),
    });
    _lastStorageWrite = _lastStorageWrite
        .catchError((_) {})
        .then(
          (_) => preferences.setString('$storagePrefix${initial.id}', payload),
        );
    await _lastStorageWrite;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!(_pendingDrained?.isCompleted ?? true)) _pendingDrained!.complete();
    _recoveryTimer?.cancel();
    _updatesSubscription?.cancel();
    _localChangesSubscription?.cancel();
    _messagesSubscription?.cancel();
    // The transport owns disconnect callbacks; keep the notifier alive until
    // that transport has closed.
    presence.dispose();
    _relay?.dispose();
    document.dispose();
  }
}

/// A drag is one CRDT move, including downward moves. Moving every intervening
/// neighbor separately exposes intermediate orders to peers over the relay.
void replacePicklistTeams(
  CRDTDocument document,
  CRDTFugueMovableListHandler<String> teams,
  List<String> values,
) {
  final desired = values.toSet().toList();
  final current = teams.value;
  if (listEquals(current, desired)) return;
  if (current.length == desired.length &&
      current.toSet().containsAll(desired)) {
    final first = current.indexed
        .firstWhere((entry) => entry.$2 != desired[entry.$1])
        .$1;
    final candidates = [
      (first, desired.indexOf(current[first])),
      (current.indexOf(desired[first]), first),
    ];
    for (final (from, to) in candidates) {
      final moved = List<String>.of(current)..removeAt(from);
      moved.insert(to, current[from]);
      if (listEquals(moved, desired)) {
        teams.move(from, to);
        return;
      }
    }
  }
  document.runInTransaction(() {
    final wanted = desired.toSet();
    for (var i = teams.value.length - 1; i >= 0; i--) {
      if (!wanted.contains(teams.value[i])) teams.delete(i);
    }
    for (var i = 0; i < desired.length; i++) {
      final now = teams.value;
      if (i < now.length && now[i] == desired[i]) continue;
      final existing = now.indexOf(desired[i], i);
      if (existing >= 0) {
        teams.move(existing, i);
      } else {
        teams.insert(i, desired[i]);
      }
    }
  });
}
