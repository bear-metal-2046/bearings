class Picklist {
  final String id;
  final String eventKey;
  final String title;
  final List<String> teamKeys;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Picklist({
    required this.id,
    required this.eventKey,
    required this.title,
    required this.teamKeys,
    required this.createdAt,
    required this.updatedAt,
  });

  Picklist copyWith({
    String? title,
    List<String>? teamKeys,
    DateTime? updatedAt,
  }) {
    return Picklist(
      id: id,
      eventKey: eventKey,
      title: title ?? this.title,
      teamKeys: teamKeys ?? this.teamKeys,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Picklist.fromJson(Map<String, dynamic> json) {
    return Picklist(
      id: json['id']?.toString() ?? '',
      eventKey: json['eventKey']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Picklist',
      teamKeys: (json['teamKeys'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'eventKey': eventKey,
    'title': title,
    'teamKeys': teamKeys,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
