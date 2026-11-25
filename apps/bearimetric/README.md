# Bearimetric

Bearimetric is Bear Metal's FRC scouting app. In Bearings it sits beside Beariscope and the shared packages so scouting data models, services, and UI pieces can move together.

## About

Bearimetric is built using Flutter. This enables scouting on Android while keeping it in the app ecosystem.

## Working on Bearimetric

From the monorepo root:

1. Run `dart pub get`
2. Run `melos run generate` if generated files are stale
3. Start the app with `cd apps/bearimetric && flutter run` or by using melos's IntelliJ run configs

## Offline scouting and tablet exports

Use **Prepare for offline** after choosing an event and position. The status
checks for a downloaded schedule, the assigned scouting form, and the scout
roster. The match slider uses that schedule, including playoff matches.

The tablet keeps editable answers in `bearimetric_matches`. Advancing with
incomplete answers leaves a draft. Completed answers are eligible for upload, and
offline edits replace the previous eligible answers for that match. When the
tablet reconnects, Grove delivers an immutable snapshot. Later changes send a
revision after Grove confirms the previous snapshot. Use **Scouting uploads**
in the app bar to check a match or reopen a failed submission.

The fleet export includes the working records from `bearimetric_matches.hive`
and Grove's delivery state in `grove_v2.hive`. Export both when recovering a
tablet. The tool also preserves any older Hive boxes it finds. **Clear Downloaded
Data** clears downloaded content and keeps working answers and pending uploads.
