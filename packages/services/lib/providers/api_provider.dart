import 'package:core/utils/hive_cache_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:services/providers/auth_provider.dart';
import 'package:services/providers/connectivity_provider.dart';

export 'package:core/utils/hive_cache_interceptor.dart' show CachePolicy;

part 'api_provider.g.dart';

const _honeycombScope = 'ORLhqJbHiTfgdF3Q8hqIbmdwT1wTkkP7';

@riverpod
Dio dio(Ref ref) {
  final endpointSelection = ref.watch(honeycombEndpointPreferenceProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: endpointSelection.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  final Box<dynamic> cacheBox = Hive.box('api_cache');

  dio.interceptors.add(HiveCacheInterceptor(cacheBox));
  return dio;
}

@riverpod
HoneycombClient honeycombClient(Ref ref) {
  return HoneycombClient(ref);
}

class HoneycombClient {
  final Ref _ref;
  final Future<String?> Function()? tokenOverride;

  HoneycombClient(this._ref, {this.tokenOverride});

  Future<T> _performRequest<T>(
    String method,
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    CachePolicy cachePolicy = CachePolicy.networkFirst,
    Duration? cacheTtl,
  }) async {
    final dio = _ref.read(dioProvider);

    bool isOffline = !(await checkOnline(_ref));
    String? token;

    if (!isOffline) {
      try {
        if (tokenOverride != null) {
          token = await tokenOverride!();
        } else {
          final authService = await _ref.read(authProvider.future);
          token = await authService.getAccessToken([_honeycombScope]);
        }
      } on OfflineAuthException {
        isOffline = true;
      } catch (e) {
        rethrow;
      }
    }

    try {
      final response = await dio.request(
        endpoint,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          extra: {
            'cachePolicy': cachePolicy,
            'isOffline': isOffline,
            'cacheTtl': ?cacheTtl,
          },
        ),
      );

      return response.data as T;
    } on DioException catch (e) {
      if (e.response != null) {
        final responseData = e.response?.data;
        throw Exception(
          'API Error: ${e.response?.statusCode} - ${e.response?.statusMessage} ${responseData ?? ''}',
        );
      }
      throw Exception('Network Error: ${e.message}');
    }
  }

  Future<T> get<T>(
    String endpoint, {
    CachePolicy cachePolicy = CachePolicy.networkFirst,
    Map<String, dynamic>? queryParams,
    Duration? cacheTtl,
  }) async {
    return _performRequest<T>(
      'GET',
      endpoint,
      cachePolicy: cachePolicy,
      queryParameters: queryParams,
      cacheTtl: cacheTtl,
    );
  }

  void invalidateCache(String endpoint, {Map<String, dynamic>? queryParams}) {
    final dio = _ref.read(dioProvider);
    final requestOptions = Options(
      method: 'GET',
    ).compose(dio.options, endpoint, queryParameters: queryParams);
    final keys = HiveCacheInterceptor.cacheKeysForUri(requestOptions.uri);

    final box = Hive.box<dynamic>('api_cache');
    for (final key in keys) {
      box.delete(key);
    }
  }

  Future<void> clearCache() async {
    await Hive.box<dynamic>('api_cache').clear();
  }

  Future<T> post<T>(String endpoint, {required dynamic data}) async {
    return _performRequest<T>('POST', endpoint, data: data);
  }

  Future<T> put<T>(String endpoint, {required dynamic data}) async {
    return _performRequest<T>('PUT', endpoint, data: data);
  }

  Future<T> patch<T>(String endpoint, {required dynamic data}) async {
    return _performRequest<T>('PATCH', endpoint, data: data);
  }

  Future<void> delete(String endpoint, {dynamic data}) async {
    return _performRequest<void>('DELETE', endpoint, data: data);
  }
}

@Deprecated('Use get<Map<String, dynamic>>() in honeycombClientProvider.')
@riverpod
Future<Map<String, dynamic>> getData(
  Ref ref, {
  required String endpoint,
  bool forceRefresh = false,
}) async {
  return ref
      .watch(honeycombClientProvider)
      .get<Map<String, dynamic>>(
        endpoint,
        cachePolicy: forceRefresh
            ? CachePolicy.networkFirst
            : CachePolicy.cacheFirst,
      );
}

@Deprecated('Use get<List<dynamic>>() in honeycombClientProvider.')
@riverpod
Future<List<dynamic>> getListData(
  Ref ref, {
  required String endpoint,
  bool forceRefresh = false,
}) async {
  return ref
      .watch(honeycombClientProvider)
      .get<List<dynamic>>(
        endpoint,
        cachePolicy: forceRefresh
            ? CachePolicy.networkFirst
            : CachePolicy.cacheFirst,
      );
}
