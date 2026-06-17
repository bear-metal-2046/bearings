# Changelog

## v26.5.0
**Released:** 2026-04-25

### Bug Fixes
- beariscope: Fix image sharing build issue on web (1b2e046)


### Features
- pawfinder: Fix crash in strat scouting (07c7205)
- beariscope: Add ranking score and match labels to team card (f837742)
- beariscope: Add icon labels to team card graphs (ce5dcf7)
- beariscope: Add team website link to team card media tab (fccce1b)
- pawfinder: Add match spam check and color scheme settings (84a6b31)
- beariscope: Collapse team card when there's no data (dae4e0e)
- beariscope: TBA deviation calculations use point difference instead of percent difference (501ad3d)
- repo: Beached and high center added to tele and average in team card, and to pawfinder (4739478)
- beariscope: Added broken down/ defense symbols to the graph in the graph tab (abcf599)
- Feat(beariscope: clean up visuals

* fix(services): make networkFirst cache policy the default

* fix(beariscope): standardize AppBar padding across all pages

* fix(beariscope): fix changing accent color opacity in appearance settings

* feat(beariscope): add observations and sort notes by upload time

* feat(beariscope): add customizable app icons on iOS

* chore(deps): clean up pubspecs (02f8663)


## v26.4.0
**Released:** 2026-04-08

### Features
- pawfinder: Overhaul how match form looks (6d789fe)
- beariscope: Add media tab to team card (2a7a2c3)
- beariscope: Improve media tab image gestures (a782201)
- beariscope: Add links for cd threads, cad, videos in media tab (3309fa6)
- beariscope: Redesign event selection and sidebar menu; change provision payload (1581f03)
- beariscope: Clean up and remove unused code (76195d2)
- beariscope: Enhance caching and clean up code (954bdc6)
- beariscope: Fix drawer swipe gesture logic (d10214b)
- beariscope: Add strat to scout audit and stop uploading duplicate strat docs (25d0d57)
- pawfinder: Add match select dropdown when scouting (a49b180)
- beariscope: Add match lookup page (4741a56)
- beariscope: Add tower capability to team card (27e6c0b)
- beariscope: Update ios/macos project, switch to swift pm from cocoapods (8cf9782)


## v26.3.3
**Released:** 2026-03-29

### Bug Fixes
- beariscope: Fix wromg permissions in main view (74eb823)


### Features
- beariscope: Add permission checks for exporting notes (ce08179)
- beariscope: Sort match documents by match number (585a2c3)
- beariscope: Add matches after schedule to scout audit (f31f82d)
- beariscope: Add anonymization option for scouter names in exports (5c65c49)
- beariscope: Add defended against to expanded team card (74395ef)


## v26.3.2
**Released:** 2026-03-27

### Features
- beariscope: Update team card with graph, z-score ranks (2f89b18)
- beariscope: Add version number to splash and welcome page (fea68e6)
- beariscope: Show scouter name alongside matches and pits (4119af8)
- beariscope: Add matches with 0 teams scouted to audit page (dc2c238)


## v26.3.1
**Released:** 2026-03-27

### Bug Fixes
- beariscope: Fix error in pits scouting page (c41e24e)
- services: Update token storage to use shared prefrences on web (8828a17)


## v26.3.0
**Released:** 2026-03-27

### Features
- beariscope: Add team colors to team cards (28959f5)
- repo: Pits scouting and playstyles changes (3496f3c)
- beariscope: Add data export, scout audit pages, ui tweaks (44729b2)
- beariscope: Add custom color picker to theme selector (a8bd335)
- pawfinder: Add defended to post match (276bfd3)
- ci: Update AppImageBuilder and release workflows (3160ac5)


## v26.2.2
**Released:** 2026-03-21

### Features
- beariscope: Improve up next page sorting and ux (f04af86)
- beariscope: Add tba beta site toggle (acba6c4)
- beariscope: Improve team card, add sorting to team lookup (53575ab)


## v26.2.1
**Released:** 2026-03-20

### CI
- release: Fix release workflow to stop errors (bef8aad)


## v26.2.0
**Released:** 2026-03-20

### Bug Fixes
- Fixing formattign (5f7a296)
- Fixed an error i accidentally made (1a5f305)
- Android build now uses flutter doctor to accept licences (8201e2b)
- Change email local part checks to just use email instead (3130da8)
- Remove random link from README (753dddd)
- Post sign in onboarding + sign out fixed (9f0af38)
- Pits scouting map didn't prefill the forum (9cab14a)
- Fixed file names (9f61d13)
- Fixed merge conflicts (a9a93a0)
- Fixed android gradle thing (a281088)
- Fixed hive (6f6d6f1)
- Fixed problems with rebasing and such, Will create new branch for future merging and I need to connect all the systems together ASAP (cb17a1f)
- Fixed android gradle thing (04a8988)
- Fixed hive (242a875)
- Fix ci caching issues (4b8e6a1)
- Fixed alot, trying to size big_int_button (987baec)
- Fixed alot, with match creator (87b852f)
- Fixed dropdown (0d7f2d0)
- Fixed dropdown (e4b65b9)
- Fix android (5aa4b77)
- Fixed slider, text box and added play style (489bb0b)
- Fixing conflicts (3f55c8d)
- Fixing conflicts pt 2 (256b8e6)
- Fix merge conflicts (43f9b55)
- Fix crash in match scouting (aef86d9)
- beariscope: Change accuracy percentages to be 10x less (634167c)
- beariscope: Change up next page to show all teams' matches in the current event and get rid of past tab (456a8eb)


### Build
- Build release with android debug mode; fix hive python export (876be65)


### CI
- Ci: add Azure Static Web Apps workflow file
on-behalf-of: @Azure opensource@microsoft.com (977a62c)
- release: Fix syntax in user ID in release workflow (722ca9a)


### Chores
- Initialize bearings monorepo (0da1744)
- Apply dart format and dart fix (4752e64)
- Apply dart format and dart fix (01657d8)
- Apply dart format and dart fix (5518bda)
- Apply dart format and dart fix (86c36b3)
- Update git-cliff-action to v4 (50d7b7e)
- Bump version to 26.0.0 [skip ci] (e8f17a3)
- Bump version to 26.0.0 [skip ci] (cd14193)
- Bump version to 26.0.0 [skip ci] (cff3101)
- Update Gradle and Android plugin versions to latest (5f9d730)
- Bump version to 26.0.0 [skip ci] (440ffc8)
- Update README with better wording (222cad1)
- Remove server project reference in readme (aed0d9a)
- Update libkoala to 5.0.0 (d6a40bc)
- Apply dart format and dart fix (61091e4)
- Restore riverpod_lint in dev dependencies (8a0e312)
- Bump version to 26.0.1 [skip ci] (628a165)
- Format & update deps (4923f61)
- Apply dart format and dart fix (a2b802e)
- Update deps (84e129c)
- Bump version to 26.1.0 [skip ci] (a05a0ab)
- Release workflow now bases build number on existing number in pubspec (2e33abd)
- Bump version to 26.1.1 [skip ci] (5f8d527)
- Make the readme look better (d2c8948)
- Bump version to 26.1.2 [skip ci] (154c829)
- Clean up monorepo migration (ba48ec5)
- pawfinder: Remove giant problems report file (a879ab1)
- repo: Dart format (88b6164)
- pawfinder: Dart format . (b572362)
- pawfinder: Dart format . again (a2eebcc)


### Documentation
- repo: Update README to clarify conventional commits (a7b1e7b)


### Features
- Completely refactor CI/CD workflows (6415726)
- Update build workflows to fix issues and actually build (2667c6a)
- Add scout selection page (0638769)
- Switch to using Auth0 rather than Entra (805793f)
- Add about page (74e5fb2)
- Add CurrentEvent provider and settings tile (84627cb)
- Add scouter CSV import functionality (99f013e)
- Add roles and user editing (1976f3d)
- Update all Icons to use Symbols instead; replace deprecated providers (15e314c)
- Add team lookup page & card functionality (6e9238c)
- Add pits data fetching and fix it's widgets (0e41ad0)
- Add post sign-in onboarding (dde24af)
- Create pits scouting scouting page (47a8970)
- Change pits scouting scouting page to reflect car (154f170)
- Migrate iOS to newer UIScene lifecycle (15f8efb)
- I hate apple (f6e9425)
- Add full functionality to team cards (2841124)
- Add sorting by ranking to team lookup (5543611)
- Add pull to refresh + new libkoala (71c7603)
- Add filters for last n matches to team card averages tab (a5c83a6)
- Add api credits to about page (1832055)
- Add pits scouting map view (d57b204)
- Fix arrow rendering in pits map (e4930d2)
- Update pits for stability (cc69a80)
- Prep for app store review (fb7c4bd)
- Add privacy policy around the app (af1150e)
- Display codename around app (5d63e61)
- Add drive team notes functionality (1d50a33)
- Add pawfinder device provisioning (aeae05c)
- Add z-score for strat, add drive team notes (3d896eb)
- Pits scouting scouting page changes from feedback (6a7b085)
- Bundle fonts with app to avoid downloading them (c4a5d42)
- Update team card details to match pawfinder (3e34918)
- beariscope: Add jingle easter egg (caec1e8)
- repo: Added no show in post match, next match tab automatically goes to auto now, play style shows all the play styles instead of just index, color coded red and blue alliance, changed averages to 0-100%, changed up next page to show all teams matches for each current event (6f22c88)
- repo: Added no show in post match, next match tab automatically goes to auto now, play style shows all the play styles instead of just index, color coded red and blue alliance, changed averages to 0-100%, changed up next page to show all teams matches for each current event (d220133)
- Feat(beariscope): add an option to choose to view our teams' matches vs all matches
t (b9821d7)
- beariscope: Update match filter and improve UI in up next (35c75d3)
- beariscope: Match preview and pits functional edits (3355310)
- Feat!(pawfinder): strat page should be done (013fbc5)
- services: Completely refactor data sync and move internal code (e476b72)
- beariscope: Rename defensive susceptibility to defensive resilience (7eb9c66)


### Refactoring
- Refactor!(pawfinder): StratStateNotifier changed to have two human player scores (6ac4da9)
- Refactor!(pawfinder): fixed an oopsie poopsie in scout_upload_service.dart (3ee15e3)


# Changelog