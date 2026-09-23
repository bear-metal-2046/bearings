import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'database.dart';

const permissionMetadata = [
  {
    'key': 'external.read',
    'name': 'External Data Read',
    'description': 'Read TBA, Nexus, and other external endpoint data.',
  },
  {
    'key': 'match.read',
    'name': 'Match Scouting Read',
    'description': 'Read match scouting data.',
  },
  {
    'key': 'match.upload',
    'name': 'Match Scouting Upload',
    'description': 'Upload match scouting data.',
  },
  {
    'key': 'match.correct',
    'name': 'Match Scouting Correct',
    'description': 'Correct match scouting submissions.',
  },
  {
    'key': 'pits.read',
    'name': 'Pits Scouting Read',
    'description': 'Read pits scouting data.',
  },
  {
    'key': 'pits.upload',
    'name': 'Pits Scouting Upload',
    'description': 'Upload pits scouting data.',
  },
  {
    'key': 'notes.read',
    'name': 'Scouted Notes Read',
    'description': 'Read written scouted notes.',
  },
  {
    'key': 'drive_team.upload',
    'name': 'Drive Team Notes Upload',
    'description': 'Submit drive team scouting notes.',
  },
  {'key': 'scouts.read', 'name': 'Scouts Read', 'description': 'View scouts.'},
  {
    'key': 'scouts.manage',
    'name': 'Scouts Manage',
    'description': 'Create, update, and delete scouts.',
  },
  {
    'key': 'rbac.manage',
    'name': 'Users & Roles Manage',
    'description': 'Manage users, roles, and role assignments.',
  },
  {
    'key': 'picklists.read',
    'name': 'Picklists Read',
    'description': 'View picklists.',
  },
  {
    'key': 'picklists.manage',
    'name': 'Picklists Manage',
    'description': 'Create, update, and delete picklists.',
  },
  {
    'key': 'device.provision',
    'name': 'Device Provisioning',
    'description': 'View and share Pawfinder device credentials.',
  },
];

class Access {
  const Access(this.userId, this.username, this.permissions);
  final String userId;
  final String username;
  final Set<String> permissions;

