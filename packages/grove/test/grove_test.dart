import 'dart:async';

import 'package:grove/grove.dart';
import 'package:test/test.dart';

class Note {
  const Note(this.id, this.text, {this.priority});
  final String id;
  final String text;
  final int? priority;
  static const textField = EntityField<Note, String>('text');
  static const priorityField = EntityField<Note, int?>('priority');
  Json toJson() => {'id': id, 'text': text, 'priority': priority};
  factory Note.fromJson(Json data) => Note(
    data['id'] as String,
    data['text'] as String,
    priority: data['priority'] as int?,
  );
}

EntityDescriptor<Note> descriptor({int version = 2, bool offline = false}) =>
    EntityDescriptor(
      type: 'test.note',
      version: version,
      offlineMutable: offline,
      encode: (n) => n.toJson(),
      decode: Note.fromJson,
      fieldVersions: const {'priority': 2},
      migrations: {
        1: (data) => {...data, 'priority': null},
      },
    );

class SwitchableTransport implements GroveTransport {
  SwitchableTransport(this.remote);
  final GroveTransport remote;
  bool online = true;
  void _check() {
    if (!online) throw const GroveOffline();
  }

  @override
  Future<QuerySnapshot> fetch(QueryDescription query) async {
    _check();
    return remote.fetch(query);
  }

  @override
  Stream<QuerySnapshot> watch(QueryDescription query) async* {
    _check();
    yield* remote.watch(query);
  }

