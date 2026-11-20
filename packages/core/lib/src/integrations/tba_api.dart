import 'package:grove/grove.dart';

import '../entities/competition/competition_entities.dart';
import 'pit_map.dart';

const firstMirroredTbaSeason = 2026;

int? tbaSeason(String key) =>
    key.length < 4 ? null : int.tryParse(key.substring(0, 4));

bool isMirroredTbaKey(String key) =>
    (tbaSeason(key) ?? 0) >= firstMirroredTbaSeason;

/// Converts public TBA v3 response fields at the API boundary.
abstract final class TbaApi {
  static CompetitionTeam team(Json data) {
    final key = data['key'] as String;
    return CompetitionTeam(
      id: key,
      number:
          data['team_number'] as int? ??
          int.parse(RegExp(r'\d+').firstMatch(key)!.group(0)!),
      nickname: data['nickname'] as String?,
      name: data['name'] as String?,
      schoolName: data['school_name'] as String?,
      location: _location(data),
      website: data['website'] as String?,
      rookieYear: data['rookie_year'] as int?,
      motto: data['motto'] as String?,
    );
  }

  static CompetitionEvent event(Json data) {
    final key = data['key'] as String;
    return CompetitionEvent(
      id: key,
      season: data['year'] as int? ?? tbaSeason(key)!,
      name: data['name'] as String? ?? key,
      code: data['event_code'] as String? ?? key.substring(4),
      eventType: data['event_type'] as int?,
      eventTypeName: data['event_type_string'] as String?,
      shortName: data['short_name'] as String?,
      week: data['week'] as int?,
      startDate: _calendarDate(data['start_date']),
      endDate: _calendarDate(data['end_date']),
      location: _location(data),
      timezone: data['timezone'] as String?,
      website: data['website'] as String?,
      firstEventId: data['first_event_id'] as String?,
      firstEventCode: data['first_event_code'] as String?,
      district: _ref<District>((data['district'] as Json?)?['key']),
      parent: _ref<CompetitionEvent>(data['parent_event_key']),
      divisions: _refs<CompetitionEvent>(data['division_keys']),
      playoffType: data['playoff_type'] as int?,
      playoffTypeName: data['playoff_type_string'] as String?,
      webcasts: _list(
        data['webcasts'],
        (item) => EventWebcast(
          type: item['type'] as String,
          channel: item['channel'] as String,
          date: item['date'] as String?,
          file: item['file'] as String?,
          status: item['status'] as String?,
          streamTitle: item['stream_title'] as String?,
          viewerCount: item['viewer_count'] as int?,
        ),
      ),
      remappedTeams:
          (data['remap_teams'] as Map?)?.cast<String, String>() ?? const {},
    );
  }

  static CompetitionLocation _location(Json data) => CompetitionLocation(
    city: data['city'] as String?,
    stateProvince: data['state_prov'] as String?,
    country: data['country'] as String?,
    address: data['address'] as String?,
    postalCode: data['postal_code'] as String?,
    name: data['location_name'] as String?,
    mapsPlaceId: data['gmaps_place_id'] as String?,
    mapsUrl: data['gmaps_url'] as String?,
    latitude: _double(data['lat']),
    longitude: _double(data['lng']),
  );

  static CompetitionMatch match(Json data, {bool? practice}) {
    final key = data['key'] as String;
    final event = data['event_key'] as String? ?? key.split('_').first;
    final level = data['comp_level'] as String? ?? '';
    final alliances = data['alliances'] as Json?;
    final breakdown = data['score_breakdown'] as Json?;
    final red = _alliance(
      alliances?['red'] as Json?,
      breakdown?['red'] as Json?,
    );
    final blue = _alliance(
      alliances?['blue'] as Json?,
      breakdown?['blue'] as Json?,
    );
    final teams = {
      for (final team in [...?red?.teams, ...?blue?.teams]) team.id,
    }.toList()..sort();
    return CompetitionMatch(
      id: key,
      season: tbaSeason(event)!,
      event: EntityRef(event),
      level: level,
      setNumber: data['set_number'] as int? ?? 1,
      matchNumber: data['match_number'] as int? ?? 0,
      practice: practice ?? level == 'pm',
      teams: teams.map(EntityRef<CompetitionTeam>.new).toList(),
      red: red,
      blue: blue,
      winningAlliance: data['winning_alliance'] as String?,
      scheduledAt: _timestamp(data['time']),
      predictedAt: _timestamp(data['predicted_time']),
      playedAt: _timestamp(data['actual_time']),
      resultPostedAt: _timestamp(data['post_result_time']),
      videos: _list(
        data['videos'],
        (item) => MatchVideo(
          type: item['type'] as String,
          key: item['key'] as String,
        ),
      ),
    );
  }

