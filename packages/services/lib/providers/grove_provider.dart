import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:grove/grove.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod/riverpod.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/connectivity_provider.dart';

const _boxName = 'grove_v2';
const _previousBoxName = 'grove_v1';

/// Call after the app initializes Hive. Browser persistence is opt-in.
Future<void> initializeGroveStorage({bool persistOnWeb = false}) async {
  if (!kIsWeb || persistOnWeb) {
    // The GamePack cutover changes the binding and offline observation shape.
    // Drop old snapshots and queued submissions instead of replaying them.
    if (!kIsWeb && await Hive.boxExists(_previousBoxName)) {
      await Hive.deleteBoxFromDisk(_previousBoxName);
    }
    await Hive.openBox<String>(_boxName);
  }
}

final groveSubjectProvider = FutureProvider<String?>((ref) async {
  if (ref.watch(authStatusProvider) != AuthStatus.authenticated) return null;
  return (await ref.watch(authProvider.future)).user?.subject;
});

typedef GroveAccessToken = Future<String> Function({
  required bool forceRefresh,
});

final groveAccessTokenProvider = Provider<GroveAccessToken>((ref) {
  return ({required forceRefresh}) async {
    final auth = await ref.read(authProvider.future);
    return auth.getAccessToken([
      auth.config.audience,
    ], forceRefresh: forceRefresh);
  };
});

final persistGroveOnWebProvider = Provider<bool>((ref) => false);

final bearingsGroveProvider = Provider<Grove>((ref) {
  final endpoint = ref.watch(honeycombEndpointPreferenceProvider).baseUrl;
  final status = ref.watch(authStatusProvider);
  final subject = ref.watch(groveSubjectProvider.future);
  final token = ref.watch(groveAccessTokenProvider);
  final base = Uri.parse(endpoint);
  final uri = base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/grove/ws',
  );
  final cache =
      (!kIsWeb || ref.watch(persistGroveOnWebProvider)) &&
          Hive.isBoxOpen(_boxName)
      ? _HiveGroveCache(Hive.box<String>(_boxName), endpoint, subject)
      : MemoryGroveCache();
  final grove = Grove(
    registry: bearingsEntityRegistry(),
    cache: cache,
    transport: WebSocketGroveTransport(
      uri: uri,
      accessToken: () {
        if (status != AuthStatus.authenticated) {
          throw const GroveException('unauthenticated', 'Sign in to use Grove');
        }
        return token(forceRefresh: false);
      },
      refreshAccessToken: () => token(forceRefresh: true),
    ),
  );
  ref.onDispose(() => unawaited(grove.close()));
  return grove;
});

/// Honeycomb operations that call an upstream service or use server secrets.
final honeycombActionsProvider = Provider<WebSocketGroveTransport>((ref) {
  final transport = ref.watch(bearingsGroveProvider).transport;
  if (transport is! WebSocketGroveTransport) {
    throw const GroveException('unavailable', 'Server actions are unavailable');
  }
  return transport;
});

/// Finishes after the initial attempt. Grove owns subsequent retries.
final connectHoneycombProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final transport = ref.read(bearingsGroveProvider).transport;
    if (transport is! GroveConnectionTransport) return;
    try {
      await transport.connect();
    } on GroveException catch (error) {
      if (error.code == 'unauthenticated') _requireSignIn(ref, transport);
    }
  };
});

void _requireSignIn(Ref ref, GroveConnectionTransport transport) {
  if (ref.mounted &&
      ref.read(authStatusProvider) == AuthStatus.authenticated &&
      identical(ref.read(bearingsGroveProvider).transport, transport)) {
    ref.read(authStatusProvider.notifier).setStatus(AuthStatus.unauthenticated);
  }
}

