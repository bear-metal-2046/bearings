import 'dart:math';

enum PicklistMode { offline, multiplayer }

extension PicklistModeLabel on PicklistMode {
  String get label => switch (this) {
    PicklistMode.offline => 'Offline',
    PicklistMode.multiplayer => 'Multiplayer',
  };

  String get description => switch (this) {
    PicklistMode.offline => 'Private to this device.',
    PicklistMode.multiplayer =>
      'Shared with teammates and synced in real time.',
  };
}

/// A small, recognizable palette that works well as a picklist thumbnail.
const picklistEmojis = [
  '🐻',
  '🤖',
  '🚀',
  '⚡',
  '🔥',
  '⭐',
  '🏆',
  '🎯',
  '🦊',
  '🐼',
  '🐸',
  '🐯',
  '🦁',
  '🐙',
  '🦄',
  '🐲',
  '🍀',
  '🌻',
  '🌵',
  '🌈',
  '🌙',
  '🪐',
  '☄️',
  '🌊',
  '🍕',
  '🍩',
  '🍉',
  '🍋',
  '🍒',
  '🥑',
  '🍿',
  '🧋',
  '🎸',
  '🎮',
  '🎲',
  '🧩',
  '💎',
  '🧲',
  '🛠️',
  '🧠',
  '🏎️',
  '🚁',
  '🛸',
  '⛵',
  '🎈',
  '🎉',
  '👑',
  '🦋',
];

String randomPicklistEmoji() =>
    picklistEmojis[Random().nextInt(picklistEmojis.length)];

class Picklist {
  final String id;
  final String eventKey;
  final String title;
  final String emoji;
  final List<String> teamKeys;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PicklistMode mode;

  const Picklist({
    required this.id,
    required this.eventKey,
    required this.title,
    required this.teamKeys,
    required this.createdAt,
    required this.updatedAt,
    this.mode = PicklistMode.offline,
    required this.emoji,
  });

  Picklist copyWith({
    String? title,
    String? emoji,
    List<String>? teamKeys,
    DateTime? updatedAt,
    PicklistMode? mode,
  }) {
    return Picklist(
      id: id,
      eventKey: eventKey,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      teamKeys: teamKeys ?? this.teamKeys,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mode: mode ?? this.mode,
    );
  }

  factory Picklist.fromJson(
    Map<String, dynamic> json, {
    PicklistMode defaultMode = PicklistMode.offline,
  }) {
    final modeName = json['mode']?.toString();
    final mode =
        PicklistMode.values
            .where((value) => value.name == modeName)
            .firstOrNull ??
        defaultMode;
    return Picklist(
      id: json['id']?.toString() ?? '',
      eventKey: json['eventKey']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Picklist',
      emoji: json['emoji'] as String,
      teamKeys: (json['teamKeys'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      mode: mode,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'eventKey': eventKey,
    'title': title,
    'emoji': emoji,
    'teamKeys': teamKeys,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'mode': mode.name,
  };
}