  static CompetitionAlliance? _alliance(Json? data, Json? breakdown) =>
      data == null
      ? null
      : CompetitionAlliance(
          teams: _refs(data['team_keys']),
          surrogateTeams: _refs(data['surrogate_team_keys']),
          disqualifiedTeams: _refs(data['dq_team_keys']),
          score: data['score'] as int?,
          gameBreakdown: breakdown,
        );

  static List<EventRanking> rankings(String event, Json? data) => _list(
    data?['rankings'],
    (item) => ranking(
      event,
      item,
      sortOrderInfo: _metrics(data?['sort_order_info']),
      extraStatsInfo: _metrics(data?['extra_stats_info']),
    ),
  );

  static EventRanking ranking(
    String event,
    Json data, {
    List<RankingMetric> sortOrderInfo = const [],
    List<RankingMetric> extraStatsInfo = const [],
  }) {
    final team = data['team_key'] as String;
    return EventRanking(
      id: '$event:$team',
      season: tbaSeason(event)!,
      event: EntityRef(event),
      team: EntityRef(team),
      result: _rankingResult(data),
      sortOrderInfo: sortOrderInfo,
      extraStatsInfo: extraStatsInfo,
    );
  }

  static RankingResult _rankingResult(Json data) => RankingResult(
    rank: data['rank'] as int,
    matchesPlayed: data['matches_played'] as int?,
    disqualifications: data['dq'] as int?,
    record: _record(data['record']),
    qualificationAverage: _double(data['qual_average']),
    sortOrders: _numbers(data['sort_orders']),
    extraStats: _numbers(data['extra_stats']),
  );

  static PlayoffAlliance playoffAlliance(String event, int number, Json data) =>
      PlayoffAlliance(
        id: '$event:$number',
        season: tbaSeason(event)!,
        event: EntityRef(event),
        number: number,
        name: data['name'] as String?,
        picks: _refs(data['picks']),
        declines: _refs(data['declines']),
        backup: _backup(data['backup']),
        status: _playoffStatus(data['status'] as Json?),
      );

  static EventTeamStatus eventTeamStatus(String event, String team, Json data) {
    final qual = data['qual'] as Json?;
    final ranking = qual?['ranking'] as Json?;
    final alliance = data['alliance'] as Json?;
    return EventTeamStatus(
      id: '$event:$team',
      season: tbaSeason(event)!,
      event: EntityRef(event),
      team: EntityRef(team),
      pitLocation: data['pit_location'] as String?,
      qualificationTeamCount: qual?['num_teams'] as int?,
      qualificationRanking: ranking == null ? null : _rankingResult(ranking),
      qualificationSortOrderInfo: _metrics(qual?['sort_order_info']),
      qualificationStatus: qual?['status'] as String?,
      allianceName: alliance?['name'] as String?,
      allianceNumber: alliance?['number'] as int?,
      alliancePick: alliance?['pick'] as int?,
      allianceBackup: _backup(alliance?['backup']),
      playoff: _playoffStatus(data['playoff'] as Json?),
      allianceStatusText: data['alliance_status_str'] as String?,
      playoffStatusText: data['playoff_status_str'] as String?,
      overallStatusText: data['overall_status_str'] as String?,
      nextMatch: _ref(data['next_match_key']),
      lastMatch: _ref(data['last_match_key']),
    );
  }