/// Bind the current authenticated session to the app lifecycle and network hints.
final honeycombSessionProvider = Provider<void>((ref) {
  if (ref.watch(authStatusProvider) != AuthStatus.authenticated) return;
  final transport = ref.watch(bearingsGroveProvider).transport;
  if (transport is! GroveConnectionTransport) return;

  final connection = transport.watchConnection().listen((state) {
    if (state == GroveConnectionState.signInRequired) {
      _requireSignIn(ref, transport);
    }
  });
  final lifecycle = AppLifecycleListener(onResume: transport.checkConnection);
  final network = Connectivity().onConnectivityChanged.listen(
    (_) => transport.checkConnection(),
    onError: (Object _, StackTrace _) {},
  );
  ref.onDispose(() {
    unawaited(connection.cancel());
    unawaited(network.cancel());
    lifecycle.dispose();
  });

  // Also start after interactive login, provisioning or an endpoint change.
  scheduleMicrotask(() {
    if (ref.mounted) unawaited(ref.read(connectHoneycombProvider)());
  });
});

/// Reports readiness of the selected Honeycomb session.
final honeycombConnectionProvider =
    StreamProvider.autoDispose<GroveConnectionState>((ref) {
      if (ref.watch(authStatusProvider) != AuthStatus.authenticated) {
        return Stream.value(GroveConnectionState.signInRequired);
      }
      final transport = ref.watch(bearingsGroveProvider).transport;
      return transport is GroveConnectionTransport
          ? transport.watchConnection()
          : Stream.value(GroveConnectionState.disconnected);
    });

final honeycombConnectionInfoProvider =
    StreamProvider.autoDispose<GroveConnectionInfo?>((ref) {
      if (ref.watch(authStatusProvider) != AuthStatus.authenticated) {
        return Stream.value(null);
      }
      final transport = ref.watch(bearingsGroveProvider).transport;
      return transport is WebSocketGroveTransport
          ? transport.watchConnectionInfo()
          : Stream.value(null);
    });

/// The roster is shared by the Beariscope editor and Bearimetric scout picker.
final scoutRosterProvider = Provider<AsyncValue<List<Scout>>>((ref) {
  final grove = ref.watch(bearingsGroveProvider);
  final query = scoutRosterQuery(grove);
  return ref.watch(groveQueryProvider(query)).whenData((result) {
    if (result.updateRequired) result.requireComplete();
    return result.items;
  });
});

GroveQuery<Scout> scoutRosterQuery(Grove grove) =>
    grove.query<Scout>().orderBy(ScoutFields.name);

class _HiveGroveCache implements GroveCache {
  _HiveGroveCache(this.box, this.endpoint, this.subject);
  final Box<String> box;
  final String endpoint;
  final Future<String?> subject;
  final _fallback = MemoryGroveCache();
  Future<String?> _key(String key) async {
    final id = await subject;
    if (id == null) return null;
    final scoped = jsonEncode([endpoint, id, key]);
    final bytes = utf8.encode(scoped);
    // Hive stores the UTF-8 key size in one byte. Keep existing keys that fit.
    return bytes.length <= 255 ? scoped : 'sha256:${sha256.convert(bytes)}';
  }

  @override
  Future<Json?> read(String key) async {
    final scoped = await _key(key);
    if (scoped == null) return _fallback.read(key);
    final value = box.get(scoped);
    return value == null ? null : jsonDecode(value) as Json;
  }

  @override
  Future<void> write(String key, Json value) async {
    final scoped = await _key(key);
    if (scoped == null) return _fallback.write(key, value);
    await box.put(scoped, jsonEncode(value));
  }

  @override
  Future<void> remove(String key) async {
    final scoped = await _key(key);
    if (scoped == null) return _fallback.remove(key);
    await box.delete(scoped);
  }

  @override
  Future<void> clearQuerySnapshots() async {
    final keys = box.keys.whereType<String>().where(_isQuerySnapshot).toList();
    await box.deleteAll(keys);
    await _fallback.clearQuerySnapshots();
  }

  bool _isQuerySnapshot(String key) {
    try {
      if (key.startsWith('sha256:')) {
        // Long keys hide the entry type. QuerySnapshot has only these fields.
        final value = jsonDecode(box.get(key) ?? 'null');
        return value is Map &&
            (value['_download'] == 'competition' ||
                (value.length == 2 &&
                    value['records'] is List &&
                    value['revision'] is int));
      }
      return switch (jsonDecode(key)) {
        [String _, String _, String entry] =>
          entry.startsWith('query:') || entry.startsWith('competition:'),
        _ => false,
      };
    } on FormatException {
      return false;
    }
  }
}
