import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:beariscope/pages/flash_cards/flash_card_deck_editor_page.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_import_page.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_share_page.dart';
import 'package:beariscope/pages/flash_cards/flash_card_progress.dart';
import 'package:beariscope/pages/flash_cards/flash_card_study_page.dart';
import 'package:beariscope/pages/flash_cards/flash_cards_page.dart';
import 'package:beariscope/pages/main_view.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:beariscope/pages/flash_cards/flash_card_qr.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:shared_preferences/shared_preferences.dart';

FlashCardDeckDefinition _deck({String? id, String name = 'PNW'}) =>
    FlashCardDeckDefinition.create(
      id: id,
      name: name,
      emoji: '🐻',
      eventKeys: ['2026wabon', '2026pncmp'],
    );
Team _team(int number, String name) =>
    Team(key: 'frc$number', number: number, name: name, website: null);
final _events = [
  EventOption.fromJson({
    'key': '2026wabon',
    'name': 'Bonney Lake',
    'year': 2026,
  }),
  EventOption.fromJson({
    'key': '2026pncmp',
    'name': 'PNW Championship',
    'year': 2026,
  }),
];

Future<
  ({
    ProviderContainer container,
    GoRouter router,
    SharedPreferences preferences,
  })
>
showFlashCardLibraryTestApp(
  WidgetTester tester, {
  List<FlashCardDeckDefinition> decks = const [],
  String location = '/flash_cards',
  SharedPreferences? preferences,
  Future<List<Team>> Function(Ref, String)? roster,
  Future<List<EventOption>> Function(Ref, int)? catalog,
}) async {
  if (preferences == null) {
    SharedPreferences.setMockInitialValues({
      FlashCardLibrary.storageKey: jsonEncode(
        decks.map((deck) => deck.toJson()).toList(),
      ),
    });
  }
  final prefs = preferences ?? await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      teamEventsProvider.overrideWith((_) async => _events),
      teamsProvider.overrideWith((ref) async {
        ref.watch(currentEventProvider);
        return [
          {'team_number': 254, 'nickname': 'Cheesy Poofs'},
          {'team_number': 2046, 'nickname': 'Bear Metal'},
        ];
      }),
      eventTeamMediaProvider.overrideWith((_) async => []),
      flashCardEventCatalogProvider.overrideWith(
        catalog ??
            (ref, year) async => _events
                .where((event) => event.key.startsWith('$year'))
                .toList(),
      ),
      flashCardEventRosterProvider.overrideWith(
        roster ??
            (ref, event) async => [
              _team(2046, 'Bear Metal'),
              if (event == '2026wabon') _team(254, 'Cheesy Poofs'),
              if (event == '2026pncmp') _team(2910, 'Jack in the Bot'),
            ],
      ),
      flashCardEventMediaProvider.overrideWith((ref, event) async => []),
    ],
  );
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/flash_cards',
        builder: (_, _) => const FlashCardsPage(),
        routes: [
          GoRoute(
            path: 'current',
            builder: (_, _) => const FlashCardStudyPage(),
          ),
          GoRoute(
            path: 'create',
            builder: (_, _) => const FlashCardDeckEditorPage(),
          ),
          GoRoute(
            path: 'import',
            builder: (_, _) => const FlashCardDeckImportPage(),
          ),
          GoRoute(
            path: 'edit/:deckId',
            builder: (_, state) =>
                FlashCardDeckEditorPage(deckId: state.pathParameters['deckId']),
          ),
          GoRoute(
            path: 'share/:deckId',
            builder: (_, state) =>
                FlashCardDeckSharePage(deckId: state.pathParameters['deckId']!),
          ),
          GoRoute(
            path: ':deckId',
            builder: (_, state) =>
                FlashCardStudyPage(deckId: state.pathParameters['deckId']),
          ),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MainViewController(
          isDesktop: true,
          openDrawer: () {},
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, router: router, preferences: prefs);
}

