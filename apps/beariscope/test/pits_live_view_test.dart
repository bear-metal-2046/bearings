import 'dart:async';

import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/pits_scouting/pits_scouting_home_page.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/grove_provider.dart';

class _Event extends CurrentEvent {
  @override
  String build() => '2026test';
}

class _Transport implements GroveTransport {
  _Transport(this.first);
  final Map<String, QuerySnapshot> first;
  final subscriptions = <String, int>{};
  final listeners = <String, Set<StreamController<QuerySnapshot>>>{};

  @override
  Stream<QuerySnapshot> watch(QueryDescription query) {
    final type = query.type;
    final current = listeners.putIfAbsent(type, () => {});
    late final StreamController<QuerySnapshot> controller;
    controller = StreamController<QuerySnapshot>(
      onListen: () {
        subscriptions.update(type, (value) => value + 1, ifAbsent: () => 1);
        current.add(controller);
        controller.add(first[type] ?? QuerySnapshot([]));
      },
      onCancel: () {
        current.remove(controller);
      },
    );
    return controller.stream;
  }

  void emit(String type, QuerySnapshot next) {
    first[type] = next;
    for (final controller in listeners[type] ?? const {}) {
      controller.add(next);
    }
  }

  void disconnect() {
    for (final current in listeners.values) {
      for (final controller in current) {
        controller.addError(const GroveOffline());
      }
    }
  }

  @override
  Future<QuerySnapshot> fetch(QueryDescription query) async =>
      first[query.type] ?? QuerySnapshot([]);

  @override
  Future<EntityRecord> mutate(EntityMutation mutation) async =>
      throw const GroveOffline();

  @override
  Future<void> close() async {}
}

QuerySnapshot _snapshot<T>(
  EntityDescriptor<T> descriptor,
  T value, {
  int revision = 1,
}) {
  final data = descriptor.encode(value);
  return QuerySnapshot([
    EntityRecord(
      type: descriptor.type,
      id: data['id'] as String,
      version: descriptor.version,
      revision: revision,
      data: data,
    ),
  ], revision: revision);
}

void main() {
  testWidgets('Pits keeps its viewport across snapshots and reconnects', (
    tester,
  ) async {
    final event = _snapshot(
      competitionEventEntity,
      TbaApi.event({'key': '2026test', 'first_event_code': 'TEST'}),
    );
    final layout = _snapshot(
      pitLayoutEntity,
      const PitLayout(
        id: '2026test',
        map: PitMapBackground(size: PitMapPoint(x: 100, y: 200)),
      ),
    );
    final transport = _Transport({
      competitionEventEntity.type: event,
      pitLayoutEntity.type: layout,
    });
    final grove = Grove(
      registry: bearingsEntityRegistry(),
      transport: transport,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bearingsGroveProvider.overrideWithValue(grove),
          currentEventProvider.overrideWith(_Event.new),
        ],
        child: MaterialApp(
          home: MainViewController(
            isDesktop: true,
            openDrawer: () {},
            child: const PitsScoutingHomePage(),
          ),
        ),
      ),
    );

    final map = find.byType(InteractiveViewer);
    Future<void> pumpUpdates({bool expectMap = true}) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (expectMap) expect(map, findsOneWidget);
      }
    }

    await pumpUpdates(expectMap: false);
    final viewer = tester.widget<InteractiveViewer>(map);
    final controller = viewer.transformationController!;
    final zoomed = Matrix4.identity()
      ..translateByDouble(50, 20, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
    controller.value = zoomed.clone();

    void expectViewportUnchanged() {
      final current = tester.widget<InteractiveViewer>(map);
      expect(current.transformationController, same(controller));
      expect(current.transformationController!.value.storage, zoomed.storage);
      expect(transport.subscriptions[pitLayoutEntity.type], 1);
    }

    transport.emit(pitLayoutEntity.type, layout);
    await pumpUpdates();
    expectViewportUnchanged();

    await grove.stageCreate(
      GamePackObservation(
        id: 'unrelated-match',
        release: const EntityRef('pack'),
        event: const EntityRef('2026test'),
        capturedAt: DateTime.utc(2026),
        answers: const {'points': 4},
      ),
    );
    await pumpUpdates();
    expectViewportUnchanged();

    transport.disconnect();
    await pumpUpdates();
    expect(find.text('Showing cached data'), findsNothing);
    expectViewportUnchanged();

    transport.emit(competitionEventEntity.type, event);
    transport.emit(pitLayoutEntity.type, layout);
    await pumpUpdates();
    expectViewportUnchanged();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await grove.close();
  });
}
