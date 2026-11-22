import 'package:grove/grove.dart';

import 'authorization/access.dart';
import 'authorization/role.dart';
import 'competition/competition_entities.dart';
import 'gamepack/gamepack_entities.dart';
import 'identity/user.dart';
import 'scouting/scout.dart';
import 'strategy/picklist.dart';

const competitionReadPermission = 'external.read';
const deviceProvisionPermission = 'device.provision';

Iterable<String> bearingsPermissions(EntityRegistry registry) sync* {
  yield competitionReadPermission;
  yield deviceProvisionPermission;
  yield gamePackReadPermission;
  yield gamePackPublishPermission;
  yield gamePackObservationReadPermission;
  yield gamePackSubmitPermission;
  yield gamePackCorrectPermission;
  for (final descriptor in registry.descriptors) {
    if (descriptor.type == groveAccessEntity.type ||
        descriptor.type == gamePackReleaseEntity.type ||
        descriptor.type == gamePackDraftEntity.type ||
        descriptor.type == eventGamePackEntity.type ||
        descriptor.type == gamePackObservationEntity.type ||
        descriptor.serverManaged) {
      continue;
    }
    yield '${descriptor.type}.read';
    yield '${descriptor.type}.mutate';
  }
}

EntityRegistry bearingsEntityRegistry() {
  final registry = EntityRegistry()
    ..register(gamePackDraftEntity)
    ..register(gamePackReleaseEntity)
    ..register(tbaMatchRevisionEntity)
    ..register(eventGamePackEntity)
    ..register(gamePackObservationEntity)
    ..register(grovePicklistEntity)
    ..register(scoutEntity)
    ..register(groveUserEntity)
    ..register(groveRoleEntity)
    ..register(groveAccessEntity);
  registerCompetitionEntities(registry);
  return registry;
}
