# Honeycomb Nexus contract

What Beariscope's Up Next expects from Honeycomb's Nexus-enriched event data. The
current backend is the TypeScript Honeycomb (Azure Functions,
`src/functions/events.ts`). Any replacement, such as the Dart Frog server in
`backend/honeycomb`, should keep this contract so the app keeps working.

## Endpoint

```
GET /events?event={tbaEventKey}&enrich=true
Authorization: Bearer <access token>
```

- `event` is a TBA event key, for example `2026new`.
- `enrich=true` asks Honeycomb to attach Nexus data. It defaults to true whenever
  `event` is given.
- The caller needs the `external.read` permission. Without a token the response
  is `401`; without the permission it is `403`.
- Honeycomb reads the Nexus key from the `NEXUS_API_KEY` environment variable
  and sends it as the `Nexus-Api-Key` header to
  `https://frc.nexus/api/v1/event/{nexusEventKey}`. The key never reaches the
  app.
- The Nexus event key is built as `{tbaEvent.year}{tbaEvent.first_event_code}`.
  If TBA has no `first_event_code`, there is no Nexus lookup.

The app calls this every 15 seconds while Up Next is open
(`nexusPollInterval` in `packages/services`).

## Response

A single JSON object: the TBA event fields in camelCase (`key`, `name`, `year`,
`timezone`, ...) plus these Nexus fields at the top level. Every Nexus field may
be missing or null, and the app treats them that way.

| Field | Type | Notes |
| --- | --- | --- |
| `matches` | `NexusMatch[]` | `[]` when Nexus is unavailable. |
| `nowQueuing` | `string \| null` | A match label, for example `"Qualification 12"`. |
| `announcements` | `{id, announcement, postedTime}[]` | `postedTime` is an ISO string after Honeycomb's date coercion. |
| `partsRequests` | `{id, parts, requestedByTeam, postedTime}[]` | Not used by the app. |
| `nexusDataAsOfTime` | `string \| null` | ISO time when Nexus produced the data. |

`NexusMatch`:

| Field | Type | Notes |
| --- | --- | --- |
| `label` | `string` | Required. `Practice N`, `Qualification N`, `Playoff N`, `Final N`, optionally followed by ` Replay`. |
| `status` | `string \| null` | `Queuing soon`, `Now queuing`, `On deck`, `On field`. Can be missing for future matches. |
| `redTeams`, `blueTeams` | `(string \| null)[] \| null` | Team numbers without `frc`. Practice slots can be null, and playoff alliances can have 4 teams. |
| `times` | object | Every member is a number of ms since epoch, or null. |
| `times.scheduledStartTime` | `number \| null` | |
| `times.estimatedQueueTime`, `estimatedOnDeckTime`, `estimatedOnFieldTime`, `estimatedStartTime` | `number \| null` | |
| `times.actualQueueTime`, `actualOnDeckTime`, `actualOnFieldTime` | `number \| null` | |
| `breakAfter` | `string \| null` | |
| `replayOf` | `string \| null` | Label of the match being replayed. |

### How the app uses it

- `packages/core` (`NexusEventStatus.fromHoneycombEvent`) parses each match on
  its own. A match without a usable label is skipped and logged as a warning,
  without dropping the rest of the event. Timestamps can be ms, seconds,
  numeric strings, or ISO strings.
- Labels map to TBA match keys with `nexusLabelToMatchKey`:
  - `Qualification N` becomes `{event}_qmN`.
  - `Playoff N` becomes `{event}_sfNm1`.
  - `Final N` becomes `{event}_f1mN`.
  - A replay maps to the same key as the original match and replaces it.
  - Practice matches have no TBA key and are hidden from Up Next.
- `packages/services` (`upNextFeedProvider`) uses the Nexus matches when there
  is at least one qualification or playoff match. Otherwise it falls back to
  `GET /matches?event=` and shows why Nexus was not used.

## Error behavior

| Situation | Honeycomb today | Should be |
| --- | --- | --- |
| No token / no `external.read` | `401` / `403` | Same. The app shows "Not allowed to read event data". |
| TBA event not found | TBA's status, for example `404` | Same. |
| `NEXUS_API_KEY` missing or invalid | `200` with `matches: []` and no reason given | `200` with empty Nexus fields plus a `nexusError` string. Log the Nexus status. |
| Nexus has no data for the event | `200` with `matches: []` | Same, with `nexusError` explaining it. |
| Nexus response fails schema validation | `200` with `matches: []`, so one bad field drops the whole event | Accept the nullable shapes above. Log what failed. |
| Nexus slow or down | `200` with `matches: []` after the timeout | Same, with `nexusError`. |

The app logs every failure it can see (`Nexus: ...` in the debug console), but
it cannot tell the silent cases apart because Honeycomb returns the same empty
data for all of them.

## Known backend gaps (handoff)

These need changes in the TypeScript Honeycomb. The app does not depend on them,
but Nexus data will keep disappearing until they ship.

1. **Schema too strict** (`src/schemas/nexusEventStatus.ts`):
   - `status: z.string()` should be `z.string().nullable().optional()`.
   - `redTeams` and `blueTeams` should be
     `z.array(z.string().nullable()).nullable().optional()`.
   - Remove `.int()` from the `times` fields, and add `actualStartTime` and
     `actualCommitTime` if Nexus sends them.
2. **Silent failures** (`tryOrNull` in `src/functions/events.ts`): log the error
   with `context.warn`, and optionally return it as `nexusError` on the event.
3. **Demo events**: Nexus demo keys are not TBA events, so `/events?event=demo...`
   returns TBA's `404`. Add either a `nexusEvent=` query parameter that
   overrides the Nexus key, or skip TBA when the key starts with `demo`.
4. **Caching**: each app polls every 15 seconds. Cache Nexus responses in memory
   per Nexus key for 10 to 15 seconds so many open apps make one upstream call.
5. **Event code casing**: unverified whether `first_event_code` matches the
   Nexus key's casing for every event (for example `2026newton`).
