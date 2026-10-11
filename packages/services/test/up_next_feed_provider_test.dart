import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/services.dart';

class _FakeClient implements HoneycombClient {
  _FakeClient({this.event = const {}, this.schedule});

  final Map<String, dynamic> event;
  final List<dynamic>? schedule;
  var nexusRequests = 0;

  @override
  Future<T> get<T>(
    String endpoint, {
    CachePolicy cachePolicy = CachePolicy.networkFirst,
    Map<String, dynamic>? queryParams,
    Duration? cacheTtl,
  }) async {
    if (endpoint == '/events' && queryParams?['enrich'] == 'false') {
      return {'key': '2026wabel', ...event} as T;
    }
    if (endpoint == '/events') {
      nexusRequests++;
      return {'key': '2026wabel', 'matches': [], 'nowQueuing': null} as T;
    }
    if (schedule != null) return schedule as T;
    throw const HoneycombApiException(502, 'API Error: 502 - Bad Gateway');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeClient client) {
  final container = ProviderContainer(
    overrides: [honeycombClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a failing schedule surfaces as an error instead of loading', () async {
    final container = _container(_FakeClient());
    final feed = upNextFeedProvider('2026wabel');
    container.listen(feed, (_, _) {});

    await expectLater(
      container.read(feed.future).timeout(const Duration(seconds: 2)),
      throwsA(isA<HoneycombApiException>()),
    );
    expect(container.read(feed).isLoading, isFalse);
  });

  test('skips Nexus and shows the schedule after the event', () async {
    final client = _FakeClient(
      event: {'endDate': '2026-03-08'},
      schedule: [
        {'key': '2026wabel_qm1', 'event_key': '2026wabel', 'comp_level': 'qm'},
      ],
    );
    final container = _container(client);
    final feed = upNextFeedProvider('2026wabel');
    container.listen(feed, (_, _) {});

    final result = await container.read(feed.future);
    expect(result.eventOver, isTrue);
    expect(result.matches.map((match) => match.key), ['2026wabel_qm1']);
    expect(client.nexusRequests, 0);
  });
}