  @override
  Future<EntityRecord> mutate(EntityMutation mutation) async {
    _check();
    return remote.mutate(mutation);
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('distinguishes an empty cached query from a missing snapshot', () async {
    final registry = EntityRegistry()..register(descriptor());
    final remote = MemoryGroveTransport(registry);
    addTearDown(remote.close);
    final transport = SwitchableTransport(remote);
    final grove = Grove(registry: registry, transport: transport);
    addTearDown(grove.close);
    final cached = grove.query<Note>().byId('cached');
    final unknown = grove.query<Note>().byId('unknown');
    expect((await cached.result()).items, isEmpty);
    transport.online = false;

    final cachedResult = await grove.watch(cached).first;
    expect(cachedResult.offline, isTrue);
    expect(cachedResult.requireAvailable().items, isEmpty);
    final result = await grove.watch(unknown).first;
    expect(result.hasSnapshot, isFalse);
    expect(result.requireAvailable, throwsA(isA<GroveOffline>()));
  });

  test(
    'registry and query descriptions round trip; cardinality is checked',
    () async {
      final registry = EntityRegistry()..register(descriptor());
      expect(() => registry.register(descriptor()), throwsStateError);
      final grove = Grove(
        registry: registry,
        transport: MemoryGroveTransport(registry),
      );
      addTearDown(grove.close);
      await grove.create(const Note('a', 'before', priority: 1));
      await grove.create(const Note('b', 'after', priority: 3));
      final query = grove
          .query<Note>()
          .where(Note.priorityField.greaterThan(0))
          .orderBy(Note.priorityField, descending: true)
          .limit(1);
      expect(
        QueryDescription.fromJson(query.description.toJson()).key,
        query.description.key,
      );
      expect((await query.one()).id, 'b');
      expect((await grove.query<Note>().byId('a').one()).text, 'before');
      expect(await grove.query<Note>().byId('missing').oneOrNull(), isNull);
      await expectLater(grove.query<Note>().oneOrNull(), throwsStateError);
      await expectLater(
        grove.query<Note>().byId('missing').one(),
        throwsStateError,
      );
    },
  );

  test(
    'compatible edits preserve old schema and new fields upgrade lazily',
    () async {
      final registry = EntityRegistry()..register(descriptor());
      final remote = MemoryGroveTransport(registry);
      final grove = Grove(registry: registry, transport: remote);
      addTearDown(grove.close);
      await remote.mutate(
        EntityMutation(
          mutationId: 'old',
          type: 'test.note',
          id: 'a',
          version: 1,
          kind: MutationKind.create,
          data: {'id': 'a', 'text': 'old'},
        ),
      );
      expect((await grove.query<Note>().one()).priority, isNull);
      expect(remote.records['test.note/a']!.version, 1);
      await grove.update<Note>('a', (n) => Note(n.id, 'edited'));
      expect(remote.records['test.note/a']!.data, {
        'id': 'a',
        'text': 'edited',
      });
      expect(remote.records['test.note/a']!.version, 1);
      await grove.update<Note>('a', (n) => Note(n.id, n.text, priority: 8));
      expect(remote.records['test.note/a']!.version, 2);
      final oldClient = Grove(
        registry: EntityRegistry()..register(descriptor(version: 1)),
        transport: SwitchableTransport(remote),
      );
      addTearDown(oldClient.close);
      final result = await oldClient.query<Note>().result();
      expect(result.updateRequired, isTrue);
      expect(result.complete, isFalse);
      expect(result.items, isEmpty);
      final filtered = await oldClient
          .query<Note>()
          .where(Note.textField.equals('unmatched'))
          .limit(1)
          .result();
      expect(filtered.updateRequired, isTrue);
      expect(filtered.complete, isFalse);
      expect(await oldClient.query<Note>().byId('absent').oneOrNull(), isNull);
      await expectLater(
        oldClient.query<Note>().oneOrNull(),
        throwsA(isA<IncompleteQuery>()),
      );
    },
  );

  test(
    'opted-in offline changes survive reopening and replay changed fields',
    () async {
      final registry = EntityRegistry()..register(descriptor(offline: true));
      final remote = MemoryGroveTransport(registry);
      addTearDown(remote.close);
      final cache = MemoryGroveCache();
      final transport = SwitchableTransport(remote);
      final grove = Grove(
        registry: registry,
        transport: transport,
        cache: cache,
      );
      await grove.create(const Note('a', 'before', priority: 1));
      await grove.query<Note>().byId('a').one();
      transport.online = false;
      await grove.update<Note>(
        'a',
        (n) => Note(n.id, 'offline edit', priority: n.priority),
      );
      await grove.create(const Note('b', 'created offline'));
      expect(await grove.pendingMutationCount, 2);
      final local = await grove.query<Note>().result();
      expect(local.offline, isTrue);
      expect(local.items.map((n) => n.text), [
        'offline edit',
        'created offline',
      ]);
      await grove.close();

      final other = Grove(
        registry: registry,
        transport: SwitchableTransport(remote),
      );
      addTearDown(other.close);
      await other.update<Note>('a', (n) => Note(n.id, n.text, priority: 9));
      final reopened = Grove(
        registry: registry,
        transport: SwitchableTransport(remote),
        cache: cache,
      );
      addTearDown(reopened.close);
      await reopened.synchronize();
      expect(await reopened.pendingMutationCount, 0);
      final note = await reopened.query<Note>().byId('a').one();
      expect(note.text, 'offline edit');
      expect(note.priority, 9);
      expect(
        (await reopened.query<Note>().byId('b').one()).text,
        'created offline',
      );
    },
  );

  test('mutations require a connection unless explicitly enabled', () async {
    final registry = EntityRegistry()..register(descriptor());
    final remote = MemoryGroveTransport(registry);
    addTearDown(remote.close);
    final transport = SwitchableTransport(remote)..online = false;
    final grove = Grove(registry: registry, transport: transport);
    addTearDown(grove.close);
    await expectLater(
      grove.create(const Note('a', 'offline')),
      throwsA(isA<GroveOffline>()),
    );
    expect(await grove.pendingMutationCount, 0);
  });

  test(
    'staging a stale form does not undo independent edits merged on sync',
    () async {
      final registry = EntityRegistry()..register(descriptor(offline: true));
      final remote = MemoryGroveTransport(registry);
      addTearDown(remote.close);
      final grove = Grove(
        registry: registry,
        transport: SwitchableTransport(remote),
      );
      addTearDown(grove.close);
      final other = Grove(
        registry: registry,
        transport: SwitchableTransport(remote),
      );
      addTearDown(other.close);
      await grove.stage(const Note('a', 'draft', priority: 1));
      await grove.synchronize();
      await other.update<Note>(
        'a',
        (note) => Note(note.id, note.text, priority: 9),
      );
      await grove.stage(const Note('a', 'first edit', priority: 1));
      await grove.synchronize();
      await grove.stage(const Note('a', 'second edit', priority: 1));
      await grove.synchronize();
      final result = await other.query<Note>().byId('a').one();
      expect(result.text, 'second edit');
      expect(result.priority, 9);
    },
  );

  test('watch tracks creation, field updates and deletion', () async {
    final registry = EntityRegistry()..register(descriptor());
    final grove = Grove(
      registry: registry,
      transport: MemoryGroveTransport(registry),
    );
    addTearDown(grove.close);
    final results = StreamIterator(
      grove.watch(grove.query<Note>().where(Note.textField.equals('visible'))),
    );
    addTearDown(results.cancel);
    expect(await results.moveNext(), isTrue);
    expect(results.current.items, isEmpty);
    await grove.create(const Note('a', 'visible'));
    expect(await results.moveNext(), isTrue);
    expect(results.current.items.single.id, 'a');
    await grove.update<Note>('a', (n) => Note(n.id, n.text, priority: 2));
    expect(await results.moveNext(), isTrue);
    expect(results.current.items.single.priority, 2);
    await grove.delete<Note>('a');
    expect(await results.moveNext(), isTrue);
    expect(results.current.items, isEmpty);
  });
}