  static AllianceBackup? _backup(Object? value) {
    final data = value as Json?;
    final incoming = _ref<CompetitionTeam>(data?['in']);
    final outgoing = _ref<CompetitionTeam>(data?['out']);
    return incoming == null || outgoing == null
        ? null
        : AllianceBackup(incoming: incoming, outgoing: outgoing);
  }

  static PlayoffStatus? _playoffStatus(Json? data) => data == null
      ? null
      : PlayoffStatus(
          playoffType: data['playoff_type'] as int?,
          level: data['level'] as String?,
          status: data['status'] as String?,
          doubleEliminationRound: data['double_elim_round'] as String?,
          currentLevelRecord: _record(data['current_level_record']),
          record: _record(data['record']),
          playoffAverage: _double(data['playoff_average']),
          advancedToRoundRobinFinals:
              data['advanced_to_round_robin_finals'] as bool?,
          roundRobinRank: data['round_robin_rank'] as int?,
        );

  static EventAward award(String event, Json data) {
    final type = data['award_type'] as int;
    return EventAward(
      id: '$event:$type',
      season: data['year'] as int? ?? tbaSeason(event)!,
      event: EntityRef(event),
      type: type,
      name: data['name'] as String,
      recipients: _list(
        data['recipient_list'],
        (item) => AwardRecipient(
          team: _ref(item['team_key']),
          person: item['awardee'] as String?,
        ),
      ),
    );
  }

  static District district(Json data) {
    final key = data['key'] as String;
    final counts = data['official_advancement_counts'] as Json?;
    return District(
      id: key,
      season: data['year'] as int? ?? tbaSeason(key)!,
      abbreviation: data['abbreviation'] as String,
      name: data['display_name'] as String? ?? key,
      officialDistrictChampionshipSpots: counts?['dcmp'] as int?,
      officialChampionshipSpots: counts?['cmp'] as int?,
    );
  }

  static AdvancementRanking advancementRanking(
    int season,
    String? district,
    Json data,
  ) {
    final team = data['team_key'] as String;
    return AdvancementRanking(
      id: '${district ?? '$season:regional'}:$team',
      season: season,
      district: _ref(district),
      team: EntityRef(team),
      rank: data['rank'] as int,
      totalPoints: data['point_total'] as int?,
      rookieBonus: data['rookie_bonus'] as int?,
      singleEventBonus: data['single_event_bonus'] as int?,
      otherBonus: data['other_bonus'] as int?,
      adjustments: data['adjustments'] as int?,
      events: _list(
        data['event_points'],
        (item) => RankingEventPoints(
          event: EntityRef(item['event_key'] as String),
          points: _points(item),
          districtChampionship: item['district_cmp'] as bool?,
        ),
      ),
    );
  }

  static Iterable<EventPoints> eventPoints(
    String event,
    String pool,
    Json? data,
  ) sync* {
    final points = data?['points'] as Json? ?? const {};
    final tiebreakers = data?['tiebreakers'] as Json? ?? const {};
    for (final team in {...points.keys, ...tiebreakers.keys}) {
      final result = points[team] as Json?;
      final tie = tiebreakers[team] as Json?;
      yield EventPoints(
        id: '$event:$pool:$team',
        season: tbaSeason(event)!,
        event: EntityRef(event),
        team: EntityRef(team),
        pool: pool,
        points: result == null ? null : _points(result),
        highestMatchScores:
            ((tie?['highest_match_scores'] ?? tie?['highest_qual_scores'])
                    as List?)
                ?.cast<int>() ??
            const [],
        qualificationWins: tie?['qual_wins'] as int?,
      );
    }
  }

  static AdvancementPoints _points(Json data) => AdvancementPoints(
    total: data['total'] as int?,
    alliance: data['alliance_points'] as int?,
    awards: data['award_points'] as int?,
    elimination: data['elim_points'] as int?,
    qualification: data['qual_points'] as int?,
  );

