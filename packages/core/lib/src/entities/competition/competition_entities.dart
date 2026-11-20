import 'package:grove/grove.dart';

import '../../utils/nexus_match_key.dart';

part 'competition_entities.g.dart';
part 'teams.dart';
part 'events.dart';
part 'matches.dart';
part 'rankings.dart';
part 'playoffs.dart';
part 'awards.dart';
part 'districts.dart';
part 'advancement.dart';
part 'media.dart';
part 'pit_layout.dart';
part 'queue_summary.dart';
part 'event_status.dart';

void registerCompetitionEntities(EntityRegistry registry) {
  registry
    ..register(competitionTeamEntity)
    ..register(teamSeasonEntity)
    ..register(competitionEventEntity)
    ..register(eventTeamEntity)
    ..register(competitionMatchEntity)
    ..register(eventRankingEntity)
    ..register(playoffAllianceEntity)
    ..register(eventTeamStatusEntity)
    ..register(eventAwardEntity)
    ..register(districtEntity)
    ..register(districtTeamEntity)
    ..register(advancementRankingEntity)
    ..register(eventPointsEntity)
    ..register(advancementEntity)
    ..register(advancementCutoffsEntity)
    ..register(playoffAdvancementEntity)
    ..register(teamRobotEntity)
    ..register(competitionMediaEntity)
    ..register(mediaTagEntity)
    ..register(pitLayoutEntity)
    ..register(eventQueueSummaryEntity)
    ..register(eventStatusSnapshotEntity);
}
