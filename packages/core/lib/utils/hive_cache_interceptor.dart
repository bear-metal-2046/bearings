import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

/// Controls how the cache is consulted for a GET request.
///
/// Most policies are offline-safe by preferring cached data when available.
/// `networkOnly` intentionally bypasses cache and fails while offline.
enum CachePolicy {
  /// Return cached data if it is fresh (< 1 hour old). If stale or absent,
  /// fetch from the network. If offline, return any cached data regardless
  /// of age.
  cacheFirst,

  /// Always attempt a network fetch. Fall back to any cached data (regardless
  /// of age) on any network error or when offline.
  ///
  /// This is the default policy
  networkFirst,

  /// Always attempt a network fetch. Do not fall back to cache on transient
  /// network errors and fail immediately while offline.
  networkOnly,

  /// Return cached data only. Never perform a network fetch. Rejects the
  /// request if no cached data exists.
  cacheOnly,
}

class HiveCacheInterceptor extends Interceptor {
  final Box<dynamic> box;
  final Duration defaultTtl;

  HiveCacheInterceptor(this.box, {Duration? defaultTtl})
    : defaultTtl = defaultTtl ?? const Duration(hours: 1);

  static const _kFromCache = '__hive_from_cache__';
  static const _kStoredAtEpochMs = 'storedAtEpochMs';
  static const _kLegacyTimestamp = 'timestamp';

  static String cacheKeyForUri(Uri uri) {
    final sortedKeys = uri.queryParametersAll.keys.toList()..sort();
    final segments = <String>[];

    for (final key in sortedKeys) {
      final values = List<String>.from(uri.queryParametersAll[key] ?? const [])
        ..sort();
      if (values.isEmpty) {
        segments.add(Uri.encodeQueryComponent(key));
        continue;
      }
      for (final value in values) {
        segments.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
        );
      }
    }

