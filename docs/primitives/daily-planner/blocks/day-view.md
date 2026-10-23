# Day view (DP-DAY)

The day view block is the surface that lays out one day: the shape of the timeline, the all-day
row above it, and the other ways research apps draw a day (hour grid, part-of-day sections,
agenda list, split day, the day as a note). It holds all 7 DP-DAY patterns from research
`ANALYSIS.md` section 3.1. Sizes are in pt; in the Sidekick's WKWebView 1 CSS px is 1 pt.
Colours are theme tokens (CSS custom properties, defined in `recipe.md`); the value in brackets is
the Structured preset value from `structured-ui-teardown.md`. "Checklist N" is item N of
`checklist.md` (the numbering of research `ANALYSIS.md` section 6). Screenshot paths are relative
to the shots folder named in `ANALYSIS.md` section 8. Tests assume the page runs with a fixed
clock and a seeded store.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-DAY-01 | Vertical timeline of bubbles | core | Structured string of pearls |
| DP-DAY-02 | Proportional hour grid | on request | Apple Calendar day grid |
| DP-DAY-03 | Part-of-day sections | on request | Tiimo Anytime / Morning / Day / Evening |
| DP-DAY-04 | Agenda list with time as text | on request | Routine agenda (gap labels, dimmed past) |
| DP-DAY-05 | Timeline plus task sheet | on request | Readdle Planner ("Today 4" sheet) |
| DP-DAY-06 | All-day row | core | Structured round bubbles |
| DP-DAY-07 | The day as a text note | on request | NotePlan note plus Timeline sheet |

---

### DP-DAY-01 Vertical timeline of bubbles

**Tag:** core (checklist 25 and 26 name it). **Variations:** A, Structured: one vertical line
through round bubbles and capsules, height grows with duration but not linearly, gaps compressed.
B, TickTick list day view: hollow circles on a thin spine, cards evenly spaced. C, Routine
agenda: a thin line at the left.
**Default variation:** A, Structured.

**What it is.** One vertical line runs through a column of bubbles, one bubble per timed task,
with the task's text to the right. A short task is a circle; a longer one is a capsule. Elapsed
parts are in the task colour, future parts are grey, and gaps between tasks are a dashed line.

