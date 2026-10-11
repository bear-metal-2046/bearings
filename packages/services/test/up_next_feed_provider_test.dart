import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/services.dart';

class _NoNexusFailingScheduleClient implements HoneycombClient {
  @override
  Future<T> get<T>(
    String endpoint, {
    CachePolicy cachePolicy = CachePolicy.networkFirst,
    Map<String, dynamic>? queryParams,
    Duration? cacheTtl,
  }) async {
    if (endpoint == '/events') {
      return {'key': '2026wabel', 'matches': [], 'nowQueuing': null} as T;
    }
    throw const HoneycombApiException(502, 'API Error: 502 - Bad Gateway');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a failing schedule surfaces as an error instead of loading', () async {
    final container = ProviderContainer(
      overrides: [
        honeycombClientProvider.overrideWithValue(
          _NoNexusFailingScheduleClient(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final feed = upNextFeedProvider('2026wabel');
    container.listen(feed, (_, _) {});

    await expectLater(
      container.read(feed.future).timeout(const Duration(seconds: 2)),
      throwsA(isA<HoneycombApiException>()),
    );
    expect(container.read(feed).isLoading, isFalse);
  });
}