  static Advancement advancement(
    int season,
    String team,
    Json data, {
    String? district,
    String? qualification,
  }) => Advancement(
    id: '${district ?? '$season:regional'}:$team',
    season: season,
    district: _ref(district),
    team: EntityRef(team),
    districtChampionship: data['dcmp'] as bool?,
    championship: data['cmp'] as bool?,
    championshipStatus: data['cmp_status'] as String?,
    championshipQualification:
        data['cmp_qualification'] as String? ?? qualification,
    qualifyingEvent: _ref(data['qualifying_event']),
    qualifyingAwardName: data['qualifying_award_name'] as String?,
    qualifyingPoolWeek: data['qualifying_pool_week'] as int?,
  );

  static AdvancementCutoffs advancementCutoffs(String district, Json data) =>
      AdvancementCutoffs(
        id: district,
        season: tbaSeason(district)!,
        district: EntityRef(district),
        districtChampionshipOriginal: data['dcmp_original'] as int?,
        districtChampionshipEffective: data['dcmp_effective'] as int?,
        districtChampionshipDeclines: _refs(data['dcmp_declines']),
        championshipOriginal: data['cmp_original'] as int?,
        championshipEffective: data['cmp_effective'] as int?,
        championshipDeclines: _refs(data['cmp_declines']),
      );

  static PlayoffAdvancement playoffAdvancement(String event, Json data) {
    final level = data['level'] as String;
    return PlayoffAdvancement(
      id: '$event:$level',
      season: tbaSeason(event)!,
      event: EntityRef(event),
      level: level,
      name: data['level_name'] as String,
      type: data['type'] as String,
      rankings: data['rankings'] == null
          ? null
          : _list(
              data['rankings'],
              (item) => PlayoffRanking(
                teams: _refs(item['team_keys']),
                allianceName: item['alliance_name'] as String,
                allianceColor: item['alliance_color'] as String?,
                rank: item['rank'] as int?,
                record: _record(item['record']),
                matchesPlayed: item['matches_played'] as int?,
                sortOrders: _numbers(item['sort_orders']),
                extraStats: _numbers(item['extra_stats']),
              ),
            ),
      sortOrderInfo: _metrics(data['sort_order_info']),
      extraStatsInfo: _metrics(data['extra_stats_info']),
    );
  }

  static TeamRobot robot(String team, Json data) {
    final season = data['year'] as int;
    return TeamRobot(
      id: data['key'] as String? ?? '$team:$season',
      season: season,
      team: EntityRef(team),
      name: data['robot_name'] as String,
    );
  }

  static CompetitionMedia media(
    String source,
    Json data, {
    int? season,
    String? event,
    String? team,
    String? tag,
    bool rosterMedia = false,
  }) {
    final type = data['type'] as String;
    final foreignKey = data['foreign_key'] as String? ?? '';
    final details = data['details'] as Json? ?? const {};
    final teams = _refs<CompetitionTeam>(data['team_keys']);
    return CompetitionMedia(
      id: '$source:$type:$foreignKey',
      season: season,
      event: _ref(event),
      team: _ref(team),
      teams: teams.isEmpty && team != null ? [EntityRef(team)] : teams,
      rosterMedia: rosterMedia,
      tag: tag,
      type: type,
      foreignKey: foreignKey,
      preferred: data['preferred'] as bool? ?? false,
      directUrl: data['direct_url'] as String?,
      viewUrl: data['view_url'] as String?,
      details: MediaDetails(
        avatarBase64: details['base64Image'] as String?,
        modelCreated: _dateTime(details['model_created']),
        modelDescription: details['model_description'] as String?,
        modelImage: details['model_image'] as String?,
        modelName: details['model_name'] as String?,
        title:
            (details['title'] ?? details['video_title'] ?? details['name'])
                as String?,
        caption: details['caption'] as String?,
        webUri: details['web_uri'] as String?,
        imageUrl: details['image_url'] as String?,
        mediumImageUrl: details['image_url_med'] as String?,
        smallImageUrl: details['image_url_sm'] as String?,
        imagePartial: details['image_partial'] as String?,
        coverUrl: details['cover_url'] as String?,
        mediumCoverUrl: details['cover_url_med'] as String?,
        smallCoverUrl: details['cover_url_sm'] as String?,
        imageCount: details['image_count'] as int?,
        threadTitle: details['thread_title'] as String?,
      ),
    );
  }

