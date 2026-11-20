import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'entity.dart';
import 'query.dart';
import 'transport.dart';

/// One authenticated connection multiplexes queries, mutations and subscriptions.
/// Authentication is a first message, keeping access tokens out of URLs and logs.
class WebSocketGroveTransport
    implements GroveConnectionTransport, GrovePresenceTransport {
  WebSocketGroveTransport({
    required this.uri,
    required this.accessToken,
    this.refreshAccessToken,
    this.reconnectDelay = const Duration(seconds: 1),
    this.requestTimeout = const Duration(seconds: 15),
    this.heartbeatInterval = const Duration(seconds: 10),
    this.heartbeatTimeout = const Duration(seconds: 5),
  });

  final Uri uri;
  final Future<String> Function() accessToken;
  final Future<String> Function()? refreshAccessToken;
  final Duration reconnectDelay;
  final Duration requestTimeout;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;

  WebSocketChannel? _channel;
  Future<void>? _connecting;
  Completer<void>? _ready;
  Timer? _retry;
  Timer? _heartbeat;
  bool _closed = false;
  bool _authenticated = false;
  bool _attempted = false;
  bool _keepConnected = false;
  bool _supportsHeartbeat = false;
  bool _refreshOnConnect = false;
  String? _pingId;
  int _retryCount = 0;
  final _random = Random();
  GroveConnectionState _state = GroveConnectionState.disconnected;
  DateTime? _lastReplyAt;
  GroveException? _lastFailure;
  final _connectionChanges = StreamController<GroveConnectionInfo>.broadcast();

  int _nextId = 0;
  final _pending = <String, Completer<Json>>{};
  final _watches =
      <
        String,
        ({QueryDescription query, StreamController<QuerySnapshot> controller})
      >{};
  final _presence =
      <
        String,
        ({
          String type,
          String entityId,
          StreamController<List<GrovePresencePeer>> controller,
        })
      >{};

  @override
  GroveConnectionState get connectionState => _state;

  GroveConnectionInfo get _connectionInfo => GroveConnectionInfo(
    state: _state,
    lastReplyAt: _lastReplyAt,
    lastFailure: _lastFailure,
  );

  Stream<GroveConnectionInfo> watchConnectionInfo() => Stream.multi((listener) {
    final subscription = _connectionChanges.stream.listen(
      listener.add,
      onDone: listener.close,
    );
    listener.add(_connectionInfo);
    listener.onCancel = subscription.cancel;
  }, isBroadcast: true);

  @override
  Stream<GroveConnectionState> watchConnection() =>
      watchConnectionInfo().map((info) => info.state).distinct();

  @override
  Future<void> connect() {
    _keepConnected = true;
    return _ensureConnected();
  }

  Future<void> _ensureConnected() {
    if (_closed) return Future.error(const GroveOffline());
    if (_authenticated) return Future.value();
    if (_connecting case final attempt?) return attempt;
    if (_state == GroveConnectionState.signInRequired ||
        _retry?.isActive == true) {
      return Future.error(_lastFailure ?? const GroveOffline());
    }
    return _connecting = _open().whenComplete(() => _connecting = null);
  }

  @override
  void checkConnection() {
    if (_closed || _state == GroveConnectionState.signInRequired) return;
    if (_authenticated) {
      _ping();
    } else if (_keepConnected || _watches.isNotEmpty || _presence.isNotEmpty) {
      _retry?.cancel();
      _retry = null;
      unawaited(_ensureConnected().catchError((Object _) {}));
    }
  }

  void _setConnection(GroveConnectionState state) {
    if (_closed) return;
    _state = state;
    _connectionChanges.add(_connectionInfo);
  }

  Future<void> _open() async {
    _setConnection(
      _attempted
          ? GroveConnectionState.reconnecting
          : GroveConnectionState.connecting,
    );
    _attempted = true;
    final elapsed = Stopwatch()..start();
    Duration remaining() => requestTimeout - elapsed.elapsed;
    try {
      var renew = _refreshOnConnect && refreshAccessToken != null;
      while (true) {
        final token = await (renew ? refreshAccessToken!() : accessToken())
            .timeout(remaining());
        if (_closed) throw const GroveOffline();
        _refreshOnConnect = false;
        try {
          await _openChannel(token, remaining);
          break;
        } on GroveException catch (error) {
          if (_closed ||
              renew ||
              refreshAccessToken == null ||
              error.code != 'unauthenticated') {
            rethrow;
          }
          renew = true;
          _refreshOnConnect = true;
        }
      }
      if (_closed || _channel == null) throw const GroveOffline();
      _authenticated = true;
      _retryCount = 0;
      _lastReplyAt = DateTime.now();
      _setConnection(GroveConnectionState.connected);
      _scheduleHeartbeat();
      for (final entry in _watches.entries) {
        _send({
          'op': 'subscribe',
          'id': entry.key,
          'query': entry.value.query.toJson(),
        });
      }
      for (final entry in _presence.entries) {
        _joinPresence(entry.key, entry.value.type, entry.value.entityId);
      }
    } catch (error) {
      final failure = switch (error) {
        GroveException() => error,
        TimeoutException() => const GroveOffline(
          'Connection to the server timed out',
        ),
        _ => const GroveOffline('Could not connect to the server'),
      };
      if (_channel case final channel?) {
        _disconnect(channel, failure);
      } else if (!_closed) {
        _connectionFailed(failure);
      }
      throw failure;
    }
  }

  Future<void> _openChannel(String token, Duration Function() remaining) async {
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    try {
      await channel.ready.timeout(remaining());
      if (_closed || !identical(channel, _channel)) throw const GroveOffline();
      final ready = _ready = Completer<void>();
      final authenticated = ready.future.timeout(remaining());
      channel.stream.listen(
        (raw) {
          if (identical(channel, _channel)) _message(raw);
        },
        onError: (Object _) => _channelEnded(channel),
        onDone: () => _channelEnded(channel),
      );
      channel.sink.add(jsonEncode({'op': 'authenticate', 'token': token}));
      await authenticated;
      if (!identical(channel, _channel)) throw const GroveOffline();
    } catch (_) {
      if (identical(channel, _channel)) {
        _channel = null;
        _ready = null;
        unawaited(channel.sink.close());
      }
      rethrow;
    }
  }

  void _send(Json message) => _channel!.sink.add(jsonEncode(message));

  void _message(dynamic raw) {
    try {
      final message = jsonDecode(raw as String) as Json;
      final operation = message['op'];
      if (operation == 'ready') {
        if (_ready?.isCompleted == false) {
          _supportsHeartbeat = message['heartbeat'] == true;
          _ready!.complete();
        }
        return;
      }
      final id = message['id'] as String?;
      if (_authenticated && (operation != 'pong' || id == _pingId)) {
        _lastReplyAt = DateTime.now();
        _pingId = null;
        _connectionChanges.add(_connectionInfo);
        _scheduleHeartbeat();
      }
      if (operation == 'pong') return;
      if (operation == 'error') {
        final error = GroveException(
          message['code'] as String,
          message['message'] as String,
        );
        if (id == null) {
          if (_ready?.isCompleted == false) _ready!.completeError(error);
          return;
        }
        _pending.remove(id)?.completeError(error);
        _watches[id]?.controller.addError(error);
        _presence[id]?.controller.addError(error);
      } else if (operation == 'presence') {
        _presence[id]?.controller.add(
          (message['peers'] as List)
              .map((peer) => GrovePresencePeer.fromJson(peer as Json))
              .toList(),
        );
      } else if (operation == 'snapshot') {
        _watches[id]?.controller.add(
          QuerySnapshot.fromJson(message['result'] as Json),
        );
      } else if (id != null) {
        _pending.remove(id)?.complete(message['result'] as Json);
      }
    } catch (_) {
      if (_channel case final channel?) _channelEnded(channel);
    }
  }

  void _scheduleHeartbeat() {
    _heartbeat?.cancel();
    if (_supportsHeartbeat && !_closed) {
      _heartbeat = Timer(heartbeatInterval, _ping);
    }
  }

  void _ping() {
    final channel = _channel;
    if (_closed ||
        !_authenticated ||
        !_supportsHeartbeat ||
        _pingId != null ||
        channel == null) {
      return;
    }
    _heartbeat?.cancel();
    final id = _pingId = 'heartbeat:${_nextId++}';
    _heartbeat = Timer(heartbeatTimeout, () {
      _disconnect(
        channel,
        const GroveOffline('The server did not answer its connection check'),
      );
    });
    try {
      _send({'op': 'ping', 'id': id});
    } catch (_) {
      _channelEnded(channel);
    }
  }

  void _channelEnded(WebSocketChannel channel) {
    if (!identical(channel, _channel)) return;
    final authenticationClosed = channel.closeCode == 4401;
    if (!_authenticated && _ready?.isCompleted == false) {
      _ready!.completeError(
        authenticationClosed
            ? const GroveException(
                'unauthenticated',
                'The server rejected the session',
              )
            : const GroveOffline('The server closed the connection'),
      );
      return;
    }
    if (authenticationClosed) _refreshOnConnect = true;
    _disconnect(
      channel,
      const GroveOffline('The server closed the connection'),
    );
  }

  void _disconnect(WebSocketChannel channel, GroveException error) {
    if (!identical(channel, _channel)) return;
    _channel = null;
    _authenticated = false;
    _supportsHeartbeat = false;
    _pingId = null;
    _heartbeat?.cancel();
    if (_ready?.isCompleted == false) _ready!.completeError(error);
    _ready = null;
    unawaited(channel.sink.close());
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
    if (!_closed) _connectionFailed(error);
  }

  void _connectionFailed(GroveException error) {
    // Retain a sanitized reason for diagnostics. Auth errors can originate at the token endpoint.
    _lastFailure = switch (error.code) {
      'unauthenticated' => const GroveException(
        'unauthenticated',
        'Sign in again to connect to the server',
      ),
      'offline' => error,
      _ => const GroveOffline('The server could not establish a session'),
    };
    _setConnection(
      error.code == 'unauthenticated'
          ? GroveConnectionState.signInRequired
          : GroveConnectionState.disconnected,
    );
    for (final watch in _watches.values) {
      watch.controller.addError(_lastFailure!);
    }
    for (final member in _presence.values) {
      member.controller.add(const []);
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed ||
        _state == GroveConnectionState.signInRequired ||
        (!_keepConnected && _watches.isEmpty && _presence.isEmpty) ||
        _retry?.isActive == true) {
      return;
    }
    final maximum = const Duration(seconds: 30).inMilliseconds;
    final delay = min(
      maximum,
      reconnectDelay.inMilliseconds * (1 << min(_retryCount++, 10)),
    );
    final jitter = _random.nextInt(delay ~/ 4 + 1);
    _retry = Timer(Duration(milliseconds: min(maximum, delay + jitter)), () {
      _retry = null;
      unawaited(_ensureConnected().catchError((Object _) {}));
    });
  }

  Future<Json> _request(Json message, {Duration? timeout}) async {
    await _ensureConnected();
    final channel = _channel;
    if (!_authenticated || channel == null) throw const GroveOffline();
    final id = 'request:${_nextId++}';
    final completer = Completer<Json>();
    _pending[id] = completer;
    try {
      _send({...message, 'id': id});
      return await completer.future.timeout(timeout ?? requestTimeout);
    } on TimeoutException {
      if (identical(channel, _channel) && !_supportsHeartbeat) {
        const failure = GroveOffline('The server did not respond');
        _pending.remove(id);
        _disconnect(channel, failure);
        throw failure;
      }
      if (identical(channel, _channel)) _ping();
      throw const GroveRequestTimeout();
    } finally {
      _pending.remove(id);
    }
  }

  /// Retrieves an upstream competition response through Honeycomb.
  Future<Object?> competition(String resource, Json arguments) async =>
      (await _request({
        'op': 'competition',
        'resource': resource,
        'arguments': arguments,
      }, timeout: const Duration(seconds: 75)))['data'];

  /// Runs an authenticated Honeycomb account action.
  Future<Json> account(String action, [Json arguments = const {}]) => _request({
    'op': 'account',
    'action': action,
    'arguments': arguments,
  }, timeout: const Duration(seconds: 35));

  @override
  Future<QuerySnapshot> fetch(QueryDescription query) async =>
      QuerySnapshot.fromJson(
        await _request({'op': 'query', 'query': query.toJson()}),
      );
  @override
  Future<EntityRecord> mutate(EntityMutation mutation) async =>
      EntityRecord.fromJson(
        await _request({'op': 'mutate', 'mutation': mutation.toJson()}),
      );
  @override
  Stream<QuerySnapshot> watch(QueryDescription query) {
    final id = 'subscription:${_nextId++}';
    late StreamController<QuerySnapshot> controller;
    controller = StreamController(
      onListen: () {
        final connected = _authenticated && _channel != null;
        _watches[id] = (query: query, controller: controller);
        if (connected) {
          _send({'op': 'subscribe', 'id': id, 'query': query.toJson()});
        } else if (_state == GroveConnectionState.signInRequired ||
            _retry?.isActive == true) {
          controller.addError(_lastFailure ?? const GroveOffline());
        } else {
          unawaited(_ensureConnected().catchError((Object _) {}));
        }
      },
      onCancel: () {
        _watches.remove(id);
        if (_authenticated && _channel != null) {
          _send({'op': 'unsubscribe', 'id': id});
        }
      },
    );
    return controller.stream;
  }

  void _joinPresence(String id, String type, String entityId) => _send({
    'op': 'joinPresence',
    'id': id,
    'type': type,
    'entityId': entityId,
  });

  @override
  Stream<List<GrovePresencePeer>> watchPresence(String type, String entityId) {
    final id = 'presence:${_nextId++}';
    late StreamController<List<GrovePresencePeer>> controller;
    controller = StreamController(
      onListen: () {
        _presence[id] = (
          type: type,
          entityId: entityId,
          controller: controller,
        );
        if (_authenticated && _channel != null) {
          _joinPresence(id, type, entityId);
        } else {
          unawaited(
            _ensureConnected().catchError((Object _) => _scheduleRetry()),
          );
        }
      },
      onCancel: () {
        _presence.remove(id);
        if (_authenticated && _channel != null) {
          _send({'op': 'leavePresence', 'id': id});
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _retry?.cancel();
    _heartbeat?.cancel();
    final channel = _channel;
    if (channel != null) {
      _disconnect(channel, const GroveOffline());
    }
    for (final watch in _watches.values.toList()) {
      unawaited(watch.controller.close());
    }
    _watches.clear();
    for (final member in _presence.values.toList()) {
      unawaited(member.controller.close());
    }
    _presence.clear();
    await _connectionChanges.close();
  }
}
