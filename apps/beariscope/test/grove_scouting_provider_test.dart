import 'dart:async';

import 'package:beariscope/providers/current_event_provider.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';

class _CurrentEvent extends CurrentEvent {
  @override
  String build() => '2026test';
}

void main() {
  test(
    'Beariscope observes live Grove scouting and permission changes',
    () async {
      final registry = bearingsEntityRegistry();
      final grove = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
      );
      addTearDown(grove.close);
      await grove.create(
        GroveAccess('actor', [gamePackObservationReadPermission]),
      );
      final container = ProviderContainer(
        overrides: [
          currentEventProvider.overrideWith(_CurrentEvent.new),
          bearingsGroveProvider.overrideWithValue(grove),
          groveSubjectProvider.overrideWith((ref) async => 'actor'),
        ],
      );
      addTearDown(container.dispose);
      final reportChanges =
          StreamController<List<GamePackObservation>>.broadcast();
      final accessChanges = StreamController<PermissionChecker?>.broadcast();
      addTearDown(() async {
        await reportChanges.close();
        await accessChanges.close();
      });
      final scouting = container.listen(
        gamePackObservationHistoryProvider('2026test'),
        (_, state) {
          if (state.asData case final value?)
            reportChanges.add(value.value.items);
        },
      );
      final permissionsDuringUpdates = <PermissionChecker?>[];
      final access = container.listen(permissionCheckerProvider, (_, value) {
        permissionsDuringUpdates.add(value);
        accessChanges.add(value);
      });
      addTearDown(() {
        scouting.close();
        access.close();
      });
      expect(
        (await waitForValue(
          container,
          gamePackObservationHistoryProvider('2026test'),
        )).items,
        isEmpty,
      );
      expect(
        (await waitForValue(
          container,
          groveAccessProvider,
        ))!.items.single.permissions,
        {gamePackObservationReadPermission},
      );

      permissionsDuringUpdates.clear();
      final report = GamePackObservation(
        id: 'new-observation',
        gamePack: const EntityRef('pack'),
        event: const EntityRef('2026test'),
        capturedAt: DateTime.utc(2026),
        answers: const {},
      );
      final received = reportChanges.stream.firstWhere(
        (reports) => reports.isNotEmpty,
      );
      await grove.create(report);
      expect(
        (await received.timeout(const Duration(seconds: 3))).single.id,
        report.id,
      );

      final revoked = accessChanges.stream.firstWhere(
        (access) => access != null && access.permissions.isEmpty,
      );
      await grove.update<GroveAccess>('actor', (_) => GroveAccess('actor', []));
      expect(
        (await revoked.timeout(const Duration(seconds: 3)))!.permissions,
        isEmpty,
      );
      expect(permissionsDuringUpdates, isNot(contains(null)));
    },
  );
}