  static EventQueueSummary nexus(String event, Json data) {
    final queue = data['now_queueing'] as Json?;
    final map = data['pit_map'] as Json?;
    return EventQueueSummary(
      id: event,
      season: tbaSeason(event)!,
      event: EntityRef(event),
      dataAsOf: _milliseconds(data['data_as_of_ms']),
      nowQueueing: _ref(queue?['match_key']),
      nowQueueingName: queue?['match_name'] as String?,
      matches: (data['matches'] as Json? ?? const {}).map((key, value) {
        final item = value as Json;
        final times = item['times'] as Json? ?? const {};
        return MapEntry(
          key,
          QueueMatchSummary(
            label: item['label'] as String,
            status: item['status'] as String,
            played: item['played'] as bool,
            estimatedQueueAt: _milliseconds(times['estimated_queue_time_ms']),
            estimatedStartAt: _milliseconds(times['estimated_start_time_ms']),
          ),
        );
      }),
      pitMap: map == null ? null : parsePitMap(map),
    );
  }

  static DateTime? _milliseconds(Object? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          (value as num).toInt(),
          isUtc: true,
        );

  // The original competition action and a few existing UI/export formatters
  // still consume the upstream field names.
  static Json eventJson(CompetitionEvent event) => {
    ..._locationJson(event.location),
    'key': event.id,
    'year': event.season,
    'name': event.name,
    'short_name': event.shortName,
    'event_code': event.code,
    'event_type': event.eventType,
    'event_type_string': event.eventTypeName,
    'week': event.week,
    'timezone': event.timezone,
    'website': event.website,
    'first_event_id': event.firstEventId,
    'first_event_code': event.firstEventCode,
    'start_date': event.startDate?.toIso8601String().split('T').first,
    'end_date': event.endDate?.toIso8601String().split('T').first,
    'playoff_type': event.playoffType,
    'playoff_type_string': event.playoffTypeName,
    'parent_event_key': event.parent?.id,
    'division_keys': _ids(event.divisions),
    'remap_teams': event.remappedTeams,
    'webcasts': [
      for (final webcast in event.webcasts)
        {
          'type': webcast.type,
          'channel': webcast.channel,
          'date': webcast.date,
          'file': webcast.file,
          'status': webcast.status,
          'stream_title': webcast.streamTitle,
          'viewer_count': webcast.viewerCount,
        },
    ],
  };

  static Json teamJson(CompetitionTeam team) => {
    ..._locationJson(team.location),
    'key': team.id,
    'team_number': team.number,
    'name': team.name,
    'nickname': team.nickname,
    'school_name': team.schoolName,
    'rookie_year': team.rookieYear,
    'website': team.website,
    'motto': team.motto,
  };

  static Json _locationJson(CompetitionLocation location) => {
    'city': location.city,
    'state_prov': location.stateProvince,
    'country': location.country,
    'address': location.address,
    'postal_code': location.postalCode,
    'location_name': location.name,
    'gmaps_place_id': location.mapsPlaceId,
    'gmaps_url': location.mapsUrl,
    'lat': location.latitude,
    'lng': location.longitude,
  };

  static Json matchJson(CompetitionMatch match) => {
    'key': match.id,
    'event_key': match.event.id,
    'comp_level': match.level,
    'set_number': match.setNumber,
    'match_number': match.matchNumber,
    'alliances': {
      'red': _allianceJson(match.red),
      'blue': _allianceJson(match.blue),
    },
    'winning_alliance': match.winningAlliance,
    'time': _seconds(match.scheduledAt),
    'actual_time': _seconds(match.playedAt),
    'predicted_time': _seconds(match.predictedAt),
    'post_result_time': _seconds(match.resultPostedAt),
    'score_breakdown':
        match.red?.gameBreakdown == null && match.blue?.gameBreakdown == null
        ? null
        : {'red': match.red?.gameBreakdown, 'blue': match.blue?.gameBreakdown},
    'videos': [
      for (final video in match.videos) {'type': video.type, 'key': video.key},
    ],
  };

