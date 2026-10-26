import 'dart:async';

import 'package:beariscope/pages/flash_cards/flash_card_study_page.dart';
import 'package:beariscope/pages/flash_cards/flash_card_media.dart';
import 'package:beariscope/pages/flash_cards/flash_card_progress.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _teams = [
  {'team_number': 2046, 'nickname': 'Bear Metal'},
  {'team_number': 254, 'nickname': 'Cheesy Poofs'},
];

Future<ProviderContainer> _showPage(
  WidgetTester tester, {
  Future<List<Map<String, dynamic>>> Function(Ref)? loadTeams,
  Future<List<TeamMediaRecord>> Function(Ref)? loadMedia,
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      teamsProvider.overrideWith(
        loadTeams ??
            (ref) async {
              ref.watch(currentEventProvider);
              return _teams;
            },
      ),
      eventTeamMediaProvider.overrideWith(loadMedia ?? (_) async => []),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: MainViewController(
          isDesktop: true,
          openDrawer: () {},
          child: const FlashCardStudyPage(),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _openOptions(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Flash card options'));
  await tester.pumpAndSettle();
}

Future<void> _closeOptions(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close options'));
  await tester.pumpAndSettle();
}

TeamMediaRecord _media({
  String teamKey = 'frc2046',
  String type = 'imgur',
  String? url,
  bool preferred = false,
}) => TeamMediaRecord(
  foreignKey: 'photo',
  type: type,
  preferred: preferred,
  teamKeys: [teamKey],
  details: const {},
  directUrl: url,
  viewUrl: null,
  base64Image: null,
);

void main() {
  test('photos match the team and prefer photos over avatars and previews', () {
    final records = [
      _media(type: 'avatar', url: 'avatar', preferred: true),
      _media(type: 'youtube', url: 'thumbnail', preferred: true),
      _media(teamKey: 'frc254', url: 'other team', preferred: true),
      _media(url: 'first'),
      _media(preferred: true),
      _media(url: 'preferred', preferred: true),
    ];
    expect(flashCardPhoto(records, 'frc2046'), 'preferred');
    expect(flashCardPhoto(records, 'frc254'), 'other team');
    expect(flashCardPhoto(records, 'frc999'), isNull);
    expect(flashCardPhoto([_media(url: 'first')], 'frc2046'), 'first');
    expect(
      flashCardPhoto([_media(type: 'avatar', url: 'avatar')], 'frc2046'),
      isNull,
    );
  });

  testWidgets('flip, sorting gestures, undo, round review and reset', (
    tester,
  ) async {
    final container = await _showPage(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('254'));
    await tester.pumpAndSettle();
    expect(find.text('Cheesy Poofs'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('flash-card-deck')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('2046'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mark-known')));
    await tester.pumpAndSettle();
    expect(find.text('Round complete'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo last sort'));
    await tester.pumpAndSettle();
    expect(find.text('Bear Metal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mark-known')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study again'));
    await tester.pumpAndSettle();
    expect(find.text('254'), findsOneWidget);
    expect(find.text('2046'), findsNothing);
    final store = FlashCardStore(container.read(sharedPreferencesProvider));
    expect(store.readProgress('2026wabon').order, ['frc254']);
    await tester.tap(find.byKey(const ValueKey('mark-known')));
    await tester.pumpAndSettle();
    expect(find.text('All known'), findsOneWidget);
    await tester.tap(find.text('Reset progress'));
    await tester.pumpAndSettle();
    expect(find.text('254'), findsOneWidget);
    expect(store.readProgress('2026wabon').ratings, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing the first side applies immediately and to later cards',
    (tester) async {
      await _showPage(tester);
      await tester.pumpAndSettle();
      await _openOptions(tester);
      await tester.tap(find.text('Name'));
      await _closeOptions(tester);
      await tester.pumpAndSettle();
      expect(find.text('Cheesy Poofs'), findsOneWidget);
      expect(find.text('254'), findsNothing);
      await tester.tap(find.text('Cheesy Poofs'));
      await tester.pumpAndSettle();
      expect(find.text('254'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mark-known')));
      await tester.pumpAndSettle();
      expect(find.text('Bear Metal'), findsOneWidget);
      await _openOptions(tester);
      await tester.tap(find.text('Number'));
      await _closeOptions(tester);
      await tester.pumpAndSettle();
      expect(find.text('2046'), findsOneWidget);
    },
  );

  testWidgets(
    'event changes clear the previous deck while loading and reset progress',
    (tester) async {
      final nextEvent = Completer<List<Map<String, dynamic>>>();
      final media = Completer<List<TeamMediaRecord>>();
      final container = await _showPage(
        tester,
        loadTeams: (ref) async {
          final event = ref.watch(currentEventProvider);
          return event == '2026wabon' ? _teams : nextEvent.future;
        },
        loadMedia: (_) => media.future,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mark-known')));
      await tester.pumpAndSettle();
      expect(find.text('2046'), findsOneWidget);

      await container
          .read(currentEventProvider.notifier)
          .setEventKey('2026test');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('2046'), findsNothing);
      nextEvent.complete([
        {'team_number': 1114, 'nickname': 'Simbotics'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('1114'), findsOneWidget);
      expect(
        FlashCardStore(container.read(sharedPreferencesProvider))
            .readProgress('2026test')
            .index,
        0,
      );

      media.completeError(Exception('Media unavailable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1114'));
      await tester.pumpAndSettle();
      expect(find.text('Simbotics'), findsOneWidget);
    },
  );

  testWidgets('loading, recoverable team errors, and empty events', (
    tester,
  ) async {
    final request = Completer<List<Map<String, dynamic>>>();
    var attempts = 0;
    await _showPage(
      tester,
      loadTeams: (_) {
        attempts++;
        return attempts == 1 ? request.future : Future.value([]);
      },
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    request.completeError(Exception('Teams unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Teams unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('No teams in this event'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('small screens and enlarged text remain usable', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _showPage(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('254'));
    await tester.pumpAndSettle();
    expect(find.text('Cheesy Poofs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'photo belongs only to the number side and failure keeps the card usable',
    (tester) async {
      await _showPage(
        tester,
        loadMedia: (_) async => [
          _media(teamKey: 'frc254', url: 'https://example.com/robot.jpg'),
        ],
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as NetworkImage).url,
        'https://example.com/robot.jpg',
      );
      expect(find.text('254'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('254'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Cheesy Poofs'), findsOneWidget);
    },
  );

  testWidgets('reduced motion and semantics expose only the visible answer', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _showPage(tester, disableAnimations: true);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('254'), findsOneWidget);
      expect(find.bySemanticsLabel('Cheesy Poofs'), findsNothing);
      await tester.tap(find.text('254'));
      await tester.pump();
      expect(find.bySemanticsLabel('Cheesy Poofs'), findsOneWidget);
      expect(find.bySemanticsLabel('254'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
