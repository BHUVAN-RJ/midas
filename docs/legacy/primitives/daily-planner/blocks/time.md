# Time representation (DP-TIME)

The time block is how a planner page shows where the person is in the day and how much time is
in it: the now mark, the current task's fill and countdown, free time, the end of the day,
capacity, planned against actual, overlaps, and outside hints. It holds all 9 DP-TIME patterns
from research `ANALYSIS.md` section 3.2. Sizes are in pt (1 CSS px in the Sidekick's WKWebView).
Colours are theme tokens (CSS custom properties, defined in `recipe.md`); the value in brackets is
the Structured preset value from `structured-ui-teardown.md`. "Checklist N" is item N of
`checklist.md` (the numbering of research `ANALYSIS.md` section 6). Screenshot paths are relative
to the shots folder named in `ANALYSIS.md` section 8. Everything here runs only while the page is
open; outside the page the same information needs the widget or Live Activity briefs. Tests
assume a fixed clock and a seeded store.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-TIME-01 | Now indicator | core | Structured bold time in the gutter, no line |
| DP-TIME-02 | Current-task progress fill | core | Structured top-down bubble fill |
| DP-TIME-03 | Time remaining on the current item | core | Structured "19m remaining" on line 1 |
| DP-TIME-04 | Gap and free-time labels | core | Structured gap row with Add Task |
| DP-TIME-05 | Projected end time and totals | on request | Llama Life "End time" and list total |
| DP-TIME-06 | Overcommit and capacity signals | core | Time capacity against free time (Sunsama-style) |
| DP-TIME-07 | Planned versus actual time | on request | Sunsama "0:30 / 0:30" |
| DP-TIME-08 | Overlap display | core | Stacked with a label (timeline); side by side (hour grid) |
| DP-TIME-09 | Contextual day hints | on request | Timepage "Free after" line |

---

### DP-TIME-01 Now indicator

**Tag:** core (checklist 1 names it). **Variations:** A, Structured: the current time as a bold
label in the gutter, no line. B, Apple, Routine, FlowSavvy: red line with a red time pill. C,
Google, Notion, Motion: black line with a dot. D, Readdle: navy pill. E, Ellie, Morgen: purple
line. F, Routine: the now line drawn inside the current event card. G, Fantastical list, Routine:
past rows greyed instead of a line.
**Default variation:** A, Structured.

**What it is.** A mark for the current moment on today's view. In Structured it is the time
itself, bold, in the gutter; the coloured line above it shows what has passed.

**Anatomy.**
- Label: the current time, 12 pt bold `--ink` (#000000), right-aligned in the 52 pt gutter, its
  centre at the y of now.
- y of now: inside a task, linear within that bubble's height; inside a gap, linear within the
  gap row (DP-DAY-01 layout).
- Any gutter label whose centre is within 14 pt of the now label is hidden.
- Variation B for DP-DAY-02: a 1 pt line in `--danger` (#FF3B30) across the grid, with a pill
  (time 11 pt bold white on `--danger`, radius 4) in the gutter.

**States.** Today: shown. Any other day: not shown. Before day start or after day end: not shown.
Minimal layout (DP-SET-04): the research does not say whether Structured keeps the now label when
other timestamps are hidden; here it stays.

**Interactions.** None. It moves every 30 s and at once on `visibilitychange` to visible. With
Reduced Motion, moves are not animated; otherwise 300 ms linear.

**Words.** The time, formatted by the 12/24-hour setting: "9:41" (12-hour shows no AM/PM in the
gutter, as Structured) or "09:41".

**Data.** Reads `settings:planner` (12/24h, day start, day end). The clock comes from `Date`;
`time.now` in the SDK is display only and is not needed here.

**Needs.** Page alone.

**Edge cases.** Checklist 1: the day opens on today with the mark in the right place (with
DP-NAV-08). Checklist 16: 12-hour and 24-hour both follow `settings:planner`. Checklist 27: with a
day end after midnight (e.g. 3:00), at 1:30 the mark shows on the previous date's view.

**Tests.**
- Given the clock at 9:41, a task 9:00–10:00 and 12-hour time, when today renders, then the
  gutter holds a bold "9:41" whose y is 41/60 of the way down the task's bubble (±1 pt).
- Given 24-hour time, then the label reads "09:41".
- Given 13 Oct is shown and today is 12 Oct, then no now label is in the DOM.
- Given the page hidden at 9:41 and made visible at 11:41, when `visibilitychange` fires, then
  the label reads "11:41" before the next 30 s tick.

**Evidence.** DP-TIME-01 [C]. Loves: no direct quotes; Reddit 2026-06-12 asks for a timeline that
"would show me exactly where I am in my day" (E). Teardown 1.1 "Left time gutter". Screenshots:
`b/appstore/routine_1.jpg`, `c/notioncal/appstore_0.png`.

---

### DP-TIME-02 Current-task progress fill

**Tag:** core (checklist 2 names it). **Variations:** A, Structured: the bubble fills top-down
with the task colour, soft edge; the line above now takes the task colour. B, Akiflow: live cards
with a progress bar. C, Sunsama: a thin day progress bar for done time. D, Tiimo: routine rows
with a bar and "1/3".
**Default variation:** A, Structured.

**What it is.** The task in progress fills with its colour as time passes, so the bubble shows
how much of it is gone.

**Anatomy.**
- Fill: the task colour from the bubble top down to the y of now, over `--bubble-future`
  (#EBEBEB) below.
- Edge: an 8 pt vertical gradient from the task colour to transparent at the fill line.
- Glyph: two copies clipped at the fill line, white above it, task colour below it.
- Line segment above the bubble: task colour once the task has started.

**States.** Future: no fill. Current: partial fill. Past or done: full fill. Done while current:
full fill.

**Interactions.** None. Updates with DP-TIME-01 (every 30 s and on becoming visible). No
transition under Reduced Motion; otherwise a 300 ms linear height change.

**Words.** None.

**Data.** Reads `task:<id>` (start, duration, colour, done). `exception:<taskId>:<date>` for a
changed occurrence of a repeat.

**Needs.** Page alone while open. The same fill on the Home Screen needs
`shell/planner-widget.md`; in the Dynamic Island, `shell/live-activity.md`.

**Edge cases.** Checklist 2 (shows how much is left, with DP-TIME-03). A zero-duration task is
never "current" and has no partial fill. A task crossing midnight fills across both days' views.

**Tests.**
- Given a task 9:00–10:00 and the clock at 9:15, when today renders, then the filled part is 25%
  of the bubble height (±1 pt).
- Given the same task marked done at 9:15, then the fill is 100%.
- Given the clock at 8:59, then the fill height is 0.

**Evidence.** DP-TIME-02 [C]. Loves: Structured "the blocks get gradually colored / filled as the
time goes on" (5★ 2026-08-12, E), inside ~24 "visual" mentions (RG-C). Complaints: none found.
Screenshots: `pm.png`, `agent/help/331010_1.png`.

---

### DP-TIME-03 Time remaining on the current item

**Tag:** core (checklist 2 names it). **Variations:** A, Structured: "19m remaining" in place of
the time line. B, Tiimo: "Now: Brush your teeth / 9:33 left". C, Notion: "Upcoming in 19 min"
sheet. D, Akiflow: "In 2 minutes". E, Amie widget: "1h 35m left".
**Default variation:** A, Structured.

**What it is.** While a task runs, its time line is replaced by how much of it is left.

**Anatomy.** Line 1 of the row, 13 pt regular `--ink-2` (#8A8A8E), same place as the time line
(DP-ITEM-03).

**States.**
- Current, not done: remaining text.
- Current, done: the normal time line (the research does not show which Structured uses).
- Not current: the normal time line.

**Interactions.** None. Updates every 30 s and on becoming visible. Minutes only, no seconds
(Timepage's seconds were called "unnerving").

**Words.**
- Under 1 hour: "{m}m remaining", minutes rounded up ("19m remaining").
- 1 hour or more: "{h}:{mm} remaining" ("2:10 remaining").

**Data.** Reads `task:<id>` (start, duration, done).

**Needs.** Page alone while open. Outside the page: `shell/live-activity.md` (Dynamic Island
countdown), `shell/planner-widget.md`.

**Edge cases.** Checklist 2. Checklist 21: if the task's duration is extended (DP-FOC-02), the
text follows the new end at the next update.

**Tests.**
- Given a task 9:00–10:00 and the clock at 9:41:30, then line 1 reads "19m remaining".
- Given a task 9:00–12:00 and the clock at 9:49:27, then line 1 reads "2:11 remaining".
- Given the clock at 10:00:00 for the 9:00–10:00 task, then line 1 reads the time range.

**Evidence.** DP-TIME-03 [C]. Loves: Tiimo 1 ("live countdown timer at the top of the iPhone
screen", A); Structured 5★ 2026-08-12 (E). Complaints: Timepage second-by-second countdown
"unnerving" (1, C). Screenshots: `a/tiimo/site_subtask_timers.webp`, `c/notioncal/appstore_0.png`.

---

### DP-TIME-04 Gap and free-time labels

**Tag:** core (checklist 3 and 20 name it). **Variations:** A, Structured Full: a stopwatch glyph,
a sentence with the duration in accent, and an "⊕ Add Task" pill; Simplified: "⏱ 3h 15m" only.
B, Routine: centred grey "45 mins". C, Tiimo: a small readout (look not found [U]). D, Timepage:
"Free for the rest of the day afterwards" on the event card.
**Default variation:** A, Structured.

**What it is.** The free time between two items is printed in the gap, with a button to fill it.

**Anatomy.**
- Gap row, 44 pt tall, left edge 16 pt right of the bubble column. The dashed line passes through
  it (DP-DAY-01).
- Stopwatch glyph 15 pt `--ink-2`, then text 15 pt regular `--ink-2` with the duration in
  `--accent` (#F49F99).
- Add Task pill: 28 pt tall, radius 14, `--accent-tint` background, `--accent` text 13 pt
  semibold, "⊕" glyph before the label. The research gives no value for the tint.
- Simplified and Minimal layouts (DP-SET-04): glyph and duration only, no sentence, no pill.

**States.**
- Gap of 5 min or more: row shown. Under 5 min: no label (8 pt gap).
- Overlapping items: no gap row (negative gap).
- Before the first task: from day start (`settings:planner`). After the last: to day end.
- Current gap (now inside it): the duration counts from now to the next item.
- Past gap: Structured shows "Pause concluded. Onwards!" with a Zzz glyph; here a past gap shows
  the dashed line only.
- Empty day: one gap row from day start to day end.

**Interactions.** Tap Add Task: the add sheet (DP-ADD-01) opens with start = the gap start, or now
rounded up to the next 5 min in a current gap; duration = the default from `settings:planner`.
Tap anywhere else in the row: nothing.

**Words.** "{duration} free" ("1h 30m free"), "Add Task". Simplified: "{duration}". Durations:
"30m", "1h", "1h 30m". Structured's eight sentences ("Use 1h 30m wisely. Create away!", "Major
strides in 2h 15m?", "You've got 1h 35m 'til kickoff.", "3h 15m—what's your goal?", "You'll have
30m free.", "Task nears. 12m to strategize.", "A short 25m to breathe.", "Brief 1h. Quick
stretch?") explain nothing the duration does not, so docs/WRITING.md rule 1 cuts them.

**Data.** Reads `task:<id>` (day, start, duration, done, inbox, allDay), `settings:planner`
(day start, day end, default duration, layout via DP-SET-04).

**Needs.** Page alone.

**Edge cases.**
- Checklist 3: free time is visible as free time.
- Checklist 9: Add Task never defaults to midnight; it uses the gap start or now.
- Checklist 20: when a running task is ended early (DP-FOC-02 rewrites its duration), the gap
  after it grows at once.
- Checklist 50: the empty-day gap row is drawn only after the store query returns.

**Tests.**
- Given tasks 8:00–8:30 and 10:00–10:15, when today renders in Full, then one gap row reads
  "1h 30m free" with an Add Task pill.
- Given the Simplified layout, then the same row reads "1h 30m" and has no Add Task pill.
- Given that row, when Add Task is tapped, then the add sheet opens with start 8:30.
- Given the clock at 9:47 inside that gap, then the row reads "13m free" and Add Task opens with
  start 9:50.
- Given a task 9:00–10:00 ended at 9:30 by rewriting its duration to 30 min, and the next task
  at 10:00, then a gap row reads "30m free".
- Given tasks 9:00–10:00 and 9:30–10:30, then no gap row sits between them.

**Evidence.** DP-TIME-04 [C]. Loves: Tiimo 1 ("the most liberating thing I did not understand I
needed", A); Reddit 2026-06-12 "how much time I have" (E). Complaints: none found. Teardown 1.1
"Gap prompts". Screenshots: `agent/help/338050_1.png`, `b/appstore/routine_1.jpg`.

---

### DP-TIME-05 Projected end time and totals

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Llama Life:
"🎉 3:47pm End time" and "List time" in the footer. B, Routinery: estimated ready time, "End:
6:50am" on the Watch. C, Sorted³: "30m → 6:30 AM" per row. D, Sunsama: planned-total pill and a
finish-time line against shutdown time. E, Ellie: a total on the add row [U].
**Default variation:** A, Llama Life.

**What it is.** The sum of what is left, shown as a total and as the clock time the day ends.

**Anatomy.** A footer bar above the tab bar, 44 pt, `--bg-sheet` at 90% with
`backdrop-filter: blur(20px)`. Two values side by side, each a 13 pt `--ink-2` label over a
17 pt semibold `--ink` value.

**States.** No undone tasks left: footer hidden. Past day: hidden. Future day: total only, no end
time.

**Interactions.** None. Updates every 30 s and on any task write.

**Words.** "Planned" over "6h 30m"; "Ends" over "3:47 PM".

**Data.** Reads `task:<id>` (day, start, duration, done). Planned = sum of durations of today's
undone tasks. Ends = the later of (end of the last undone timed task) and (now + the remaining
minutes of undone tasks, untimed ones included). The research does not settle the formula for a
timeline (Llama has a list with no clock times).

**Needs.** Page alone.

**Edge cases.** Checklist 18 and 21: after a shift or an extension, Ends moves. A task crossing
midnight puts Ends on the next day ("1:00 AM").

**Tests.**
- Given undone tasks 9:00–10:00 and 14:00–15:30 and the clock at 9:30, then Planned reads
  "2h 30m" (both durations, undone) and Ends reads "3:30 PM".
- Given the 14:00 task marked done, then Ends reads "10:00 AM".
- Given an untimed task of 4 h and the clock at 13:00, then Ends reads at least "5:00 PM".

**Evidence.** DP-TIME-05 [C]. Loves: Llama 3 quotes ("I can see what time my day will end!"),
Routinery 3 quotes (A). Complaints: none found. Screenshots: `a/llama/as_02.png`,
`a/routinery/as_08.png`.

---

### DP-TIME-06 Overcommit and capacity signals

**Tag:** core (checklist 52 names it). **Variations:** A, Sunsama: a workload counter, yellow then
red against a threshold. B, FlowSavvy: task colour green / orange / red by deadline, a red
triangle with a count, "This task won't be completed on time!". C, Motion: red "!" on tasks and
in the header. D, Reclaim: 🆓 flipping to 🛡️. E, Structured: Energy Monitor ring "19 25" green /
orange / red in the all-day row, and "Tasks are overlapping".
**Default variation:** A, Sunsama-style time capacity (it needs no field beyond duration).
The Structured preset uses E.

**What it is.** The day says when it holds more than fits.

**Anatomy.**
- Variation A: a capsule at the right of the header date line, 24 pt tall, 13 pt semibold, text
  "{planned} / {free}". Colours: `--ok` under 80% of free time, `--warn` from 80% to 100%,
  `--danger` (#FF3B30) over 100%. The teardown names green, orange and red without values.
- Variation E: the first item of the all-day row (DP-DAY-06). A 56 pt ring, 4 pt stroke, ⚡ glyph
  centred, "19 25" (used, limit) 11 pt under it, label "Energy" under the ring. Ring colour as
  above. Points come from each task's `energy` level.

**States.** Under capacity: `--ok`. Near: `--warn`. Over: `--danger`. Past day: computed on all
tasks, no now. No tasks: hidden.

**Interactions.** Tap the capsule or ring: a small card listing planned time and free time.

**Words.** "6h 30m / 5h" (A). "Energy" (E). Card rows "Planned" and "Free".

**Data.** Reads `task:<id>` (day, start, duration, done, energy), `settings:planner` (day start,
day end). Planned = the minutes of undone tasks still ahead of now (the unelapsed part of a
current task included). Free = day end minus the later of now and day start. For E, the energy limit
and the points per level are not fields of `settings:planner` or settled by the research.

**Needs.** Page alone.

**Edge cases.** Checklist 52: an overloaded day shows as over capacity. Checklist 5: overlap is
also shown by DP-TIME-08. Done tasks do not count.

**Tests.**
- Given day 8:00–22:00, clock 18:00 and 5 h of undone tasks after 18:00, then the capsule is `--danger`
  (5 h > 4 h free).
- Given the same with 3 h 30 m, then `--warn` (87.5%).
- Given the same with 2 h, then `--ok`.
- Given the 5 h of tasks all marked done, then the capsule shows "0m / 4h" in `--ok`.

**Evidence.** DP-TIME-06 [C]. Loves: B 3 quotes (FlowSavvy 2, Sunsama 1); Structured Energy ~5
mentions, 2 quotes (RG-C). Complaints: none against the signal. Screenshots:
`b/appstore/flowsavvy_6.jpg`, `agent/help/338050_5.png`.

---

### DP-TIME-07 Planned versus actual time

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Sunsama:
"0:30 / 0:30" on the row and a counter mode "Actual vs. planned". B, Motion: "0 min of 30 min".
C, Llama: overtime in red and an Overview "Planned 10h 31m / Spent 4h 00m".
**Default variation:** A, Sunsama.

**What it is.** Each row shows time spent against time planned.

**Anatomy.** A pill at the right of line 1, 11 pt semibold monospaced digits, `--bg-header`
background, `--ink-2` text; `--danger` text when spent exceeds planned.

**States.** Not started: "0:00 / 0:30". Running: spent counts up. Over: red. Done: final value.

**Interactions.** None on the pill. Spent is recorded by a focus timer (DP-FOC-01) or when done.

**Words.** "{spent} / {planned}" as "0:30 / 0:30".

**Data.** Needs a spent-time value per task; `task:` has no such field in records.md. Reads
duration as planned.

**Needs.** Page alone (spent is counted only while the page is open or from timestamps).

**Edge cases.** Checklist 20 (ending early sets spent to the real time).

**Tests.**
- Given planned 30 min and spent 45 min, then the pill reads "0:45 / 0:30" in `--danger`.
- Given spent 0, then it reads "0:00 / 0:30" in `--ink-2`.

**Evidence.** DP-TIME-07 [C]. Loves: weak; Routinery 1 ("helped me identify which tasks were
taking too long", A). Complaints: none found. Screenshots: `a/llama/as_08.png`,
`b/appstore/sunsama_3.jpg`.

---

### DP-TIME-08 Overlap display

**Tag:** core (checklist 5 and 6 name it; overlap is in leave reason 11). **Variations:** A,
Structured: stacked one above the other with a text label. B, Ellie (since Dec 2025), Google,
FlowSavvy: side by side. C, Morgen: offset.
**Default variation:** A on the timeline (DP-DAY-01), B on the hour grid (DP-DAY-02).

**What it is.** How two items at the same time are drawn. Both stay fully readable.

**Anatomy.**
- Timeline: the later-starting item's row follows the earlier one directly. Between them, a
  28 pt label row: 13 pt regular `--ink-2` with the word "overlap" in `--accent`. The line
  between the two bubbles is solid, not dashed. Each row keeps its full title and time line.
- Hour grid: overlapping blocks share the width in equal columns, 2 pt apart, ordered by start
  then by duration (longer first).

**States.** Two items: one label. Three or more in a chain: one label between each pair. Identical
start and end: still two rows or two columns. One item inside another: same rules.

**Interactions.** As DP-DAY-01 and DP-DAY-02. A drag that creates an overlap is accepted
(DP-RES-01).

**Words.** "Tasks overlap" (Structured: "Tasks are overlapping").

**Data.** Reads `task:<id>` (start, duration).

**Needs.** Page alone.

**Edge cases.** Checklist 5: both items fully readable. Checklist 6: the page never refuses to
save an overlap; no save path checks for one. The now fill (DP-TIME-02) runs in each overlapping
current item.

**Tests.**
- Given A 9:00–10:00 and B 9:30–10:00, when the timeline renders, then both titles render with
  no `text-overflow` clipping and one "Tasks overlap" row sits between them.
- Given A, B and C all 9:00–10:00 on the hour grid, then each block is a third of the column
  width (±2 pt).
- Given A 9:00–10:00, when B 9:15–9:45 is saved, then the store holds both records.

**Evidence.** DP-TIME-08 [C]. Complaints: Structured board "Side-by-side visualization" 1.0k
votes, In Progress; 2 quotes; Apple Calendar "won't let me overlap tasks" (1); 34 review hits, 18
negative (E). Screenshots: `agent/help/338050_8.png`, `c/gcal/appstore_1.jpg`.

---

### DP-TIME-09 Contextual day hints (leave-by, travel, weather)

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Timepage:
"Free for the rest of the day afterwards" on the event card, leave-by car and widget "Leave by
7:45am". B, Apple: Time to Leave. C, Motion, Akiflow: travel-time blocks. D, Reclaim: 🚌 events.
E, Fantastical, Readdle, Timepage: weather in day headers.
**Default variation:** A, the "Free after" line only (it needs no outside data).

**What it is.** The day carries outside facts: when the person is free after, when to leave, the
weather.

**Anatomy.** A third line on the last item of the day, 13 pt `--ink-2`. Weather variation: a
glyph and "18°" 13 pt at the right of the header date line.

**States.** Last undone item of today: line shown. Others: not shown.

**Interactions.** None.

**Words.** "Free after 5:00 PM". Weather: "{n}°". Leave-by: "Leave by 7:45 AM".

**Data.** Reads `task:<id>` (start, duration). Weather and travel time are outside data.

**Needs.** "Free after": page alone. Weather and travel time: outside APIs through the Midas
backend proxy (PRODUCT.md section 5; not stated as built); leave-by from location needs native
location, listed as later native reach. No `shell/` brief covers these.

**Edge cases.** Checklist 25: an item crossing midnight gives "Free after 1:00 AM". Apple iOS 27
removed automatic travel time (1 complaint, C).

**Tests.**
- Given the last task today ends at 17:00, then its third line reads "Free after 5:00 PM".
- Given that task marked done and an earlier undone task ending 15:00, then the line moves to that
  task and reads "Free after 3:00 PM".

**Evidence.** DP-TIME-09 [C]. Loves: Timepage 2 (C). Complaints: Apple iOS 27 removed automatic
travel time (1, C). Screenshots: `c/timepage/appstore_1.png`, `b/appstore/motion_6.jpg`.
