import 'dart:async';
import 'dart:io';

import 'package:beariscope/providers/current_event_provider.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:beariscope/widgets/server_connection_button.dart';
import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/connectivity_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ui/widgets/bearings_modal.dart';

class _CurrentEvent extends CurrentEvent {
  @override
  String build() => '2026test';
}

class _ObservationCount extends ConsumerWidget {
  const _ObservationCount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref
        .watch(
          gamePackObservationHistoryProvider(ref.watch(currentEventProvider)),
        )
        .whenData((result) => result.requireAvailable().items);
    return Text('Observations: ${reports.asData?.value.length ?? 'loading'}');
  }
}

void main() {
  testWidgets('server icon opens live connection details', (tester) async {
    final connection = StreamController<GroveConnectionInfo>.broadcast(
      sync: true,
    );
    addTearDown(connection.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          honeycombConnectionProvider.overrideWith(
            (ref) => connection.stream.map((details) => details.state),
          ),
          honeycombConnectionInfoProvider.overrideWith(
            (ref) => connection.stream,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: const Scaffold(body: ServerConnectionButton()),
        ),
      ),
    );
    final button = find.byTooltip('Connecting…');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();

    final modal = find.byType(BearingsModal);
    expect(modal, findsOneWidget);
    expect(find.text('Server connection'), findsOneWidget);
    final endpoint = const HoneycombEndpointSelection.azure().baseUrl;
    expect(find.text(endpoint), findsOneWidget);
    expect(find.text('No reply yet'), findsOneWidget);
    expect(find.text('None recorded'), findsOneWidget);

    const failure = GroveOffline('The server closed the connection');
    final reply = DateTime(2026, 11, 16, 13, 30);
    connection.add(
      GroveConnectionInfo(
        state: GroveConnectionState.disconnected,
        lastReplyAt: reply,
        lastFailure: failure,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text(failure.message), findsOneWidget);
    final context = tester.element(modal);
    final formattedReply =
        '${MaterialLocalizations.of(context).formatShortDate(reply)} · '
        '${TimeOfDay.fromDateTime(reply).format(context)}';
    expect(find.text(formattedReply), findsOneWidget);

    connection.add(GroveConnectionInfo(state: GroveConnectionState.connected));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a Honeycomb commit rebuilds a Beariscope scouting widget', (
    tester,
  ) async {
    final registry = bearingsEntityRegistry();
    final store = EntityStore(sqlite3.openInMemory(), registry);
    addTearDown(store.close);
    final service = EntityService(
      store: store,
      bootstrapSubject: 'widget-test',
      authenticate: (token) async => AuthenticatedActor(
        token,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );
    final server = (await tester.runAsync(
      () => serve(service.handler, InternetAddress.loopbackIPv4, 0),
    ))!;
    addTearDown(() => server.close(force: true));
    final grove = (await tester.runAsync(
      () async => Grove(
        registry: registry,
        transport: WebSocketGroveTransport(
          uri: Uri.parse('ws://127.0.0.1:${server.port}'),
          accessToken: () async => 'widget-test',
        ),
      ),
    ))!;
    addTearDown(grove.close);
    final container = ProviderContainer(
      overrides: [
        currentEventProvider.overrideWith(_CurrentEvent.new),
        bearingsGroveProvider.overrideWithValue(grove),
      ],
    );
    try {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: _ObservationCount(),
            ),
          ),
        );
        await waitForValue(
          container,
          gamePackObservationHistoryProvider('2026test'),
        );
        await tester.pump();
        expect(find.text('Observations: 0'), findsOneWidget);
        final observation = GamePackObservation(
          id: 'server-observation',
          release: const EntityRef('pack'),
          event: const EntityRef('2026test'),
          capturedAt: DateTime.utc(2026),
          answers: const {'points': 4},
        );
        store.mutate(
          EntityMutation(
            mutationId: 'server-create',
            type: gamePackObservationEntity.type,
            id: observation.id,
            version: gamePackObservationEntity.version,
            kind: MutationKind.create,
            data: gamePackObservationEntity.encode(observation),
          ),
          'server',
        );
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.text('Observations: 1').evaluate().isNotEmpty) break;
        }
        expect(find.text('Observations: 1'), findsOneWidget);
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        container.dispose();
        await grove.close();
        await service.disconnectClients();
        await server.close(force: true);
      });
    }
  });
}
