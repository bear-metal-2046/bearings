import 'package:core/core.dart';
import 'package:grove/grove.dart';

import 'entity_store.dart';
import 'gamepack_mutations.dart';

class AuthenticatedActor {
  const AuthenticatedActor(this.id, {required this.expiresAt, this.clientId});
  final String id;
  final DateTime expiresAt;
  final String? clientId;
}

class EntityAuthorization {
  EntityAuthorization(this.store, {this.bootstrapSubject});
  final EntityStore store;

  /// Explicit Auth0 subject configured by the operator, never first-user-wins.
  final String? bootstrapSubject;
  Set<String> get capabilities => bearingsPermissions(store.registry).toSet();

  Set<String> permissions(AuthenticatedActor actor) {
    if (!actor.expiresAt.isAfter(DateTime.now()))
      throw const GroveException('unauthenticated', 'Access token expired');
    final userRecord = store.get('identity.user', actor.id);
    if (userRecord?.deleted ?? false) {
      throw const GroveException('unauthenticated', 'Account has been deleted');
    }
    if (bootstrapSubject != null && actor.id == bootstrapSubject)
      return capabilities;
    if (userRecord == null) return {};
    final user = GroveUser.fromJson(userRecord.data);
    final result = <String>{};
    for (final reference in user.roles) {
      final role = store.get('authorization.role', reference.id);
      if (role != null && !role.deleted)
        result.addAll(GroveRole.fromJson(role.data).permissions);
    }
    return result;
  }

  void read(AuthenticatedActor actor, QueryDescription query) {
    final allowed = permissions(actor);
    _requireLiveEntity(query.type);
    final capability = switch (query.type) {
      'gamepack' || 'gamepack.binding' => gamePackReadPermission,
      _ when store.registry.isServerManaged(query.type) =>
        competitionReadPermission,
      _ => '${query.type}.read',
    };
    if (allowed.contains(capability)) return;
    if (query.type == gamePackObservationEntity.type &&
        allowed.contains(gamePackSubmitPermission) &&
        allowed.contains(gamePackReadPermission) &&
        query.filters.any(
          (f) =>
              f.field == 'author' &&
              f.operator == FilterOperator.equal &&
              f.value == actor.id,
        )) {
      return;
    }
    final idFilters = query.filters
        .where((f) => f.field == 'id' && f.operator == FilterOperator.equal)
        .toList();
    if (idFilters.length == 1) {
      final id = idFilters.single.value;
      if ((query.type == 'identity.user' ||
              query.type == 'authorization.access') &&
          id == actor.id)
        return;
      if (query.type == 'authorization.role') {
        final user = store.get('identity.user', actor.id);
        if (user != null &&
            !user.deleted &&
            GroveUser.fromJson(user.data).roles.any((r) => r.id == id))
          return;
      }
    }
    throw const GroveException('forbidden', 'Entity read capability required');
  }

  QuerySnapshot query(AuthenticatedActor actor, QueryDescription query) {
    read(actor, query);
    if (query.type != 'authorization.access') return store.query(query);
    return schemaQuery(store.registry, query, [
      EntityRecord(
        type: query.type,
        id: actor.id,
        version: 1,
        data: GroveAccess(actor.id, permissions(actor)).toJson(),
      ),
    ], store.revision);
  }

  bool _isOwnObservationCorrection(
    AuthenticatedActor actor,
    EntityMutation mutation,
    String parentId,
  ) {
    final parent = store.get(gamePackObservationEntity.type, parentId);
    final data = mutation.data!;
    return parent != null &&
        !parent.deleted &&
        parent.data['author'] == actor.id &&
        parent.data['scout'] == data['scout'] &&
        parent.data['retracted'] != true &&
        data['retracted'] != true;
  }

