# Item anatomy (DP-ITEM)

The item block is what one planner item looks like and carries: its colour, its icon, its time
line, its done control, how a task differs from a calendar event, its subtasks and its context
chips. It holds all 7 DP-ITEM patterns from research `ANALYSIS.md` section 3.4. Sizes are in pt
(1 CSS px in the Sidekick's WKWebView). Colours are theme tokens (CSS custom properties, defined
in `recipe.md`); the value in brackets is the Structured preset value from
`structured-ui-teardown.md`. "Checklist N" is item N of `checklist.md` (the numbering of research
`ANALYSIS.md` section 6). Screenshot paths are relative to the shots folder named in
`ANALYSIS.md` section 8. Tests assume a fixed clock and a seeded store.

Structured preset palette, `--palette-1` to `--palette-12` (order of "Choose a color › Presets",
teardown 2.1): #F49F99 salmon, #F19C74 apricot, #EAA93B amber, #91BE6C leaf green, #6085A8 steel
blue, #3A8564 forest green, #974667 plum, #2B5073 navy, #6983A5 slate blue, #9FE0E8 ice cyan,
#D1E6BA pale sage, #EF8583 coral red.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-ITEM-01 | Colour per item | core | Structured 12-colour preset palette |
| DP-ITEM-02 | Icon or emoji per item | on request | Emoji per item, suggested from the title |
| DP-ITEM-03 | Time and duration on the row | core | Structured "7:00–7:15 AM (15 min)" |
| DP-ITEM-04 | Completion control and done state | core | Structured right-side ring, filled with ✓ |
| DP-ITEM-05 | Tasks versus events styling | core | No ring and a calendar glyph on events |
| DP-ITEM-06 | Inline subtasks and progress | on request | Structured "☑ 0/3 ›" chip |
| DP-ITEM-07 | Source and context chips | on request | Structured energy chip |

---

### DP-ITEM-01 Colour per item

**Tag:** core (leave reason 1 names colours behind a paywall as a basic, Readdle 2026).
**Variations:** A, Structured: 12-colour preset palette, hex and sliders, 12 custom presets
(Pro), Color Prediction (beta). B, Tiimo: colour assigned by AI. C, Llama: "🌈 Color Me!" for the
whole list. D, Google: about 200 colours (2026, [R]). E, Readdle: named colours ("Family"). F,
Sunsama: channel colours. G, TickTick: colour by list, tag or priority. H, Timepage: 60+ themes.
I, FlowSavvy: colour by deadline status.
**Default variation:** A, Structured, without the paid and beta parts.

**What it is.** Every item carries one colour. The colour paints its bubble, its line, its ring
and its dots everywhere the item appears.

