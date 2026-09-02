# Bearings

### FRC scouting and strategy

Bearings is our collection of apps for scouting, strategizing, and scheming with data at FRC competitions. All of it is
written in Dart and in this monorepo for simplicity when developing across multiple apps.

---

## Apps

### [Beariscope](apps/beariscope)

The strategy app. Runs on personal devices like phones and laptops.

### [Bearimetric](apps/bearimetric)

The scouting app. Runs on team-issued tablets.

### [Honeycomb](backend/honeycomb)

Backend written with Dart Frog. (wip)

### Shared packages

- [`core`](packages/core) - Models and utilities shared by everything, no Flutter allowed.
- [`services`](packages/services) - API client, auth (Auth0), permissions, secure storage, and other Flutter services.
- [`ui`](packages/ui) - Reusable Flutter widgets that drive both apps.

---

## Getting started

```sh
flutter upgrade
melos bootstrap
```

Then use `melos run` for day-to-day tasks: `test`, `analyze`, `format`, `generate`, and `ci`.

## Melos commands

- `melos run format`: apply formatting
- `melos run format:check`: check formatting without writing changes
- `melos run analyze`: analyze all packages
- `melos run generate`: run `build_runner` where needed
- `melos run test`: run Dart and Flutter tests
- `melos run ci`: run the full validation sequence used by CI

## Conventional commits

Conventional commits are a standardized way to write commit messages. They look like this:

```
<type>(<scope>): <description>
```

Notice how everything is lowercase, the type and scope are separated by parentheses, and the description is separated
from the type/scope by a colon and space.

A type is what the commit is doing. Use one of these types:

- `feat` - adding a new feature in the app
- `fix` - fixing a bug
- `chore` - doing repo busywork

You can also signify a breaking change by adding an `!` after the type like this:  
`feat!(services): refactor honeycomb api provider`

A scope is where the commit edits things. Use one of these scopes:

- `beariscope`
- `bearimetric`
- `core`
- `services`
- `ui`
- `honeycomb`
- `repo`
- `workspace`
- `ci`
- `release`
- `docs`

Examples of good commits:

- `feat(beariscope): add pit map refresh`
- `fix(services): retry secure storage read`
- `chore(ci): add a 1% chance to delete pull requests when tests fail`
