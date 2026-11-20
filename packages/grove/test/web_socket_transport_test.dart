import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grove/grove.dart';
import 'package:test/test.dart';

Future<Uri> _server(
  void Function(WebSocket socket, Map<String, dynamic> message) onMessage,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.transform(WebSocketTransformer()).listen((socket) {
    socket.listen(
      (message) => onMessage(socket, jsonDecode(message as String) as Json),
    );
  });
  return Uri.parse('ws://127.0.0.1:${server.port}');
}

void _reply(WebSocket socket, Json message) => socket.add(jsonEncode(message));

void main() {
  test('a failed WebSocket upgrade opens offline', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      unawaited(request.response.close());
    });
    final transport = WebSocketGroveTransport(
      uri: Uri.parse('ws://127.0.0.1:${server.port}'),
      accessToken: () async => 'token',
    );
    addTearDown(transport.close);

    await expectLater(transport.connect(), throwsA(isA<GroveOffline>()));
    expect(transport.connectionState, GroveConnectionState.disconnected);
  });

  test('an idle session detects a silent drop and reconnects', () async {
    var connections = 0;
    final uri = await _server((socket, message) {
      if (message['op'] == 'authenticate') {
        connections++;
        _reply(socket, {'op': 'ready', 'heartbeat': true});
      } else if (message['op'] == 'ping' && connections > 1) {
        _reply(socket, {'op': 'pong', 'id': message['id']});
      }
    });
    final transport = WebSocketGroveTransport(
      uri: uri,
      accessToken: () async => 'token',
      reconnectDelay: const Duration(milliseconds: 10),
      heartbeatInterval: const Duration(milliseconds: 25),
      heartbeatTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(transport.close);
    await transport.connect();
    final recovered = transport
        .watchConnection()
        .skipWhile((state) => state != GroveConnectionState.disconnected)
        .firstWhere((state) => state == GroveConnectionState.connected);
    await recovered.timeout(const Duration(seconds: 3));
    final info = await transport.watchConnectionInfo().first;
    expect(info.lastFailure?.message, contains('connection check'));
    expect(info.lastReplyAt, isNotNull);
    expect(connections, 2);
  });

  test('concurrent callers share authentication and a rejected token is renewed once', () async {
    final tokens = <String>[];
    final uri = await _server((socket, message) {
      if (message['op'] != 'authenticate') return;
      final token = message['token'] as String;
      tokens.add(token);
      if (token == 'old') {
        _reply(socket, {
          'op': 'error',
          'code': 'unauthenticated',
          'message': 'Expired',
        });
      } else {
        _reply(socket, {'op': 'ready', 'heartbeat': true});
      }
    });
    var tokenReads = 0;
    var renewals = 0;
    final transport = WebSocketGroveTransport(
      uri: uri,
      accessToken: () async {
        tokenReads++;
        return 'old';
      },
      refreshAccessToken: () async {
        renewals++;
        return 'renewed';
      },
    );
    addTearDown(transport.close);
    await Future.wait([transport.connect(), transport.connect()]);
    expect(transport.connectionState, GroveConnectionState.connected);
    expect(tokens, ['old', 'renewed']);
    expect(tokenReads, 1);
    expect(renewals, 1);
  });

  test('a slow request leaves a responsive connection open', () async {
    var connections = 0;
    final ping = Completer<void>();
    final uri = await _server((socket, message) {
      if (message['op'] == 'authenticate') {
        connections++;
        _reply(socket, {'op': 'ready', 'heartbeat': true});
      } else if (message['op'] == 'ping') {
        _reply(socket, {'op': 'pong', 'id': message['id']});
        if (!ping.isCompleted) ping.complete();
      }
    });
    final transport = WebSocketGroveTransport(
      uri: uri,
      accessToken: () async => 'token',
      requestTimeout: const Duration(milliseconds: 200),
      heartbeatInterval: const Duration(seconds: 10),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.fetch(QueryDescription(type: 'sample')),
      throwsA(isA<GroveRequestTimeout>()),
    );
    await ping.future.timeout(const Duration(seconds: 2));
    expect(transport.connectionState, GroveConnectionState.connected);
    expect(connections, 1);
  });
}
