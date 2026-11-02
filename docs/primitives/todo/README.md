# To-do list primitive

The building docs for to-do list Sidekicks (founder, 2026-10-31): "build one with all these as
primitives and then give a basic version; users can change and edit as needed." A to-do list is
the plain personal list (Things, Todoist, Apple Reminders, Microsoft To Do and the others in the
research). The Claude Code link and the founder's own two views come later, when the primitive is
made his own.

A **primitive** is everything an agent, or later the generator, needs to build any to-do Sidekick
without researching the category again:

1. **Page blocks** (`blocks/`): every UI/UX pattern from the research, each with its variations,
   tagged **core** or **on request**, specified so it can be built and tested.
2. **Records** (`records.md`): the record shapes kept through `store`.
3. **Recipe** (`recipe.md`): how to assemble a to-do Sidekick, the **basic preset** (default) and
   the look presets (Paper, Notebook, Soft, Wallpaper, Heat).
4. **Completeness** (`checklist.md`): the checklist, each item tied to blocks and tests.
5. **Make it yours**: every variation is a setting in `settings:self`, so the person changes the
   look and behaviour from the page itself (block TD-SET), without a rebuild.

Prototype (clickable, every variation live):
`docs/mockups/todo-primitive-2026-10-31.html`.

Source research (midas-intel `docs/research/todo/`): `LOOK-ANALYSIS.md`, `look-group-a..d.md`,
`ANALYSIS.md`, `group-a.md` (today models), `group-d.md` (checklist #1–58), plus
`docs/research/reminders/`.

Rules every block follows: `docs/WRITING.md`, `docs/NOTIFICATIONS.md`, `docs/PRODUCT.md`
section 5 (one HTML page, records through `store`, max 64 KB per record, no localStorage or
IndexedDB). Inside a Sidekick the brand palette of `docs/DESIGN.md` does not apply.

## Block index

| File | ID | Patterns |
|---|---|---|
| `blocks/look.md` | TD-LOOK | 01 page style (paper, notebook, soft cards, wallpaper, heat), 02 light/dark, 03 accent and list colour, 04 text size, 05 density, 06 font |
| `blocks/row.md` | TD-ROW | 01 checkbox shape (circle, square, end tick, none), 02 meta line, 03 colour as meaning, 04 emoji/icon, 05 long titles |
| `blocks/done.md` | TD-DONE | 01 tick animation, 02 tick sound (off, ding, rising chimes, pop), 03 haptic, 04 celebration, 05 where done goes (stay struck, sink, hide, logbook), 06 undo with name, 07 logbook / done today |
| `blocks/capture.md` | TD-ADD | 01 floating +, 02 drag + to a spot, 03 always-on bar, 04 tap-to-add row per section, 05 natural language with live highlight, 06 insert between |
| `blocks/gestures.md` | TD-GEST | 01 swipe right/left (configurable), 02 drag to reorder (drop line above finger, no accidental nest), 03 long press menu, 04 keyboard (laptop) |
| `blocks/navigation.md` | TD-NAV | 01 home style (list, tiles, tab bar), 02 smart lists (Today, Upcoming, All, Logbook), 03 user lists, 04 search everywhere incl. done |
| `blocks/today.md` | TD-DAY | 01 today model (stay, carry over, fresh start, date-gated), 02 parts of day, 03 upcoming by day, 04 overdue without shame |
| `blocks/item.md` | TD-ITEM | 01 detail card, 02 notes, 03 subtasks, 04 repeat (schedule or after done), 05 date, time, deadline, 06 move list, delete |
| `blocks/settings.md` | TD-SET | 01 make it yours panel, 02 presets, 03 first open, 04 import from Reminders, 05 empty and all-done states |
| `blocks/outside.md` | TD-OUT | 01 notifications for timed items, 02 widget, 03 Lock Screen / Control Center add |

Block template: same as `docs/primitives/daily-planner/README.md` ("Block template"), with IDs
`TD-XXX-NN`.

## Core or on request

Core: its absence is a leave reason or a checklist item (`LOOK-ANALYSIS.md` sections 3 and 4), or
every loved app has it. Everything else is on request. Proposal; the founder edits it.

## Status

Docs and a prototype. The Sidekick itself is built after the founder tries the prototype.
Written 2026-10-31.