void main() {
  testWidgets(
    'library is the landing page and current-event play returns to it',
    (tester) async {
      final app = await showFlashCardLibraryTestApp(tester);
      expect(find.text('Your decks'), findsNothing);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Bonney Lake'), findsOneWidget);
      expect(find.text('254'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('flash-card-current-event')));
      await tester.pumpAndSettle();
      expect(find.text('254'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mark-known')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Current event'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      await app.container
          .read(currentEventProvider.notifier)
          .setEventKey('2026pncmp');
      await tester.pumpAndSettle();
      expect(find.text('PNW Championship'), findsOneWidget);
      expect(find.text('Your decks'), findsNothing);
      expect(find.byType(GridView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'create compiles selected events and custom progress ignores selected event',
    (tester) async {
      final app = await showFlashCardLibraryTestApp(tester);
      await tester.tap(find.text('New deck'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Deck name'),
        'PNW tour',
      );
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('catalog-event-2026wabon')));
      await tester.tap(find.byKey(const ValueKey('catalog-event-2026pncmp')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use 2 events'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create deck'));
      await tester.pumpAndSettle();
      final deck = app.container.read(flashCardLibraryProvider).single;
      expect(deck.eventKeys, ['2026pncmp', '2026wabon']);
      expect(find.text('254'), findsOneWidget);
      final progress = FlashCardStore(app.preferences)
          .readProgress(deck.progressScope);
      expect(progress.order, ['frc254', 'frc2046', 'frc2910']);
      await tester.tap(find.byKey(const ValueKey('mark-known')));
      await tester.pumpAndSettle();
      expect(find.text('2046'), findsOneWidget);
      await app.container
          .read(currentEventProvider.notifier)
          .setEventKey('2026elsewhere');
      await tester.pumpAndSettle();
      expect(find.text('2046'), findsOneWidget);
      expect(
        FlashCardStore(app.preferences)
            .readProgress(deck.progressScope)
            .ratings,
        {'frc254': true},
      );
      expect(
        FlashCardStore(app.preferences).readProgress('2026elsewhere').ratings,
        isEmpty,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('PNW tour'), findsOneWidget);
      expect(find.text('2 events'), findsOneWidget);
      expect(find.text('33%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor searches the catalog, accepts keys and preserves progress when renamed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final deck = _deck();
        final app = await showFlashCardLibraryTestApp(tester, decks: [deck]);
        final store = FlashCardStore(app.preferences);
        await store.saveProgress(
          deck.progressScope,
          const FlashCardProgress(ratings: {'frc254': true}),
        );
        await tester.tap(find.byTooltip('Deck options for PNW'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Deck name'),
          'PNW revised',
        );
        await tester.tap(find.bySemanticsLabel('Use 🚀 as thumbnail'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Events'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Find an event'),
          'Bonney',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('catalog-event-2026wabon')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('catalog-event-2026pncmp')),
          findsNothing,
        );
        await tester.tap(find.byTooltip('Add event keys'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('deck-event-keys')),
          '2026test, 2026WABON',
        );
        await tester.tap(find.byTooltip('Add events'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use 3 events'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        final updated = app.container.read(flashCardLibraryProvider).single;
        expect(updated.id, deck.id);
        expect(updated.name, 'PNW revised');
        expect(updated.emoji, '🚀');
        expect(updated.eventKeys, ['2026pncmp', '2026test', '2026wabon']);
        expect(store.readProgress(updated.progressScope).ratings, {
          'frc254': true,
        });
        expect(find.text('Your decks'), findsNothing);
        expect(find.byType(GridView), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'import previews codes, rejects invalid data and preserves duplicate progress',
    (tester) async {
      final existing = _deck();
      final app = await showFlashCardLibraryTestApp(tester, decks: [existing]);
      final store = FlashCardStore(app.preferences);
      await store.saveProgress(
        existing.progressScope,
        const FlashCardProgress(ratings: {'frc254': true}),
      );
      await tester.tap(find.byTooltip('Import deck'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('deck-import-code')),
        'invalid',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
      await tester.pumpAndSettle();
      expect(
        find.text('This is not a valid flashcard deck code.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('deck-import-code')),
        existing.shareCode,
      );
      await tester.pumpAndSettle();
      expect(find.text('PNW').hitTestable(), findsOneWidget);
      expect(find.text('Bonney Lake · 2026'), findsOneWidget);
      expect(find.text('PNW Championship · 2026'), findsOneWidget);
      expect(find.text('3 teams · 2 events'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
      await tester.pumpAndSettle();
      expect(app.container.read(flashCardLibraryProvider).length, 1);
      expect(find.text('2046'), findsOneWidget);
      expect(store.readProgress(existing.progressScope).ratings, {
        'frc254': true,
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('share screen shows the same code in QR and clipboard', (
    tester,
  ) async {
    final deck = _deck();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await showFlashCardLibraryTestApp(
      tester,
      decks: [deck],
      location: '/flash_cards/share/${deck.id}',
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('deck-share-qr')),
    );
    final code = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return decodeFlashCardQrImage(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    });
    expect(code, deck.shareCode);
    await tester.ensureVisible(find.text('Copy code'));
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(copied, deck.shareCode);
    expect(find.text('Deck code copied.'), findsOneWidget);
    expect(find.text('Download QR code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom reset never clears the selected event progress', (
    tester,
  ) async {
    final deck = _deck();
    final app = await showFlashCardLibraryTestApp(
      tester,
      decks: [deck],
      location: '/flash_cards/${deck.id}',
    );
    final store = FlashCardStore(app.preferences);
    await store.saveProgress(
      '2026wabon',
      const FlashCardProgress(ratings: {'frc42': true}),
    );
    await tester.tap(find.byKey(const ValueKey('mark-known')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Flash card options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reset progress'));
    await tester.tap(find.text('Reset progress'));
    await tester.pumpAndSettle();
    expect(find.text('Reset progress?'), findsOneWidget);
    expect(store.readProgress(deck.progressScope).ratings, {'frc254': true});
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Options'), findsOneWidget);
    expect(store.readProgress(deck.progressScope).ratings, {'frc254': true});
    await tester.tap(find.text('Reset progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset progress'));
    await tester.pumpAndSettle();
    expect(find.text('Options'), findsNothing);
    expect(find.text('254'), findsOneWidget);
    expect(store.readProgress(deck.progressScope).ratings, isEmpty);
    expect(store.readProgress('2026wabon').ratings, {'frc42': true});
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening a custom deck refreshes its live event rosters', (
    tester,
  ) async {
    var includeNewTeam = false;
    final deck = _deck();
    await showFlashCardLibraryTestApp(
      tester,
      decks: [deck],
      roster: (ref, event) async => [
        _team(2046, 'Bear Metal'),
        if (includeNewTeam) _team(2910, 'Jack in the Bot'),
      ],
    );
    await tester.tap(find.byKey(ValueKey('deck-${deck.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mark-known')));
    await tester.pumpAndSettle();
    expect(find.text('All known'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    includeNewTeam = true;
    await tester.tap(find.byKey(ValueKey('deck-${deck.id}')));
    await tester.pumpAndSettle();
    expect(find.text('2910'), findsOneWidget);
    expect(find.text('2046'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting one deck leaves other decks and current event intact', (
    tester,
  ) async {
    final a = _deck(name: 'A');
    final b = _deck(name: 'B');
    final app = await showFlashCardLibraryTestApp(tester, decks: [a, b]);
    await tester.tap(find.byTooltip('Deck options for A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete deck'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(app.container.read(flashCardLibraryProvider).single.id, b.id);
    expect(app.container.read(currentEventProvider), '2026wabon');
    expect(find.text('B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'event selection is a draft until applied and editor dismissal discards edits',
    (tester) async {
      final deck = _deck();
      final app = await showFlashCardLibraryTestApp(tester, decks: [deck]);
      await tester.tap(find.byTooltip('Deck options for PNW'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Deck name'),
        'Discard me',
      );
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('catalog-event-2026wabon')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close options').last);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Close options'));
      await tester.pumpAndSettle();
      expect(
        app.container.read(flashCardLibraryProvider).single.shareCode,
        deck.shareCode,
      );
      expect(find.text('Discard me'), findsNothing);
    },
  );

  testWidgets('sharing from options saves edits and returns to the editor', (
    tester,
  ) async {
    final deck = _deck();
    final app = await showFlashCardLibraryTestApp(tester, decks: [deck]);
    await tester.tap(find.byTooltip('Deck options for PNW'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Deck name'),
      'PNW edited',
    );
    await tester.tap(find.byTooltip('Share deck'));
    await tester.pumpAndSettle();
    expect(
      app.container.read(flashCardLibraryProvider).single.name,
      'PNW edited',
    );
    expect(find.text('Copy code'), findsOneWidget);
    await tester.tap(find.byTooltip('Close options').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'PNW edited'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('deck sheets handle $size, large text and keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final deck = _deck();
      await showFlashCardLibraryTestApp(tester, decks: [deck]);
      await tester.scrollUntilVisible(
        find.byTooltip('Deck options for PNW'),
        160,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Deck options for PNW'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Events'));
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Add event keys'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.height > 400) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.showKeyboard(
          find.byKey(const ValueKey('deck-event-keys')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Use 2 events').hitTestable(), findsOneWidget);
      }
    });
  }

  testWidgets(
    'learned bars use unique current teams, excluding stale and still-learning ratings',
    (tester) async {
      final deck = _deck();
      SharedPreferences.setMockInitialValues({
        FlashCardLibrary.storageKey: jsonEncode([deck.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = FlashCardStore(prefs);
      await store.saveProgress(
        '2026wabon',
        const FlashCardProgress(ratings: {'frc254': true, 'frc999': true}),
      );
      await store.saveProgress(
        deck.progressScope,
        const FlashCardProgress(
          ratings: {'frc2046': true, 'frc254': false, 'frc999': true},
        ),
      );
      var extraTeam = false;
      final app = await showFlashCardLibraryTestApp(
        tester,
        preferences: prefs,
        roster: (ref, event) async => [
          _team(2046, 'Bear Metal'),
          if (event == '2026wabon') _team(254, 'Cheesy Poofs'),
          if (event == '2026pncmp') _team(2910, 'Jack in the Bot'),
          if (extraTeam) _team(1678, 'Citrus Circuits'),
        ],
      );
      final current = find.descendant(
        of: find.byKey(const ValueKey('flash-card-current-event')),
        matching: find.byType(LinearProgressIndicator),
      );
      final custom = find.descendant(
        of: find.byKey(ValueKey('deck-${deck.id}')),
        matching: find.byType(LinearProgressIndicator),
      );
      expect(tester.widget<LinearProgressIndicator>(current).value, .5);
      expect(
        tester.widget<LinearProgressIndicator>(custom).value,
        closeTo(1 / 3, .0001),
      );
      expect(
        tester.widget<LinearProgressIndicator>(custom).semanticsValue,
        '33%',
      );
      extraTeam = true;
      app.container.invalidate(flashCardEventRosterProvider('2026wabon'));
      await tester.pumpAndSettle();
      expect(tester.widget<LinearProgressIndicator>(custom).value, .25);
      expect(find.text('25%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'import count waits for every roster and deduplicates across seasons',
    (tester) async {
      final pending = Completer<List<Team>>();
      final deck = FlashCardDeckDefinition.create(
        name: 'Across seasons',
        emoji: '🐻',
        eventKeys: ['2025wabon', '2026wabon'],
      );
      await showFlashCardLibraryTestApp(
        tester,
        location: '/flash_cards/import',
        catalog: (ref, year) async => [
          EventOption.fromJson({
            'key': '${year}wabon',
            'name': 'Bonney Lake',
            'year': year,
          }),
        ],
        roster: (ref, key) async => key == '2025wabon'
            ? [_team(2046, 'Bear Metal'), _team(254, 'Cheesy Poofs')]
            : pending.future,
      );
      await tester.enterText(
        find.byKey(const ValueKey('deck-import-code')),
        deck.shareCode,
      );
      await tester.pumpAndSettle();
      expect(find.text('Counting teams…'), findsOneWidget);
      expect(find.text('Bonney Lake · 2025'), findsOneWidget);
      expect(find.text('Bonney Lake · 2026'), findsOneWidget);
      pending.complete([
        _team(2046, 'Bear Metal'),
        _team(2910, 'Jack in the Bot'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('3 teams · 2 events'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'import preview falls back safely on metadata failure and retries without partial counts',
    (tester) async {
      final deck = _deck();
      var fail = true;
      await showFlashCardLibraryTestApp(
        tester,
        location: '/flash_cards/import',
        catalog: (ref, year) async {
          if (fail) throw StateError('Offline');
          return _events;
        },
        roster: (ref, key) async {
          if (key == '2026pncmp' && fail) throw StateError('Offline');
          return [
            _team(2046, 'Bear Metal'),
            if (key == '2026pncmp') _team(2910, 'Jack in the Bot'),
          ];
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('deck-import-code')),
        deck.shareCode,
      );
      await tester.pumpAndSettle();
      expect(find.text('Team count unavailable'), findsOneWidget);
      expect(find.text('2026wabon'), findsOneWidget);
      expect(find.text('1 team · 2 events'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Import deck'),
            )
            .onPressed,
        isNotNull,
      );
      fail = false;
      await tester.tap(find.byTooltip('Retry team count'));
      await tester.tap(find.text('Retry event names'));
      await tester.pumpAndSettle();
      expect(find.text('2 teams · 2 events'), findsOneWidget);
      expect(find.text('Bonney Lake · 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'populated import preview works on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await showFlashCardLibraryTestApp(
        tester,
        location: '/flash_cards/import',
      );
      await tester.enterText(
        find.byKey(const ValueKey('deck-import-code')),
        _deck(name: 'A long deck title for the entire district').shareCode,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('deck-import-team-count')),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 teams · 2 events'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final location in [
    '/flash_cards',
    '/flash_cards/create',
    '/flash_cards/import',
  ]) {
    testWidgets('$location works on a narrow screen with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await showFlashCardLibraryTestApp(
        tester,
        decks: [_deck()],
        location: location,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
