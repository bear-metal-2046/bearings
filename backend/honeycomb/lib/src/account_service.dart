import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/src/authorization.dart';
import 'package:honeycomb/src/entity_store.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Keeps shared Auth0 profile fields in Grove and hosts uploaded photos.
class AccountService {
  AccountService({
    required this.store,
    required this.issuer,
    required this.deviceCredentials,
    this.managementClientId,
    this.managementClientSecret,
    this.publicApiUrl,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    store.database.execute('''
CREATE TABLE IF NOT EXISTS profile_photos (
  id TEXT PRIMARY KEY,
  owner TEXT NOT NULL UNIQUE,
  photo BLOB NOT NULL
)
''');
    store.database.execute('''
CREATE TABLE IF NOT EXISTS profile_photo_uploads (
  id TEXT PRIMARY KEY,
  owner TEXT NOT NULL,
  photo BLOB NOT NULL,
  created_at INTEGER NOT NULL
)
''');
    store.database.execute('''
CREATE INDEX IF NOT EXISTS profile_photo_uploads_owner
ON profile_photo_uploads (owner)
''');
    store.database.execute('''
CREATE TABLE IF NOT EXISTS auth0_user_profiles (
  id TEXT PRIMARY KEY,
  updated_at TEXT,
  data TEXT NOT NULL
)
''');
  }

  final EntityStore store;
  final Uri issuer;
  final String? managementClientId;
  final String? managementClientSecret;
  final Uri? publicApiUrl;
  final Json? deviceCredentials;
  final http.Client _client;
  ({String token, DateTime expires})? _managementToken;
  Future<String>? _loadingToken;
  final _accountWrites = <String, Future<void>>{};

  static const _profileFields = {
    'name': 'name',
    'email': 'email',
    'email_verified': 'emailVerified',
    'picture': 'avatarUrl',
  };
  static const _identityActor = 'honeycomb:auth0';

  /// Whether Honeycomb can access the Auth0 Management API.
  bool get managementEnabled =>
      (managementClientId?.isNotEmpty ?? false) &&
      (managementClientSecret?.isNotEmpty ?? false);

  Future<T> _serialize<T>(String id, Future<T> Function() work) async {
    final job = (_accountWrites[id] ?? Future<void>.value()).then(
      (_) => work(),
    );
    final tail = job.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _accountWrites[id] = tail;
    try {
      return await job;
    } finally {
      if (identical(_accountWrites[id], tail)) {
        unawaited(_accountWrites.remove(id));
      }
    }
  }

  Future<Json> run(AuthenticatedActor actor, String action, Json args) async {
    if (actor.id.endsWith('@clients')) {
      throw const GroveException('forbidden', 'A user account is required');
    }
    if (action == 'refreshProfile') {
      _requireLiveAccount(actor.id, actor);
      if (managementEnabled) await refreshUser(actor.id);
      return {};
    }
    return _serialize(actor.id, () => _run(actor, action, args));
  }

  Future<Json> _run(AuthenticatedActor actor, String action, Json args) async {
    _requireLiveAccount(actor.id, actor);
    switch (action) {
      case 'changeEmail':
        final email = args['email'] as String;
        if (email.length > 254 ||
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
          throw ArgumentError('Invalid email address');
        }
        final result = await _user('PATCH', actor.id, {
          'email': email,
          'email_verified': false,
          'verify_email': true,
        });
        final updated = result['email'] as String;
        _mergeProfile(
          actor.id,
          {
            'email': updated,
            'email_verified': result['email_verified'] ?? false,
          },
          actor: actor.id,
          explicit: const {'email', 'email_verified'},
        );
        return {'email': updated};
      case 'resetPassword':
        final profile = await _user('GET', actor.id);
        final email = profile['email'] as String?;
        final identities = (profile['identities'] as List).cast<Json>();
        final identity = identities
            .where(
              (item) =>
                  item['provider'] == 'auth0' && item['isSocial'] == false,
            )
            .firstOrNull;
        final connection = identity?['connection'] as String?;
        final clientId = actor.clientId;
        if (email == null || connection == null || clientId == null) {
          throw const GroveException(
            'invalid_request',
            'This account uses an external sign-in provider',
          );
        }
        await _request(
          'POST',
          issuer.resolve('dbconnections/change_password'),
          body: {
            'client_id': clientId,
            'email': email,
            'connection': connection,
          },
          decode: false,
        );
        return {};
      case 'deleteAccount':
        await _user('DELETE', actor.id);
        _retire(actor.id, actor.id);
        return {};
      case 'uploadPhoto':
        return {'url': await _savePhoto(actor.id, args['jpeg'] as String)};
      default:
        throw ArgumentError('Unknown account action');
    }
  }

  /// Whether the mutation writes shared profile data to Auth0.
  bool syncsMutation(EntityMutation mutation) =>
      managementEnabled &&
      mutation.type == groveUserEntity.type &&
      mutation.kind == MutationKind.update &&
      !mutation.id.endsWith('@clients') &&
      mutation.changes.any(
        (change) => const {'name', 'avatarUrl'}.contains(change.path.first),
      );

  /// Confirms a Grove profile edit with Auth0 before committing the mutation.
  Future<EntityRecord> syncMutation(
    EntityMutation mutation,
    AuthenticatedActor actor, {
    required void Function() authorize,
  }) => _serialize(mutation.id, () async {
    authorize();
    if (store.mutationReceipt(mutation, actor.id) case final receipt?) {
      return receipt;
    }
    // Validate the entire Grove mutation before changing the Auth0 profile.
    final proposed = commitMutation(
      store.registry,
      mutation,
      store.get(mutation.type, mutation.id),
      0,
    );
    final fields = {
      for (final entry in _profileFields.entries)
        if (const {'name', 'picture'}.contains(entry.key) &&
            mutation.changes.any((change) => change.path.first == entry.value))
          entry.key: proposed.data[entry.value],
    };
    if (fields.containsKey('name') &&
        ((fields['name'] as String?)?.trim().isEmpty ?? true)) {
      throw ArgumentError('Enter a display name');
    }
    if (fields.containsKey('picture')) {
      final picture = Uri.tryParse((fields['picture'] as String?) ?? '');
      if (picture == null ||
          picture.scheme != 'https' ||
          picture.host.isEmpty) {
        throw ArgumentError('Profile photo URL must use HTTPS');
      }
    }
    final result = await _user('PATCH', mutation.id, fields);
    return _mergeProfile(
      mutation.id,
      {for (final key in fields.keys) key: result[key] as String},
      actor: actor.id,
      explicit: fields.keys.toSet(),
      mutation: mutation,
      authorize: authorize,
    )!;
  });

  /// Fetches one page of Auth0's directory index.
  Future<Json> listUsers(int page, {String? query}) async {
    final url = issuer
        .resolve('api/v2/users')
        .replace(
          queryParameters: {
            'search_engine': 'v3',
            'page': '$page',
            'per_page': '100',
            'include_totals': 'true',
            'fields': 'user_id,updated_at',
            'include_fields': 'true',
            if (query != null) 'q': query,
          },
        );
    return _request('GET', url, token: await _token());
  }

  /// Profiles previously observed through the Management API.
  Set<String> get importedUserIds => store.database
      .select('SELECT id FROM auth0_user_profiles')
      .map((row) => row['id'] as String)
      .toSet();

  /// Refreshes a user by ID and returns whether an API lookup was needed.
  Future<bool> refreshUser(
    String id, {
    String? catalogVersion,
    bool confirmDeletion = false,
    Json reportedChanges = const {},
  }) => _serialize(id, () async {
    if (id.endsWith('@clients') ||
        (store.get(groveUserEntity.type, id)?.deleted ?? false)) {
      return false;
    }
    final known = store.database.select(
      'SELECT updated_at FROM auth0_user_profiles WHERE id = ?',
      [id],
    ).firstOrNull?['updated_at'];
    if (catalogVersion != null &&
        known == catalogVersion &&
        store.database.select(
          'SELECT 1 FROM profile_photo_uploads WHERE owner = ? LIMIT 1',
          [id],
        ).isEmpty) {
      return false;
    }
    final Json profile;
    try {
      profile = await _user('GET', id);
    } on GroveException catch (error) {
      if (error.code != 'not_found') rethrow;
      if (confirmDeletion || known != null) _retire(id, _identityActor);
      return true;
    }
    if (profile['user_id'] != id) {
      throw const GroveException('unavailable', 'Invalid Auth0 user profile');
    }
    _mergeProfile(
      id,
      {for (final field in _profileFields.keys) field: profile[field]},
      actor: _identityActor,
      updatedAt: profile['updated_at'] as String?,
      explicit: {
        for (final entry in reportedChanges.entries)
          if (profile[entry.key] == entry.value) entry.key,
      },
    );
    // A response can be lost after Auth0 applies a photo change. Retain
    // uncertain uploads until an authoritative refresh can clean them up.
    store.database.execute(
      'DELETE FROM profile_photo_uploads WHERE owner = ? AND created_at < ?',
      [
        id,
        DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      ],
    );
    return true;
  });

  void _requireLiveAccount(String id, AuthenticatedActor actor) {
    if (!actor.expiresAt.isAfter(DateTime.now()) ||
        (store.get(groveUserEntity.type, id)?.deleted ?? true)) {
      throw const GroveException('unauthenticated', 'Account is unavailable');
    }
  }

  EntityRecord? _mergeProfile(
    String id,
    Json profile, {
    required String actor,
    String? updatedAt,
    Set<String> explicit = const {},
    EntityMutation? mutation,
    void Function()? authorize,
  }) {
    final current = store.get(groveUserEntity.type, id);
    if (current?.deleted ?? false) return null;
    final saved =
        store.database.select(
              'SELECT data FROM auth0_user_profiles WHERE id = ?',
              [id],
            ).firstOrNull?['data']
            as String?;
    final previous = saved == null
        ? <String, dynamic>{}
        : jsonDecode(saved) as Json;
    final pendingPhoto = _pendingPhotoId(id, profile['picture'] as String?);
    final changes = <FieldChange>[
      ...?mutation?.changes.where(
        (change) => !profile.keys.any(
          (key) => _profileFields[key] == change.path.first,
        ),
      ),
    ];
    final imported = <String, dynamic>{...previous};
    for (final entry in profile.entries) {
      final field = _profileFields[entry.key]!;
      final remote = field == 'emailVerified'
          ? entry.value as bool?
          : entry.value as String?;
      imported[entry.key] = remote;
      final local = current?.data[field];
      if (local == remote) continue;
      final firstSeen = !previous.containsKey(entry.key);
      final keepLegacyValue =
          firstSeen &&
          local != null &&
          const {'name', 'avatarUrl'}.contains(field);
      if (explicit.contains(entry.key) ||
          (field == 'avatarUrl' && pendingPhoto != null) ||
          (firstSeen ? !keepLegacyValue : previous[entry.key] != remote)) {
        changes.add(FieldChange([field], remote));
      }
    }
    void saveRelatedRows() {
      store.database.execute(
        'REPLACE INTO auth0_user_profiles (id, updated_at, data) VALUES (?, ?, ?)',
        [id, updatedAt, jsonEncode(imported)],
      );
      if (pendingPhoto != null) _promotePhoto(pendingPhoto);
    }

    if (current != null && changes.isEmpty && mutation == null) {
      saveRelatedRows();
      return current;
    }
    final write =
        mutation ??
        EntityMutation(
          mutationId: const Uuid().v4(),
          type: groveUserEntity.type,
          id: id,
          version: groveUserEntity.version,
          kind: current == null ? MutationKind.create : MutationKind.update,
          data: current == null
              ? applyChanges(GroveUser(id: id).toJson(), changes)
              : null,
          changes: current == null ? const [] : changes,
        );
    return store.mutate(
      write,
      actor,
      authorize: authorize,
      writeRelatedRows: saveRelatedRows,
      confirmedChanges: mutation == null ? null : changes,
    );
  }

  void _retire(String id, String actor) {
    final record = store.get(groveUserEntity.type, id);
    if (record == null || record.deleted) return;
    store.mutate(
      EntityMutation(
        mutationId: const Uuid().v4(),
        type: groveUserEntity.type,
        id: id,
        version: groveUserEntity.version,
        kind: MutationKind.delete,
      ),
      actor,
      writeRelatedRows: () {
        store.database.execute('DELETE FROM profile_photos WHERE owner = ?', [
          id,
        ]);
        store.database.execute(
          'DELETE FROM profile_photo_uploads WHERE owner = ?',
          [id],
        );
        store.database.execute('DELETE FROM auth0_user_profiles WHERE id = ?', [
          id,
        ]);
      },
    );
  }

  Future<String> _savePhoto(String owner, String encoded) async {
    final base = publicApiUrl;
    if (base == null || base.scheme != 'https' || !base.path.endsWith('/')) {
      throw const GroveException(
        'unavailable',
        'Photo publishing is not configured',
      );
    }
    final bytes = base64Decode(encoded);
    if (bytes.length < 4 ||
        bytes.length > 2 * 1024 * 1024 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes.last != 0xd9) {
      throw ArgumentError('Upload a JPEG photo under 2 MiB');
    }
    final id = const Uuid().v4();
    final url = base.resolve('account/photo/$id').toString();
    if (managementEnabled) {
      // Keep the old URL live while the new photo is being published to Auth0.
      store.database.execute(
        '''INSERT INTO profile_photo_uploads (id, owner, photo, created_at)
           VALUES (?, ?, ?, ?)''',
        [id, owner, bytes, DateTime.now().millisecondsSinceEpoch],
      );
      final Json result;
      try {
        result = await _user('PATCH', owner, {'picture': url});
      } on _Auth0HttpError catch (error) {
        if (error.statusCode >= 400 && error.statusCode < 500) {
          store.database.execute(
            'DELETE FROM profile_photo_uploads WHERE id = ?',
            [id],
          );
        }
        rethrow;
      }
      final picture = result['picture'] as String;
      _mergeProfile(
        owner,
        {'picture': picture},
        actor: owner,
        explicit: const {'picture'},
      );
      return picture;
    }
    store.mutate(
      EntityMutation(
        mutationId: const Uuid().v4(),
        type: groveUserEntity.type,
        id: owner,
        version: groveUserEntity.version,
        kind: MutationKind.update,
        changes: [
          FieldChange(['avatarUrl'], url),
        ],
      ),
      owner,
      writeRelatedRows: () {
        store.database.execute(
          'INSERT OR REPLACE INTO profile_photos (id, owner, photo) VALUES (?, ?, ?)',
          [id, owner, bytes],
        );
      },
    );
    return url;
  }

  String? _pendingPhotoId(String owner, String? url) {
    final base = publicApiUrl;
    if (base == null || url == null) return null;
    final id = Uri.tryParse(url)?.pathSegments.lastOrNull;
    if (id == null || base.resolve('account/photo/$id').toString() != url) {
      return null;
    }
    return store.database.select(
          'SELECT id FROM profile_photo_uploads WHERE id = ? AND owner = ?',
          [id, owner],
        ).isEmpty
        ? null
        : id;
  }

  void _promotePhoto(String id) {
    store.database.execute(
      '''
INSERT OR REPLACE INTO profile_photos (id, owner, photo)
SELECT id, owner, photo FROM profile_photo_uploads WHERE id = ?
''',
      [id],
    );
    store.database.execute('DELETE FROM profile_photo_uploads WHERE id = ?', [
      id,
    ]);
  }

  Uint8List? photo(String id) =>
      store.database
              .select(
                '''SELECT photo FROM profile_photos WHERE id = ?
               UNION ALL SELECT photo FROM profile_photo_uploads WHERE id = ?''',
                [id, id],
              )
              .firstOrNull?['photo']
          as Uint8List?;

  Future<Json> _user(String method, String id, [Json? body]) async => _request(
    method,
    issuer.resolve('api/v2/users/${Uri.encodeComponent(id)}'),
    body: body,
    token: await _token(),
    allowMissing: method == 'DELETE',
    missingIsNotFound: method == 'GET',
  );

  Future<String> _token() async {
    final current = _managementToken;
    if (current != null && current.expires.isAfter(DateTime.now())) {
      return current.token;
    }
    return _loadingToken ??= _fetchToken().whenComplete(
      () => _loadingToken = null,
    );
  }

  Future<String> _fetchToken() async {
    final id = managementClientId;
    final secret = managementClientSecret;
    if (id == null || id.isEmpty || secret == null || secret.isEmpty) {
      throw const GroveException(
        'unavailable',
        'Auth0 management is not configured',
      );
    }
    final payload = await _request(
      'POST',
      issuer.resolve('oauth/token'),
      body: {
        'grant_type': 'client_credentials',
        'client_id': id,
        'client_secret': secret,
        'audience': issuer.resolve('api/v2/').toString(),
      },
    );
    final token = payload['access_token'] as String;
    final seconds = payload['expires_in'] as int;
    _managementToken = (
      token: token,
      expires: DateTime.now().add(Duration(seconds: seconds - 30)),
    );
    return token;
  }

  Future<Json> _request(
    String method,
    Uri uri, {
    Json? body,
    String? token,
    bool decode = true,
    bool allowMissing = false,
    bool missingIsNotFound = false,
  }) async {
    try {
      final request = http.Request(method, uri)..followRedirects = false;
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      if (token != null) request.headers['authorization'] = 'Bearer $token';
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 10));
      if (allowMissing && response.statusCode == 404) return {};
      if (missingIsNotFound && response.statusCode == 404) {
        throw const GroveException('not_found', 'Auth0 account does not exist');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 409 &&
            (body?.containsKey('email') ?? false)) {
          throw const GroveException(
            'conflict',
            'Email address is already in use',
          );
        }
        throw _Auth0HttpError(response.statusCode);
      }
      return decode && response.body.isNotEmpty
          ? jsonDecode(response.body) as Json
          : {};
    } on TimeoutException {
      throw const GroveException('unavailable', 'Auth0 did not respond');
    } on http.ClientException {
      throw const GroveException('unavailable', 'Auth0 is unavailable');
    }
  }
}

class _Auth0HttpError extends GroveException {
  _Auth0HttpError(this.statusCode)
    : super(
        'unavailable',
        'Auth0 could not complete the account operation (HTTP $statusCode)',
      );

  final int statusCode;
}