  void mutate(AuthenticatedActor actor, EntityMutation mutation) {
    final allowed = permissions(actor);
    _requireLiveEntity(mutation.type);
    if (mutation.type == gamePackEntity.type) {
      if (!allowed.contains(gamePackManagePermission)) {
        throw const GroveException(
          'forbidden',
          'GamePack manage permission required',
        );
      }
      if (mutation.kind != MutationKind.create) {
        read(
          actor,
          QueryDescription(
            type: gamePackEntity.type,
            filters: [
              QueryFilter('id', FilterOperator.equal, mutation.id),
            ],
          ),
        );
      }
      authorizeGamePackUpdate(store, mutation);
      return;
    }
    if (mutation.type == eventGamePackEntity.type) {
      if (!allowed.contains(gamePackManagePermission)) {
        throw const GroveException(
          'forbidden',
          'GamePack manage permission required',
        );
      }
      if (mutation.kind != MutationKind.create) {
        read(
          actor,
          QueryDescription(
            type: eventGamePackEntity.type,
            filters: [
              QueryFilter('id', FilterOperator.equal, mutation.id),
            ],
          ),
        );
      }
      authorizeEventGamePackMutation(store, mutation);
      return;
    }
    if (mutation.type == gamePackObservationEntity.type) {
      final parentId = mutation.data?['supersedes'];
      final isCorrection = parentId is String;
      final canCorrect =
          allowed.contains(gamePackCorrectPermission) &&
          allowed.contains(gamePackObservationReadPermission);
      final canSubmit = allowed.contains(gamePackSubmitPermission);
      if (!allowed.contains(gamePackReadPermission) ||
          (isCorrection
              ? !canCorrect &&
                    !(canSubmit &&
                        _isOwnObservationCorrection(actor, mutation, parentId))
              : !canSubmit)) {
        throw const GroveException(
          'forbidden',
          'GamePack observation permission required',
        );
      }
      authorizeGamePackObservationMutation(mutation);
      return;
    }
    if (store.registry.isServerManaged(mutation.type)) {
      throw const GroveException(
        'forbidden',
        'Server-managed entities are read-only',
      );
    }
    if (mutation.type == groveUserEntity.type &&
        (mutation.changes.any(
              (change) =>
                  const {'email', 'emailVerified'}.contains(change.path.first),
            ) ||
            mutation.data?['email'] != null ||
            mutation.data?['emailVerified'] != null)) {
      throw const GroveException(
        'forbidden',
        'Email updates require the identity service',
      );
    }
    final selfProfileEdit =
        mutation.type == 'identity.user' &&
        mutation.id == actor.id &&
        mutation.kind == MutationKind.update &&
        mutation.changes.every(
          (c) =>
              c.path.length == 1 &&
              const {'name', 'avatarUrl'}.contains(c.path.first),
        );
    if (selfProfileEdit) return;
    if (!allowed.contains('${mutation.type}.mutate'))
      throw const GroveException(
        'forbidden',
        'Entity mutate capability required',
      );
    if (mutation.kind != MutationKind.create) {
      // Update/delete receipts contain the affected row. A mutate grant alone
      // cannot be used to obtain records the actor cannot read.
      read(
        actor,
        QueryDescription(
          type: mutation.type,
          filters: [QueryFilter('id', FilterOperator.equal, mutation.id)],
        ),
      );
    }
    if (mutation.type == 'strategy.picklist' &&
        mutation.kind == MutationKind.update) {
      final previous = _liveData(store.get(mutation.type, mutation.id));
      final history = previous['teamChanges'] as Map;
      for (final change in mutation.changes) {
        if (change.path.first != 'teamChanges') continue;
        if (change.path.length != 2 ||
            change.remove ||
            (history.containsKey(change.path.last) &&
                history[change.path.last] != change.value)) {
          throw ArgumentError('Picklist operations are immutable');
        }
      }
    }
    if (mutation.type == 'authorization.role' &&
        mutation.kind != MutationKind.delete) {
      final current = store.get(mutation.type, mutation.id);
      final data = mutation.kind == MutationKind.create
          ? mutation.data!
          : applyChanges(_liveData(current), mutation.changes);
      final role = GroveRole.fromJson(data);
      final old = current == null
          ? <String>{}
          : GroveRole.fromJson(current.data).permissions.toSet();
      // Editing an existing more privileged role is also a delegation of its
      // permissions. Require authority over both removed and retained grants.
      if (!allowed.containsAll({...role.permissions, ...old}) ||
          !capabilities.containsAll(role.permissions)) {
        throw const GroveException(
          'forbidden',
          'Cannot delegate permissions you do not hold',
        );
      }
    }
    if (mutation.type == 'authorization.role' &&
        mutation.kind == MutationKind.delete) {
      final current = store.get(mutation.type, mutation.id);
      if (current != null &&
          !allowed.containsAll(GroveRole.fromJson(current.data).permissions)) {
        throw const GroveException(
          'forbidden',
          'Cannot remove a more privileged role',
        );
      }
    }
    if (mutation.type == 'identity.user') {
      if (mutation.kind == MutationKind.delete) {
        throw const GroveException(
          'forbidden',
          'Account deletion requires the identity service',
        );
      }
      final current = store.get(mutation.type, mutation.id);
      final data = mutation.kind == MutationKind.create
          ? mutation.data!
          : applyChanges(_liveData(current), mutation.changes);
      final user = GroveUser.fromJson(data);
      final old = current == null
          ? <EntityRef<GroveRole>>[]
          : GroveUser.fromJson(current.data).roles;
      for (final ref in old) {
        final role = store.get('authorization.role', ref.id);
        if (role != null &&
            !role.deleted &&
            !allowed.containsAll(GroveRole.fromJson(role.data).permissions)) {
          throw const GroveException(
            'forbidden',
            'Cannot edit a more privileged user',
          );
        }
      }
      for (final ref in user.roles) {
        final role = store.get('authorization.role', ref.id);
        if (role == null ||
            role.deleted ||
            !allowed.containsAll(GroveRole.fromJson(role.data).permissions)) {
          throw const GroveException(
            'forbidden',
            'Cannot assign a missing or more privileged role',
          );
        }
      }
    }
  }

  Json _liveData(EntityRecord? record) {
    if (record == null || record.deleted)
      throw const GroveException('not_found', 'Entity does not exist');
    return record.data;
  }

  void _requireLiveEntity(String type) {
    if (type == 'scouting.report') {
      throw const GroveException(
        'unsupported_schema',
        'Legacy scouting reports are retired. Use the event GamePack.',
      );
    }
  }
}
