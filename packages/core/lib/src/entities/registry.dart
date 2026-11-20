import 'package:grove/grove.dart';

import 'authorization/access.dart';
import 'authorization/role.dart';
import 'competition/competition_entities.dart';
import 'identity/user.dart';
import 'scouting/report.dart';
import 'scouting/scout.dart';
import 'strategy/picklist.dart';

const competitionReadPermission = 'external.read';
const deviceProvisionPermission = 'device.provision';

Iterable<String> bearingsPermissions(EntityRegistry registry) sync* {
  yield competitionReadPermission;
  yield deviceProvisionPermission;
  for (final descriptor in registry.descriptors) {
    if (descriptor.type == groveAccessEntity.type || descriptor.serverManaged) {
      continue;
    }
    yield '${descriptor.type}.read';
    yield '${descriptor.type}.mutate';
  }
}

EntityRegistry bearingsEntityRegistry() {
  final registry = EntityRegistry()
    ..register(grovePicklistEntity)
    ..register(scoutingReportEntity)
    ..register(scoutEntity)
    ..register(groveUserEntity)
    ..register(groveRoleEntity)
    ..register(groveAccessEntity);
  registerCompetitionEntities(registry);
  return registry;
}
