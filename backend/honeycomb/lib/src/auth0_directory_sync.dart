import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/src/account_service.dart';

/// Reconciles Auth0's directory and handles user lifecycle events.
class Auth0DirectorySync {
  /// Uses the same Management API client as interactive account writes.
  Auth0DirectorySync({
    required AccountService accounts,
    String? webhookToken,
  }) : _accounts = accounts,
       _webhookToken = webhookToken;

  final AccountService _accounts;
  final String? _webhookToken;
  Timer? _timer;
  Future<void>? _pending;

  /// Starts importing users separately from Grove client connections.
  void start() {
    if (!_accounts.managementEnabled || _timer != null) return;
    _timer = Timer(Duration.zero, _poll);
  }

  Future<void> _poll() async {
    var delay = const Duration(minutes: 5);
    try {
      await reconcile();
    } catch (error) {
      // Auth0 responses and request URLs can contain profile data.
      final detail = error is GroveException
          ? error.message
          : error.runtimeType;
      stderr.writeln('Auth0 directory reconciliation failed: $detail');
      delay = const Duration(minutes: 1);
    }
    _timer = Timer(delay, _poll);
  }

  /// Synchronizes one catalog pass, sharing any pass already in flight.
  Future<void> reconcile() => _pending ??= _reconcile().whenComplete(
    () => _pending = null,
  );

  Future<void> _reconcile() async {
    final missing = _accounts.importedUserIds;
    final users = <String, String?>{};
    await _list(
      users,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    for (final user in users.entries) {
      missing.remove(user.key);
      final fetched = await _accounts.refreshUser(
        user.key,
        catalogVersion: user.value,
      );
      if (fetched) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    // Search is eventually consistent. Confirm missing users by ID.
    for (final id in missing) {
      final fetched = await _accounts.refreshUser(id, confirmDeletion: true);
      if (fetched) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  Future<void> _list(
    Map<String, String?> users,
    DateTime start,
    DateTime end, {
    String? query,
  }) async {
    var result = await _accounts.listUsers(0, query: query);
    final total = result['total'] as int;
    if (total >= 1000) {
      // Auth0 caps the results of any one search, even with pagination.
      final span = end.difference(start).inMilliseconds;
      if (span < 2) {
        throw const GroveException(
          'unavailable',
          'Auth0 search limit exceeded for a single creation timestamp',
        );
      }
      final middle = start.add(Duration(milliseconds: span ~/ 2));
      await _list(users, start, middle, query: _createdBetween(start, middle));
      await _list(users, middle, end, query: _createdBetween(middle, end));
      return;
    }

    for (var page = 0; ; page++) {
      final rows = result['users'] as List;
      for (final row in rows.cast<Json>()) {
        final id = row['user_id'] as String;
        if (id.isNotEmpty) users[id] = row['updated_at'] as String?;
      }
      if (rows.length < 100 || (page + 1) * 100 >= total) return;
      result = await _accounts.listUsers(page + 1, query: query);
    }
  }

  String _createdBetween(DateTime start, DateTime end) =>
      'created_at:[${start.toIso8601String()} TO ${end.toIso8601String()}}';

  /// Accepts a bearer-authenticated Auth0 CloudEvent and refreshes its user.
  Future<Response> receive(Request request) async {
    if (request.method != HttpMethod.post) {
      return Response(statusCode: 405, headers: {'allow': 'POST'});
    }
    final token = _webhookToken;
    if (token == null || token.isEmpty || !_accounts.managementEnabled) {
      return Response(statusCode: 503);
    }
    final supplied = request.headers['authorization'];
    if (!_tokenMatches(supplied, 'Bearer $token')) {
      return Response(statusCode: 401);
    }
    final Json event;
    try {
      final bytes = <int>[];
      await for (final chunk in request.bytes()) {
        if (bytes.length + chunk.length > 256 * 1024) {
          return Response(statusCode: 413);
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Json) return Response(statusCode: 400);
      event = decoded;
    } on FormatException {
      return Response(statusCode: 400);
    }
    final type = event['type'];
    if (type is! String) return Response(statusCode: 400);
    if (!const {
      'user.created',
      'user.updated',
      'user.deleted',
    }.contains(type)) {
      return Response(statusCode: 204);
    }
    final data = event['data'];
    final object = data is Json ? data['object'] : null;
    final id = object is Json ? object['user_id'] : null;
    if (id is! String || id.isEmpty || id.length > 256) {
      return Response(statusCode: 400);
    }
    final before = (data as Json)['previous_object'];
    final reportedChanges = <String, dynamic>{
      if (type == 'user.updated' && before is Json && object is Json)
        for (final field in const {'name', 'picture'})
          if (before.containsKey(field) && before[field] != object[field])
            field: object[field],
    };
    try {
      await _accounts.refreshUser(
        id,
        confirmDeletion: type == 'user.deleted',
        reportedChanges: reportedChanges,
      );
      return Response(statusCode: 204);
    } catch (_) {
      return Response(statusCode: 503);
    }
  }

  bool _tokenMatches(String? supplied, String expected) {
    if (supplied == null || supplied.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= supplied.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }
}
