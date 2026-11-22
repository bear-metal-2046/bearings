import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:grove/grove.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'publishes, captures offline, and delivers one validated result over Grove',
    () async {
      final registry = bearingsEntityRegistry();
      final store = EntityStore(sqlite3.openInMemory(), registry);
      addTearDown(store.close);
      const event = CompetitionEvent(
        id: '2026pilot',
        season: 2026,
        name: 'Pilot Event',
        code: 'pilot',
        location: CompetitionLocation(),
      );
      const match = CompetitionMatch(
        id: '2026pilot_qm1',
        season: 2026,
        event: EntityRef('2026pilot'),
        level: 'qm',
        setNumber: 1,
        matchNumber: 1,
        practice: false,
        red: CompetitionAlliance(
          teams: [EntityRef('frc2046')],
          gameBreakdown: {
            'hubScore': {'autoCount': 20},
          },
        ),
      );
      EntityRecord record<T>(T entity) {
        final descriptor = registry.descriptor<T>();
        final data = descriptor.encode(entity);
        return EntityRecord(
          type: descriptor.type,
          id: data['id'] as String,
          version: descriptor.version,
          data: data,
        );
      }

      store.replaceExternalDataset('pilot', [
        record(event),
        record(match),
        record(
          const CompetitionTeam(
            id: 'frc2046',
            number: 2046,
            location: CompetitionLocation(),
          ),
        ),
      ], checkpoint: () {});
      final service = EntityService(
        store: store,
        bootstrapSubject: 'publisher',
        authenticate: (token) async => AuthenticatedActor(
          token,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );
      final server = await serve(
        service.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));

      Grove connect(Future<String> Function() token, {GroveCache? cache}) {
        final grove = Grove(
          registry: registry,
          cache: cache,
          transport: WebSocketGroveTransport(
            uri: Uri.parse('ws://127.0.0.1:${server.port}'),
            accessToken: token,
            reconnectDelay: const Duration(seconds: 30),
            requestTimeout: const Duration(seconds: 3),
          ),
        );
        addTearDown(grove.close);
        return grove;
      }

      final publisher = connect(() async => 'publisher');
      final cache = MemoryGroveCache();
      final onlineTablet = connect(() async => 'tablet', cache: cache);
      await onlineTablet.query<GroveAccess>().byId('tablet').one();
      await publisher.create(
        GroveRole(
          id: 'collector',
          name: 'Collector',
          permissions: [
            gamePackReadPermission,
            gamePackSubmitPermission,
            competitionReadPermission,
          ],
        ),
      );
      await publisher.update<GroveUser>(
        'tablet',
        (user) => user.copyWith(roles: [const EntityRef('collector')]),
      );

      await publisher.create(
        GamePackDraft(
          id: 'draft',
          name: 'Draft pack',
          documentJson: '{"formatVersion":2,"forms":[]}',
          updatedAt: DateTime.utc(2026),
        ),
      );
      await expectLater(
        onlineTablet.query<GamePackDraft>().byId('draft').one(),
        throwsA(
          isA<GroveException>().having(
            (error) => error.code,
            'code',
            'forbidden',
          ),
        ),
      );
      await publisher.update<GamePackDraft>(
        'draft',
        (draft) => GamePackDraft(
          id: draft.id,
          name: 'Edited pack',
          documentJson: jsonEncode({...draft.document, 'name': 'Edited pack'}),
          updatedAt: DateTime.utc(2026, 2),
        ),
      );
      expect(
        (await publisher.query<GamePackDraft>().byId('draft').one())
            .document['name'],
        'Edited pack',
      );

      GamePackDefinition pack(String field, String label) =>
          GamePackDefinition.typed(
            name: 'Scouting test',
            season: 2026,
            fields: [
              GamePackField(field, label),
              const GamePackField(
                'notes',
                'Notes',
                type: GamePackType.text,
              ),
            ],
            forms: [
              GamePackForm(
                id: 'match',
                label: 'Match scouting',
                kind: GamePackFormKind.match,
                pages: [
                  GamePackFormPage.scrolling(
                    id: 'match',
                    label: 'Match',
                    sections: [
                      GamePackSection.controls(
                        id: 'scores',
                        label: 'Scores',
                        controls: [
                          GamePackControl(
                            field: field,
                            type: GamePackControlType.number,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              GamePackForm(
                id: 'observation',
                label: 'Observations',
                kind: GamePackFormKind.observation,
                pages: [
                  GamePackFormPage.scrolling(
                    id: 'note',
                    label: 'Observation',
                    sections: [
                      GamePackSection.controls(
                        id: 'notes',
                        label: 'Notes',
                        controls: const [
                          GamePackControl(
                            field: 'notes',
                            type: GamePackControlType.multiline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
      final definition = pack('count', 'Scouted count');
      final release = GamePackRelease(
        id: 'release-a',
        document: definition.toJson(),
      );
      await expectLater(
        onlineTablet.create(release),
        throwsA(
          isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
        ),
      );
      await publisher.create(release);
      await publisher.create(
        const EventGamePack(id: '2026pilot', release: EntityRef('release-a')),
      );
      await expectLater(
        publisher.delete<GamePackRelease>(release.id),
        throwsA(
          isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
        ),
      );
      final analysis = GamePackRelease(
        id: 'analysis',
        document: {...definition.toJson(), 'name': 'Revised analysis'},
      );
      await publisher.create(analysis);
      await publisher.update<EventGamePack>(
        event.id,
        (binding) => EventGamePack(
          id: binding.id,
          release: binding.release,
          analysisRelease: EntityRef(analysis.id),
        ),
      );
      final updated = await publisher
          .query<EventGamePack>()
          .byId(event.id)
          .one();
      expect(updated.release.id, release.id);
      expect(updated.effectiveAnalysisRelease.id, analysis.id);

      final incompatible = GamePackRelease(
        id: 'incompatible',
        document: pack('other', 'Other').toJson(),
      );
      await publisher.create(incompatible);
      await expectLater(
        publisher.update<EventGamePack>(
          event.id,
          (binding) => EventGamePack(
            id: binding.id,
            release: binding.release,
            analysisRelease: EntityRef(incompatible.id),
          ),
        ),
        throwsA(
          isA<GroveException>().having(
            (error) => error.code,
            'code',
            'invalid_request',
          ),
        ),
      );
      await expectLater(
        publisher.update<EventGamePack>(
          event.id,
          (binding) =>
              EventGamePack(id: binding.id, release: EntityRef(analysis.id)),
        ),
        throwsA(
          isA<GroveException>().having(
            (error) => error.code,
            'code',
            'forbidden',
          ),
        ),
      );
      final binding = await onlineTablet
          .query<EventGamePack>()
          .byId(event.id)
          .one();
      await onlineTablet
          .query<GamePackRelease>()
          .byId(binding.release.id)
          .one();
      await onlineTablet.query<CompetitionMatch>().byId(match.id).one();
      await onlineTablet.close();

      var connected = false;
      final tablet = connect(() async {
        if (!connected) throw const GroveOffline();
        return 'tablet';
      }, cache: cache);
      final cachedRelease = await tablet
          .query<GamePackRelease>()
          .byId(release.id)
          .result();
      expect(cachedRelease.offline, isTrue);
      expect(
        cachedRelease.items.single.definition.fieldById['count']?.label,
        'Scouted count',
      );
      expect(
        (await tablet.query<CompetitionMatch>().byId(match.id).result())
            .items
            .single
            .id,
        match.id,
      );
      GamePackObservation observation({
        String id = 'observation-a',
        String team = 'frc2046',
        num count = 12,
      }) => GamePackObservation(
        id: id,
        event: const EntityRef('2026pilot'),
        match: const EntityRef('2026pilot_qm1'),
        team: EntityRef(team),
        release: const EntityRef('release-a'),
        station: 0,
        capturedAt: DateTime.utc(2026, 3),
        answers: {'count': count},
        author: 'untrusted client value',
      );
      await tablet.stageCreate(observation());
      await tablet.stageCreate(observation());
      expect(await tablet.pendingMutationCount, 1);
      await expectLater(
        tablet.stageCreate(observation(count: 18)),
        throwsA(
          isA<GroveException>().having((e) => e.code, 'code', 'conflict'),
        ),
      );

      final results = publisher.query<GamePackObservation>().where(
        GamePackObservationFields.event.equals(const EntityRef('2026pilot')),
      );
      final delivered = publisher
          .watch(results)
          .firstWhere((value) => value.items.isNotEmpty);
      connected = true;
      await (tablet.transport as WebSocketGroveTransport).connect();
      await tablet.synchronize();
      final accepted = (await delivered.timeout(const Duration(seconds: 3)))
          .items
          .single;
      expect(accepted.author, 'tablet');
      expect(accepted.answers, {'count': 12});

      // Replaying an acknowledged submission cannot append another observation.
      await tablet.stageCreate(observation());
      await tablet.synchronize();
      expect(
        store.history(gamePackObservationEntity.type, accepted.id),
        hasLength(1),
      );
      await expectLater(
        tablet.create(
          observation(id: 'wrong-team', team: 'frc1678'),
          allowOffline: false,
        ),
        throwsA(
          isA<GroveException>().having(
            (e) => e.code,
            'code',
            'invalid_request',
          ),
        ),
      );
      await expectLater(
        publisher.delete<GamePackObservation>(accepted.id),
        throwsA(
          isA<GroveException>().having((e) => e.code, 'code', 'forbidden'),
        ),
      );
      expect(await results.many(), hasLength(1));

      GamePackObservation revision(
        String id,
        GamePackObservation parent, {
        bool retract = false,
      }) => GamePackObservation(
        id: id,
        event: parent.event,
        match: parent.match,
        team: parent.team,
        release: parent.release,
        station: parent.station,
        capturedAt: parent.capturedAt,
        form: parent.formId,
        supersedes: EntityRef(parent.id),
        retracted: retract,
        reason: retract ? 'Wrong encounter' : 'Reviewed video',
        answers: retract ? {} : {'count': 14},
      );
      await expectLater(
        tablet.create(revision('unprivileged', accepted), allowOffline: false),
        throwsA(
          isA<GroveException>().having(
            (error) => error.code,
            'code',
            'forbidden',
          ),
        ),
      );
      final corrected = await publisher.create(revision('corrected', accepted));
      await expectLater(
        publisher.create(revision('stale-correction', accepted)),
        throwsA(
          isA<GroveException>().having(
            (error) => error.code,
            'code',
            'conflict',
          ),
        ),
      );
      expect(activeGamePackObservations(await results.many()).single.answers, {
        'count': 14,
      });
      await publisher.create(revision('withdrawn', corrected, retract: true));
      final history = await results.many();
      expect(history, hasLength(3));
      expect(activeGamePackObservations(history), isEmpty);
      expect(history.firstWhere((record) => record.id == accepted.id).answers, {
        'count': 12,
      });

      // Older tablets can finish sending an already queued v1 match.
      final oldData = gamePackObservationEntity.encode(
        observation(id: 'from-v1'),
      );
      for (final key in GamePackObservation.groveFieldVersions.keys) {
        oldData.remove(key);
      }
      final oldReceipt = await tablet.transport.mutate(
        EntityMutation(
          mutationId: 'v1-queue-entry',
          type: gamePackObservationEntity.type,
          id: 'from-v1',
          version: 1,
          kind: MutationKind.create,
          data: oldData,
        ),
      );
      expect(oldReceipt.version, 1);
      expect(gamePackObservationEntity.read(oldReceipt).formId, 'match');

      GamePackObservation teamObservation(
        String id, {
        String? matchId,
        String team = 'frc2046',
        int? station,
      }) => GamePackObservation(
        id: id,
        event: const EntityRef('2026pilot'),
        match: matchId == null ? null : EntityRef(matchId),
        team: EntityRef(team),
        release: const EntityRef('release-a'),
        station: station,
        capturedAt: DateTime.utc(2026, 3),
        form: 'observation',
        answers: {'notes': id},
      );

      final general = await tablet.create(teamObservation('general'));
      final linked = await tablet.create(
        teamObservation('at-match', matchId: match.id),
      );
      expect(general.formId, linked.formId);
      expect(general.team?.id, linked.team?.id);
      expect(general.match, isNull);
      expect(linked.match?.id, match.id);
      for (final invalid in [
        teamObservation('wrong-match-team', matchId: match.id, team: 'frc1678'),
        teamObservation('with-station', matchId: match.id, station: 0),
      ]) {
        await expectLater(
          tablet.create(invalid, allowOffline: false),
          throwsA(
            isA<GroveException>().having(
              (error) => error.code,
              'code',
              'invalid_request',
            ),
          ),
        );
      }
    },
  );
}
