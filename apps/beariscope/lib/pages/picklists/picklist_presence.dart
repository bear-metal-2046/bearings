import 'dart:async';

import 'package:flutter/foundation.dart';

/// Ephemeral room presence. Heartbeats expire after an ungraceful disconnect;
/// none of this data is written to the CRDT or the local picklist cache.
class PicklistPresence {
  final String documentId;
  final String peerId;
  Map<String, dynamic> _profile;
  Map<String, dynamic> get profile => _profile;
  final DateTime Function() now;
  final peers = ValueNotifier<List<Map<String, dynamic>>>(const []);
  final _seen = <String, ({DateTime at, Map<String, dynamic> profile})>{};
  Timer? _heartbeat;
  bool _disposed = false;
  void Function(Map<String, dynamic>)? _send;

  PicklistPresence({
    required this.documentId,
    required this.peerId,
    required Map<String, dynamic> profile,
    this.now = DateTime.now,
  }) : _profile = Map.unmodifiable(profile);

  void updateProfile(Map<String, dynamic> profile) {
    if (_disposed || mapEquals(_profile, profile)) return;
    _profile = Map.unmodifiable(profile);
    _announce();
  }

  void connect(void Function(Map<String, dynamic>) send) {
    if (_disposed) return;
    disconnect();
    _send = send;
    _announce();
    send({'type': 101, 'documentId': documentId, 'presence': true});
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      _announce();
      _publish();
    });
  }

  void _announce() => _send?.call({
    'type': 100,
    'documentId': documentId,
    'presence': true,
    'peerId': peerId,
    'profile': profile,
  });

  bool receive(Map<String, dynamic> frame) {
    if (_disposed) return true;
    if (frame['presence'] != true || frame['documentId'] != documentId) {
      return false;
    }
    final id = frame['peerId'];
    switch (frame['type']) {
      case 101:
        _announce();
      case 100:
        if (id is String && id != peerId && frame['profile'] is Map) {
          _seen[id] = (
            at: now(),
            profile: {
              for (final key in ['id', 'name', 'avatarUrl'])
                if ((frame['profile'] as Map)[key] is String)
                  key: (frame['profile'] as Map)[key],
            },
          );
          _publish();
        }
      case 102:
        _seen.remove(id);
        _publish();
    }
    return true;
  }

  void _publish() {
    final cutoff = now().subtract(const Duration(seconds: 45));
    _seen.removeWhere((_, value) => value.at.isBefore(cutoff));
    final users = <String, Map<String, dynamic>>{};
    for (final entry in _seen.entries) {
      users[entry.value.profile['id']?.toString() ?? entry.key] =
          entry.value.profile;
    }
    peers.value = List.unmodifiable(users.values);
  }

  void disconnect() {
    if (_disposed) return;
    _heartbeat?.cancel();
    _heartbeat = null;
    _send = null;
    _seen.clear();
    peers.value = const [];
  }

  void leave() {
    _send?.call({
      'type': 102,
      'documentId': documentId,
      'presence': true,
      'peerId': peerId,
    });
    disconnect();
  }

  void dispose() {
    leave();
    _disposed = true;
    peers.dispose();
  }
}
