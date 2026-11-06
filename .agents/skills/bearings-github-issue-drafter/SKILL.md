---
name: bearings-github-issue-drafter
description: Convert rough Bear Metal Apps notes or bullet points into clean, copy-paste-ready GitHub issue drafts for the Bearings repository. Use when the user provides one or more informal ideas, bugs, or desired changes and wants them triaged into Bug/Feature issues with priority and effort ratings, concise titles, useful bodies, and parent-child relationships when appropriate.
---

# Bearings GitHub Issue Drafter

Turn rough Apps notes into GitHub issue drafts with as little bureaucracy as possible.

The user should be able to provide input like:

```text
- team search should ignore punctuation
- rankings aren't showing up sometimes
- picklist needs crossout, locking, notes, and defense/offense markers
- cooler year-specific graphics
```

and receive a clean Markdown document containing the fields needed to create GitHub issues.

## Bearings issue architecture

Use only these issue types:

- **Bug** — existing behavior is broken, incorrect, unreliable, or regressed.
- **Feature** — new functionality or an improvement to existing functionality.

A Feature may have child Features or Bugs. Large Features can act as parent issues.

Use only these priorities:

- **High** — important to core competition use, reliability, data correctness, or a major workflow; should generally be worked before other available work.
- **Medium** — worthwhile functionality or a meaningful problem, but not currently critical.
- **Low** — polish, speculative ideas, small quality-of-life improvements, or work that can comfortably wait.

Use only these effort ratings:

- **Low** — a small, straightforward change with limited scope and little investigation.
- **Medium** — a moderately involved change requiring several related pieces of work, some investigation, or coordination across existing components.
- **High** — a complex change involving substantial investigation, broad architectural work, multiple integrations, or difficult technical uncertainty.

Effort describes how hard the work is likely to be to complete. Rate it independently of priority: an urgent bug may have Low effort, while a Low-priority idea may have High effort.

Do not create milestones, iterations, story points, numeric or time estimates, deadlines, or project statuses.

## Core rules

1. Preserve the user's intent.
2. Do not invent product decisions, implementation details, edge cases, or requirements that were not stated or strongly implied.
3. Prefer a short issue over a detailed issue when the title already explains the work.
4. Do not add sections merely because a template permits them.
5. Do not add acceptance criteria unless they clarify a genuinely non-obvious definition of done.
6. Do not add implementation notes unless the user supplied implementation information.
7. Do not prefix titles with `[Bug]`, `[Feature]`, priority, app name, or issue number. GitHub fields already represent that metadata.
8. Use the user's existing product names and terminology when known.
9. Make titles action-oriented for Features and problem-oriented for Bugs.
10. Do not ask follow-up questions just to make an issue more detailed. Make the best draft possible from the supplied notes. If a missing decision materially affects the issue, include a short `Open question` in the body instead of guessing.

## Triage

For each input item, decide whether to keep it, merge it, split it, or group it.

### Merge

Merge multiple notes when they describe the same underlying problem or change.

Do not create duplicate issues just because the notes use different wording.

### Split

Split a note only when it clearly contains independently useful work that could reasonably be implemented, reviewed, or completed separately.

Do not split a small feature into multiple issues just to create hierarchy.

### Parent Features

Create a parent Feature when several separate issues clearly contribute to one larger named capability or redesign.

Good:

```text
Feature: Picklist redesign
├── Feature: Support crossing out teams
├── Feature: Support locking teams
├── Feature: Add defense/offense markers
└── Feature: Add team notes
```

Do not create a parent merely because several issues happen to be in the same screen or area.

For a parent Feature used mainly for organization:

- Do not assign a priority unless the parent itself represents actionable work.
- Omit effort for purely organizational parents. If the parent itself represents actionable work, rate that work rather than adding up its children's effort.
- Keep the body focused on the overall outcome.
- Output the parent before its children.

### Bug vs Feature

Use **Bug** when the note indicates something that is supposed to work but does not work correctly.

Examples:

- "ranked not showing up sometimes" → Bug
- "offline login breaks after reconnect" → Bug
- "team search should ignore punctuation" → Feature unless the user indicates punctuation-insensitive search was already intended behavior

Use **Feature** for additions, redesigns, improvements, polish, refactors visible as planned work, or new capabilities.

When genuinely ambiguous, prefer **Feature** rather than claiming existing behavior is broken.

## Priority inference

Infer priority conservatively from impact, not from how strongly the note is worded.

### High

Use High when the issue appears to involve:

- data loss or incorrect scouting/strategy data
- crashes or serious reliability problems
- inability to use a core competition workflow
- authentication/sync/offline failures that materially block competition use
- a change the user explicitly marks as urgent, blocking, or high priority

### Medium

Use Medium for:

- meaningful workflow improvements
- useful new capabilities
- bugs with reasonable workarounds
- improvements likely to matter during normal competition use

Medium is the default when an actionable item has no strong High or Low signal.

### Low

Use Low for:

- visual polish
- speculative ideas
- "cooler" or nicer presentation
- minor convenience changes
- explicitly low-priority work

Priority is a suggestion. Do not manufacture urgency from missing context.

## Effort inference

Suggest Low, Medium, or High effort for every actionable issue based on the supplied scope, likely implementation difficulty, and technical uncertainty.

