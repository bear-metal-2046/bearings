import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:grove/grove.dart';

part 'picklist.g.dart';

/// A shared picklist. Team edits are immutable CRDT changes keyed by operation
/// ID, so concurrent Grove patches can add changes without replacing the list.
@GroveEntity('strategy.picklist', version: 1)
class GrovePicklist {
  GrovePicklist({
    required this.id,
    required this.eventKey,
    required this.title,
    required this.emoji,
    required this.createdAt,
    required this.updatedAt,
    Map<String, String> teamChanges = const {},
  }) : teamChanges = Map.unmodifiable(teamChanges) {
    if (id.isEmpty ||
        eventKey.isEmpty ||
        title.trim().isEmpty ||
        emoji.isEmpty) {
      throw ArgumentError('A picklist requires an ID, event, title, and emoji');
    }
    // Reject incomplete or unreadable histories before they enter storage.
    teamKeys;
  }

  final String id;
  final String eventKey;
  final String title;
  final String emoji;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, String> teamChanges;

  late final List<String> teamKeys = _withTeams(
    (_, teams) => List.unmodifiable(teams.value.toSet()),
  );

  GrovePicklist customize({
    String? title,
    String? emoji,
    required DateTime at,
  }) => GrovePicklist(
    id: id,
    eventKey: eventKey,
    title: title ?? this.title,
    emoji: emoji ?? this.emoji,
    createdAt: createdAt,
    updatedAt: at,
    teamChanges: teamChanges,
  );

  GrovePicklist replaceTeams(List<String> keys, {required DateTime at}) {
    final desired = keys.toSet().toList();
    return _withTeams((document, teams) {
      _replaceTeams(document, teams, desired);
      final changes = {
        for (final change in document.exportChanges())
          change.id.toString(): base64Encode(change.toBytes()),
      };
      return GrovePicklist(
        id: id,
        eventKey: eventKey,
        title: title,
        emoji: emoji,
        createdAt: createdAt,
        updatedAt: at,
        teamChanges: changes,
      );
    });
  }

  T _withTeams<T>(
    T Function(CRDTDocument, CRDTFugueMovableListHandler<String>) action,
  ) {
    final document = CRDTDocument(documentId: id);
    try {
      final teams = CRDTFugueMovableListHandler<String>(
        document,
        'teams',
        handlerType: 'bearings.picklist.teams',
      );
      final changes = <Change>[];
      for (final entry in teamChanges.entries) {
        final change = Change.fromBytes(base64Decode(entry.value));
        if (change.id.toString() != entry.key) {
          throw const FormatException('Picklist change ID mismatch');
        }
        changes.add(change);
      }
      document.importChanges(changes);
      if (document.exportChanges().length != changes.length) {
        throw const FormatException(
          'Picklist history has missing dependencies',
        );
      }
      return action(document, teams);
    } finally {
      document.dispose();
    }
  }

  Json toJson() => _GrovePicklistToGroveJson(this);
  factory GrovePicklist.fromJson(Json json) =>
      _GrovePicklistFromGroveJson(json);
}

bool _sameOrder(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);

/// A drag moves one item, preserving concurrent edits to its neighbors.
void _replaceTeams(
  CRDTDocument document,
  CRDTFugueMovableListHandler<String> teams,
  List<String> desired,
) {
  final current = teams.value;
  if (_sameOrder(current, desired)) return;
  if (current.length == desired.length &&
      current.toSet().containsAll(desired)) {
    final first = current.indexed
        .firstWhere((entry) => entry.$2 != desired[entry.$1])
        .$1;
    final candidates = [
      (first, desired.indexOf(current[first])),
      (current.indexOf(desired[first]), first),
    ];
    for (final (from, to) in candidates) {
      final moved = List<String>.of(current)..removeAt(from);
      moved.insert(to, current[from]);
      if (_sameOrder(moved, desired)) {
        teams.move(from, to);
        return;
      }
    }
  }
  document.runInTransaction(() {
    final seen = <String>{};
    final wanted = desired.toSet();
    final duplicates = <int>[];
    for (final (index, key) in teams.value.indexed) {
      if (!wanted.contains(key) || !seen.add(key)) duplicates.add(index);
    }
    for (final index in duplicates.reversed) {
      teams.delete(index);
    }
    for (var index = 0; index < desired.length; index++) {
      final now = teams.value;
      if (index < now.length && now[index] == desired[index]) continue;
      final existing = now.indexOf(desired[index], index);
      if (existing >= 0) {
        teams.move(existing, index);
      } else {
        teams.insert(index, desired[index]);
      }
    }
  });
}
