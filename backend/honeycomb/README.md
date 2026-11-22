# Honeycomb

Honeycomb is the Dart Frog service for Grove. It stores shared entities, revisions,
audit history, and offline mutation receipts in SQLite. Both apps connect to
`/api/grove/ws` for authenticated queries, mutations, and live subscriptions.

Run `dart pub get` from the repository root and install the system SQLite library
(`libsqlite3-dev` on Debian and Ubuntu). Install the Dart Frog CLI with
`dart pub global activate dart_frog_cli`, then run `dart_frog dev` in
`backend/honeycomb`. The root route is a health check.

## Install or update the Ubuntu VM

From the Bearings checkout on your computer, run the deploy script with the
VM's SSH alias and public DNS name. If you already copied the compiled bundle
to `~/bundle` on the VM, use `--uploaded` to install it directly.

```sh
./backend/honeycomb/deploy/deploy.sh --uploaded honeycomb honeycomb.example.org
```

The first install opens `/etc/honeycomb.env` for the settings below, creates
the systemd service, and configures Caddy if you supply a hostname. You can
omit the hostname until DNS is ready, then repeat the command with the hostname.
If you enable profile photo URLs later, set `HONEYCOMB_PUBLIC_API_URL` in the
environment file. The VM needs inbound HTTPS and HTTP for Caddy.

For routine updates, omit `--uploaded`. Run from a Linux x64 checkout with
the workspace's Flutter SDK on `PATH`.

```sh
./backend/honeycomb/deploy/deploy.sh honeycomb
```

The script builds and uploads a new release, switches `/opt/honeycomb/current`,
and restarts Honeycomb. It switches back if the new release fails its Grove
WebSocket check. The default SQLite file lives under `/var/lib/honeycomb`
outside the release directory. Set up off-VM SQLite backups before live scouting.

## Configuration

Set the following environment variables for the features you deploy.

| Variable | Value |
| --- | --- |
| `AUTH0_ISSUER` | HTTPS issuer of the existing Auth0 tenant, including a trailing slash. |
| `AUTH0_AUDIENCE` | The Auth0 API audience used by both Bearings clients. |
| `HONEYCOMB_DATABASE` | Writable SQLite path on a persistent volume. Create the parent directory first. |
| `HONEYCOMB_BOOTSTRAP_SUBJECT` | Exact Auth0 subject of the initial administrator. |
| `TBA_API_KEY` | The Blue Alliance v3 read API key. Enables automatic import and historical lookups. |
| `NEXUS_API_KEY` | FRC Nexus API key for event discovery, status reconciliation, and pit layouts. |
| `NEXUS_WEBHOOK_TOKEN` | Token from the Nexus API dashboard for authenticating incoming live event updates. |
| `AUTH0_MANAGEMENT_CLIENT_ID` and `AUTH0_MANAGEMENT_CLIENT_SECRET` | Auth0 machine client with Management API permissions `read:users`, `update:users`, and `delete:users`. Enables directory import, profile sync, password resets, and deletion. |
| `AUTH0_WEBHOOK_TOKEN` | Shared bearer token for the optional Auth0 user Event Stream webhook. |
| `HONEYCOMB_PUBLIC_API_URL` | Public HTTPS base URL ending in `/api/` for profile photo downloads. |
| `BEARIMETRIC_AUTH0_CLIENT_ID` and `BEARIMETRIC_AUTH0_CLIENT_SECRET` | Bearimetric machine client credentials returned to authorized device provisioners. Use a separate client from Auth0 Management. |

Deploy Honeycomb on the primary app endpoint or build both Flutter apps with
`--dart-define=HONEYCOMB_URL=https://your-honeycomb.example`. Beariscope also
offers a custom URL in Server Connection settings. The endpoint must support
WebSocket upgrades. Use a single Honeycomb process per SQLite database because
live notifications and presence are held in process.

A valid token provisions a canonical Grove user keyed by Auth0 subject. Honeycomb
verifies RS256 signatures and checks issuer, audience, and token validity.
A newly provisioned user can view their own profile and access information. Use
Beariscope's Users & Roles screen as the bootstrap administrator to grant access.
Assign a durable administrator role with identity and role read and mutate
capabilities, plus the permissions the administrator can delegate, before
removing the bootstrap environment variable.

Grant scouting devices `gamepack.read`, `scouting.observation.submit`,
`scouting.scout.read`, and `external.read` as appropriate. Each device appears as
its Auth0 machine subject after its first Grove connection. The
`device.provision` permission controls access to the provisioning QR credentials.
Honeycomb evaluates permissions on reads, writes, and live updates.

## GamePacks

Use a server and both apps built from the GamePack checkout. Pick an imported
test event with a match schedule. In Beariscope's Users & Roles, grant these
capabilities in addition to the team's regular permissions.

| Role | GamePack capabilities |
| --- | --- |
| Pack author | `gamepack.read`, `gamepack.publish`, `scouting.observation.read`, `external.read` |
| Bearimetric device | `gamepack.read`, `scouting.observation.submit`, `scouting.scout.read`, `external.read` |
| Pit and notes contributor | `gamepack.read`, `scouting.observation.read`, `scouting.observation.submit`, `external.read` |
| Results viewer | `gamepack.read`, `scouting.observation.read`, `external.read` |
| Audit and corrections | `gamepack.read`, `scouting.observation.read`, `scouting.observation.correct`, `external.read` |

1. Open **Settings → GamePacks** in Beariscope and select the event. Use
   **Open visual builder** for a new season or **Import GamePack** to open
   `gamepacks/2026-rebuilt.json`. In **Scout forms**, choose a **Scrolling list**
   for sections with ordered controls and side-by-side rows, or **Grid** for
   a fixed page with controls that snap to whole cells. This checkout publishes
   GamePack format 6. In **Test data**, choose an archived match or add
   sample values. In **Calculations**, map a TBA field from the
   breakdown and choose whether it belongs to the match, alliance, or robot.
   Start a named calculation with a field or step. Each calculation has its
   own canvas, with connected fields, scoped test values, and a marked result.
   Calculations can use one another by name.
