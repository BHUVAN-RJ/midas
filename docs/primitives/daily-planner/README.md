# Daily planner primitive

The building docs for daily planner Sidekicks (founder, 2026-10-12). A daily planner is its own
category: the user's day laid out in time, tasks and events together (Structured, Tiimo,
Sunsama, Fantastical and the others in the research). Trigger: a friend of the founder asked for
a Structured-style app.

A **primitive** here is everything an agent, or later the generator, needs to build any daily
planner Sidekick without researching the category again:

1. **Page blocks** (`blocks/`): every UI/UX pattern a planner page is made of, specified so it
   can be built and tested. All 69 patterns from the research, each tagged **core** (any planner
   needs it on day one) or **on request** (built when a user asks).
2. **Records** (`records.md`): the record shapes a planner keeps through `store`, and how they
   meet the shell's notification engine.
3. **Shell briefs** (`shell/`): the native pieces a planner needs that the shell does not have
   yet, written as briefs for a shell agent. Not approved to build; the founder decides each.
4. **Recipe** (`recipe.md`): how to assemble a planner Sidekick from the blocks, with presets
   (the Structured preset first).
5. **Completeness** (`checklist.md`): the 56-item checklist, each item tied to the blocks and
   records that satisfy it and the test that proves it.

Source research (midas-intel, read for evidence, quotes and screenshots):
`docs/research/daily-planner/ANALYSIS.md` (pattern catalogue, loves, leave reasons, checklist,
Part 3), `structured-ui-teardown.md`, `group-a.md` to `group-d.md`,
`category-and-completeness.md`, `BRIEF.md`.

Rules every block follows: `docs/WRITING.md` (words), `docs/NOTIFICATIONS.md` (alerts),
`docs/PRODUCT.md` section 5 (one HTML page, no native API, records through `store`, max 64 KB per
record, no localStorage or IndexedDB, bundle rules). Inside a Sidekick the brand palette of
`docs/DESIGN.md` does not apply: a Sidekick has its own look.

## Files

| File | Holds |
|---|---|
| `README.md` | This index, the core/on-request rule, the block template |
| `recipe.md` | Assembly order, presets, what a planner Sidekick's manifest and page contain |
| `records.md` | Record types, fields, keys, size, how alerts reach the engine, what is not mapped |
| `checklist.md` | Completeness checklist mapped to blocks and tests |
| `blocks/day-view.md` | DP-DAY, 7 patterns |
| `blocks/time.md` | DP-TIME, 9 patterns |
| `blocks/navigation.md` | DP-NAV, 8 patterns |
| `blocks/item.md` | DP-ITEM, 7 patterns |
| `blocks/capture.md` | DP-ADD, 8 patterns |
| `blocks/rescheduling.md` | DP-RES, 7 patterns |
| `blocks/focus.md` | DP-FOC, 5 patterns |
| `blocks/feedback.md` | DP-FB, 4 patterns |
| `blocks/outside.md` | DP-OUT, 7 patterns |
| `blocks/settings.md` | DP-SET, 7 patterns |
| `shell/*.md` | One brief per native piece not built (calendar access, local-time alerts, repeat exceptions, planner widget, Live Activity) |

## Core or on request

A pattern is **core** when its absence is a reason users leave or a completeness checklist item
(research `ANALYSIS.md` sections 5 and 6), or when every app in the research has it. Everything
else is **on request**: specified here, built when a user asks ("start minimal, rebuild on
request", 2026-10-08). The tag is a proposal from the research; the founder edits it.

## Block template

Every pattern in `blocks/` uses this shape, so agents and the generator read them the same way.

```markdown
### DP-XXX-NN Name

**Tag:** core | on request. **Variations:** A, B, C (one line each; which app does which).
**Default variation:** the one the recipe uses unless a preset says otherwise.

**What it is.** Two or three sentences.

**Anatomy.** Parts on screen, sizes in pt, colours as tokens (see recipe.md theme), font sizes and
weights. Values from the Structured teardown where the Structured preset uses them.

**States.** Empty, one item, many, overloaded, past, current, done, offline, permission denied:
whichever apply, with what each shows.

**Interactions.** Tap, long press, swipe, drag, pull; what each does; motion (duration, curve);
haptics if any (note: a Sidekick page has no haptics API; say so where the research pattern has
one).

**Words.** Every on-screen string, following docs/WRITING.md.

**Data.** Records read and written (records.md names), fields used.

**Needs.** Page alone | shell has it (name it) | shell lacks it (link shell/ brief).

**Edge cases.** Checklist items (checklist.md numbers) this pattern must handle, and how.

**Tests.** Checks that can fail for the reason they exist: given, when, then.

**Evidence.** Research IDs, quote counts, screenshot path from ANALYSIS.md section 8.
```

## Status

Docs only. Nothing here is approved to build: "discuss, the founder approves, then build"
(`CLAUDE.md`). Written 2026-10-12.
