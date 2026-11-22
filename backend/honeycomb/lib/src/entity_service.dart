import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';
import 'package:grove/grove.dart';

import 'account_service.dart';
import 'authentication.dart';
import 'authorization.dart';
import 'competition_sources.dart';
import 'entity_store.dart';
import 'gamepack_mutations.dart';
import 'nexus_sync.dart';

class EntityService {
  EntityService({
    required this.store,
    required this.authenticate,
    String? bootstrapSubject,
    this.competitionSources,
    this.nexus,
    this.accounts,
  }) : authorization = EntityAuthorization(
         store,
         bootstrapSubject: bootstrapSubject,
       ) {
    store.changes.listen((type) {
      final authorizationChanged =
          type == 'identity.user' || type == 'authorization.role';
      for (final room in _presence.keys.toList()) {
        if (authorizationChanged || room.$1 == type) _publishPresence(room);
      }
    });
  }
  final EntityStore store;
  final AuthenticateToken authenticate;
  final EntityAuthorization authorization;
  final CompetitionSources? competitionSources;
  final NexusSync? nexus;
  final AccountService? accounts;
  final _connections = <WebSocketChannel>{};
  final _presence = <(String, String), Set<_PresenceMember>>{};

  bool _canObserve(AuthenticatedActor actor, (String, String) room) {
    try {
      authorization.read(
        actor,
        QueryDescription(
          type: room.$1,
          filters: [QueryFilter('id', FilterOperator.equal, room.$2)],
        ),
      );
      final record = store.get(room.$1, room.$2);
      return record != null && !record.deleted;
    } on GroveException {
      return false;
    }
  }

  void _publishPresence((String, String) room) {
    final members = _presence[room];
    if (members == null) return;
    final allowed = members
        .where((member) => _canObserve(member.actor, room))
        .toSet();
    final peers = <String, GrovePresencePeer>{};
    for (final member in allowed) {
      final id = member.actor.id;
      final record = store.get('identity.user', id);
      final user = record == null || record.deleted
          ? null
          : GroveUser.fromJson(record.data);
      peers[id] = GrovePresencePeer(
        id,
        name: user?.name,
        avatarUrl: user?.avatarUrl,
      );
    }
    for (final member in members) {
      member.send({
        'op': 'presence',
        'id': member.id,
        'peers': [
          if (allowed.contains(member))
            for (final peer in peers.values)
              if (peer.id != member.actor.id) peer.toJson(),
        ],
      });
    }
  }

  Handler get handler =>
      webSocketHandler(_connect, pingInterval: const Duration(seconds: 20));