**Anatomy.**
- Sheet: `--bg-sheet` (#FFFFFF), top corner radius 30 pt, overlapping the header area
  `--bg-header` (#F2F2F5). Grabber centred at the top: 36 x 5 pt capsule, colour
  `--line-future` (#EBEBEB).
- Left gutter: 52 pt wide. Hour and start/end labels 12 pt regular `--ink-2` (#8A8A8E). Where two
  tasks abut, the shared label stacks ("6:30 / 6:45"). The now label is DP-TIME-01.
- Bubble column: bubble centre 80 pt from the left edge. Bubble width 57 pt. A task of 15 min
  or less, or of zero duration, is a 57 pt circle.
- Bubble height: `57 + 36.5 x log2(duration / 15)` pt for durations over 15 min, capped at
  240 pt. This gives 57 pt at 15 min and 130 pt at 60 min, the two values measured on `pm.png`.
- Line: 4 pt wide, round caps, through the bubble centres. Future segments `--line-future`.
  Elapsed segments take the colour of the task above them. Gap segments are dashed (4 pt dash,
  4 pt space): `--accent` (#F49F99) above now, `--line-future` below.
- Gap rows: 44 pt tall when a gap label shows (DP-TIME-04), 8 pt when the gap is under 5 min.
- Glyph: 24 pt, centred in the bubble (DP-ITEM-02). On a future bubble: task colour on
  `--bubble-future` (#EBEBEB). On a filled bubble: white.
- Row text, left-aligned 16 pt right of the bubble edge: line 1 time (DP-ITEM-03), 13 pt regular
  `--ink-2`; line 2 title, 17 pt semibold `--ink` (#000000), up to 2 lines; line 3 chips
  (DP-ITEM-06, DP-ITEM-07).
- Completion ring at the right edge, 16 pt inset (DP-ITEM-04).
- Minimum row height 64 pt. Font `-apple-system` (SF Pro).

**States.**
- Loading: the sheet shows nothing until the first `store.query` returns. No empty text.
- Empty: a single gap row from day start to day end (DP-TIME-04), plus the DP-SET-03 empty line.
- One item, many: rows in start order. On open, today scrolls so now sits a third of the way down.
- Overloaded: overlapping tasks follow DP-TIME-08.
- Future: grey bubble, coloured glyph.
- Current: DP-TIME-02 fill; line 1 becomes DP-TIME-03.
- Past, not done: bubble filled in the task colour, white glyph.
- Done: bubble filled in the task colour, title struck through (DP-ITEM-04).
- Offline: no difference; records are local.
- Notification permission denied: no difference in the view.

**Interactions.**
- Vertical scroll moves through the day.
- Tap a row: opens the editor in edit mode (DP-ADD-01, `capture.md`).
- Tap the ring: done (DP-ITEM-04).
- Long press a row: lift and drag (DP-RES-01, `rescheduling.md`).
- Drag the grabber down: week view (DP-NAV-02, if on).
- The now position and fill update every 30 s and at once on `visibilitychange` to visible.
  With Reduced Motion (`prefers-reduced-motion`), position changes are not animated.
- The research pattern has no haptic in the timeline itself.

**Words.** None of its own. Time lines come from DP-ITEM-03, gap words from DP-TIME-04.

**Data.** Reads `task:<id>` (title, colour, icon, day, start, duration, allDay, done, repeat,
inbox), `exception:<taskId>:<date>` (to drop a skipped occurrence or show a changed one),
`settings:planner` (day start, day end, 12/24h, theme). Shows tasks where `inbox` is false,
`allDay` is false and a `start` is set. The page reads all `task:` records once with
`store.query('task:')` and expands repeats in the page. Writes nothing itself.

**Needs.** Page alone. Calendar events on the same timeline need the calendar read in
`shell/calendar-access.md` (DP-ITEM-05).

**Edge cases.**
- Checklist 25: a task that crosses midnight shows on its start day, the bubble running to the
  bottom of the day, the time line reading its real end ("11:00 PM–1:00 AM (2 hr)").
- Checklist 26: the same task also shows on the next day as a continuation bubble at the top,
  from day start to its end, same colour; tapping it opens the same task.
- Checklist 27: a task before the day end set in `settings:planner` (e.g. 1:30 AM with day end
  3:00 AM) belongs to the previous day's view.
- Checklist 31: a task at a time skipped by daylight saving shows at the next valid time.
- Checklist 50: the empty day is distinct from loading (see States).
- Checklist 51: works offline (local records).

**Tests.**
- Given tasks at 9:00 for 60 min and 10:00 for 15 min, when the day renders, then the first
  bubble is 130 pt tall (±2) and the second is a 57 pt circle.
- Given a task 9:00–10:00 and the clock at 9:30, when the day renders, then the line segment
  above the task's bubble is the task colour, the segment below the next bubble is
  `--line-future`, and the dashed gap segment before 9:00 is `--accent`.
- Given a task on 12 Oct at 23:00 for 120 min, when 12 Oct shows, then its time line reads
  "11:00 PM–1:00 AM (2 hr)"; when 13 Oct shows, then a continuation bubble sits first and ends
  at the 1:00 AM label.
- Given a daily task and `exception:<id>:2026-10-14` marked skipped, when 14 Oct shows, then
  the task is absent; when 15 Oct shows, it is present.
- Given the store query has not returned, when the sheet renders, then no empty-state text is
  in the DOM.
- Given a task at 2:30 on the spring-forward day (America/New_York, 8 Mar 2026), when that day
  shows, then the task sits at the 3:00 AM position.

**Evidence.** DP-DAY-01 [C]. Loves: Structured "visual" ~24 mentions and 4 quotes (RG-C);
Reddit 2026-10-05 "What kept me on Structured is the timeline view" (E). Complaints: dragging
down anywhere opens the week by accident (2025-10-14, E); overlaps "a visual mess" (5★
2026-09-17, E). Teardown 1.1, 2.3. Screenshots: `pm.png`, `agent/lazyweb/lw_home.png`.

---

### DP-DAY-02 Proportional hour grid

**Tag:** on request (checklist 4 names it, but DP-DAY-01 with DP-ITEM-05 meets that item; this is
an alternative day shape). **Variations:** A, Apple Day: hour scale, blocks sized by duration,
red now line. B, Google Day and 3-day. C, Ellie Timebox beside a list. D, NotePlan timeline
sheet. E, TickTick Day / 3-Day / Week. F, Morgen 1-day and work-week. G, Akiflow, Motion,
FlowSavvy, Notion Calendar (1 to 3 days), Todoist calendar layout, Tiimo calendar view.
**Default variation:** A, Apple Day.

**What it is.** An hour scale runs down the left; every timed item is a block whose height is
exactly proportional to its duration. Empty time takes real space.

**Anatomy.**
- Gutter 52 pt, hour labels 12 pt regular `--ink-2`, at each hour line.
- Hour lines: 0.5 pt `--line-future`. Hour height 60 pt (1 pt per minute).
- Visible range: day start to day end from `settings:planner`.
- Block: left 60 pt, right inset 8 pt, corner radius 6 pt, fill the task colour at 20% over
  `--bg-sheet`, a 3 pt left bar in the task colour. Title 13 pt semibold `--ink`; time 11 pt
  `--ink-2` when the block is 40 pt or taller. Minimum block height 20 pt.
- Done block: fill at 10%, title struck through.
- Now indicator: DP-TIME-01 variation (line across the grid).

**States.** Empty: grid only, plus the DP-SET-03 empty line. Many: scroll; on open, scroll so now
is a third of the way down. Overlap: side by side columns (DP-TIME-08). Past: blocks at 60%
opacity. Done: as Anatomy. Offline: no difference.

**Interactions.** Tap a block: editor (DP-ADD-01). Tap an empty slot: create at that time
(DP-ADD-07). Long press a block: drag; handles resize (DP-RES-01). Pinch: DP-NAV-07 if on. Apple
gives a haptic on drag snap; a Sidekick page has no haptics API.

**Words.** Hour labels only: "7 AM" (12-hour) or "07" (24-hour), from `settings:planner`.

**Data.** Same reads as DP-DAY-01.

**Needs.** Page alone. Events need `shell/calendar-access.md`.

**Edge cases.** Checklist 4 (events and tasks on one grid, with calendar access). Checklist 5 and
6 (overlaps side by side, never refused). Checklist 25 and 26 (a block crossing midnight is cut
at the day end and continues at the top of the next day).

**Tests.**
- Given tasks of 30 and 120 min, when the grid renders, then the second block is 4 times the
  height of the first (±1 pt).
- Given a task 9:00–9:05, when the grid renders, then its block is 20 pt tall.
- Given an empty 10:00 slot, when tapped, then the add sheet opens with start 10:00.

**Evidence.** DP-DAY-02 [C]. Loves: Ellie timeboxing 3 quotes (A). Complaints: Notion Calendar
limited to 3 days on iPhone (8+, C); Sorted³ users wanted length to show (1, A). Screenshots:
`c/applecal/appstore_0.jpg`, `a/ellie/as_05.png`.

---

### DP-DAY-03 Part-of-day sections

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Tiimo:
"ANYTIME / MORNING / DAY / EVENING" with icons, counts and a "+" per section. B, Routinery:
"Morning · Daytime · Afternoon · Evening" plus Anytime. C, Things: "Today" and "This Evening".
**Default variation:** A, Tiimo.

**What it is.** The day as collapsible buckets with counts, instead of or beside times. Untimed
items sit in Anytime.

**Anatomy.**
- Section header: icon 17 pt, name 13 pt semibold uppercase-styled via CSS on a Title Case
  string, count in brackets, chevron at right, "+" button 28 pt. Header height 44 pt.
- Rows: icon chip left (DP-ITEM-02), title 17 pt semibold, time line under it 13 pt `--ink-2`
  ("8:30–9:00 AM"; Anytime rows show only the duration, "30 min"), ring right (DP-ITEM-04).
- Section bounds: Morning day start to 12:00, Day 12:00 to 17:00, Evening 17:00 to day end.
  Anytime: tasks with a `day` and no `start`.

**States.** Empty section: header only, count "(0)". Collapsed: header only. Done rows faded to
50% and struck. Past sections stay open.

**Interactions.** Tap a header: collapse or expand (200 ms ease-out height). Tap "+": add sheet
with start at the section's first free slot (Anytime: no time). Tap a row: editor.

**Words.** "Anytime", "Morning", "Day", "Evening". Count as "(3)".

**Data.** Reads `task:<id>` (day, start, duration, title, icon, colour, done), `settings:planner`
(day start, day end). The collapsed state is per-viewer page state; it is not stored (no
localStorage under PRODUCT.md section 5, so it resets on reopen).

**Needs.** Page alone.

**Edge cases.** Checklist 13 (a task with no time is kept and shown in Anytime). Tiimo sorts by
clock time with no override (2 complaints); a manual order needs an order field that
`task:` does not have.

**Tests.**
- Given a task at 13:30, when sections render, then it is under "Day", not "Morning".
- Given a task with a day and no start, then it is under "Anytime" and its time line is its
  duration only.
- Given Morning has 3 tasks, then its header reads "Morning (3)".

**Evidence.** DP-DAY-03 [C]. Loves: Tiimo 2 quotes (A); Things This Evening 3 (D, RG-A).
Complaints: Tiimo auto-sorts with no override (2, A); Things has one evening bucket (2 asks, D).
Screenshots: `a/tiimo/as_01.png`, `d/things/appstore_2.png`.

---

### DP-DAY-04 Agenda list with time as text

**Tag:** on request (no checklist item or leave reason names it). **Variations:** A, Routine
agenda: gap labels, dimmed past. B, Google Schedule: full-colour pills, illustrations. C,
Fantastical list under the DayTicker, grouped by day, past greyed. D, Readdle List. E, Sunsama in
user order with a planned-total pill. F, Tiimo Today, Llama Life, Sorted³. G, Timepage Timeline,
Todoist and Things Upcoming: one scrolling list of many days with day headers.
**Default variation:** A, Routine agenda.

**What it is.** Rows in time order, evenly spaced, no hour scale. Each row prints its time.

**Anatomy.**
- Row: 64 pt tall card, `--bg-sheet`, radius 12 pt, 8 pt apart. Left: time 13 pt semibold
  `--ink` over duration 11 pt `--ink-2`. Middle: colour bar 4 pt, icon, title 17 pt semibold.
  Right: ring (DP-ITEM-04).
- Gap label between rows: centred, 13 pt `--ink-2` ("45 min").
- Multi-day variation G: day header 15 pt semibold ("Today", "Tomorrow", "Wed 14 Oct").

**States.** Empty: DP-SET-03. Past rows: 50% opacity. Current row: DP-TIME-03 text. Done: struck.

**Interactions.** Tap a row: editor. Long press: drag to reorder in time (DP-RES-01).

**Words.** Gap label "{duration}" ("45 min", "1 hr 30 min"). Day headers "Today", "Tomorrow",
then weekday, day, month.

**Data.** Same reads as DP-DAY-01; includes untimed day tasks at the end of the day.

**Needs.** Page alone.

**Edge cases.** Checklist 3 (gap labels show free time). Checklist 25 (a midnight-crossing row
shows its real end). Sorted³ row height ignores duration (1 complaint); this shape does so by
design.

**Tests.**
- Given tasks at 9:00 (15 min) and 10:00, when the list renders, then one gap label reads
  "45 min" between them.
- Given the clock at 11:00 and a task that ended at 10:15, then that row's opacity is 0.5.
- Given rows of 15 min and 3 h, then both rows are 64 pt tall.

**Evidence.** DP-DAY-04 [C]. Loves: Routine "schedule view ... PERFECT" 1 (B); Google Schedule 6
complaints when its date picker was removed (C). Complaints: Sorted³ row height ignores duration
(1, A). Screenshots: `c/gcal/hires_0.png`, `b/appstore/routine_1.jpg`.

---

### DP-DAY-05 Timeline plus task sheet (split day)

**Tag:** on request (checklist 4 names it, but DP-DAY-01 with DP-ITEM-05 meets that item; this is
an alternative layout). **Variations:** A, Readdle Planner: timeline on top, a pull-up sheet
"Today 4"; timed tasks show in both. B, Amie Split View with a draggable divider. C, Routine task
drawer under the agenda. D, NotePlan inverted: note on top, "Timeline ⌄" sheet below. E, Ellie
iPad three columns.
**Default variation:** A, Readdle Planner.

**What it is.** The day's timeline fills the top; a sheet of today's tasks pulls up from the
bottom. Tasks can be dragged from the sheet onto the timeline.

**Anatomy.**
- Top: DP-DAY-01 or DP-DAY-02, whichever the preset uses.
- Sheet: `--bg-sheet`, radius 20 pt, grabber 36 x 5 pt. Three heights: 88 pt (title only), 50%
  and 90% of the screen.
- Sheet title "Today" 17 pt semibold, count badge 13 pt in a 22 pt `--bg-header` capsule.
- Rows: ring left, title 15 pt, time 13 pt `--ink-2` when timed.

**States.** Empty: title with "0" and no rows. Many: the sheet scrolls inside. Done rows move to
the end, struck.

**Interactions.** Drag the grabber between the three heights (spring, 300 ms). Long press a row
and drag onto the timeline: places it at that time (DP-ADD-06). Amie fires haptics while the
divider moves (and a user complained of 5+ in one move); a Sidekick page has no haptics API.

**Words.** "Today", count as a numeral.

**Data.** Reads `task:<id>` with `day` = the shown day (timed and untimed), `inbox` false. Writes
`start` on a drop (through DP-ADD-06).

**Needs.** Page alone. Events in the timeline need `shell/calendar-access.md`.

**Edge cases.** Checklist 4 (events and tasks together, with calendar access). Checklist 13
(untimed tasks kept). Checklist 15 (a failed drop leaves the task in the sheet, unchanged).

**Tests.**
- Given 3 timed and 1 untimed task today, when the sheet opens, then it lists 4 rows and the
  badge reads "4".
- Given an untimed task dropped on 14:00, then its record has `start` 14:00 and it shows in the
  timeline and still in the sheet.
- Given a drop released outside the timeline, then the record is unchanged.

**Evidence.** DP-DAY-05 [C]. Loves: Readdle 2 (C, D), Amie 1 (D). Complaints: Amie haptics 5+
per divider move (1, D). Screenshots: `d/calendars/appstore_4.png`, `d/amie/appstore_1.png`.

---

### DP-DAY-06 All-day row

**Tag:** core (checklist 7 names it). **Variations:** A, Structured: round bubbles with labels,
Energy and Cycle items first, done ones struck. B, Apple all-day band with reminders as circles.
C, Google band. D, Routine "ALL DAY" chips. E, Readdle all-day row with a checkbox. F, Morgen
chips.
**Default variation:** A, Structured.

**What it is.** A strip above the timed items for all-day and untimed things on that day.

**Anatomy.**
- Sits at the top of the timeline sheet, under the grabber. Row height 96 pt.
- Item: 56 pt circle, `--bubble-future` (#EBEBEB), glyph 24 pt in the task colour. Label under
  it, 12 pt semibold `--ink`, centred, 2 lines at most, 72 pt wide.
- Done: circle filled in the task colour, white glyph, label struck through.
- When DP-TIME-06 Energy Monitor is on, its ring is the first item, then a 1 pt x 40 pt divider
  in `--line-future`.
- More items than fit: the row scrolls horizontally; its height does not grow.

**States.** Empty: the row is not drawn. One, many: as Anatomy. Done: as Anatomy. Calendar
all-day events: same circle with a calendar glyph and no done state (DP-ITEM-05).

**Interactions.** Tap an item: editor. Horizontal drag: Structured reorders items; this needs an
order field `task:` does not have. Drag an item into the timeline: sets a time (DP-RES-01).
Drag a timeline row onto the row: makes it all-day (DP-RES-01).

**Words.** The task title. No other strings.

**Data.** Reads `task:<id>` where `allDay` is true and `day` is the shown day; also tasks with a
`day`, no `start` and `inbox` false. Writes `allDay`, `start` and `duration` when turned into a
timed task.

**Needs.** Page alone. All-day calendar events need `shell/calendar-access.md`.

**Edge cases.**
- Checklist 7: shown apart from timed items, and can be turned into a timed task (editor "Adjust
  Time", or a drag into the timeline).
- An all-day item runs midnight to midnight on its `day`, floating: it stays on the same date
  after travel.
- Akiflow's all-day events overflowed its header (B): the fixed row height prevents this.
- The research does not show how Structured completes an all-day item in one tap; here it is done
  from the editor header circle (DP-ITEM-04).

**Tests.**
- Given a done all-day task, when the row renders, then its circle background is the task colour
  and its label has `text-decoration: line-through`.
- Given 8 all-day tasks on a 402 pt wide screen, when the row renders, then the row is 96 pt tall
  and scrolls horizontally.
- Given an all-day task, when it is given a time of 9:00 for 30 min, then `allDay` is false,
  `start` is 9:00, and it renders in the timeline and not in the row.

**Evidence.** DP-DAY-06 [C]. Loves: none direct. Complaints: Tiimo cannot turn an all-day event
into a task (1, E); Notion shows only all-day events (1, E); Akiflow all-day overflow (B).
Teardown 1.1 "All-day row". Screenshots: `agent/help/325186_1.png`, `c/applecal/appstore_0.jpg`.

---

### DP-DAY-07 The day as a text note

**Tag:** on request (no checklist item or leave reason names it). **Variations:** NotePlan only:
the day is a document; a line that starts with a time becomes a block on a timeline sheet.
**Default variation:** NotePlan.

**What it is.** The day is a text page. Typing "15:00 Call Sam" on a line makes a 15:00 block on
a timeline below.

**Anatomy.**
- Top: a full-width text area, 17 pt regular `--ink`, placeholder 17 pt `--ink-2`.
- Bottom: a sheet titled "Timeline ⌄" holding a DP-DAY-02 grid of the parsed lines.
- A parsed line shows its time in `--accent`.

**States.** Empty: the placeholder. Lines with no time: text only. Lines with a time: also a
block.

**Interactions.** Type; parsing runs on each line when focus leaves it, never mid-word. Tap a
block: scrolls the note to its line.

**Words.** Placeholder "What's planned for {weekday, month day}?" (NotePlan: "What's planned for
Thu, Jan 23? Type here..."). "Timeline".

**Data.** The note text needs a per-day note record; `task:` has no such shape and records.md
names none. Parsed lines map to `task:<id>` fields title, day, start, duration.

**Needs.** Page alone.

**Edge cases.** Checklist 11 (parsing never acts while typing). Checklist 12 (half-typed text is
kept; the note saves on each change). Checklist 16 (accepts "15:00" and "3pm").

**Tests.**
- Given the line "15:00 Call Sam", when focus leaves the line, then a block titled "Call Sam" sits
  at 15:00.
- Given the line "Buy milk", then no block is made.
- Given typing "15:0" and a pause, then no block is made until focus leaves the line.

**Evidence.** DP-DAY-07 [C]. Loves: NotePlan "daily" 19 of 103 positive hits (A). Complaints:
learning curve 13 mentions (A). Screenshots: `a/noteplan/help_timeblock_3_small.jpg`,
`a/noteplan/as_04.png`.
