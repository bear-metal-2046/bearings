import 'dart:async';

import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/processed_scouting_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
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
  test('scouting normalization reads the Grove match breakdown', () async {
    final registry = bearingsEntityRegistry();
    final grove = Grove(
      registry: registry,
      transport: MemoryGroveTransport(registry),
    );
    addTearDown(grove.close);
    await grove.create(
      const CompetitionMatch(
        id: '2026test_qm1',
        season: 2026,
        event: EntityRef('2026test'),
        level: 'qm',
        setNumber: 1,
        matchNumber: 1,
        practice: false,
        red: CompetitionAlliance(
          teams: [EntityRef('frc2046')],
          gameBreakdown: {
            'hubScore': {'autoCount': 20, 'teleopFuelCount': '30'},
          },
        ),
      ),
    );
    await grove.create(
      ScoutingReport.fromMatch(
        MatchFormData.blank(
              eventKey: '2026test',
              matchNumber: 1,
              pos: 0,
              season: 2026,
              configVersion: 1,
              teamNumber: 2046,
            )
            .copyWithField(kSectionAuto, kAutoFuelScored, 10)
            .copyWithField(kSectionTele, kTeleFuelScored, 10),
      ),
    );
    final container = ProviderContainer.test(
      overrides: [
        currentEventProvider.overrideWith(_CurrentEvent.new),
        bearingsGroveProvider.overrideWithValue(grove),
      ],
    );
    final bundle = await waitForValue(container, processedScoutingProvider);
    expect(bundle.processedDocs.single.autoFuelScalar, 2);
    expect(bundle.processedDocs.single.teleFuelScalar, 3);
  });

  test(
    'Beariscope observes live Grove scouting and permission changes',
    () async {
      final registry = bearingsEntityRegistry();
      final grove = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
      );
      addTearDown(grove.close);
      await grove.create(GroveAccess('actor', ['scouting.report.read']));
      final container = ProviderContainer(
        overrides: [
          currentEventProvider.overrideWith(_CurrentEvent.new),
          bearingsGroveProvider.overrideWithValue(grove),
          groveSubjectProvider.overrideWith((ref) async => 'actor'),
        ],
      );
      addTearDown(container.dispose);
      final reportChanges = StreamController<List<ScoutingReport>>.broadcast();
      final accessChanges = StreamController<PermissionChecker?>.broadcast();
      addTearDown(() async {
        await reportChanges.close();
        await accessChanges.close();
      });
      final scouting = container.listen(
        groveQueryProvider(container.read(scoutingQueryProvider)),
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
        (await container.read(
          groveQueryProvider(container.read(scoutingQueryProvider)).future,
        )).items,
        isEmpty,
      );
      expect(
        (await waitForValue(
          container,
          groveAccessProvider,
        ))!.items.single.permissions,
        {'scouting.report.read'},
      );

      permissionsDuringUpdates.clear();
      final report = ScoutingReport.fromMatch(
        MatchFormData.blank(
          eventKey: '2026test',
          matchNumber: 1,
          pos: 0,
          season: 2026,
          configVersion: 1,
        ),
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
