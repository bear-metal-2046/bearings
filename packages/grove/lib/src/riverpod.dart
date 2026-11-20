import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;

import 'client.dart';
import 'query.dart';

final groveProvider = Provider<Grove>(
  (ref) => throw StateError(
    'Override groveProvider with the application Grove instance',
  ),
);

final _providers =
    <GroveQuery<dynamic>, StreamProvider<QueryResult<dynamic>>>{};

/// One generic adapter; Grove owns data and subscriptions, Riverpod observes.
StreamProvider<QueryResult<T>> groveQueryProvider<T>(GroveQuery<T> query) {
  final existing = _providers[query];
  if (existing != null) return existing as StreamProvider<QueryResult<T>>;
  var containers = 0;
  late StreamProvider<QueryResult<T>> provider;
  provider = StreamProvider.autoDispose<QueryResult<T>>((ref) {
    containers++;
    ref.onDispose(() {
      containers--;
      if (containers == 0 && identical(_providers[query], provider))
        _providers.remove(query);
    });
    return query.grove.watch(query);
  });
  _providers[query] = provider;
  return provider;
}

extension AsyncValueComposition<T> on AsyncValue<T> {
  /// Compose dependent sources without restarting their loading state.
  AsyncValue<R> flatMap<R>(AsyncValue<R> Function(T) transform) {
    try {
      return when(
        data: transform,
        error: AsyncError<R>.new,
        loading: AsyncLoading<R>.new,
      );
    } catch (error, stackTrace) {
      return AsyncError(error, stackTrace);
    }
  }
}

/// Wait for a live value during an imperative action, such as startup.
Future<T> waitForValue<T>(
  ProviderContainer container,
  ProviderListenable<AsyncValue<T>> provider,
) async {
  final ready = Completer<T>();
  final subscription = container.listen(provider, (_, value) {
    if (ready.isCompleted) return;
    value.whenOrNull(
      skipLoadingOnReload: true,
      data: ready.complete,
      error: ready.completeError,
    );
  }, fireImmediately: true);
  try {
    return await ready.future;
  } finally {
    subscription.close();
  }
}
