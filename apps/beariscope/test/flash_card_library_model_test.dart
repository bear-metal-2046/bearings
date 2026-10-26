import 'dart:convert';
import 'dart:typed_data';

import 'package:beariscope/pages/flash_cards/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/flash_card_deck_provider.dart';
import 'package:beariscope/pages/flash_cards/flash_card_progress.dart';
import 'package:beariscope/pages/flash_cards/flash_card_qr.dart';
import 'package:beariscope/pages/team_lookup/team_model.dart';
import 'package:beariscope/pages/team_lookup/team_providers.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

FlashCardDeckDefinition _deck({
  String? id,
  String name = 'PNW',
  List<String> events = const ['2026wabon', '2026pncmp'],
}) => FlashCardDeckDefinition.create(
  id: id,
  name: name,
  emoji: '🐻',
  eventKeys: events,
);
Team _team(int number, String name) =>
    Team(key: 'frc$number', number: number, name: name, website: null);
TeamMediaRecord _media(
  String url, {
  String type = 'imgur',
  bool preferred = false,
}) => TeamMediaRecord(
  foreignKey: url,
  type: type,
  preferred: preferred,
  teamKeys: const ['frc2046'],
  details: const {},
  directUrl: url,
  viewUrl: null,
  base64Image: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deck definitions normalize and deduplicate event keys', () {
    final deck = _deck(events: [' 2026WABON ', '2026pncmp', '2026wabon']);
    expect(deck.eventKeys, ['2026pncmp', '2026wabon']);
    expect(() => deck.eventKeys.add('2026test'), throwsUnsupportedError);
    expect(FlashCardDeckDefinition.fromJson(deck.toJson()).id, deck.id);
  });

  test(
    'sharing round-trips Unicode and excludes local identity and progress',
    () {
      final deck = FlashCardDeckDefinition.create(
        name: '世界 🤖',
        emoji: '👨‍👩‍👧‍👦',
        eventKeys: ['2026wabon'],
      );
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(deck.shareCode))) as Map;
      expect(payload.keys.toSet(), {
        'type',
        'version',
        'name',
        'emoji',
        'events',
      });
      final imported = FlashCardDeckDefinition.fromShareCode(
        ' \n${deck.shareCode}\n ',
      );
      expect(imported.name, deck.name);
      expect(imported.emoji, deck.emoji);
      expect(imported.eventKeys, deck.eventKeys);
      expect(imported.id, isNot(deck.id));
      expect(imported.progressScope, isNot(deck.progressScope));
      expect(imported.shareCode, deck.shareCode);
    },
  );

  test('import rejects unrelated, malformed and unsupported payloads', () {
    String encode(Object value) => base64Encode(utf8.encode(jsonEncode(value)));
    final valid = jsonDecode(
      utf8.decode(base64Url.decode(_deck().shareCode)),
    ) as Map<String, dynamic>;
    for (final code in [
      '',
      'not a deck',
      encode(['wrong']),
      encode({...valid, 'type': 'another-app'}),
      encode({...valid, 'version': 99}),
      encode({...valid, 'events': []}),
      encode({
        ...valid,
        'events': [3],
      }),
      encode({
        ...valid,
        'events': ['2026foo/../../secret'],
      }),
      encode({...valid, 'emoji': '🐻🤖'}),
      encode({...valid, 'name': ''}),
      List.filled(6001, 'a').join(),
    ]) {
      expect(
        () => FlashCardDeckDefinition.fromShareCode(code),
        throwsFormatException,
      );
    }
  });

  test(
    'definition limits keep every accepted code small enough for QR sharing',
    () {
      final deck = _deck(
        name: List.filled(64, '界').join(),
        events: [
          for (var i = 0; i < 32; i++) '2026${List.filled(26, 'a').join()}$i',
        ],
      );
      expect(
        deck.shareCode.length,
        lessThanOrEqualTo(maxFlashCardDeckCodeLength),
      );
      expect(
        () => _deck(events: [for (var i = 0; i < 33; i++) '2026event$i']),
        throwsFormatException,
      );
      expect(() => _deck(events: ['0000invalid']), throwsFormatException);
      expect(
        () => _deck(name: List.filled(65, 'a').join()),
        throwsFormatException,
      );
    },
  );

  test(
    'current and explicit event rosters share and refresh event data',
    () async {
      SharedPreferences.setMockInitialValues({});
      var requests = 0;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          eventTeamsProvider.overrideWith((ref, event) async {
            requests++;
            return [
              {'team_number': 2046, 'nickname': 'Old name'},
              {'team_number': 0, 'nickname': 'Invalid'},
              {'team_number': 254, 'nickname': 'Cheesy Poofs'},
              {'team_number': 2046, 'nickname': 'Bear Metal'},
            ];
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(teamsProvider.future);
      final current = normalizeCurrentFlashCardRoster(
        container.read(teamsProvider),
      ).requireValue;
      final explicit = await container.read(
        flashCardEventRosterProvider('2026wabon').future,
      );
      expect(current.map((team) => team.number), [254, 2046]);
      expect(explicit.map((team) => team.number), [254, 2046]);
      expect(current.last.name, 'Bear Metal');
      expect(explicit.last.name, current.last.name);
      expect(requests, 1);

      container.invalidate(eventTeamsProvider('2026wabon'));
      await container.read(teamsProvider.future);
      expect(requests, 2);
    },
  );

  test('rosters deduplicate by team number and prefer newer metadata', () {
    final combined = combineFlashCardRosters({
      '2026wabon': [_team(2046, 'Bear Metal'), _team(254, 'Cheesy Poofs')],
      '2025pncmp': [_team(2046, 'Older name'), _team(2910, 'Jack in the Bot')],
    });
    expect(combined.map((team) => team.number), [254, 2046, 2910]);
    expect(
      combined.where((team) => team.number == 2046).single.name,
      'Bear Metal',
    );
  });

  test('photos use the newest available season and logos can fall back', () {
    final media = combineFlashCardMedia({
      '2025pncmp': [
        _media('old-photo', preferred: true),
        _media('old-logo', type: 'avatar'),
      ],
      '2026wabon': [_media('new-photo')],
    });
    expect(
      media.where((record) => record.isPhoto).single.directUrl,
      'new-photo',
    );
    expect(
      media.where((record) => record.isAvatar).single.directUrl,
      'old-logo',
    );
  });

  test('library persists globally, duplicate import keeps its progress, deletion is scoped', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final library = container.read(flashCardLibraryProvider.notifier);
    final a = await library.save(_deck());
    final b = await library.save(_deck(name: 'Another deck'));
    final store = FlashCardStore(prefs);
    await store.saveProgress(
      a.progressScope,
      const FlashCardProgress(ratings: {'frc2046': true}),
    );
    await store.saveProgress(
      b.progressScope,
      const FlashCardProgress(ratings: {'frc254': true}),
    );
    final imported = await library.importDeck(
      FlashCardDeckDefinition.fromShareCode(a.shareCode),
    );
    expect(imported.id, a.id);
    expect(container.read(flashCardLibraryProvider).length, 2);
    expect(store.readProgress(imported.progressScope).ratings, {
      'frc2046': true,
    });
    await container
        .read(currentEventProvider.notifier)
        .setEventKey('2026other');
    expect(container.read(flashCardLibraryProvider).length, 2);
    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(
      restored.read(flashCardLibraryProvider).map((deck) => deck.id).toSet(),
      {a.id, b.id},
    );
    await library.delete(a);
    expect(store.readProgress(a.progressScope).ratings, isEmpty);
    expect(store.readProgress(b.progressScope).ratings, {'frc254': true});
  });

  test(
    'custom roster providers are independent of the selected event',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final requests = <String>[];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          flashCardEventRosterProvider.overrideWith((ref, event) async {
            requests.add(event);
            return [
              _team(2046, 'Bear Metal'),
              if (event == '2026wabon') _team(254, 'Cheesy Poofs'),
            ];
          }),
        ],
      );
      addTearDown(container.dispose);
      final deck = await container
          .read(flashCardLibraryProvider.notifier)
          .save(_deck());
      final teams = await container.read(
        flashCardCustomTeamsProvider(deck.id).future,
      );
      expect(teams.map((team) => team.number), [254, 2046]);
      await container
          .read(currentEventProvider.notifier)
          .setEventKey('2026other');
      expect(
        await container.read(flashCardCustomTeamsProvider(deck.id).future),
        same(teams),
      );
      expect(requests.toSet(), {'2026wabon', '2026pncmp'});
      expect(requests.length, 2);
    },
  );

  test(
    'a missing event does not silently produce a partial study deck',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          flashCardEventRosterProvider.overrideWith((ref, event) async {
            if (event == '2026pncmp') throw StateError('Offline');
            return [_team(2046, 'Bear Metal')];
          }),
        ],
      );
      addTearDown(container.dispose);
      final deck = await container
          .read(flashCardLibraryProvider.notifier)
          .save(_deck());
      await expectLater(
        container.read(flashCardCustomTeamsProvider(deck.id).future),
        throwsStateError,
      );
    },
  );

  test(
    'exported PNGs, including large decks, decode back to the exact code',
    () async {
      for (final deck in [
        _deck(),
        _deck(events: [for (var i = 0; i < 32; i++) '2026event$i']),
      ]) {
        final bytes = await renderFlashCardQr(deck.shareCode);
        expect(decodeFlashCardQrImage(bytes), deck.shareCode);
        final image = img.decodePng(bytes)!;
        final rotated = img.encodePng(img.copyRotate(image, angle: 90));
        expect(decodeFlashCardQrImage(rotated), deck.shareCode);
      }
    },
  );

  test('QR image imports reject invalid and oversized files', () {
    expect(
      () => decodeFlashCardQrImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => decodeFlashCardQrImage(Uint8List(12 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
}