  static Json? _allianceJson(CompetitionAlliance? alliance) => alliance == null
      ? null
      : {
          'score': alliance.score,
          'team_keys': _ids(alliance.teams),
          'surrogate_team_keys': _ids(alliance.surrogateTeams),
          'dq_team_keys': _ids(alliance.disqualifiedTeams),
        };

  static Json rankingJson(EventRanking ranking) => {
    'team_key': ranking.team.id,
    'rank': ranking.result.rank,
    'matches_played': ranking.result.matchesPlayed,
    'dq': ranking.result.disqualifications,
    'qual_average': ranking.result.qualificationAverage,
    'sort_orders': ranking.result.sortOrders,
    'extra_stats': ranking.result.extraStats,
    'record': switch (ranking.result.record) {
      final record? => {
        'wins': record.wins,
        'losses': record.losses,
        'ties': record.ties,
      },
      null => null,
    },
  };

  static Json mediaJson(CompetitionMedia media) => {
    'foreign_key': media.foreignKey,
    'type': media.type,
    'preferred': media.preferred,
    'team_keys': _ids(media.teams),
    'direct_url': media.directUrl,
    'view_url': media.viewUrl,
    'details': {
      'base64Image': media.details.avatarBase64,
      'thread_title': media.details.threadTitle,
      'model_created': media.details.modelCreated?.toIso8601String(),
      'model_description': media.details.modelDescription,
      'model_name': media.details.modelName,
      'model_image': media.details.modelImage,
      'image_url': media.details.imageUrl,
      'image_url_med': media.details.mediumImageUrl,
      'image_url_sm': media.details.smallImageUrl,
      'image_partial': media.details.imagePartial,
      'title': media.details.title,
      'caption': media.details.caption,
      'web_uri': media.details.webUri,
      'cover_url': media.details.coverUrl,
      'cover_url_med': media.details.mediumCoverUrl,
      'cover_url_sm': media.details.smallCoverUrl,
      'image_count': media.details.imageCount,
    },
  };

  static List<String> _ids<T>(List<EntityRef<T>> references) =>
      references.map((reference) => reference.id).toList();

  static int? _seconds(DateTime? time) =>
      time == null ? null : time.millisecondsSinceEpoch ~/ 1000;

  static EntityRef<T>? _ref<T>(Object? key) =>
      key == null ? null : EntityRef<T>(key as String);

  static List<EntityRef<T>> _refs<T>(Object? keys) =>
      (keys as List? ?? const []).cast<String>().map(EntityRef<T>.new).toList();

  static List<T> _list<T>(Object? rows, T Function(Json) decode) =>
      (rows as List? ?? const []).cast<Json>().map(decode).toList();

  static List<double> _numbers(Object? values) => (values as List? ?? const [])
      .cast<num>()
      .map((value) => value.toDouble())
      .toList();

  static List<RankingMetric> _metrics(Object? rows) => _list(
    rows,
    (item) => RankingMetric(
      name: item['name'] as String,
      precision: _double(item['precision']),
      type: item['type'] as String?,
    ),
  );

  static WinLossRecord? _record(Object? value) => value == null
      ? null
      : WinLossRecord(
          wins: (value as Json)['wins'] as int,
          losses: value['losses'] as int,
          ties: value['ties'] as int,
        );

  static double? _double(Object? value) => (value as num?)?.toDouble();
  static DateTime? _dateTime(Object? value) =>
      value == null ? null : DateTime.tryParse(value as String);
  static DateTime? _calendarDate(Object? value) =>
      value == null ? null : DateTime.parse('${value}T00:00:00Z');
  static DateTime? _timestamp(Object? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          (value as num).toInt() * 1000,
          isUtc: true,
        );
}
