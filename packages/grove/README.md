# Grove

Grove is a pure Dart client for typed Bearings entities. Entity definitions are
shared between Honeycomb and Flutter in `core`. Grove owns queries, mutations,
local snapshots, and reconnects; Riverpod observes the client.

```dart
final grove = ref.watch(bearingsGroveProvider);
final query = grove.query<ScoutingReport>()
    .where(ScoutingReport.event.equals(eventKey));
final reports = ref.watch(groveQueryProvider(query));
```

Use `query.byId(id).one()` when exactly one record is required, `oneOrNull()`
when absence is allowed, and `many()` for a collection. Those methods require
complete results. Use `result()` or `groveQueryProvider(query)` to inspect
`items`, `offline`, and `updateRequired` when the app can display a partial
result. A disconnected client uses the last snapshot for that exact query and
its queued changes, and explicitly marks the result incomplete. On reconnect,
Honeycomb sends a new snapshot for each active query, including removals.

```dart
await grove.create(Scout.create('Ada'));
await grove.update<Scout>(id, (scout) => Scout(uuid: scout.uuid, name: 'Ada B.'));
await grove.delete<Scout>(id);
```

`update` sends only changed fields. Use `basedOn` when saving a form based on
an earlier snapshot, so unrelated remote edits do not become part of its
patch. Map leaves are separate fields; a list is replaced as a unit. Honeycomb
orders writes by committed revision, including replayed offline edits. Deletes
keep tombstones. Unless the descriptor opts into offline changes, a mutation
returns only after Honeycomb commits it. Opted-in entities may use `stage` to
submit immediately to the durable local queue; `watchSyncStatus()` distinguishes
local acceptance from server confirmation. Permanently rejected submissions are
retained in the local queue state for inspection.

Add `grove_generator` as a development dependency and declare a generated part
in the model's library. Annotate the Dart model and run build_runner.

```dart
part 'event_note.g.dart';

@GroveEntity('scouting.event_note', version: 1)
class EventNote {
  const EventNote({required this.id, required this.eventKey, required this.text});

  final String id;
  final String eventKey;
  final String text;
}
```

Register `eventNoteEntity` in the shared registry. Use
`EventNoteFields.eventKey.equals(eventKey)` in queries. The generator supports
public final constructor fields including scalars, dates, typed references,
lists, string sets, and string-keyed maps. Use the `idField` option when the
model's ID has a different name. Static `groveMigrations` and
`groveFieldVersions` maps opt into schema evolution. The field versions mark
the earliest schema that can represent the current field value.
Reads transform in memory. Compatible patches leave the stored version alone;
patches that need the newer representation upgrade the record in the same
transaction. A decoder or migration must never invent required data.

`MemoryGroveTransport` and `MemoryGroveCache` support pure Dart tests. Flutter
services use a Hive-backed cache on native platforms, scoped to endpoint and
subject, and an in-memory cache on the web. Deploy the Grove endpoint with TLS
and see [Honeycomb](../../backend/honeycomb/README.md) for setup.