    final base = uri.replace(query: '').toString();
    final query = segments.join('&');
    return query.isEmpty ? base : '$base?$query';
  }

  static String legacyCacheKeyForUri(Uri uri) => uri.toString();

  static List<String> cacheKeysForUri(Uri uri) {
    final canonical = cacheKeyForUri(uri);
    final legacy = legacyCacheKeyForUri(uri);
    if (canonical == legacy) return <String>[canonical];
    return <String>[canonical, legacy];
  }

  CachePolicy _readPolicy(RequestOptions options) {
    final raw = options.extra['cachePolicy'];
    if (raw is CachePolicy) return raw;
    if (raw is String) {
      return CachePolicy.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => CachePolicy.networkFirst,
      );
    }
    return CachePolicy.networkFirst;
  }

  Duration _readTtl(RequestOptions options) {
    final raw = options.extra['cacheTtl'];
    if (raw is Duration) return raw;
    if (raw is int && raw > 0) {
      return Duration(milliseconds: raw);
    }
    return defaultTtl;
  }

  _CacheLookup _loadCache(Uri uri) {
    final keys = cacheKeysForUri(uri);

    for (final key in keys) {
      final entry = _CacheEntry.fromBoxValue(box.get(key));
      if (entry != null) {
        return _CacheLookup(entry: entry);
      }
    }

    return const _CacheLookup(entry: null);
  }

  Response<dynamic> _buildCacheResponse(
    RequestOptions options,
    _CacheEntry entry,
  ) {
    options.extra[_kFromCache] = true;
    return Response<dynamic>(
      requestOptions: options,
      data: _deepClone(entry.data),
      statusCode: 200,
      statusMessage: 'From Cache',
    );
  }

  void _rejectCacheMiss(
    RequestOptions options,
    RequestInterceptorHandler handler, {
    required String message,
  }) {
    handler.reject(
      DioException(
        requestOptions: options,
        error: message,
        type: DioExceptionType.connectionError,
      ),
    );
  }

  bool _isNetworkFailure(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.badCertificate ||
        error.type == DioExceptionType.unknown;
  }

  dynamic _deepClone(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>(
        (key, nestedValue) => MapEntry(key.toString(), _deepClone(nestedValue)),
      );
    }
    if (value is List) {
      return value.map(_deepClone).toList(growable: false);
    }
    return value;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method != 'GET') {
      return handler.next(options);
    }

    final policy = _readPolicy(options);
    final ttl = _readTtl(options);
    final isOffline = options.extra['isOffline'] == true;
    final lookup = _loadCache(options.uri);
    final entry = lookup.entry;
    final cacheHit = entry != null;

    switch (policy) {
      case CachePolicy.cacheOnly:
        if (cacheHit) {
          return handler.resolve(_buildCacheResponse(options, entry));
        }
        return _rejectCacheMiss(
          options,
          handler,
          message: 'Cache miss for ${options.uri}',
        );

      case CachePolicy.networkFirst:
        if (isOffline) {
          if (cacheHit) {
            return handler.resolve(_buildCacheResponse(options, entry));
          }
          return _rejectCacheMiss(
            options,
            handler,
            message: 'Offline and no cached data for ${options.uri}',
          );
        }
        return handler.next(options);

      case CachePolicy.networkOnly:
        if (isOffline) {
          return _rejectCacheMiss(
            options,
            handler,
            message: 'Offline and policy is networkOnly for ${options.uri}',
          );
        }
        return handler.next(options);

      case CachePolicy.cacheFirst:
        if (cacheHit) {
          if (entry.isFresh(ttl) || isOffline) {
            return handler.resolve(_buildCacheResponse(options, entry));
          }
        }
        if (isOffline) {
          return _rejectCacheMiss(
            options,
            handler,
            message: 'Offline and no cached data for ${options.uri}',
          );
        }
        return handler.next(options);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final request = err.requestOptions;
    if (request.method != 'GET') return handler.next(err);

    final policy = _readPolicy(request);

    if (policy == CachePolicy.networkOnly || policy == CachePolicy.cacheOnly) {
      return handler.next(err);
    }

    if (!_isNetworkFailure(err)) return handler.next(err);

    final lookup = _loadCache(request.uri);
    final entry = lookup.entry;
    if (entry == null) return handler.next(err);

    return handler.resolve(_buildCacheResponse(request, entry));
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final fromCache = response.requestOptions.extra[_kFromCache] == true;

    if (!fromCache &&
        response.requestOptions.method == 'GET' &&
        (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300)) {
      final uri = response.requestOptions.uri;
      final key = cacheKeyForUri(uri);
      final legacyKey = legacyCacheKeyForUri(uri);

      box.put(key, <String, dynamic>{
        'data': _deepClone(response.data),
        _kStoredAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      });

      if (legacyKey != key) {
        box.delete(legacyKey);
      }
    }

    handler.next(response);
  }
}

class _CacheLookup {
  final _CacheEntry? entry;

  const _CacheLookup({required this.entry});
}

class _CacheEntry {
  final dynamic data;
  final int storedAtEpochMs;

  const _CacheEntry({required this.data, required this.storedAtEpochMs});

  bool isFresh(Duration ttl) {
    if (storedAtEpochMs <= 0) return false;
    final age = DateTime.now().millisecondsSinceEpoch - storedAtEpochMs;
    return age <= ttl.inMilliseconds;
  }

  static _CacheEntry? fromBoxValue(dynamic raw) {
    if (raw is! Map) return null;
    if (!raw.containsKey('data')) return null;

    final timestamp = _parseStoredAt(raw);
    return _CacheEntry(data: raw['data'], storedAtEpochMs: timestamp);
  }

  static int _parseStoredAt(Map<dynamic, dynamic> raw) {
    final candidate =
        raw[HiveCacheInterceptor._kStoredAtEpochMs] ??
        raw[HiveCacheInterceptor._kLegacyTimestamp];

    if (candidate is int) return candidate;
    if (candidate is DateTime) return candidate.millisecondsSinceEpoch;
    if (candidate is String) {
      final parsed = int.tryParse(candidate);
      if (parsed != null) return parsed;
    }

    return 0;
  }
}
