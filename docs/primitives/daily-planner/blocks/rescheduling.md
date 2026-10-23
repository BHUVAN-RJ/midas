# Rescheduling (DP-RES)

Rescheduling is how a planned day changes: dragging items, the replan pass over unfinished items,
roll-over and overdue, shifting the rest of the day, auto-scheduling, swipe actions on rows, and
actions on a whole date. Seven patterns, from research `ANALYSIS.md` section 3.6. "The plan
breaks when the day changes" is leave reason 8. Structured preset values come from
`structured-ui-teardown.md` (T) sections 1.1, 1.8 and 3. Screenshot paths are relative to the
base folder in `ANALYSIS.md` section 8. Theme tokens are defined in `recipe.md`.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-RES-01 | Drag to move, handles to resize | core | Structured lift-and-drop; resize in the editor |
| DP-RES-02 | Replan ritual | core | Structured Replan card stack, plus "Move All to Tomorrow" |
| DP-RES-03 | Roll-over and overdue | core | Overdue section with one bulk action (Todoist, Readdle, TickTick, Routine) |
| DP-RES-04 | Shift the rest of the day | core | Shift later tasks by a chosen amount (TimeFinder increments) |
| DP-RES-05 | Auto-schedule and recalculate | on request | FlowSavvy-style button, proposals confirmed before saving |
| DP-RES-06 | Swipe actions on rows | on request | Structured: right complete, left delete |
| DP-RES-07 | Whole-day actions | on request | Structured long-press a date |

Rules for every pattern here: no haptics (a Sidekick page has no haptics API); every gesture
ignores a touch that starts within 20 pt of the left screen edge, which belongs to the shell's
back-to-home swipe; motion is instant under `prefers-reduced-motion: reduce`; every move, delete
and bulk change is undoable through DP-FB-04 (checklist 54). Any change to a task's time rewrites
its derived `reminder:` records, so the alerts move with it (checklist 21, 43).

---

### DP-RES-01 Drag to move, handles to resize

**Tag:** core (checklist 15 and 54). **Variations:**
- Structured: lift as a white shadowed card; hover a week-strip day to change day; drop on "+" (turns into a red 🗑) to delete (T).
- Ellie: haptics, edge auto-scroll, drop zones (A).
- Apple, Google, Fantastical, TickTick: resize handles on blocks (C, D).
- Timepage: press-hold-drag (C).

**Default variation:** Structured lift-and-drop on the bubble timeline. No resize handles on
bubbles (Structured has none; duration changes in the editor). The hour-grid day view
(DP-DAY-02) uses top and bottom handles, as Apple and Google do.

**What it is.** Long-press an item on the day and move it to another time, another day, the
all-day row, the Inbox, or delete.

**Anatomy.**
- Lifted item: its row as a white card, 16 pt radius, shadow `0 8px 24px rgba(0,0,0,.12)`, scale 1.03.
- Drop preview on the timeline: the bubble at the drop place with the range "9:15–10:00 AM" 13 pt in the task colour, snapped to 15 minutes.
- "+" button while dragging: turns into a red #FF3B30 circle with a white 🗑 glyph (literal colour, not a theme token).
- Grid handles (DP-DAY-02 only): 10 pt circles in the task colour at the block's top-left and bottom-right, shown after a tap selects the block.

**States.** Lifted; over the timeline (preview); over a week-strip day (day highlight, then that
day opens after 600 ms); over the all-day row; over the Inbox tab; over the trash; released
outside every target (returns).

