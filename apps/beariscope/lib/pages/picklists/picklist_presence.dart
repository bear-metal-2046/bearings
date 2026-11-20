import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:grove/grove.dart';

class PicklistPresence {
  PicklistPresence(Stream<List<GrovePresencePeer>> stream) {
    _subscription = stream.listen(
      (value) => peers.value = List.unmodifiable(value.map((p) => p.toJson())),
      onError: (Object _) => peers.value = const [],
      onDone: () => peers.value = const [],
    );
  }

  final peers = ValueNotifier<List<Map<String, dynamic>>>(const []);
  late final StreamSubscription<List<GrovePresencePeer>> _subscription;

  void dispose() {
    unawaited(_subscription.cancel());
    peers.dispose();
  }
}
