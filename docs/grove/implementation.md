# Grove in Bearings

Grove replaces the legacy Bearings data client in Beariscope and Bearimetric.
Shared definitions live in `packages/core/lib/src/entities`, grouped into
authorization, identity, scouting, strategy, and competition. Competition types
include `team`, `event`, `match`, `event_status`, and `pit_layout`. Match,
strategy, pit, and team observations keep their game-specific
payloads. Role assignments reference Grove roles from the user profile.

`packages/grove` provides serializable typed queries, CRUD, Riverpod observation,
offline synchronization, and schema migrations. `packages/grove_generator`
generates codecs, entity descriptors, and query fields from annotated Dart
models. Honeycomb persists authoritative records, tombstones, and audit
history in SQLite. Live queries and editor presence share an authenticated
WebSocket connection. Beariscope and Bearimetric use a native Hive cache scoped
to the account and server, and the web client uses memory.

Beariscope reads and edits scouting reports, the scout roster, profiles,
roles, and shared picklists through Grove. Picklist team changes use the
existing movable-list CRDT, stored as immutable operations in the shared
entity. Private picklists stay on the device. Bearimetric keeps local editing
drafts and stages match and strategy submissions in Grove's durable queue.
Practice forms remain local.

Honeycomb imports TBA and Nexus data through adapters in `packages/core/lib/src/integrations`
and keeps their credentials on the server. Competition entities declare
server-managed writes explicitly. The app caches downloaded schedules for
offline use. Account credential actions call Auth0, profile photos live
alongside Grove data, and device provisioning remains restricted to authorized
users. Google Drive is still an independent integration.

The old HTTP client, response cache, picklist relay, and Bearimetric upload
queue have been removed. The server starts with a fresh database. See
[Honeycomb setup](../../backend/honeycomb/README.md) for deployment variables
and role setup.

## Operational limits

Grove v1 sends full query snapshots and runs one Honeycomb process per
database. Honeycomb applies concurrent edits in commit order at the field level.
Normal lists are atomic values. Shared picklist team changes merge independently.
Offline snapshots and results with an unsupported schema are explicitly
incomplete. Rejected offline submissions stay in local storage and appear
in the status indicator. There is no dedicated recovery screen for rejected
payloads.

Local tests use fixture data, mock upstream services, and loopback sockets.
Live Auth0, TBA, Nexus, and hosting settings require verification when the
service is deployed.
