import 'dart:convert';
import 'dart:math';

import 'package:beariscope/pages/flash_cards/decks/flash_card_deck_codec.dart';
import 'package:characters/characters.dart';

const maxFlashCardDeckEvents = 32;
const maxFlashCardDeckCodeLength = 2200;
const flashCardDeckLinkScheme = 'org.tahomarobotics.beariscope';
const _shareCodePrefix = 'BFC2:';
final _sharePayloadPattern = RegExp(r'^[A-Za-z0-9_-]+$');
final _eventKeyPattern = RegExp(r'^\d{4}[a-z0-9_-]{1,32}$');

String flashCardDeckProgressScope(String id) => 'custom-deck:$id';

String normalizeFlashCardEventKey(String key) {
  final normalized = key.trim().toLowerCase();
  if (!_eventKeyPattern.hasMatch(normalized) ||
      int.parse(normalized.substring(0, 4)) < 1992 ||
      int.parse(normalized.substring(0, 4)) > 2100) {
    throw const FormatException('Enter an event key such as 2026wabon.');
  }
  return normalized;
}

String _newDeckId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(0x100000000).toRadixString(36)}';

/// A live collection of event rosters. Sharing intentionally excludes local IDs
/// and learning progress, so each imported deck has its own progress scope.
class FlashCardDeckDefinition {
  FlashCardDeckDefinition._({
    required this.id,
    required this.name,
    required this.emoji,
    required this.eventKeys,
    required this.excludedTeamIndexes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FlashCardDeckDefinition.create({
    String? id,
    required String name,
    required String emoji,
    required Iterable<String> eventKeys,
    Map<String, Iterable<int>> excludedTeamIndexes = const {},
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final title = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final symbol = emoji.trim();
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(title) ||
        title.isEmpty ||
        title.characters.length > 64 ||
        utf8.encode(title).length > 240) {
      throw const FormatException(
        'Use a deck name between 1 and 64 characters.',
      );
    }
    if (symbol.characters.length != 1 ||
        utf8.encode(symbol).length > 64 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(symbol)) {
      throw const FormatException('Choose one emoji for the deck.');
    }
    final keys = eventKeys.map(normalizeFlashCardEventKey).toSet().toList()
      ..sort();
    if (keys.isEmpty || keys.length > maxFlashCardDeckEvents) {
      throw const FormatException('Choose between 1 and 32 events.');
    }
    final exclusions = <String, List<int>>{};
    for (final entry in excludedTeamIndexes.entries) {
      final event = normalizeFlashCardEventKey(entry.key);
      if (!keys.contains(event) ||
          entry.value.any((index) => index < 0 || index > 65535)) {
        throw const FormatException('The deck has invalid team overrides.');
      }
      final indexes = {...?exclusions[event], ...entry.value}.toList()..sort();
      if (indexes.isNotEmpty) exclusions[event] = List.unmodifiable(indexes);
    }
    if (exclusions.values.fold(0, (count, indexes) => count + indexes.length) >
        maxFlashCardDeckOverrides) {
      throw const FormatException('The deck has too many team overrides.');
    }
    final now = DateTime.now().toUtc();
    final deck = FlashCardDeckDefinition._(
      id: id ?? _newDeckId(),
      name: title,
      emoji: symbol,
      eventKeys: List.unmodifiable(keys),
      excludedTeamIndexes: Map.unmodifiable(exclusions),
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
    if (deck.shareCode.length > maxFlashCardDeckCodeLength ||
        deck.qrCode.length > maxFlashCardDeckQrCodeLength) {
      throw const FormatException(
        'Use fewer events or a shorter name to fit the QR code.',
      );
    }
    return deck;
  }

  final String id;
  final String name;
  final String emoji;
  final List<String> eventKeys;

  /// Zero-based positions in each event's roster sorted by team number.
  /// A referenced team is excluded from the entire deck, including other events.
  final Map<String, List<int>> excludedTeamIndexes;
  final DateTime createdAt;
  final DateTime updatedAt;
  String get progressScope => flashCardDeckProgressScope(id);

  late final _payload = encodeFlashCardDeckFields((
    name: name,
    emoji: emoji,
    events: eventKeys,
    exclusions: excludedTeamIndexes,
  ));
  late final _codes = encodeFlashCardDeckEnvelopes(_payload);

  /// URL-safe copied text; QR deep links use a separate Base41 payload.
  late final String shareCode = _codes.text;
  late final String qrCode = _codes.qr;

  String get shareLink => Uri(
    scheme: flashCardDeckLinkScheme,
    host: 'deck',
    path: '/$shareCode',
  ).toString();

  String get qrLink => Uri(
    scheme: flashCardDeckLinkScheme,
    host: 'deck',
    path: '/$qrCode',
  ).toString();

  factory FlashCardDeckDefinition.fromShareCode(String raw) {
    if (raw.length > 6000) {
      throw const FormatException('That deck code is too long.');
    }
    var code = raw.trim();
    final link = Uri.tryParse(code);
    if (link?.scheme == flashCardDeckLinkScheme) {
      if (link!.host != 'deck' ||
          link.userInfo.isNotEmpty ||
          link.hasPort ||
          link.hasQuery ||
          link.hasFragment ||
          link.pathSegments.length != 1) {
        throw const FormatException(
          'This is not a shared Beariscope deck link.',
        );
      }
      code = link.pathSegments.single;
    }
    // Both text encodings have no whitespace in their alphabets.
    final qr = code.startsWith('BFC3:Q');
    code = code.replaceAll(RegExp(r'\s+'), '');
    if (code.isEmpty ||
        code.length >
            (qr ? maxFlashCardDeckQrCodeLength : maxFlashCardDeckCodeLength)) {
      throw const FormatException('Paste a valid flashcard deck code.');
    }
    if (code.startsWith('BFC3:')) {
      try {
        final fields = decodeFlashCardDeckEnvelope(code);
        return FlashCardDeckDefinition.create(
          name: fields.name,
          emoji: fields.emoji,
          eventKeys: fields.events,
          excludedTeamIndexes: fields.exclusions,
        );
      } catch (_) {
        throw const FormatException('This is not a valid flashcard deck code.');
      }
    }
    if (!code.startsWith(_shareCodePrefix)) {
      throw const FormatException(
        'This is not a supported Beariscope deck code.',
      );
    }
    Object? decoded;
    try {
      final mode = code[_shareCodePrefix.length];
      final encoded = code.substring(_shareCodePrefix.length + 1);
      if (!_sharePayloadPattern.hasMatch(encoded)) {
        throw const FormatException('Invalid deck encoding.');
      }
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      final payload = switch (mode) {
        'N' => bytes,
        'Z' => decodeFlashCardDeckZlib(bytes),
        _ => throw const FormatException('Invalid deck encoding.'),
      };
      if (payload.length > maxFlashCardDeckPayloadBytes) {
        throw const FormatException('The deck payload is too large.');
      }
      decoded = jsonDecode(utf8.decode(payload));
    } catch (_) {
      throw const FormatException('This is not a valid flashcard deck code.');
    }
    if (decoded is! List || (decoded.length != 3 && decoded.length != 4)) {
      throw const FormatException(
        'The deck is missing its name, emoji, or events.',
      );
    }
    return _fromFields({
      'name': decoded[0],
      'emoji': decoded[1],
      'events': decoded[2],
      if (decoded.length == 4)
        'excludedTeamIndexes': _decodeSharedExclusions(decoded[3], decoded[2]),
    });
  }

  static Map<String, List<int>> _decodeSharedExclusions(
    Object? value,
    Object? events,
  ) {
    if (value is! List ||
        events is! List ||
        events.any((event) => event is! String)) {
      throw const FormatException('The deck has invalid team overrides.');
    }
    final result = <String, List<int>>{};
    for (final group in value) {
      if (group is! List ||
          group.length < 2 ||
          group.any((index) => index is! int) ||
          (group.first as int) < 0 ||
          (group.first as int) >= events.length) {
        throw const FormatException('The deck has invalid team overrides.');
      }
      final event = events[group.first as int] as String;
      result.putIfAbsent(event, () => []).addAll(group.skip(1).cast<int>());
    }
    return result;
  }

  static FlashCardDeckDefinition _fromFields(Map json, {bool stored = false}) {
    if (json['name'] is! String ||
        json['emoji'] is! String ||
        json['events'] is! List ||
        (json['events'] as List).any((value) => value is! String)) {
      throw const FormatException(
        'The deck is missing its name, emoji, or events.',
      );
    }
    if (stored &&
        (json['id'] is! String ||
            !RegExp(r'^[a-z0-9-]{1,80}$').hasMatch(json['id']))) {
      throw const FormatException('The saved deck has an invalid ID.');
    }
    final overrides = json['excludedTeamIndexes'];
    if (json.containsKey('excludedTeamIndexes') &&
        (overrides is! Map ||
            overrides.entries.any(
              (entry) =>
                  entry.key is! String ||
                  entry.value is! List ||
                  (entry.value as List).any((index) => index is! int),
            ))) {
      throw const FormatException('The deck has invalid team overrides.');
    }
    return FlashCardDeckDefinition.create(
      id: stored ? json['id'] as String : null,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      eventKeys: (json['events'] as List).cast<String>(),
      excludedTeamIndexes: overrides == null
          ? const {}
          : {
              for (final entry in (overrides as Map).entries)
                entry.key as String: (entry.value as List).cast<int>(),
            },
      createdAt: stored ? DateTime.tryParse('${json['createdAt']}') : null,
      updatedAt: stored ? DateTime.tryParse('${json['updatedAt']}') : null,
    );
  }

  factory FlashCardDeckDefinition.fromJson(Map<String, dynamic> json) =>
      _fromFields(json, stored: true);

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'events': eventKeys,
    if (excludedTeamIndexes.isNotEmpty)
      'excludedTeamIndexes': excludedTeamIndexes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