**Interactions.**
- Long-press 500 ms lifts. Dragging near the top or bottom 60 pt auto-scrolls.
- Drop on a time: new day and start, duration kept.
- Drop on the all-day row: `allDay` true. Drop on the Inbox tab: `inbox` true, day and start cleared.
- Drop on the trash: deleted, with Undo.
- Grid handles: drag changes start (top) or end (bottom) in 15-minute steps.
- Moving one occurrence of a repeat asks "Repeating Task" (Words) before writing.
- Lift and return animate 200 ms ease-out. No haptic on lift, hover or drop (Ellie's haptics are native; none available).

**Words.** "Repeating Task" with "This Task" · "All Future Tasks" · "All Tasks" · "Cancel".
Undo toast: "Moved" / "Deleted" with "Undo" (DP-FB-04).

**Data.** Writes `task:` day, start, duration, allDay, inbox; rewrites derived `reminder:`
records; "This Task" writes `exception:<taskId>:<date>`; delete removes the `task:` and its
`reminder:` records.

**Needs.** Page alone for Midas tasks. Moving a calendar event needs calendar write:
`shell/calendar-access.md`. The alert of a moved single occurrence of a repeat needs
`shell/repeat-exceptions.md`; until then the old occurrence's alert still fires.

**Edge cases.** 6 (overlaps allowed), 15 (a failed drop never writes), 21 and 43 (alerts move),
25 (dropping late in the day so the end passes midnight keeps the start day), 54 (undo).

**Tests.**
- Given a task 9:00–9:45 with an alert at start, when it is dropped at 10:15, then start is 10:15, duration 45, and the derived `reminder:` `at` is 10:15.
- Given a lifted task, when it is released over the header, then the `task:` record is unchanged.
- Given a task dropped on the trash, when "Undo" is tapped, then the `task:` and its `reminder:` records are back with their old values.
- Given a lifted task held over Wednesday in the week strip for 600 ms, when dropped at 8:00, then `day` is that Wednesday.
- Given a daily task, when the 14 Oct occurrence is dropped at 11:00 with "This Task", then only `exception:<id>:2026-10-14` holds 11:00.

**Evidence.** DP-RES-01; Readdle 2 loves; Tiimo drag "wonky", no resize 3; Notion events lost
while moving (E). Screenshots `agent/help/338306_10.png`, `d/things/appstore_3.png`.

---

### DP-RES-02 Replan ritual

**Tag:** core (checklist 22; leave reason 8). **Variations:**
- Structured Replan: a card stack; swipe up reschedule, left inbox, right complete, down delete; a badge after 3 reschedules; a floating "↪ Replan N Tasks" pill (T 1.8).
- Sunsama Daily Planning (recap, pull in, fit check, timebox, share) and Daily Shutdown (B).
- Akiflow rituals with "Rate your Day" (B).
- Ellie Daily Planning and Shutdown, "Nothing changes until you tap Finish" (A).
- Tiimo daily "Review today" check-in (A).

**Default variation:** Structured card stack, with a "Move All to Tomorrow" action in its "•••"
menu for checklist 22. Structured's first-run intro card is not built; the four buttons are
labelled instead.

**What it is.** A pass over one day's unfinished tasks, one card at a time, each sent to a new
time, the Inbox, done or deleted.

**Anatomy.**
- Entry pill: floating glass pill above the tab bar, `--bg-sheet` at 80% with backdrop blur, "↪ Replan 3 Tasks" 15 pt semibold `--ink`. Shown when the viewed day or yesterday has unfinished timed tasks.
- Sheet over the page dimmed 20%, 32 pt top radius. Title "Replan" 28 pt bold with the date in `--ink-2` ("Replan 11 Oct"). "•••" and ✕ at right.
- Card: white, 20 pt radius, 3 cards stacked with 8 pt offsets. On the card: "11 Oct 2026 🕐 9:00 AM" 13 pt `--ink-2`, title 22 pt semibold, hollow ring 23 pt in the task colour. A badge "↻ 3" in `--palette-3` [#EAA93B] when the task was rescheduled 3 or more times.
- "3 Left" 15 pt `--ink-2` under the stack.
- Bottom pill of four 52 pt icon buttons with labels 11 pt: Inbox `--palette-5` [#6085A8], Reschedule `--palette-3` [#EAA93B], Delete `--palette-7` [#974667], Done `--palette-4` [#91BE6C]. "←" (undo last card) at left, "→" (skip) at right.

**States.** No unfinished tasks: the pill is hidden; opened from the date menu it shows "Nothing
to Replan" and "Done". One card. Many. Last card handled: the sheet closes and shows "Replanned 4"
(WRITING rule 5).

**Interactions.**
- Swipe the card up: Reschedule. It goes to tomorrow at the same start; tapping the Reschedule button opens `<input type="date">` and DP-ADD-02 to pick another time.
- Swipe left: Inbox. Swipe right: Done. Swipe down: Delete. A swipe commits past 30% of the card's width or height; the card flies off in 250 ms ease-out.
- The four buttons do the same. "→" skips; "←" undoes the last card.
- "•••": "Move All to Tomorrow" moves every remaining card at once.
- A swipe that starts within 20 pt of the left screen edge is ignored (shell gesture).
- No haptic per card (none available).

**Words.** "Replan 3 Tasks" · "Replan 11 Oct" · "3 Left" · "Inbox" · "Reschedule" · "Delete" ·
"Done" · "Move All to Tomorrow" · "Nothing to Replan" · result "Replanned 4". Structured's
"Choose how to replan your incomplete tasks…" line and "Start Replan" are not used.

**Data.** Reads `task:` (day before today or the chosen day, not done, not inbox). Writes `task:`
day, start, inbox, done, doneAt; deletes. Rescheduled count lives in a `task:` field records.md
does not list yet (`replanCount`). Rewrites derived `reminder:` records. A repeat occurrence
handled here writes `exception:<taskId>:<date>`.

**Needs.** Page alone. The scheduled morning or evening prompt that opens it is DP-OUT-06 (a daily
`reminder:` record; shell has it).

**Edge cases.** 22 ("Move All to Tomorrow"), 23 (Done records `doneAt` now, not the planned day),
24 (nothing is deleted except by Delete), 27 (the day uses the `settings:planner` day end), 54.

**Tests.**
- Given 3 unfinished tasks on 11 Oct, when "Move All to Tomorrow" is tapped on 12 Oct, then all 3 have `day` 2026-10-13 and their start times are unchanged.
- Given a card for an 11 Oct task, when it is swiped right on 12 Oct at 08:10, then `done` is true and `doneAt` is on 12 Oct.
- Given a card swiped down, when "←" is tapped, then the `task:` record exists again with its old values.
- Given a task rescheduled for the third time, when the next replan shows it, then the "↻ 3" badge shows.

**Evidence.** DP-RES-02; Sunsama 3 (RG-D) plus 4 (B), Ellie 1 (loves #11); Structured board
(Auto-)Move 2.5k (E); Sunsama ritual not on its phone (B). Screenshots
`agent/help/4511874_2.png`, `b/web/sunsama_guided_daily_planning.png`.

---

### DP-RES-03 Roll-over and overdue

**Tag:** core (checklist 22, 23, 24). **Variations:**
- Things: unfinished items stay in Today, no overdue state (D).
- Ellie: rolls them forward (A).
- Sunsama: moves them at midnight, archives after N rollovers (B).
- Fantastical: rolling reminders (E).
- Akiflow: overdue 1 h after planned end, "2d ago" (B).
- Todoist, Readdle, TickTick, Routine: an Overdue section with a bulk "Reschedule" (B, C, D).

**Default variation:** Overdue section at the top of today with one bulk button. Nothing moves by
itself; Sunsama's automatic move is the on-request variation.

**What it is.** Unfinished one-time tasks from past days, shown on today until handled.

**Anatomy.** A section above the all-day row on today's sheet: header "Overdue" 13 pt semibold
red #FF3B30 and a count, "Move to Today" 15 pt `--accent` at right. Rows as DP-ITEM rows with the
original date "11 Oct" 13 pt `--ink-2` before the time. Collapsible; more than 5 rows collapse to
"Show 12 More".

**States.** None overdue: the section is absent. Some. Collapsed. Past days are not changed:
viewing 11 Oct still shows the task there, not done.

**Interactions.** "Move to Today": every overdue task gets today's date at its clock time; one
whose time today has passed goes to the next free 15-minute mark after now, in order. Tap a row:
editor. The ring: done. Repeating occurrences never roll over (a missed daily item does not pile
up).

**Words.** "Overdue" · "Move to Today" · "Show 12 More" · "11 Oct" · result "Moved 4".

**Data.** Reads `task:` with day before today (by the `settings:planner` day end), not done,
no repeat. Writes day and start. Done writes `doneAt` now. Rewrites `reminder:` records.

**Needs.** Page alone.

**Edge cases.** 22 (one action for all), 23 (`doneAt` is the real day), 24 (never deleted or
archived by itself), 27 (a task at 1:00 AM is still "today" before a 3:00 AM day end).

**Tests.**
- Given 2 unfinished tasks on 10 Oct, when today 12 Oct opens, then "Overdue 2" shows and both records still have day 2026-10-10.
- Given those 2, when "Move to Today" is tapped at 14:00 and one was at 09:00, then that one starts at 14:00 or the next free mark, never before now.
- Given an overdue task done on 12 Oct, when 10 Oct is viewed, then the task shows done with `doneAt` on 12 Oct.
- Given 30 days pass with an overdue task untouched, when today opens, then the task still exists.
- Given a daily repeat missed yesterday, when today opens, then it is not in "Overdue".

**Evidence.** DP-RES-03; Things 1, Fantastical 1, Ellie 1, NotePlan 1 loves; rollover 56
negative hits (E); Sunsama backlog "disappears" 1; Fantastical wrong day 1; Reddit "leftover
tasks … start to look like failures". Screenshots `d/calendars/appstore_5.png`,
`b/appstore/motion_5.jpg`.

---

### DP-RES-04 Shift the rest of the day

**Tag:** core (checklist 18 and 19; leave reason 8). **Variations:**
- Sorted³: Time Ruler with Magic Select (A).
- TimeFinder: "Move everything later in increments" (E).
- Tiimo: voice "move all my task by 10min" (A).
- Llama: adds overtime to the task (A).

**Default variation:** TimeFinder increments: one action shifts every later unfinished flexible
task today by 5, 15, 30 or 60 minutes.

**What it is.** One action moves many later items by the same amount when the day runs late.

**Anatomy.** An action sheet from three places: the current task's editor "•••" ("Shift Later
Tasks"), the focus screen's overtime (DP-FOC-02), and long-press on the now marker. Title "Shift
Later Tasks", chips "5m · 15m · 30m · 1h" as DP-ADD-02 chips, a line "4 tasks, to 6:45 PM" 15 pt
`--ink-2`, button "Shift" (`--accent` capsule).

**States.** No later tasks: the menu item is hidden. Some tasks fixed: they are not counted and
not moved. A shift that pushes items past midnight: allowed; they keep today's date.

**Interactions.** Pick an amount; "Shift" moves the tasks. One undo restores all.

**Words.** "Shift Later Tasks" · "5m" "15m" "30m" "1h" · "4 tasks, to 6:45 PM" · "Shift" ·
"Cancel" · result "Shifted 4".

**Data.** Reads today's `task:` records with start after the chosen point, not done. Fixed items
are calendar events and tasks marked fixed, a `task:` field records.md does not list yet
(`fixed`). Writes start; rewrites derived `reminder:` records.

**Needs.** Page alone. Calendar events stay put because the page cannot write them
(`shell/calendar-access.md`).

**Edge cases.** 18, 19, 21 (alerts move), 25, 54.

**Tests.**
- Given tasks at 15:00, 16:00 and 17:00, when "15m" and "Shift" are tapped at 14:50, then they start at 15:15, 16:15 and 17:15 and their `reminder:` records match.
- Given the 16:00 task has `fixed: true`, when shifted by 30m, then it is still 16:00 and the others moved.
- Given a shift, when "Undo" is tapped, then every moved task and `reminder:` is back.
- Given a done task at 15:30, when shifted, then it does not move.

**Evidence.** DP-RES-04; Sorted³ 1, TimeFinder 1 loves; absence complaints Structured 1 (board
547), Tiimo 1, Motion 1; overrun 26 negative hits (E). Screenshots `a/sorted/as_07.png`,
`a/tiimo/site_plans_change_voice.png`.

---

### DP-RES-05 Auto-schedule and recalculate

**Tag:** on request (checklist 19 is met by DP-RES-04; schedulers that move placed items are a
complaint, not their absence). **Variations:**
- Motion: places by deadline and priority, re-places all day (B).
- FlowSavvy: "↻ Recalculate" button and a "Rescheduling..." card (B).
- Reclaim: 🆓 flipping to 🛡️ (B).
- Sunsama: per task, "Schedule anyway / Schedule another day / Defer" (B).
- Sorted³: Auto Schedule with a lock per item (A).
- Morgen: AI plan approved on desktop (D).

**Default variation:** FlowSavvy-style button that only runs when tapped, places inbox tasks with
a duration into today's free gaps, and shows the result as DP-ADD-04 confirm cards before
saving. Placed tasks never move.

**What it is.** Page logic that fills free time with untimed tasks. Deterministic, no AI.

**Anatomy.** Button "Fill Free Time" at the top of the Inbox, `--accent` text. Result sheet: one
card per proposed placement, "Add 5 Tasks" button.

**States.** No inbox task has a duration: the button is inert. Not all fit: the sheet lists
"2 Don't Fit" under the cards. Offline: works.

**Interactions.** Tap: proposals. ✕ on a card drops it. "Add 5 Tasks" writes all.

**Words.** "Fill Free Time" · "Add 5 Tasks" · "2 Don't Fit".

**Data.** Reads `task:` (today's placed tasks and inbox tasks with duration; `deadline` orders
them, earliest first). Writes day, start, inbox false. Free time runs from now to the
`settings:planner` day end.

**Needs.** Page alone for Midas tasks. Planning around real calendar events needs
`shell/calendar-access.md`.

**Edge cases.** 6 (never creates overlaps), 19 (placed items untouched).

**Tests.**
- Given free time 13:00–14:00 and inbox tasks of 30 and 45 min, when "Fill Free Time" runs, then one card proposes the 30 or the 45 and the other is under "1 Don't Fit"; no record changes until "Add" is tapped.
- Given a placed task at 15:00, when it runs, then that task's start is unchanged.

**Evidence.** DP-RES-05; B 9 loves (Motion 4, FlowSavvy 4, Reclaim 1; loves #7); complaints
moving placed items Motion 3, Reclaim 2; FlowSavvy wants a prompt first 1. Screenshots
`b/appstore/flowsavvy_4.jpg`, `b/appstore/motion_3.jpg`.

---

### DP-RES-06 Swipe actions on rows

**Tag:** on request (not a checklist item or leave reason; taps and drag cover the same
actions). **Variations:**
- Timepage: short swipe complete, other way reschedule, long swipe delete, "Invert Gestures" (C).
- Akiflow: left = plan menu, right = multi-select (B).
- Routinery: left Duplicate/Delete, right Skip (A).
- Structured Inbox: right complete, left delete (T).
- Things: swipe enters multi-select (D).

**Default variation:** Structured: swipe right completes, swipe left deletes, on Inbox rows and
list-shaped day rows (DP-DAY-04). Not on bubble timeline rows (they drag).

**What it is.** Horizontal swipes on a row that reveal and run one action.

**Anatomy.** Behind the row: right swipe shows a `--palette-4` [#91BE6C] panel with "✓ Done";
left swipe a red #FF3B30 panel with "🗑 Delete". Labels 15 pt semibold white. On a done row the
right panel is `--palette-2` [#F19C74] "Undone".

**States.** Resting, revealed (past 25% width, stays open), committed (past 50%, runs), done row.

**Interactions.** The row follows the finger. Release past 50% runs the action in 200 ms; between
25% and 50% stays open with a tappable button; under 25% springs back. A swipe that starts within
20 pt of the left screen edge is ignored: it is the shell's back-to-home gesture. Delete shows
Undo, no confirmation. No haptic at the threshold (none available).

**Words.** "Done" · "Undone" · "Delete" · result "Deleted" with "Undo".

**Data.** Writes `task:` done, doneAt; or deletes the `task:` and its `reminder:` records.

**Needs.** Page alone.

**Edge cases.** 43 (delete removes alerts), 54 (undo).

**Tests.**
- Given an inbox row, when swiped right past 50%, then `done` is true.
- Given an inbox row, when a swipe right starts at x = 10 pt, then nothing on the row moves.
- Given a row swiped left past 50%, when "Undo" is tapped, then the task and its `reminder:` records are back.

**Evidence.** DP-RES-06; Things 1, Readdle 1 loves; Tiimo no swipe-to-delete 1; Todoist changed
swipes 2; Sorted³ swipes collide 1. Screenshots `a/routinery/as_02.png`, `a/sorted/as_06.png`.

---

### DP-RES-07 Whole-day actions

**Tag:** on request (not a checklist item or leave reason). **Variations:**
- Structured: long-press a date: "Copy Tasks From Day", "Replan N Tasks", "Add Task", "Clear Day", "Paste from <date>" (T).
- Apple: copy and paste an event onto another time (C).

**Default variation:** Structured long-press a date in the week strip.

**What it is.** A menu of actions on one date.

**Anatomy.** A context menu anchored to the pressed date: glass card (`--bg-sheet` 85%, blur),
14 pt radius, rows 44 pt, 17 pt `--ink`, icon at right. "Clear Day" in red #FF3B30 with 🗑.

**States.** No tasks that day: only "Add Task" (and "Paste" after a copy). No unfinished tasks:
no Replan row. After a copy: "Paste from 12 Oct" appears.

**Interactions.** Long-press 500 ms on a date opens the menu (week strip, DP-NAV-01).
- "Copy Day": holds that day's tasks in page memory.
- "Paste from 12 Oct": creates new tasks on this date with the same times, not done; a repeating source becomes a one-time copy.
- "Replan 3 Tasks": DP-RES-02 for that date.
- "Add Task": DP-ADD-01 on that date.
- "Clear Day": deletes the date's one-time tasks and skips its repeat occurrences; one Undo restores all. No confirmation.

**Words.** "Copy Day" · "Paste from 12 Oct" · "Replan 3 Tasks" · "Add Task" · "Clear Day" ·
results "Pasted 5", "Cleared 5" with "Undo".

**Data.** Reads and writes `task:`; writes `exception:<taskId>:<date>` (skipped) for repeats on a
cleared day; writes and deletes `reminder:` records.

**Needs.** Page alone. The skipped occurrence's alert needs `shell/repeat-exceptions.md`; until
then it still fires.

**Edge cases.** 32 (a cleared repeat occurrence affects that date only), 54.

**Tests.**
- Given 5 tasks on 12 Oct, when "Copy Day" then "Paste from 12 Oct" on 14 Oct, then 5 new `task:` records on 14 Oct exist with new ids and the 12 Oct ones are unchanged.
- Given a day with 2 one-time tasks and 1 daily repeat, when "Clear Day", then the 2 are deleted, `exception:<id>:<date>` marks the repeat skipped, and the next day's occurrence still shows.
- Given "Clear Day" ran, when "Undo" is tapped, then all 3 show again.

**Evidence.** DP-RES-07; no loves or complaints found. Screenshot `agent/help/4511874_1.png`.
