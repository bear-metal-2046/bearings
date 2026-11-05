import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_model.dart';
import 'package:beariscope/pages/flash_cards/sharing/flash_card_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

FlashCardDeckDefinition _deck(String name) => FlashCardDeckDefinition.create(
  name: name,
  emoji: '🤖',
  eventKeys: ['2026wabon'],
);

void main() {
  test('links preserve case-sensitive codes and accept compressed decks', () {
    for (final deck in [
      _deck('Worlds Teams'),
      FlashCardDeckDefinition.create(
        name: 'PNW tour',
        emoji: '🐻',
        eventKeys: [for (var i = 0; i < 32; i++) '2026event$i'],
      ),
    ]) {
      final link = Uri.parse(deck.shareLink);
      expect(link.scheme, flashCardDeckLinkScheme);
      expect(link.host, 'deck');
      expect(link.pathSegments, [deck.shareCode]);
      final imported = FlashCardDeckDefinition.fromShareCode(deck.shareLink);
      expect(imported.name, deck.name);
      expect(imported.emoji, deck.emoji);
      expect(imported.eventKeys, deck.eventKeys);
      expect(imported.shareCode, deck.shareCode);
      expect(
        FlashCardDeckDefinition.fromShareCode(deck.shareCode).shareCode,
        deck.shareCode,
      );
    }
  });

  test('foreign, callback, and malformed links cannot import decks', () {
    final deck = _deck('Worlds Teams');
    for (final link in [
      'https://example.com/deck/${deck.shareCode}',
      '$flashCardDeckLinkScheme://callback/${deck.shareCode}',
      '$flashCardDeckLinkScheme://deck/',
      '${deck.shareLink}/extra',
      '${deck.shareLink}?code=other',
      '${deck.shareLink}#other',
      '$flashCardDeckLinkScheme://user@deck/${deck.shareCode}',
      '$flashCardDeckLinkScheme://deck:123/${deck.shareCode}',
      '$flashCardDeckLinkScheme://deck/not-a-deck',
    ]) {
      expect(
        () => FlashCardDeckDefinition.fromShareCode(link),
        throwsFormatException,
        reason: link,
      );
    }
  });

  test('cold links survive startup and login, then are consumed once', () {
    final deck = _deck('Worlds Teams');
    final redirect = FlashCardDeepLink();
    expect(redirect.redirect(Uri.parse(deck.shareLink), ready: false), isNull);
    for (final path in ['/splash', '/welcome', '/post_sign_in_onboarding']) {
      expect(redirect.redirect(Uri.parse(path), ready: false), isNull);
    }
    final target = Uri.parse(
      redirect.redirect(Uri.parse('/welcome'), ready: true)!,
    );
    expect(target.path, '/flash_cards/import');
    expect(target.queryParameters['code'], deck.shareLink);
    expect(redirect.redirect(target, ready: true), isNull);
    expect(redirect.redirect(Uri.parse('/up_next'), ready: true), isNull);
  });

  test('already-running links open import and newer pending links replace older ones', () {
    final first = _deck('First deck');
    final second = _deck('Second deck');
    final redirect = FlashCardDeepLink();
    final immediate = Uri.parse(
      redirect.redirect(Uri.parse(first.shareLink), ready: true)!,
    );
    expect(immediate.queryParameters['code'], first.shareLink);
    expect(redirect.redirect(Uri.parse(first.shareLink), ready: false), isNull);
    expect(
      redirect.redirect(Uri.parse(second.shareLink), ready: false),
      isNull,
    );
    final target = Uri.parse(
      redirect.redirect(Uri.parse('/splash'), ready: true)!,
    );
    expect(target.queryParameters['code'], second.shareLink);
  });

  test(
    'OAuth callbacks and unrelated routes are not captured as deck links',
    () {
      final redirect = FlashCardDeepLink();
      for (final link in [
        '$flashCardDeckLinkScheme://callback?code=auth-code&state=auth-state',
        '$flashCardDeckLinkScheme://other/path',
        'https://example.com/deck/code',
        '/settings',
      ]) {
        expect(redirect.redirect(Uri.parse(link), ready: true), isNull);
        expect(redirect.redirect(Uri.parse('/splash'), ready: true), isNull);
      }
    },
  );

  test(
    'native path-only delivery and internal import routes retain the payload',
    () {
      final deck = _deck('Worlds Teams');
      for (final path in [
        '/deck/${deck.shareCode}',
        '/${deck.shareCode}',
        Uri(
          path: '/flash_cards/import',
          queryParameters: {'code': deck.shareLink},
        ).toString(),
      ]) {
        final redirect = FlashCardDeepLink();
        final input = Uri.parse(path);
        expect(redirect.redirect(input, ready: false), isNull);
        final target = Uri.parse(
          redirect.redirect(Uri.parse('/splash'), ready: true)!,
        );
        expect(
          FlashCardDeckDefinition.fromShareCode(target.queryParameters['code']!)
              .shareCode,
          deck.shareCode,
        );
      }
    },
  );
}