- Use Low for isolated, familiar changes such as a straightforward text, styling, or local behavior adjustment.
- Use Medium for changes spanning several components or requiring moderate investigation, such as adding a workflow to an existing feature.
- Use High for broad rewrites, new protocols or unfamiliar integrations, or technically uncertain work such as automatic autonomous-path collection using AI vision.

Use Medium when there is no strong Low or High signal. Respect effort explicitly supplied by the user. Treat ratings as suggestions; do not imply that the codebase was inspected or invent implementation details to justify a rating. Do not ask follow-up questions just to estimate effort.

Rate each child issue on its own scope. Do not copy a parent's rating to all its children or infer effort from priority.

## Issue title rules

Titles should:

- be concise
- describe one issue
- avoid unnecessary technical wording
- use sentence case
- usually stay under about 80 characters

Feature examples:

```text
[Feature] Ignore punctuation in team-name search
[Feature] Add teams to a comparison drawer
[Feature] Add scout audit review marking
[Feature] Redesign the autonomous scouting UI
```

Bug examples:

```text
[Bug] Rankings sometimes fail to appear
[Bug] Offline login fails after reconnecting
[Bug] Picklist order resets after reconnect
```

## Issue body rules

The body should contain only information that adds value beyond the title.

For a simple issue, one sentence is enough:

```markdown
Team-name search should ignore punctuation, dashes, and similar separators when matching names.
```

For a more involved issue, use a short paragraph and, when useful, a few bullets:

```markdown
Allow users to build a team comparison while browsing Team Lookup.

- Teams can be added from Team Lookup.
- Selected teams can be removed before opening the comparison.
```

Do not restate the title in a `Summary` section.

Do not add empty sections.

Do not output `_No response_`, placeholders, or boilerplate.

## Output format

Return one clean Markdown document and nothing else unless the user asks for explanation.

Start with:

```markdown
# GitHub Issue Drafts
```

Then output each issue using this exact structure.

For a normal issue:

````markdown
## <Title>

**Type:** Bug | Feature  
**Priority:** High | Medium | Low  
**Effort:** Low | Medium | High

### Body

```markdown
<copy-paste-ready GitHub issue body>
```
````

If the body would add no useful information, write:

```markdown
### Body

_No body needed._
```

For a child issue, add:

```markdown
**Parent:** <parent issue title>
```

after Effort.

For a purely organizational parent Feature, omit both Priority and Effort:

````markdown
## Picklist redesign

**Type:** Feature

### Body

```markdown
Improve the picklist workflow through a set of independently shippable changes.
```
````

If the user's input explicitly names an assignee, include:

```markdown
**Assignee:** <name or GitHub username>
```

Otherwise omit Assignee entirely.

## Ordering

When producing multiple issues:

1. Parent Features first.
2. Their children immediately after them.
3. Remaining High-priority issues.
4. Then Medium.
5. Then Low.

Do not add a summary table because it duplicates the issue fields.

## Ambiguity

If a detail is important but unresolved, put a short section in that issue's body:

```markdown
### Open question

Should this setting persist per device or per user?
```

Only do this for decisions that materially affect the work.

Do not ask the user questions before producing the drafts.

## Non-software notes

If an input item clearly belongs outside the Bearings software tracker, do not force it into a Bug or Feature.

At the end, only when needed, add:

```markdown
# Not Software Issues

- <note> — <brief reason>
```

Examples include scout training reminders, event logistics, or hardware work unrelated to the repository.

## Example

Input:

```text
- Searching team names should ignore punctuation, dashes, etc
- ranked not showing up?
- picklist should let us cross out and lock teams, and mark defense/offense
- cooler graphics, maybe year specific
```

Output:

````markdown
# GitHub Issue Drafts

## Improve picklist team management

**Type:** Feature

### Body

```markdown
Improve picklist team management with separate controls for excluding and categorizing teams.
```

## Support crossing out teams

**Type:** Feature  
**Priority:** Medium  
**Effort:** Low  
**Parent:** Improve picklist team management

### Body

_No body needed._

## Support locking teams

**Type:** Feature  
**Priority:** Medium  
**Effort:** Low  
**Parent:** Improve picklist team management

### Body

_No body needed._

## Add defense/offense markers

**Type:** Feature  
**Priority:** Medium  
**Effort:** Low  
**Parent:** Improve picklist team management

### Body

_No body needed._

## Rankings sometimes fail to appear

**Type:** Bug  
**Priority:** Medium  
**Effort:** Medium

### Body

```markdown
Team rankings sometimes do not appear when expected.
```

## Ignore punctuation in team-name search

**Type:** Feature  
**Priority:** Medium  
**Effort:** Low

### Body

```markdown
Team-name search should ignore punctuation, dashes, and similar separators when matching names.
```

## Add year-specific graphics

**Type:** Feature  
**Priority:** Low  
**Effort:** Medium

### Body

```markdown
Add optional year-specific visual elements to make the app feel more connected to the current game.
```
````

## Final check

Before responding, verify:

- Every software issue is either Bug or Feature.
- No Epic, Story, Task, Enhancement, milestone, status, numeric or time estimate, or deadline was invented.
- There are no duplicate issues.
- Parent-child structure exists only where it makes the work clearer.
- Priority is High, Medium, or Low when included.
- Every actionable issue includes Low, Medium, or High effort, rated independently of priority. Purely organizational parents omit effort.
- Bodies are concise and contain no invented implementation details.
- The output is directly copyable into GitHub fields.
