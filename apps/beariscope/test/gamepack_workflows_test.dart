import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beariscope/pages/export/gamepack_export.dart';
import 'package:beariscope/pages/gamepacks/observation_page.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/picklists/picklist_team_quick_view_sheet.dart';
import 'package:beariscope/pages/pits_scouting/pits_scouting_home_page.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_page.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_sorting.dart';
import 'package:beariscope/pages/up_next/match_preview_page.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/match_preview_layout_provider.dart';
import 'package:beariscope/widgets/team_card.dart';
import 'package:core/core.dart';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/grove.dart';
import 'package:material_ui/material_ui.dart';
import 'package:services/providers/competition_provider.dart';
import 'package:services/providers/gamepack_analysis_provider.dart';
import 'package:services/providers/grove_provider.dart';
import 'package:services/providers/permissions_provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:ui/widgets/bearings_modal.dart';

class _RebuiltEvent extends CurrentEvent {
  @override
  String build() => '2026marea';
}

class _PreviewLayout extends MatchPreviewLayoutNotifier {
  @override
  MatchPreviewLayout build() => MatchPreviewLayout.horizontal;
}

void main() {
  testWidgets(
    '2026 pit, observations, audit, match preview, picklist and export use the assigned pack',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 1350);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = bearingsEntityRegistry();
      final grove = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
      );
      const event = '2026marea';
      final release = GamePack(
        id: 'rebuilt-2026',
        document: jsonDecode(
          File('../../gamepacks/2026-rebuilt.json').readAsStringSync(),
        ) as Json,
      );
      const team = CompetitionTeam(
        id: 'frc2877',
        number: 2877,
        nickname: 'Cybercats',
        location: CompetitionLocation(),
      );
      await grove.create(release);
      await grove.create(
        const EventGamePack(id: event, gamePack: EntityRef('rebuilt-2026')),
      );

      Future<void> mount(Widget child) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bearingsGroveProvider.overrideWithValue(grove),
              currentEventProvider.overrideWith(_RebuiltEvent.new),
              matchPreviewLayoutProvider.overrideWith(_PreviewLayout.new),
              competitionTeamsProvider(event)
                  .overrideWithValue(AsyncData(QueryResult([team]))),
              permissionCheckerProvider.overrideWithValue(
                const PermissionChecker(
                  permissions: {
                    gamePackReadPermission,
                    gamePackObservationReadPermission,
                    gamePackSubmitPermission,
                    gamePackCorrectPermission,
                  },
                ),
              ),
            ],
            child: MainViewController(
              openDrawer: () {},
              isDesktop: true,
              child: MaterialApp(home: child),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(String text) async {
        final finder = find.text(text).hitTestable();
        expect(finder, findsWidgets);
        await tester.tap(finder.first);
        await tester.pumpAndSettle();
      }

      Finder input(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );

      Future<void> submit(String action) async {
        await tap(action);
        await grove.synchronize();
        await tester.pumpAndSettle();
      }

      try {
        await mount(const PitsScoutingHomePage());
        await tap('List');
        await tap('Cybercats');
        expect(find.byType(GamePackObservationPage), findsOneWidget);
        await tester.enterText(input('Hopper Size (Max. Fuel Quantity)'), '20');
        await submit('Save observation');
        expect(find.text('Scouted'), findsOneWidget);
        final pit = (await grove.query<GamePackObservation>().many()).single;
        expect(pit.answers['pit_hopper_size'], 20);

        await mount(
          const TeamDetailsPage(teamName: 'Cybercats', teamNumber: 2877),
        );
        expect(find.text('Details'), findsOneWidget);
        expect(find.text('Averages'), findsNothing);
        expect(find.text('Capabilities'), findsNothing);
        await tap('Observations');
        await tap('Add observation');
        await tester.enterText(input('Notes'), 'New intake is working');
        await submit('Save observation');
        await tap('Observations · frc2877');
        expect(find.text('New intake is working'), findsOneWidget);

        await mount(const ScoutAuditPage());
        expect(find.text('Coverage'), findsOneWidget);
        expect(find.text('Results'), findsNothing);
        await tap('Observations');
        await tap('Pit scouting · frc2877');
        await tap('Correct');
        await tester.enterText(input('Hopper Size (Max. Fuel Quantity)'), '25');
        final reason = input('Correction reason');
        final scroller = find
            .descendant(
              of: find.byType(GamePackObservationPage),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          reason,
          400,
          scrollable: scroller,
          maxScrolls: 30,
        );
        await tester.enterText(reason, 'Measured again');
        await submit('Save correction');
        final rows = await grove.query<GamePackObservation>().many();
        final correction = rows.singleWhere(
          (row) => row.supersedes?.id == pit.id,
        );
        expect(correction.answers['pit_hopper_size'], 25);
        expect(correction.reason, 'Measured again');
        expect(
          rows
              .singleWhere((row) => row.id == pit.id)
              .answers['pit_hopper_size'],
          20,
        );

        final fixture = (jsonDecode(
          File(
            '../../packages/services/test/fixtures/tba_2026marea_matches.json',
          ).readAsStringSync(),
        ) as List).cast<Json>().first;
        final match = TbaApi.match(fixture);
        final timestamp = DateTime.utc(2026, 3, 28);
        final revision = TbaMatchRevision(
          id: '${match.id}-archive',
          event: const EntityRef(event),
          match: EntityRef(match.id),
          observedAt: timestamp,
          sequence: 1,
          payload: fixture,
        );
        await grove.create(match);
        await grove.create(revision);
        await grove.create(
          GamePackObservation(
            id: 'real-match-capture',
            event: const EntityRef(event),
            match: EntityRef(match.id),
            team: EntityRef(team.id),
            station: 0,
            gamePack: EntityRef(release.id),
            capturedAt: timestamp,
            form: 'match',
            answers: {
              'auto_fuel_scored': 10,
              'tele_fuel_scored': 20,
              'tele_lost_comms': true,
            },
          ),
        );

        tester.view.physicalSize = const Size(1250, 1350);
        await mount(MatchPreviewPage(matchKey: match.id));
        expect(find.byTooltip('Match analysis'), findsNothing);
        expect(find.byType(TeamCard), findsWidgets);
        await tester.tap(find.byTooltip('Add observation'));
        await tester.pumpAndSettle();
        await tap('Team 2877');
        await tester.enterText(input('Notes'), 'Push the far-side lane');
        await submit('Save observation');
        final observations = await grove.query<GamePackObservation>().many();
        final teamObservations = observations
            .where((row) => row.formId == 'observation')
            .toList();
        expect(teamObservations, hasLength(2));
        final matchObservation = teamObservations.singleWhere(
          (row) => row.match?.id == match.id,
        );
        expect(matchObservation.team?.id, team.id);
        expect(matchObservation.station, isNull);
        expect(
          matchObservation.answers['observation_note'],
          'Push the far-side lane',
        );
        await tap('Observations · ${match.id} · frc2877');
        expect(find.text('Push the far-side lane'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        unawaited(
          BearingsModal.show<bool>(
            tester.element(find.byType(Scaffold).last),
            builder: (_) =>
                PicklistTeamQuickViewSheet(team: Team.fromCompetition(team)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Scoring'), findsOneWidget);
        final trend = tester.widget<SfCartesianChart>(
          find.byType(SfCartesianChart),
        );
        expect(trend.series.map((series) => series.name), [
          'Auto',
          'Tele',
          'Total',
        ]);
        expect(trend.annotations, hasLength(1));
        await tester.tap(find.byTooltip('Close').hitTestable().last);
        await tester.pumpAndSettle();

        await mount(
          const TeamDetailsPage(teamName: 'Cybercats', teamNumber: 2877),
        );
        await tap('Observations');
        await tap('Observations · ${match.id} · frc2877');
        expect(find.text('Push the far-side lane'), findsOneWidget);

        final analysis = GamePackEventAnalysis(
          event: event,
          capture: release,
          analysis: release,
          observations: observations,
          revisions: [revision],
        );
        final picklistMetric = teamSortMetrics(
          analysis,
        ).singleWhere((binding) => binding.label == 'Total Avg Fuel / Match');
        final teams = [
          Team(key: 'frc6201', number: 6201, name: 'Partner', website: null),
          Team.fromCompetition(team),
        ];
        final sortedValues = sortTeamsByMetric(
          teams,
          analysis,
          picklistMetric,
          ascending: false,
        );
        expect(teams.map((item) => item.key), [team.id, 'frc6201']);
        expect(sortedValues[team.id]?.data, 80);

        final workbook = Excel.decodeBytes(
          buildGamePackWorkbook(analysis: analysis, includeScout: false),
        );
        final observationSheet = workbook.tables['Observations']!.rows;
        final observationHeadings = observationSheet.first
            .map((cell) => cell?.value.toString())
            .toList();
        final matchIndex = observationHeadings.indexOf('Match');
        expect(observationSheet, hasLength(3));
        expect(
          observationSheet
              .skip(1)
              .map((row) => row[matchIndex]?.value?.toString()),
          unorderedEquals([null, match.id]),
        );
        final normalized = workbook.tables['Normalized Match Data']!.rows;
        final headings = normalized.first
            .map((cell) => cell?.value.toString())
            .toList();
        expect(normalized, hasLength(2));
        expect(
          normalized.last[headings.indexOf('Report ID')]?.value.toString(),
          'real-match-capture',
        );
        expect(
          double.parse(
            normalized.last[headings.indexOf('Auto Avg Fuel')]!.value
                .toString(),
          ),
          21,
        );
        expect(
          double.parse(
            normalized.last[headings.indexOf('Tele Avg Fuel')]!.value
                .toString(),
          ),
          59,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(grove.close());
        await tester.pump();
      }
    },
  );
}