  void _connect(WebSocketChannel channel, String? protocol) {
    _connections.add(channel);
    AuthenticatedActor? actor;
    final queries = <String, QueryDescription>{};
    final sent = <String, String>{};
    final members = <String, _PresenceMember>{};
    void leavePresence(String id) {
      final member = members.remove(id);
      if (member == null) return;
      final room = _presence[member.room]!;
      room.remove(member);
      if (room.isEmpty) {
        _presence.remove(member.room);
      } else {
        _publishPresence(member.room);
      }
    }

    var closed = false;
    var pendingCompetition = 0;
    Timer? expiration;
    final authenticationTimeout = Timer(const Duration(seconds: 10), () {
      if (actor == null)
        unawaited(channel.sink.close(4401, 'Authentication required'));
    });
    void send(Json message) {
      if (!closed) channel.sink.add(jsonEncode(message));
    }

    void error(String? id, Object error) {
      final code = switch (error) {
        GroveException e => e.code,
        UnsupportedSchema _ => 'unsupported_schema',
        ArgumentError _ ||
        FormatException _ ||
        TypeError _ => 'invalid_request',
        _ => 'internal',
      };
      send({
        'op': 'error',
        'id': id,
        'code': code,
        'message': error is GroveException
            ? error.message
            : code == 'internal'
            ? 'Entity service failed'
            : error.toString(),
      });
    }

    Future<void> loadCompetition(
      String id,
      AuthenticatedActor actor,
      Json message,
    ) async {
      try {
        if (!authorization
            .permissions(actor)
            .contains(competitionReadPermission)) {
          throw const GroveException(
            'forbidden',
            'Competition read capability required',
          );
        }
        final sources = competitionSources;
        if (sources == null) {
          throw const GroveException(
            'unavailable',
            'Competition sources are not configured',
          );
        }
        final data = await sources.load(
          message['resource'] as String,
          message['arguments'] as Json,
        );
        if (!authorization
            .permissions(actor)
            .contains(competitionReadPermission)) {
          throw const GroveException(
            'forbidden',
            'Competition read capability required',
          );
        }
        send({
          'op': 'result',
          'id': id,
          'result': {'data': data},
        });
      } catch (failure) {
        error(id, failure);
      }
    }

    void snapshot(String id, QueryDescription query, {bool refresh = false}) {
      try {
        final result = authorization.query(actor!, query);
        if (refresh) nexus?.onRead(query);
        final fingerprint = canonicalJson(
          result.records.map((r) => r.toJson()).toList(),
        );
        if (sent[id] == fingerprint) return;
        sent[id] = fingerprint;
        send({'op': 'snapshot', 'id': id, 'result': result.toJson()});
      } catch (failure) {
        // Keep denied queries subscribed so a later role grant can restore them.
        final fingerprint = 'error:$failure';
        if (sent[id] != fingerprint) error(id, failure);
        sent[id] = fingerprint;
      }
    }

    final changes = store.changes.listen((type) {
      final authorizationChanged =
          type == 'identity.user' || type == 'authorization.role';
      for (final entry in queries.entries.toList()) {
        if (authorizationChanged || entry.value.type == type)
          snapshot(entry.key, entry.value);
      }
    });
    final externalChanges = store.externalChanges.listen((change) {
      for (final entry in queries.entries.toList()) {
        if (change.affects(entry.value)) snapshot(entry.key, entry.value);
      }
    });
    Future<void> tail = Future.value();
    channel.stream.listen(
      (dynamic raw) {
        final Json message;
        final String? id;
        try {
          if (raw is! String || raw.length > 4 * 1024 * 1024) {
            throw ArgumentError('Invalid message size');
          }
          message = jsonDecode(raw) as Json;
          id = message['id'] as String?;
        } catch (failure) {
          error(null, failure);
          return;
        }
        final op = message['op'];
        // Long account operations must not delay the connection check.
        if (op == 'ping' && actor != null) {
          try {
            authorization.permissions(actor!);
            if (id == null || id.length > 200) {
              throw ArgumentError('Request ID required');
            }
            send({'op': 'pong', 'id': id});
          } catch (failure) {
            error(id, failure);
          }
          return;
        }
        tail = tail.then((_) async {
          try {
            if (actor == null) {
              if (op != 'authenticate')
                throw const GroveException(
                  'unauthenticated',
                  'Authenticate first',
                );
              actor = await authenticate(message['token'] as String);
              if (closed) return;
              // Keep sign-in available while the Auth0 directory is syncing.
              if (store.get('identity.user', actor!.id) == null) {
                store.mutate(
                  EntityMutation(
                    mutationId: 'provision:${actor!.id}',
                    type: 'identity.user',
                    id: actor!.id,
                    version: 1,
                    kind: MutationKind.create,
                    data: GroveUser(id: actor!.id).toJson(),
                  ),
                  'honeycomb:identity',
                );
              }
              authorization.permissions(actor!);
              authenticationTimeout.cancel();
              final remaining = actor!.expiresAt.difference(DateTime.now());
              if (remaining <= Duration.zero)
                throw const GroveException('unauthenticated', 'Token expired');
              expiration = Timer(
                remaining,
                () => channel.sink.close(4401, 'Token expired'),
              );
              send({'op': 'ready', 'heartbeat': true});
              return;
            }
            authorization.permissions(
              actor!,
            ); // Re-check expiry on every operation.
            if (id == null || id.length > 200)
              throw ArgumentError('Request ID required');
            switch (op) {
              case 'joinPresence':
                if (members.length >= 16 && !members.containsKey(id)) {
                  throw ArgumentError('Too many presence subscriptions');
                }
                final type = message['type'] as String;
                store.registry.named(type);
                final entityId = message['entityId'] as String;
                if (entityId.isEmpty || entityId.length > 256) {
                  throw ArgumentError('Invalid presence entity ID');
                }
                final room = (type, entityId);
                leavePresence(id);
                final member = _PresenceMember(id, actor!, room, send);
                members[id] = member;
                (_presence[room] ??= {}).add(member);
                _publishPresence(room);
              case 'leavePresence':
                leavePresence(id);
              case 'unsubscribe':
                queries.remove(id);
                sent.remove(id);
              case 'subscribe':
                if (queries.length >= 128 && !queries.containsKey(id))
                  throw ArgumentError('Too many subscriptions');
                final query = QueryDescription.fromJson(
                  message['query'] as Json,
                );
                sent.remove(id);
                queries[id] = query;
                snapshot(id, query, refresh: true);
              case 'account':
                final service = accounts;
                if (service == null) {
                  throw const GroveException(
                    'unavailable',
                    'Account service is not configured',
                  );
                }
                final action = message['action'] as String;
                final Json result;
                if (action == 'deviceCredentials') {
                  if (actor!.id.endsWith('@clients') ||
                      !authorization
                          .permissions(actor!)
                          .contains(deviceProvisionPermission)) {
                    throw const GroveException(
                      'forbidden',
                      'Device provisioning capability required',
                    );
                  }
                  final credentials = service.deviceCredentials;
                  if (credentials == null) {
                    throw const GroveException(
                      'unavailable',
                      'Device provisioning is not configured',
                    );
                  }
                  result = credentials;
                } else {
                  result = await service.run(
                    actor!,
                    action,
                    message['arguments'] as Json,
                  );
                }
                send({'op': 'result', 'id': id, 'result': result});
              case 'competition':
                if (pendingCompetition >= 8) {
                  throw const GroveException(
                    'unavailable',
                    'Too many competition requests',
                  );
                }
                pendingCompetition++;
                unawaited(
                  loadCompetition(id, actor!, message).whenComplete(() {
                    pendingCompetition--;
                  }),
                );
              case 'query':
                final query = QueryDescription.fromJson(
                  message['query'] as Json,
                );
                final result = authorization.query(actor!, query);
                nexus?.onRead(query);
                send({
                  'op': 'result',
                  'id': id,
                  'result': result.toJson(),
                });
              case 'mutate':
                final mutation = EntityMutation.fromJson(
                  message['mutation'] as Json,
                );
                void authorize() => authorization.mutate(actor!, mutation);
                final accountService = accounts;
                final result = accountService?.syncsMutation(mutation) == true
                    ? await accountService!.syncMutation(
                        mutation,
                        actor!,
                        authorize: authorize,
                      )
                    : store.mutate(
                        mutation,
                        actor!.id,
                        authorize: authorize,
                        confirmCreate: gamePackCreateConfirmation(
                          store,
                          mutation,
                          actor!.id,
                        ),
                      );
                send({'op': 'result', 'id': id, 'result': result.toJson()});
              default:
                throw ArgumentError('Unknown Grove operation');
            }
          } catch (failure) {
            error(id, failure);
          }
        });
      },
      onError: (Object _) {},
      onDone: () {
        closed = true;
        authenticationTimeout.cancel();
        expiration?.cancel();
        unawaited(changes.cancel());
        unawaited(externalChanges.cancel());
        for (final id in members.keys.toList()) {
          leavePresence(id);
        }
        _connections.remove(channel);
      },
    );
  }

  /// Close connections for shutdown; clients recover using new full snapshots.
  Future<void> disconnectClients() async {
    await Future.wait(
      _connections.toList().map(
        (channel) => channel.sink.close(4001, 'Reconnect'),
      ),
    );
  }
}

class _PresenceMember {
  const _PresenceMember(this.id, this.actor, this.room, this.send);

  final String id;
  final AuthenticatedActor actor;
  final (String, String) room;
  final void Function(Json) send;
}