2. In **Results**, choose fields or calculations for app screens and exports.
   **Team Card** configures Team Lookup and Match Preview cards. **Team Details**
   configures the shared Details layout in Team Lookup and picklist Quick View.
   **Sorting & Filters** configures the presets for each team list.
   **Export Sheets** configures workbook tabs, row sources, and column order.
   Preview each setup with **Test data** or a live event. When a numeric or
   yes/no team-match field is available, the picker also offers its event
   average or Yes percentage. These summaries work as calculation inputs and
   retain links to the original records. Save the draft, run
   **Validate pack**, then publish and **Pin release to event**. A pinned
   collection release stays with its event. **Use for analysis** can switch
   calculations to a compatible release while keeping the capture release.
3. In Bearimetric, select the event, scout, and position, then select a match
   and press **Go**. Load the pack and schedule online before going offline.
   Save a submission and check the upload indicator for confirmation or
   rejection after reconnecting.
4. In Beariscope, check Pits, Team Lookup, Match Preview, Scout Audit, Picklists,
   and Export Data for the selected event. Team Details and Match Preview
   use the same Observations form. Match Preview attaches the match to the
   observation. Audit corrections append a new observation with the reason
   and the link to the previous record.

### Verify the clean cutover

The current Honeycomb environment has no legacy scouting submissions. Start
with its existing Grove database and publish and assign the event’s GamePack.
The service keeps existing competition records, users, scouts, and picklists.

1. Check that any test tablets show zero pending uploads before changing builds.
2. Keep a SQLite backup and the previous builds available for recovery.
3. Load the new builds and verify the workflows above. Include a tablet restart
   and reconnect after an offline submission. The checked-in REBUILT pack is
   tested with archived 2026 TBA responses.

Production rollout requires explicit authorization. For recovery, preserve the
current database before restoring a backup. Reconcile submissions accepted
since that backup before reopening scouting.

## Auth0 directory sync

With the Management API credentials configured, Honeycomb imports users on
startup and reconciles the directory every five minutes. Users appear in
Beariscope's Users & Roles before their first sign-in. Honeycomb matches each
account by Auth0 subject and copies its name, email, verification status, and
profile photo URL. The first import preserves existing Grove names and photo
URLs. Later edits to those fields sync in either direction. Assign Grove roles
in Beariscope.

To apply Auth0 edits as they happen, add a Webhook destination under Auth0
Event Streams. Enter `https://your-honeycomb.example/api/auth0/webhook`,
choose **Bearer Token**, and use the same secret as `AUTH0_WEBHOOK_TOKEN`.
Subscribe to `user.created`, `user.updated`, and `user.deleted`. The
periodic reconciliation also works without a webhook.

## The Blue Alliance import

With `TBA_API_KEY` set, Honeycomb starts importing on process startup. It uses
TBA's season and team page limits to discover every published season from 2026
forward. The same SQLite database stores the read-only competition entities
and the import queue. The first import fills in progressively, and a restart
resumes from the saved checkpoints. Both apps subscribe through Grove using
the existing `external.read` permission.

The import includes typed teams and season participation, events and rosters,
competition and practice matches, rankings, awards, playoff alliances,
districts, advancement, robot names, and media. Match alliances store
game-specific scoring in `gameBreakdown`. Event statistics, insights, and
match tracking are outside the import. Media files stay on their original
hosts. Pre-2026 lookups remain available on demand.

For example, query an event's competition matches by event reference.

```dart
final query = grove.query<CompetitionMatch>()
    .where(CompetitionMatchFields.event.equals(EntityRef<CompetitionEvent>('2026wabon')))
    .where(CompetitionMatchFields.practice.equals(false));
```

Active event schedules, rosters, rankings and team media are checked as often
as once per minute. Other datasets use longer intervals, with historical data
checked weekly or monthly. Honeycomb honors upstream `Cache-Control`, uses
conditional requests with saved ETags, and backs off when TBA rate-limits it.

Competition data is powered by [The Blue Alliance](https://www.thebluealliance.com/).

## Nexus import

Configure both Nexus environment variables and deploy Honeycomb. In the
[Nexus API dashboard](https://frc.nexus/api), register
`https://<honeycomb-host>/api/nexus/webhook` with **All events (excluding
demos)** and **Live event status**. A separate demo registration can use the
same URL. Honeycomb returns HTTP 200 to registration probes and requires the
`Nexus-Token` header before it stores event data. It applies only snapshots
with a newer `dataAsOfTime` for that Nexus event key.

Honeycomb discovers events via the Nexus API every five minutes. It fetches
live status to seed the first snapshot and reconciles active events if push
updates go quiet. It refreshes pit layouts and team pit addresses every five
minutes for active or upcoming events. Reading an individual event through
Grove also schedules a refresh, including for demo or historical event keys.

The read-only `event_status` and `pit_layout` entities use the
Nexus event key as their ID and require `external.read`. Up Next and the pit
map subscribe through Grove. Up Next falls back to the TBA schedule if the
Nexus snapshot is unavailable or older than two minutes.

See the [Nexus API docs](https://frc.nexus/api/v1/docs) for push and pull endpoints.

External API keys and Auth0 Management credentials live on the server. Shared
profile names and photos live in Grove. Auth0 still owns sign-in emails,
verification, password resets, and account deletion. Account deletion removes
the sign-in account, live Grove profile, and stored photo. Shared GamePack
observations and historical audit entries remain.
