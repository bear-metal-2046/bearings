import 'dart:convert';

import 'package:beariscope/pages/picklists/picklist_presence.dart';
import 'package:crdt_socket_sync/relay_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Azure's simple user-event transport expects JSON text, not binary frames.
/// Presence uses the relay's ephemeral 100–102 messages and is consumed here
/// before the CRDT codec sees it.
class AzureWebPubSubTransportConnector implements TransportConnector {
  final String url;
  final PicklistPresence? presence;
  final bool Function() isDisposed;

  AzureWebPubSubTransportConnector(
    this.url, {
    this.presence,
    required this.isDisposed,
  });

  @override
  Future<TransportConnection> connect() async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    try {
      await channel.ready;
      if (isDisposed()) throw StateError('Picklist session closed');
      presence?.connect((frame) => channel.sink.add(jsonEncode(frame)));
      return _AzureWebPubSubTransportConnection(channel, presence);
    } catch (_) {
      await channel.sink.close();
      rethrow;
    }
  }
}

class _AzureWebPubSubTransportConnection implements TransportConnection {
  final WebSocketChannel _channel;
  final PicklistPresence? _presence;

  _AzureWebPubSubTransportConnection(this._channel, this._presence);

  @override
  Stream<List<int>> get incoming async* {
    try {
      await for (final data in _channel.stream) {
        final bytes = data is String ? utf8.encode(data) : (data as List<int>);
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map<String, dynamic> &&
            (_presence?.receive(decoded) ?? false)) {
          continue;
        }
        yield bytes;
      }
    } finally {
      _presence?.disconnect();
    }
  }

  @override
  Future<void> send(List<int> data) async =>
      _channel.sink.add(utf8.decode(data));

  @override
  Future<void> close() {
    _presence?.leave();
    return _channel.sink.close();
  }

  @override
  bool get isConnected => _channel.closeCode == null;
}