  bool has(String permission) => permissions.contains(permission);
}

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  Map<String, dynamic>? _jwks;
  Future<Map<String, dynamic>>? _jwksLoading;
  DateTime _jwksExpires = DateTime.fromMillisecondsSinceEpoch(0);
  final _accessCache = <String, (Access, DateTime)>{};

  Future<Map<String, dynamic>> _loadJwks({bool refresh = false}) async {
    if (!refresh && _jwks != null && DateTime.now().isBefore(_jwksExpires)) {
      return _jwks!;
    }
    return _jwksLoading ??= _fetchJwks().whenComplete(() {
      _jwksLoading = null;
    });
  }

  Future<Map<String, dynamic>> _fetchJwks() async {
    final domain = Platform.environment['AUTH0_DOMAIN'];
    if (domain == null || domain.isEmpty)
      throw StateError('AUTH0_DOMAIN is required');
    final response = await http
        .get(Uri.https(domain, '/.well-known/jwks.json'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw StateError('Auth0 JWKS unavailable');
    _jwks = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    _jwksExpires = DateTime.now().add(const Duration(hours: 1));
    return _jwks!;
  }

  Future<Access?> fromRequest(
    Request request, {
    bool allowApiKey = false,
  }) async {
    if (allowApiKey) {
      final configured = Platform.environment['INTEGRATION_API_KEY'];
      final provided = request.headers['x-api-key'];
      if (configured != null &&
          configured.isNotEmpty &&
          provided != null &&
          _constantTimeEqual(provided, configured)) {
        return const Access('integration-api-key', 'integration', {
          'match.correct',
        });
      }
    }
    final authorization = request.headers['authorization'];
    if (authorization == null || !authorization.startsWith('Bearer '))
      return null;
    return fromToken(authorization.substring(7));
  }

  Future<Access?> fromToken(String token) async {
    try {
      if (token.length > 16384) return null;
      final decoded = JWT.decode(token);
      if (decoded.header?['alg'] != 'RS256') return null;
      final kid = decoded.header?['kid'];
      if (kid is! String || kid.isEmpty) return null;
      Map<String, dynamic>? key;
      for (var attempt = 0; attempt < 2; attempt++) {
        final jwks = await _loadJwks(refresh: attempt == 1);
        for (final item in jwks['keys'] as List? ?? const []) {
          if (item is Map &&
              item['kid'] == kid &&
              item['kty'] == 'RSA' &&
              (item['use'] == null || item['use'] == 'sig')) {
            key = Map<String, dynamic>.from(item);
            break;
          }
        }
        if (key != null) break;
      }
      if (key == null) return null;
      final domain = Platform.environment['AUTH0_DOMAIN'];
      final audience = Platform.environment['AUTH0_AUDIENCE'];
      if (domain == null || audience == null || audience.isEmpty) return null;
      final verified = JWT.verify(
        token,
        JWTKey.fromJWK(key),
        issuer: 'https://$domain/',
        audience: Audience.one(audience),
      );
      final claims = verified.payload;
      if (claims is! Map || claims['exp'] is! num || claims['sub'] is! String)
        return null;
      final userId = claims['sub'] as String;
      final rawName =
          claims['preferred_username'] ??
          claims['nickname'] ??
          claims['email'] ??
          claims['name'] ??
          userId;
      final username = rawName.toString().split('@').first.toLowerCase();
      return await forIdentity(userId, username);
    } catch (_) {
      return null;
    }
  }

  Future<Access> forIdentity(String userId, String username) async {
    final cached = _accessCache[userId];
    if (cached != null && DateTime.now().difference(cached.$2).inSeconds < 60) {
      return cached.$1;
    }
    final db = await HoneycombDatabase.instance;
    Set<String> permissions;
    final deviceId = Platform.environment['PAWFINDER_DEVICE_CLIENT_ID'];
    if (deviceId != null &&
        deviceId.isNotEmpty &&
        (userId == deviceId || userId == '$deviceId@clients')) {
      final role = await db.collection('role_definitions').findOne({
        r'$or': [
          {'id': 'device'},
          {'name': 'device'},
        ],
      });
      permissions = ((role?['permissions'] as List?) ?? const [])
          .whereType<String>()
          .toSet();
    } else {
      final user = await db.collection('users').findOne({
        r'$or': [
          {'id': username},
          {'id': userId},
          {'username': username},
          {'auth0UserId': userId},
        ],
      });
      final roles = ((user?['roles'] as List?) ?? const [])
          .whereType<String>()
          .toList();
      permissions = {};
      if (roles.isNotEmpty) {
        final definitions = await db.collection('role_definitions').find({
          'id': {r'$in': roles},
        }).toList();
        for (final role in definitions) {
          permissions.addAll(
            ((role['permissions'] as List?) ?? const []).whereType<String>(),
          );
        }
      }
    }
    final access = Access(userId, username, permissions);
    _accessCache[userId] = (access, DateTime.now());
    return access;
  }

  void invalidate([String? userId]) {
    if (userId == null) {
      _accessCache.clear();
    } else {
      _accessCache.remove(userId);
    }
  }

  bool _constantTimeEqual(String a, String b) {
    final left = utf8.encode(a);
    final right = utf8.encode(b);
    var difference = left.length ^ right.length;
    for (var i = 0; i < max(left.length, right.length); i++) {
      difference |=
          (i < left.length ? left[i] : 0) ^ (i < right.length ? right[i] : 0);
    }
    return difference == 0;
  }
}

class RateLimiter {
  RateLimiter._();
  static final instance = RateLimiter._();
  final _buckets = <String, (double, DateTime)>{};

  bool allow(String key, {required double ratePerSecond, required int burst}) {
    final now = DateTime.now();
    if (_buckets.length > 10000) {
      _buckets.removeWhere(
        (_, entry) => now.difference(entry.$2).inMinutes > 10,
      );
    }
    final prior = _buckets[key];
    final tokens = prior == null
        ? burst.toDouble()
        : min(
            burst.toDouble(),
            prior.$1 +
                now.difference(prior.$2).inMilliseconds / 1000 * ratePerSecond,
          );
    if (tokens < 1) {
      _buckets[key] = (tokens, now);
      return false;
    }
    _buckets[key] = (tokens - 1, now);
    return true;
  }
}
