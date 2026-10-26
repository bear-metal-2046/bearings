import 'dart:convert';
import 'dart:math';

import 'package:characters/characters.dart';

const maxFlashCardDeckEvents = 32;
const maxFlashCardDeckCodeLength = 2200;
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
  const FlashCardDeckDefinition._({
    required this.id,
    required this.name,
    required this.emoji,
    required this.eventKeys,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FlashCardDeckDefinition.create({
    String? id,
    required String name,
    required String emoji,
    required Iterable<String> eventKeys,
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
    final now = DateTime.now().toUtc();
    final deck = FlashCardDeckDefinition._(
      id: id ?? _newDeckId(),
      name: title,
      emoji: symbol,
      eventKeys: List.unmodifiable(keys),
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
    if (deck.shareCode.length > maxFlashCardDeckCodeLength) {
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
  final DateTime createdAt;
  final DateTime updatedAt;
  String get progressScope => flashCardDeckProgressScope(id);

  String get shareCode => base64UrlEncode(
    utf8.encode(
      jsonEncode({
        'type': 'beariscope.flashcards',
        'version': 1,
        'name': name,
        'emoji': emoji,
        'events': eventKeys,
      }),
    ),
  );

  factory FlashCardDeckDefinition.fromShareCode(String raw) {
    if (raw.length > 6000) {
      throw const FormatException('That deck code is too long.');
    }
    final code = raw.replaceAll(RegExp(r'\s+'), '');
    if (code.isEmpty || code.length > maxFlashCardDeckCodeLength) {
      throw const FormatException('Paste a valid flashcard deck code.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(base64.decode(base64.normalize(code))));
    } catch (_) {
      throw const FormatException('This is not a valid flashcard deck code.');
    }
    if (decoded is! Map || decoded['type'] != 'beariscope.flashcards') {
      throw const FormatException(
        'This code is not a Beariscope flashcard deck.',
      );
    }
    if (decoded['version'] != 1) {
      throw const FormatException(
        'This deck uses an unsupported sharing version.',
      );
    }
    return _fromFields(decoded);
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
    return FlashCardDeckDefinition.create(
      id: stored ? json['id'] as String : null,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      eventKeys: (json['events'] as List).cast<String>(),
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
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