**Anatomy.**
- Where the colour is used: bubble fill (past, current, done), glyph on a future bubble, line
  segments, completion ring stroke and fill (DP-ITEM-04), week strip dots (DP-NAV-01), editor
  header (darkened about 10–15%, e.g. salmon #F49F99 → about #CF847E).
- Colour row in the Color & Icon sheet: a grey track (`--bg-header`), 36 pt swatches 8 pt apart,
  about 8 visible, scrolls horizontally. Selected swatch: a 3 pt white inner ring.
- "•••" opens "Choose a Color": a hex field, a hue slider and a shade slider (each 28 pt tall,
  fully rounded), and the 4 x 3 preset grid beside a preview bubble.

**States.** New task: `--accent` (#F49F99). Changed: the new colour everywhere at once. Pale
colours (`--palette-10`, `--palette-11`): white glyphs on them have low contrast; the research
does not show what Structured does.

**Interactions.** Tap a swatch: sets the colour, the sheet stays open. Swipe the row: more
swatches. Enter a hex: sets it on a valid 6-digit value.

**Words.** "Color & Icon", "Choose a Color", "Presets", "Reset", "Edit". The App Color setting
(DP-SET-05) says it does not change existing tasks; docs/WRITING.md rule 4 cuts that caption.

**Data.** Writes the task's `colour` as a 6-digit hex string. Reads `settings:self` theme for
the default colour.

**Needs.** Page alone.

**Edge cases.** Leave reason 1: no colour is behind a paywall (Sidekicks sell nothing). A stored
colour that is not a valid hex renders as `--accent` and is not rewritten. Changing the app
accent (DP-SET-05) does not recolour existing tasks.

**Tests.**
- Given a done task with colour #974667, when it renders, then its bubble background is #974667.
- Given a task with colour "zzz", then it renders in `--accent` and the record still holds "zzz".
- Given the app accent changed from #F49F99 to #6085A8, then a task stored with #F49F99 still
  renders #F49F99.
- Given a tap on the 5th swatch, then the record's colour is #6085A8.

**Evidence.** DP-ITEM-01 [C]. Loves: Structured ~40 colour mentions, the most-praised trait
(RG-C); Google 4 (C); Readdle 4 (D); Timepage 2 (C). Complaints: Google "too many now" (1),
colours not matching (1) (C); Readdle colours behind Pro (1, D); Llama has no colour coding (1,
A). Teardown 1.5 "Color & Icon sheet", 2.1. Screenshots: `agent/help/3209090_1.png`,
`d/calendars/appstore_10.png`.

---

### DP-ITEM-02 Icon or emoji per item

**Tag:** on request (no checklist item or leave reason names it, and not every app has it).
**Variations:** A, Structured: 550+ monochrome icons, suggested live from the title by ML, shown
in the bubble. B, Tiimo: emoji or 3D icon chip chosen by AI. C, Llama: "😊 Emoji Me!". D, Ellie:
emoji per list. E, Routinery: icons per step. F, Sorted³: emoji. G, Apple: emoji leading titles.
H, Reclaim: emoji as a status prefix. I, Google: keyword illustrations.
**Default variation:** emoji per item (B, C, F, G), suggested from the title by a keyword map in
the page. The Structured preset uses A's look with a monochrome icon set.

**What it is.** A glyph on every item, inside its bubble.

**Anatomy.**
- In the bubble: 24 pt, centred (DP-DAY-01). Emoji render in colour on any bubble state; a
  monochrome icon follows the DP-DAY-01 glyph colours (task colour on grey, white on fill).
- Picker in the Color & Icon sheet: "Suggestions" (2–3 big glyphs in 56 pt white circles, the
  selected one filled with `--accent`), "Recently Used", category sections, a "Search" field, a
  bottom category bar.
- Structured's icons are SF-Symbol-style. Whether SF Symbols may be drawn inside a web page was
  not checked [U]; an open icon set as inline SVG, or emoji, avoids the question.

**States.** No icon: a default glyph (a dot) so the bubble is never empty. Suggested: the
suggestion updates as the title is typed (DP-ADD-01).

**Interactions.** Tap a glyph: sets it. Search: filters by name. Typing a title updates the
suggestion until the person picks one by hand.

**Words.** "Color & Icon", "Suggestions", "Recently Used", "Search".

**Data.** Writes the task's `icon` (an emoji string or an icon name; absent for none). Recently Used is derived
from existing tasks, not stored.

**Needs.** Page alone. An icon set is inline in the bundle; its size counts against the bundle,
not a record.

**Edge cases.** Checklist 12: picking an icon first never loses a half-typed title. A
hand-picked icon is not replaced by later suggestions.

**Tests.**
- Given the title typed "Coffee", then the suggested icon is the coffee glyph from the keyword
  map.
- Given the person picked 🚲 and then edits the title to "Coffee", then the icon stays 🚲.
- Given a task with no icon, then its bubble holds the default glyph.

**Evidence.** DP-ITEM-02 [C]. Loves: Structured ~30 icon mentions (RG-C); Apple award text
"color-coded, emoji-accented blocks" (A); FlowSavvy user asks for "emojis or symbols for each
task, the way Structured does" (B); Google illustrations 1 (C). Complaints: Gruber "distracting
and childish" (A); Tiimo AI-picked emoji and tags "cluttered" (1, A). Screenshots:
`agent/help/331138_1.png`, `a/tiimo/as_03.png`.

---

### DP-ITEM-03 Time and duration on the row

**Tag:** core (checklist 16 and 25 name it). **Variations:** A, Structured: "7:00–7:15 AM (15
min)" over a bold title, ↻ for repeats, a calendar glyph for imported items. B, Tiimo: "8.30 →
9.00"; Anytime rows show only "30m". C, Sunsama, Ellie: duration pill at the right. D, Sorted³:
"30m → 6:30 AM" chip. E, Routine: "45m" at the right. F, Llama: start→end pill.
**Default variation:** A, Structured.

**What it is.** Line 1 of a row: start, end and length, in the person's clock format.

**Anatomy.** 13 pt regular `--ink-2` (#8A8A8E), above the title. Glyphs after the text, 11 pt:
↻ for a repeating task, a calendar glyph for a calendar event (DP-ITEM-05).

**States.**
- Timed: "{start}–{end} {period} ({duration})"; the period (AM/PM) is written once when both
  times share it, twice when not.
- Zero duration: start only.
- All-day: no time line.
- Untimed with a duration (inbox, Anytime): the duration only.
- Current: replaced by DP-TIME-03.

**Interactions.** None.

**Words.**
- "7:00–7:15 AM (15 min)", "11:30 AM–12:30 PM (1 hr)", "8:30–10:00 AM (1 hr, 30 min)", "7:00 AM".
- 24-hour: "07:00–07:15 (15 min)".
- Durations: "15 min", "1 hr", "1 hr, 30 min", "2 hr". Untimed: "30 min", "2 hr".
- Midnight crossing: "11:00 PM–1:00 AM (2 hr)".
- The dash is an en dash with no spaces. `Intl.DateTimeFormat.formatRange` inserts spaces and
  thin spaces that must be normalised to this form.

**Data.** Reads the `reminder:` task (`at` read in `timeZone`, duration, allDay, repeat), `settings:self` (12/24h).

**Needs.** Page alone.

**Edge cases.** Checklist 16: both clock formats work and follow `settings:self`, not the
locale alone (Structured stuck on 24-hour, 1 complaint). Checklist 25: a task crossing midnight
shows its real end. Apple iOS 27's repeat icon that cannot be hidden eats title space (1
complaint): here the glyph sits on line 1, not the title line.

**Tests.**
- Given 12-hour, start 7:00, 15 min, then line 1 reads exactly "7:00–7:15 AM (15 min)".
- Given 12-hour, start 11:30, 60 min, then "11:30 AM–12:30 PM (1 hr)".
- Given 24-hour, start 7:00, 15 min, then "07:00–07:15 (15 min)".
- Given start 8:30, 90 min, then "8:30–10:00 AM (1 hr, 30 min)".
- Given start 23:00, 120 min, then "11:00 PM–1:00 AM (2 hr)".
- Given a weekly repeat, then line 1 ends with "↻".
- Given duration 0, then "7:00 AM".

**Evidence.** DP-ITEM-03 [C]. Loves: covered by DP-TIME-05. Complaints: Apple iOS 27 repeat icon
eats title space (1, C); Todoist durations only with a time (1, D). Teardown 1.1 "Row text".
Screenshots: `pm.png`, `a/sorted/as_07.png`.

---

### DP-ITEM-04 Completion control and done state

**Tag:** core (checklist 8 names it). **Variations:** A, Structured: a right-side ring in the
task colour, filled with a white ✓. B, Tiimo: right hollow circle; done faded and struck. C,
Sunsama: left circle filled green; done rows greyed at the bottom. D, TickTick, Readdle: square
box coloured by priority or list. E, Todoist: ring coloured by priority. F, Things: blue fill,
row stays, struck. Done items hidden by default (TickTick) or kept with "Done on Oct 14"
(Readdle).
**Default variation:** A, Structured; done items stay in place.

**What it is.** The control that marks an item done, and how a done item looks.

**Anatomy.**
- Ring: 23 pt, 2 pt stroke in the task colour, 16 pt from the right edge, vertically centred on
  the title. Tap target 44 x 44 pt.
- Done: the ring becomes a filled disc in the task colour with a white ✓ (13 pt, 2 pt stroke).
- Done row: title struck through, `--ink` at 60% opacity; bubble filled in the task colour with a
  white glyph.

**States.** Undone, done. A repeating task: done per occurrence. Past, undone: ring stays hollow.

**Interactions.**
- Tap the ring: toggles done. The disc fills with a 200 ms scale (0.8 → 1) and the strike draws
  left to right in 200 ms; under Reduced Motion both are instant.
- Structured plays a sound and a haptic, each toggleable (DP-FB-01, `feedback.md`). A Sidekick
  page has no haptics API; sound is possible in the page.
- Tapping again undoes.

**Words.** None on the row. Accessible label: "Done" or "Not Done" (`aria-pressed`).

**Data.**
- One-time task: `store.update` with `done: true`, `completedAt` now and `doneDay` today (the
  same Done change the shell writes, NOTIFICATIONS.md 4.5). Undo: `done: false`, `completedAt`
  and `doneDay` removed.
- Repeating task: writes `exception:<taskId>:<date>` with `done`, `completedAt` and `doneDay` for
  that occurrence, plus the repeat Done change on the task (`lastDoneAt` now, `doneThrough` that
  occurrence, never earlier than the stored one; records.md 3.5). The series stays `done: false`.
- Alerts: they are the task's own `alerts`, so they follow the record. For a one-time task,
  `done: true` stops every notification of the task; undo brings back those still ahead.

**Needs.** Page alone for the view and the task record. The notification engine (shell has it)
cancels a one-time task's alerts. For one done occurrence of a repeat, `doneThrough` moves the early
alerts to the next occurrence, but the task's own repeating notification still fires on that
occurrence (records.md 3.5): `shell/repeat-exceptions.md`.

**Edge cases.**
- Checklist 8: done looks distinct.
- Checklist 23: `completedAt` and `doneDay` record the real moment and day, so a carried-over task records the day it was
  actually done.
- Checklist 43: alerts for a done one-time task never fire.
- Checklist 54: done can be undone by tapping again (and by DP-FB-04).

**Tests.**
- Given an undone one-time task, when its ring is tapped at 9:12, then the record has done true
  and `completedAt` 9:12, and the ring element has the filled class.
- Given that task, when the ring is tapped again, then done is false and `completedAt` is absent.
- Given a one-time task with a 5-min-before alert ahead, when it is marked done, then its
  `reminder:` record has done true and `completedAt` set (the engine books none of its alerts).
- Given a daily task, when the 14 Oct occurrence is marked done, then `exception:<id>:2026-10-14`
  holds done true, the task's `reminder:` record has no done true and `doneThrough` is the 14 Oct
  occurrence, and 15 Oct renders undone.
- Given a done task, then its title has `text-decoration: line-through`.

**Evidence.** DP-ITEM-04 [C]. Loves: none direct. Complaints: TickTick "completed task
graveyard" (1, RG-A via D). Teardown 1.1 "Bubble states", 3 "Complete". Screenshots:
`agent/help/4511874_1.png`, `d/calendars/appstore_5.png`.

---

### DP-ITEM-05 Tasks versus events styling

**Tag:** core (checklist 4, 36, 38 and 39 name it; love 1). **Variations:** A, Morgen: filled
block = event, outlined block with a checkbox = task. B, Motion: tinted event with a left bar vs
a card with an open circle. C, FlowSavvy: events have no checkbox. D, Fantastical: dot vs empty
square. E, Google: check-circle task pills. F, Apple: reminders as one-line rows with a circle.
G, Things: events as one grey read-only card on top of Today. H, Todoist: events above tasks,
read-only. I, Akiflow: a source icon per row. J, Structured: a calendar glyph on imported items.
**Default variation:** C and J together: an event is a bubble with no completion ring and a
calendar glyph after its time line.

**What it is.** Tasks and calendar events on one surface, told apart at a glance.

**Anatomy.**
- Event bubble: same shape as a task (DP-DAY-01), in the calendar's colour, glyph a calendar
  icon unless the event has none other.
- Line 1 ends with an 11 pt calendar glyph.
- No completion ring; the right side is empty.
- Past and current fill follow DP-TIME-02 like a task.

**States.**
- No calendar access (none, denied, not built): tasks only; no banner, no error.
- Write-only access: the page cannot read events; it says so in DP-SET-06, not here.
- Events present: drawn among tasks in time order; overlaps follow DP-TIME-08.

**Interactions.** Tap an event: a read-only card with title, time and calendar name. Editing an
event in the planner needs calendar write (two-way), which is not built.

**Words.** Card: the event title, the DP-ITEM-03 time line, the calendar name.

**Data.** Tasks: `reminder:` records (`planner.item`). Events come from the calendar read described
in `shell/calendar-access.md`; they are not `reminder:` records. Apple Reminders brought in by the
existing import become `reminder:` tasks with a `source` (`{ kind, externalId }`), styled as tasks.

**Needs.** Shell lacks it: calendar read (and write for two-way), `shell/calendar-access.md`. The
page alone covers its own tasks.

**Edge cases.**
- Checklist 36: the page works with its own items when calendar access is none or denied.
- Checklist 38: events shown match the calendar within minutes (depends on the shell brief).
- Checklist 39: two-way edits (depends on the shell brief).
- Checklist 4: events and tasks on the same timeline.

**Tests.**
- Given no calendar access, when today renders with 3 tasks, then 3 rows render and no error or
  permission text is in the DOM.
- Given an event 10:00–11:00 from the calendar result, then its row has no completion ring and
  line 1 ends with the calendar glyph.
- Given a tap on that event, then a read-only card opens and the task editor does not.

**Evidence.** DP-ITEM-05 [C]. Loves: "tasks and calendar in one view" B 8, C 5, D 8 plus 4;
Readdle 9 distinct praise quotes; Reddit time-blocking thread (E). Complaints: TickTick cannot
create a real event (2, D); Todoist shows only 4 meetings and has no iCloud (3, D); Things widget
shows no events (1, D). Leave reason 3 (calendar sync). Screenshots: `d/morgen/appstore_2.png`,
`b/appstore/motion_6.jpg`.

---

### DP-ITEM-06 Inline subtasks and progress

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Structured:
"☑ 0/3 ›" chip on the row, expands inline (4.4+). B, Morgen: "0/2" with a chevron. C, Ellie:
"↻ 0/2". D, Tiimo: routine "1/3" bar. E, Routinery: steps inside a routine card.
**Default variation:** A, Structured.

**What it is.** A progress chip on the row; tapping it opens the subtasks in place, where they
can be checked.

**Anatomy.**
- Chip on line 3: 24 pt tall, radius 12, `--bg-header` background, 13 pt `--ink-2`: a checkbox
  glyph, "0/3", a chevron.
- Expanded: one line per subtask, 32 pt: a 18 pt rounded-square checkbox with an `--accent`
  stroke (filled `--accent` with a white ✓ when done), title 15 pt `--ink`, struck when done.
- The row grows to fit; the bubble keeps its DP-DAY-01 height and the line continues past it.

**States.** No subtasks: no chip. Collapsed. Expanded. All done: chip reads "3/3"; the task is
not marked done by this.

**Interactions.** Tap the chip: expand or collapse (200 ms height). Tap a subtask checkbox:
toggles it.

**Words.** "{done}/{total}".

**Data.** Reads and writes the task's `subtasks` (a list of title and done). For a repeating
task, ticking a subtask of one occurrence writes that occurrence's whole `subtasks` into its
exception (records.md 5).

**Needs.** Page alone.

**Edge cases.** The 64 KB record limit holds subtasks and notes together; a very long list can
reach it, and `store.set` or `store.update` then rejects.

**Tests.**
- Given 3 subtasks with 1 done, then the chip reads "1/3".
- Given a tap on the second checkbox, then the record's second subtask has done true and the chip
  reads "2/3".
- Given all 3 subtasks done, then the task's done stays false.

**Evidence.** DP-ITEM-06 [C]. Loves: Llama "goblin tasks-style task breakdowns" 1 (A).
Complaints: none found. Teardown 0 (4.4 row), 1.1 "Row text". Screenshots:
`agent/help/338050_5.png`, `a/routinery/as_05.png`.

---

### DP-ITEM-07 Source and context chips

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Akiflow:
source icon and name (Gmail, Slack, Notion). B, Sunsama: "# channel" in colour. C, Sorted³: list,
tag and "⚠ Important" chips. D, TickTick: list name. E, Todoist: "# project" and assignee. F,
Structured: energy "⚡ 2" and a replan badge.
**Default variation:** F, Structured energy chip.

**What it is.** Small chips on line 3 naming where an item came from or what it costs.

**Anatomy.** Line 3, 13 pt `--ink-2`, chips 20 pt tall, 6 pt apart: energy as "⚡ 2", "⚡⚡ 6",
or "🪷 1" for a relaxing task; a notes glyph when the task has notes.

**States.** No energy and no notes: no line 3.

**Interactions.** None on the chip; tap the row for the editor.

**Words.** "⚡ {points}". The points per energy level are not settled by the research (Structured
shows "⚡ 2" for low and "Low Energy … 4 Points" in its editor).

**Data.** Reads the task's `energy`, `notes`. A source chip (variations A to E) reads `source`
(`{ kind }`); Structured's replan badge reads `replanCount`.

**Needs.** Page alone.

**Edge cases.** None from the checklist.

**Tests.**
- Given a task with energy set and notes, then line 3 holds an energy chip and a notes glyph.
- Given a task with neither, then the row has no line 3 element.

**Evidence.** DP-ITEM-07 [C]. Loves: Akiflow "universal inbox" 2 plus Routine 1 (B). Complaints:
none found. Teardown 1.1 "Row text", 1.5 "Energy sheet". Screenshots: `b/appstore/akiflow_1.jpg`,
`b/appstore/sunsama_3.jpg`.
