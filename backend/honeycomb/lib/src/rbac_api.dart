import 'package:dart_frog/dart_frog.dart';

import 'auth0_management.dart';
import 'database.dart';
import 'picklists.dart';
import 'security.dart';

Future<Response> rbac(Request request, Access access, String path) async {
  if (path == 'rbac/metadata' && request.method == HttpMethod.get) {
    return reply({'permissions': permissionMetadata});
  }
  if (!access.has('rbac.manage'))
    return reply({'error': 'Forbidden'}, status: 403);
  final db = await HoneycombDatabase.instance;
  final roles = db.collection('role_definitions');
  final users = db.collection('users');
  final auth0 = Auth0Management.instance;

  if (path == 'rbac/roles') {
    if (request.method == HttpMethod.get) {
      final records = await roles.modernFind(sort: {'id': 1}).toList();
      return reply({'roles': records.map(_role).toList()});
    }
    if (request.method == HttpMethod.post) {
      final body = await readObject(request);
      final id = bounded(body?['id'], 64);
      final name = bounded(body?['name'], 128);
      final permissions = _strings(
        body?['permissions'],
        max: 128,
        itemMax: 128,
        min: 1,
      );
      if (id == null || name == null || permissions == null) {
        return reply({'error': 'Invalid payload'}, status: 400);
      }
      if (body?['description'] != null &&
          (body!['description'] is! String ||
              (body['description'] as String).length > 512)) {
        return reply({'error': 'Invalid payload'}, status: 400);
      }
      if (await roles.findOne({'id': id}) != null) {
        return reply({'error': 'Role already exists'}, status: 409);
      }
      final role = <String, dynamic>{
        'id': id,
        'name': name,
        'description': body?['description'] ?? '',
        'permissions': permissions,
      };
      await roles.insertOne(role);
      AuthService.instance.invalidate();
      return reply({'success': true, 'role': _role(role)}, status: 201);
    }
  }
  if (path.startsWith('rbac/roles/')) {
    final id = path.substring('rbac/roles/'.length);
    if (id.isEmpty || id.contains('/'))
      return reply({'error': 'Not found'}, status: 404);
    if (request.method == HttpMethod.patch) {
      final body = await readObject(request);
      if (body == null)
        return reply({'error': 'Invalid JSON payload'}, status: 400);
      final update = <String, dynamic>{};
      if (body.containsKey('name')) {
        final name = bounded(body['name'], 128);
        if (name == null)
          return reply({'error': 'Invalid payload'}, status: 400);
        update['name'] = name;
      }
      if (body.containsKey('description')) {
        if (body['description'] is! String ||
            (body['description'] as String).length > 512) {
          return reply({'error': 'Invalid payload'}, status: 400);
        }
        update['description'] = body['description'];
      }
      if (body.containsKey('permissions')) {
        final permissions = _strings(
          body['permissions'],
          max: 128,
          itemMax: 128,
          min: 1,
        );
        if (permissions == null)
          return reply({'error': 'Invalid payload'}, status: 400);
        update['permissions'] = permissions;
      }
      if (update.isEmpty)
        return reply({'error': 'No fields to update'}, status: 400);
      final result = await roles.updateOne({'id': id}, {r'$set': update});
      if (result.nMatched == 0)
        return reply({'error': 'Role not found'}, status: 404);
      AuthService.instance.invalidate();
      return reply({
        'success': true,
        'role': _role((await roles.findOne({'id': id}))!),
      });
    }
    if (request.method == HttpMethod.delete) {
      if (await users.count({'roles': id}) > 0) {
        return reply({
          'error': 'Role is assigned to one or more users',
        }, status: 409);
      }
      final result = await roles.deleteOne({'id': id});
      if (result.nRemoved == 0)
        return reply({'error': 'Role not found'}, status: 404);
      AuthService.instance.invalidate();
      return reply({'success': true});
    }
  }
  if (path == 'rbac/users' && request.method == HttpMethod.get) {
    final local = await users.find().toList();
    final byId = {
      for (final row in local)
        if (row['auth0UserId'] is String) row['auth0UserId'] as String: row,
    };
    final directory = await auth0.users();
    final merged = directory
        .whereType<Map<dynamic, dynamic>>()
        .map((item) {
          final id = item['user_id']?.toString() ?? '';
          final record = byId[id];
          final name =
              item['name'] ?? item['username'] ?? item['nickname'] ?? id;
          return {
            'id': id,
            'auth0UserId': id,
            'name': name,
            'avatarUrl': item['picture'],
            'roles': ((record?['roles'] as List?) ?? [])
                .whereType<String>()
                .toSet()
                .toList(),
          };
        })
        .where((item) => item['id'] != '')
        .toList();
    merged.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
    return reply({'users': merged});
  }
  final match = RegExp(r'^rbac/users/([^/]+)/roles$').firstMatch(path);
  if (match != null && request.method == HttpMethod.patch) {
    final id = Uri.decodeComponent(match.group(1)!);
    final body = await readObject(request);
    final roleIds = _strings(body?['roles'], max: 256, itemMax: 64);
    if (roleIds == null)
      return reply({'error': 'Invalid payload'}, status: 400);
    if (roleIds.isNotEmpty) {
      final existing = await roles.find({
        'id': {r'$in': roleIds},
      }).toList();
      final known = existing.map((role) => role['id']).toSet();
      if (roleIds.any((id) => !known.contains(id))) {
        return reply({'error': 'Unknown role ids'}, status: 400);
      }
    }
    if (body?['name'] != null) {
      final name = bounded(body?['name'], 128);
      if (name == null) return reply({'error': 'Invalid payload'}, status: 400);
      await auth0.updateUser(id, {'name': name});
    }
    await users.updateOne(
      {'auth0UserId': id},
      {
        r'$set': {'auth0UserId': id, 'roles': roleIds},
        r'$unset': {'id': '', 'name': '', 'avatarUrl': ''},
      },
      upsert: true,
    );
    final directory = await auth0.users();
    final found = directory
        .whereType<Map<dynamic, dynamic>>()
        .where((user) => user['user_id'] == id)
        .firstOrNull;
    AuthService.instance.invalidate(id);
    return reply({
      'success': true,
      'user': {
        'id': id,
        'auth0UserId': id,
        'name': body?['name'] ?? found?['name'] ?? id,
        'avatarUrl': found?['picture'],
        'roles': roleIds,
      },
    });
  }
  return reply({'error': 'Method not allowed'}, status: 405);
}

Map<String, dynamic> _role(Map<String, dynamic> record) => {
  'id': record['id'].toString(),
  'name': record['name']?.toString() ?? record['id'].toString(),
  'description': record['description'],
  'permissions': ((record['permissions'] as List?) ?? [])
      .whereType<String>()
      .toList(),
};

List<String>? _strings(
  dynamic raw, {
  required int max,
  required int itemMax,
  int min = 0,
}) {
  if (raw is! List || raw.length > max || raw.length < min) return null;
  final values = <String>{};
  for (final item in raw) {
    final value = bounded(item, itemMax);
    if (value == null) return null;
    values.add(value);
  }
  return values.toList();
}
