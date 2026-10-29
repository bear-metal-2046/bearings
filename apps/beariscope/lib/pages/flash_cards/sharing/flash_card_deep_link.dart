import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_model.dart';

/// Holds an incoming deck link until startup, login, and onboarding finish.
class FlashCardDeepLink {
  String? _pendingImport;

  String? redirect(Uri location, {required bool ready}) {
    final input = _importInput(location);
    if (input != null) {
      _pendingImport = Uri(
        path: '/flash_cards/import',
        queryParameters: {'code': input},
      ).toString();
    }
    if (!ready) return null;
    final target = _pendingImport;
    _pendingImport = null;
    return target == location.toString() ? null : target;
  }

  String? _importInput(Uri location) {
    if (location.scheme == flashCardDeckLinkScheme && location.host == 'deck') {
      // Let the import preview report malformed payloads rather than adding them.
      return location.toString();
    }
    if (location.hasScheme) return null;
    if (location.path == '/flash_cards/import') {
      return location.queryParameters['code'];
    }
    // Native platforms may forward the full URL or just its route path.
    final segments = location.pathSegments;
    if (segments.length == 2 && segments.first == 'deck') {
      return segments.last;
    }
    if (segments.length == 1 &&
        (segments.single.startsWith('BFC2:') ||
            segments.single.startsWith('BFC3:'))) {
      return segments.single;
    }
    return null;
  }
}
