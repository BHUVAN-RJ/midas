# Capture (DP-ADD)

Capture is how an item gets into the planner: the add sheet, the time and duration pickers,
typed or spoken entry, the inbox for items with no time yet, dragging inbox items onto the day,
creating an item at a place, and reusing past items. Eight patterns, from research `ANALYSIS.md`
section 3.5. Sizes and words for the Structured preset come from `structured-ui-teardown.md`
(T) sections 1.4, 1.5 and 3. Screenshot paths are relative to the base folder in `ANALYSIS.md`
section 8. Theme tokens are defined in `recipe.md`; Structured values are given here in brackets
where first used.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| DP-ADD-01 | Add sheet shape | core | Structured three-step sheet, advances only on "Continue" |
| DP-ADD-02 | Duration and time pickers | core | Structured duration chips plus 15-minute wheel; Detailed uses native time inputs |
| DP-ADD-03 | Natural-language entry | on request | Structured fills the fields; the matched words are highlighted (TickTick) |
| DP-ADD-04 | Voice or AI plan, confirmed as cards | on request | Routine confirm cards, filled by the page's own parser, not AI |
| DP-ADD-05 | Inbox or brain dump | core | Structured Inbox |
| DP-ADD-06 | Drag from a list onto a time | core | Structured: drag an inbox row over the Timeline tab, drop at a time |
| DP-ADD-07 | Create at a place | on request | Structured long-press "+" and drag |
| DP-ADD-08 | Templates, presets and suggestions | on request | Structured step-1 Suggestions with "Never Suggest" |

Rules for every pattern here: no haptics (a Sidekick page has no haptics API; listed as later
native reach in `PRODUCT.md` section 5); every gesture ignores a touch that starts within 20 pt of
the left screen edge, because that swipe belongs to the shell (back to home); motion is cut to
instant changes under `prefers-reduced-motion: reduce`.

---

### DP-ADD-01 Add sheet shape

**Tag:** core (checklist 9, 11, 12, 32, 33, 35 are about this sheet). **Variations:**
- Structured: three steps in one morphing sheet: title with suggestions, then time and duration, then a details card, then "Create Task" (T 1.5).
- Things: a card that opens in place in the list (D).
- Apple iOS 27: Event | Reminder switch, natural-language line over a form (C).
- Morgen: Task | Event full form with time zone (D).
- FlowSavvy: fields written as a sentence, "I need 1 hr during personal hours" (B).
- Timepage: full-colour screen with a horizontal time ruler (C).
- Sunsama: a one-line card (B).

**Default variation:** Structured three steps. It advances only when "Continue" is tapped, never
on a pause in typing.

**What it is.** The sheet that creates or edits one `reminder:` task record (`planner.item`). Create walks three steps;
edit opens straight on step 3. Tapping a timeline row opens step 3 in edit mode (T 1.6); the old
detail modal is not built.

**Anatomy.**
- Full-height sheet, top corners 32 pt radius, over the page dimmed 20%.
- Header block: the task colour darkened about 12% (`color-mix(in srgb, var(--task) 88%, black)`; salmon gives about #CF847E). Round translucent ✕ at top left.
- Step 1 (title):
  - 64 pt white circle at left with the task glyph in the task colour; the glyph updates as the title is typed when DP-ITEM-02 suggests icons.
  - Text field, white 22 pt semibold, a 1 pt white underline. Placeholder: "Task".
  - Body on `--bg-header` [#F2F2F5]. A "Suggestions" list shows only when DP-ADD-08 is built.
  - "Continue": full-width capsule, 16 pt side margins, 56 pt tall, `--accent` [#F49F99] fill, 17 pt semibold white. Sits above the keyboard.
- Step 2 (time): header shows "8:00–8:15 PM (15 min)" above the title. Date row, Time section, Duration section, "Continue". Pickers in DP-ADD-02.
- Step 3 (details):
  - Header: the left circle grows into a tall white capsule. A small round palette button on its lower-left corner opens Color & Icon (DP-ITEM-01, DP-ITEM-02). Time line 13 pt, title 22 pt semibold white, hollow completion ring 23 pt at right, "•••" at top right when editing.
  - Grouped white card on `--bg-sheet` [#FFFFFF], 20 pt radius, rows 52 pt tall with a 1 pt `--line-future` [#EBEBEB] divider: 📅 date … "Today ›"; 🕐 "7:00–7:30 AM" … "30 min ›"; ↻ repeat (only when set); 🔔 alerts "2 Alerts ›".
  - Chip buttons for unset options, white capsules 44 pt tall: "Repeat", "Energy" (energy only if DP-TIME-06 is built).
  - Subtasks and notes card: rounded-square checkboxes with an `--accent` stroke, "Add Subtask" placeholder row, notes area with placeholder "Notes".
  - "Create Task" (or "Update Task" when editing): the same capsule as "Continue", fixed at the bottom.
  - "Delete": white capsule at the end of the scroll, red text (#FF3B30, iOS red; a literal, not a theme token).
- Repeat sheet: segmented "Once · Daily · Weekly · Monthly" (selected = `--accent` capsule), "Every 1 week" with −/+ stepper, weekday circles (selected `--accent` filled), "Start" date, "End Date" (both `<input type="date">`). Monthly with interval 12 stands in for yearly, as in Structured; the `reminder:` format also has `year`, so a Yearly segment can be added on request.

**States.**
- New, untouched: title empty, "Continue" dimmed to 40% and inert.
- Typing: nothing advances. The keyboard stays up.
- Draft: a half-typed task is kept (checklist 12). See Data.
- Editing a repeating task: saving asks which occurrences change (Words).
- Offline: works the same; records go to the local store.
- Saving refused by the store (a record over 64 KB, for example very long notes): the sheet stays open with "Can't Save Task" and "Try Again".

**Interactions.**
- "Continue" advances one step; the sheet morphs (header circle to capsule) over 300 ms ease-in-out. Reduced motion: instant.
- ✕ or swipe the sheet down: closes. A non-empty new task is kept as a draft, not lost.
- Step 1 Return key: same as "Continue".
- Swipe the Time row left: reveals "All Day". Swipe the date row left: "Move to Inbox".
- "•••" menu (edit mode): "Duplicate", "Move to Inbox", "All Day", "Change Day".
- "Delete" on a one-time task deletes at once and shows Undo (DP-FB-04). No confirmation (WRITING rule 8).
- No haptic on step change or create (none available).

**Words.** "Task" (placeholder) · "Continue" · "Today" · "Tomorrow" · "Time" · "Duration" ·
"Repeat" · "Energy" · "Add Subtask" · "Notes" · "2 Alerts" · "Create Task" · "Update Task" ·
"Delete" · "Duplicate" · "Move to Inbox" · "All Day" · "Change Day" · Repeat sheet: "Once",
"Daily", "Weekly", "Monthly", "Every 1 week", "Start", "End Date" · Editing a repeat: title
"Repeating Task", buttons "This Task", "All Future Tasks", "All Tasks", "Cancel" · Deleting a
repeat: title "Delete Repeating Task?", buttons "Delete This Task", "Delete All Future Tasks",
"Delete All Tasks", "Cancel" · Error: "Can't Save Task" / "Try Again". Structured's "Are you
sure you want to delete this task?" is not used.

**Data.**
- Writes `reminder:<id>`: title, colour, icon, `at` (day and start, read in `timeZone`), `timeZone`, duration, allDay, notes, subtasks, repeat, alerts, energy; an inbox task has no `at`. New: done false.
- The task's alerts are rules in its own `alerts` (`{ id: "s5", kind: "before", minutes: 5 }`); the at-start alert is the task's own notification at `at` (records.md 3.2). Edit moves them; delete cancels them. End alerts are not mapped (records.md 12).
- "This Task" on a repeat writes `exception:<taskId>:<date>` with the changed fields.
- "All Future Tasks" sets the old task's `repeat.until` to the end of the day before, and writes a new `reminder:` task from that day (checklist 33). Past occurrences keep their old values.
- Draft (checklist 12): on `visibilitychange` to hidden, on closing with text, and before opening Color & Icon, the half-typed task is written as a `reminder:` task with no `at` and `draft: true`. Opening the add sheet again offers it as the title. A draft's title must not be empty (the shell refuses an empty `reminder:` title); an empty draft is not mapped (records.md 12).
- Reads `settings:self` for default duration and default alerts.

**Needs.** Page alone for the sheet. Shell has the notification engine for alerts. Shell lacks
per-occurrence exceptions in `reminder:` repeats: "This Task" changes the page's view at once,
but the notification for that one occurrence still fires at the series time until
`shell/repeat-exceptions.md` is built (records.md 3.6, 12). Native pickers: `<input type="date">`, `<input type="time">`
and `<select>` open the real iOS pickers in WKWebView with no bridge.

**Edge cases.**
- 9: default start is the next 15-minute mark after now on today, moved past any item it would overlap; on another day it is the first free 15-minute mark after `dayStart`. Never midnight.
- 11: no timer on the title field; only "Continue" or Return advances.
- 12: draft as above.
- 25: an end past midnight saves with the right end and the task stays on its start day.
- 32: "This Task" writes an exception only.
- 33: "All Future Tasks" splits the series as above.
- 35: repeats are on by default; Sidekicks sell nothing.

**Tests.**
- Given step 1 with "Answer em" typed, when 5 seconds pass with no input, then the sheet is still on step 1 and the field still holds "Answer em".
- Given a new task with title "Laundry" and the page hidden (visibilitychange), when the page shows again and the add sheet opens, then "Laundry" is offered and a `reminder:` task with `draft: true` and no `at` exists.
- Given now is 14:07 and the slot 14:15–14:30 is taken, when the add sheet reaches step 2, then the start is 14:30, not 00:00 and not 14:15.
- Given a daily task at 7:00, when the 14 Oct occurrence is moved to 8:00 with "This Task", then `exception:<id>:2026-10-14` exists with `at` at 08:00 that day and the task's `at` still starts at 07:00.
- Given a daily task, when 14 Oct is edited with "All Future Tasks", then the old record's `repeat.until` is 13 Oct end of day, a new `reminder:` task starts 14 Oct, and the 12 Oct occurrence shows the old title.
- Given a task with 2 alerts, when it is deleted, then its `reminder:` record is gone (its alerts with it) and an Undo control is shown.

**Evidence.** DP-ADD-01; complaints: auto-advance (Structured 1★ 2026-03-18), midnight default
(4★ 2026-07-05), Things picker closing, Apple iOS 27 taps, Google end time (E, D, C). Screenshots
`agent/blog/blog_ios26_taskeditor.png`, `b/appstore/flowsavvy_5.jpg`; T 1.5 images
`agent/help/338050_2.png` to `338050_8.png`.

---

### DP-ADD-02 Duration and time pickers

**Tag:** core (checklist 9 and 10 are about these pickers). **Variations:**
- Structured: duration chips "1 · 15 · 30 · 45 · 1h · 1.5h · 2h", editable presets, a 15-minute wheel whose selection is a range capsule "8:00–8:15 PM"; Standard or Detailed picker (T).
- Timepage: a drag ruler (C).
- Google: a placeholder block with drag circles (C).
- Todoist: "for 90 minutes" in text (D).
- Defaults seen: 15 min (Structured), 25 min (Llama), 30 min (Notion, Google, Todoist, Morgen), 1 h (Apple).

**Default variation:** Structured chips and Standard wheel; "Detailed" swaps the wheel for two
native `<input type="time">` fields (start, end). Default duration 15 min, from `settings:self`.

**What it is.** The step-2 controls that set start time and length, also used in step 3 rows,
the inbox editor and the Replan reschedule.

**Anatomy.**
- Date row: white card 52 pt, 📅 in `--accent`, "Fri 12 Oct" 17 pt, "Today ›" 15 pt `--ink-2` [#8A8A8E] at right. The whole row is an `<input type="date">` styled over the card.
- "Time" section title, 20 pt bold, "•••" at right with "Standard" / "Detailed".
- Standard wheel: white card, 5 visible rows of 44 pt, 15-minute slots, CSS scroll-snap. Selected row is an `--accent` capsule with the range "8:00–8:15 PM" in 17 pt semibold white. Rows fade to 30% opacity toward the card edges.
- Detailed: two `<input type="time">` fields joined by "→", 17 pt.
- "Duration" section title with "•••" ("Custom", "Presets"). Chip strip in a white rounded track 44 pt tall. Unselected chips: bare numbers 15 pt in `--line-future`-on-white grey ("1", "15", "30", "45", "1h", "1.5h", "2h"). Selected: `--accent` capsule, white, with unit ("15m"). The strip scrolls sideways past about 6 chips.
- Custom duration: two `<select>` elements, hours 0–23 and minutes 0–55 by 5, which open the iOS wheel.
- Presets editor: chips with ✕, "Reset".

**States.**
- All-day task: Time and Duration hidden; the date row only.
- Zero duration: allowed ("1" chip is 1 minute; a 0 is set by Custom). Shown as "7:00 AM" with no range.
- End past midnight: the range reads "11:30 PM–12:30 AM", start day unchanged.

**Interactions.**
- Changing the start (wheel or input) keeps the duration; the end moves (checklist 10).
- Changing the end in Detailed changes the duration; the start stays (checklist 10).
- Tapping a chip sets the duration; the wheel's capsule range updates at once.
- Wheel scroll snaps per row; no haptic tick (none available).

**Words.** "Today" · "Tomorrow" · "Time" · "Standard" · "Detailed" · "Duration" · "Custom" ·
"Presets" · "Reset" · "1" "15" "30" "45" "1h" "1.5h" "2h" · selected "15m" · ranges
"8:00–8:15 PM (15 min)", "(1 hr, 30 min)".

**Data.** Writes the task's `at` (day and start) and duration. Reads and writes `settings:self`
default duration. The duration presets list is `settings:self.durationPresets`.

**Needs.** Page alone. Native pickers through `<input type="date|time">` and `<select>`, no
bridge. The native time picker shows 12- or 24-hour by the iOS setting, not by
`settings:self`; the page's own labels follow `settings:self` (DP-SET-07).

**Edge cases.** 9 (default start, see DP-ADD-01), 10, 16 (labels by setting), 25 (end past
midnight).

**Tests.**
- Given a task 9:00–9:45, when the start is changed to 10:00, then the end is 10:45 and duration is 45.
- Given Detailed with 9:00 → 9:45, when the end is changed to 10:30, then the start is 9:00 and duration is 90.
- Given `settings:self` default duration 30, when a new task reaches step 2, then the "30m" chip is selected.
- Given start 23:30 and duration 60, when saved, then the day of the task's `at` is the start day and the row reads "11:30 PM–12:30 AM".

**Evidence.** DP-ADD-02; complaints: Structured midnight default (E), Akiflow default-duration
fix (B). Screenshots `agent/help/338050_3.png`, `c/timepage/appstore_6.png`.

---

### DP-ADD-03 Natural-language entry

**Tag:** on request (not a checklist item or leave reason; its absence draws only single
complaints). **Variations:**
- Fantastical: live preview, words "fall" into fields; keywords "todo", "!!!", "/work", "every Tuesday"; drafts (C).
- Todoist: tokens turn into inline chips (D).
- Akiflow: tokens highlighted, parsed chips above (B).
- TickTick: the phrase is highlighted (D).
- Apple iOS 27 on Apple Intelligence phones (C); Readdle Pro (C, D).
- Structured beta: "1h ballet class Friday at 4" fills time, duration and date (T).
- NotePlan: "15:00" in a note line (A). Sunsama: `~` for planned time (B).

**Default variation:** Structured: typing in the step-1 title field fills date, time, duration
and repeat; the matched words are highlighted in `--accent` (TickTick) and removed from the title
only when "Continue" is tapped.

**What it is.** A parser in the page's own code, no AI and no network. `PRODUCT.md` section 4:
natural-language input inside an app is baseline behaviour, not an agent.

**Anatomy.** The step-1 field. Matched words get an `--accent` 20% tint background, 4 pt radius.
Under the field, chips for each parsed value ("Fri 14 Oct", "4:00 PM", "1h", "Every Tuesday"),
white 30% capsules on the header colour, 13 pt white, each with ✕.

**States.** No match: no chips. Ambiguous ("at 4" with no am/pm): the next 4 o'clock after now
within `dayStart`–`dayEnd`. Matched words that are also the task's name: the chip's ✕ keeps them
in the title.

**Interactions.** Parsing runs on each input event. Tapping a chip's ✕ drops that value and keeps
the words in the title (the "too eager" complaint). "Continue" goes to step 2 with fields filled.

**Words.** Chip text only; no new strings.

**Data.** Writes the same `reminder:` task fields as DP-ADD-01. English only in the first version.

**Needs.** Page alone.

**Edge cases.** 9 (no time parsed: default start rule), 16 (12/24-hour input both parsed), 25
("11pm for 2h" ends next day).

**Tests.**
- Given "1h ballet class Friday at 4" typed on Monday 12 Oct, when "Continue" is tapped, then title is "ballet class", day 2026-10-16, start 16:00, duration 60.
- Given "Call Tuesday" typed, when the "Tue" chip's ✕ is tapped, then the title stays "Call Tuesday" and no day is set from it.
- Given "Gym every Tuesday 7am", when saved, then `repeat` is `{ every: 'week', weekdays: [2] }` and start 07:00.

**Evidence.** DP-ADD-03; loves Fantastical 4 plus Zapier, Todoist 5, Akiflow 1 (loves #9);
complaints Fantastical "too eager" 3, Readdle rewrites titles 1. Screenshots
`c/fantastical/appstore_3.jpg`, `d/todoist/appstore_2.png`.

---

### DP-ADD-04 Voice or AI plan, confirmed as cards

**Tag:** on request (AI pushed in is leave reason 6; its absence is not a leave reason).
**Variations:**
- Routine: voice turns into one card per change, "Nothing saved yet — tap ✓ to add these items." (B).
- Tiimo Co-planner: cards, pick which to create (A); "I'm late, move all my task by 10min." (A).
- Structured AI: "Accept All" / "Regenerate" (T 1.9).
- Todoist Ramble; TickTick AI Voice Add (D).
- Akiflow: hold "+" to send voice (B). Motion: Siri with suggested steps (B).

**Default variation:** Routine's confirm cards, filled by the DP-ADD-03 parser run over each line
of a typed or dictated list. No AI.

**What it is.** Several items entered at once and shown as cards; nothing is saved until the
person adds them.

**Anatomy.** A sheet titled with the count. One white card per line, 20 pt radius: time line 13 pt
`--ink-2`, title 17 pt semibold, the task glyph at left, ✕ at right. A full-width `--accent`
capsule at the bottom.

**States.** Empty input: the button is inert. One card. Many: scrolls. A line that parses to
nothing but a title becomes an inbox card ("Inbox" in place of a time).

**Interactions.** Tap a card: opens it in DP-ADD-01 step 3 before adding. ✕ removes a card.
"Add 4 Tasks" writes all. ✕ on the sheet discards all.

**Words.** Title "4 Tasks" · button "Add 4 Tasks" · "Inbox" · placeholder "One task per line".
Routine's "Nothing saved yet…" line is not used (WRITING rule 4).

**Data.** Writes one `reminder:` task per card, with its `alerts`.

**Needs.**
- Voice: the iOS keyboard's dictation key works in any page text field; no shell piece needed. Speech recognition from page code inside WKWebView is unverified [U].
- AI planning (Tiimo, Structured, Todoist): would call a model through the Midas backend proxy, which is decided but not stated as built. `PRODUCT.md` section 5: user data never goes into prompts. A typed plan and the existing tasks are user data, so an AI version waits on the founder's decision on how that rule applies here. Siri add: DP-OUT-07 (outside this block).

**Edge cases.** 9 (a line with no time goes to the inbox, not midnight), 13.

**Tests.**
- Given "Gym 7am 1h\nGroceries\nCall mom 6pm", when the sheet opens, then 3 cards show and no `reminder:` record has been written.
- Given those 3 cards, when "Add 3 Tasks" is tapped, then 3 `reminder:` tasks exist and "Groceries" has no `at`.
- Given the AI variation is requested, when the build is checked, then no request body to the proxy contains a `reminder:` value (fails if user data reaches a prompt).

**Evidence.** DP-ADD-04; Tiimo AI 18 positive vs 39 of 115 negative (A); AI 240 negative hits
(E); Todoist Ramble 3; Akiflow 1. Screenshots `b/appstore/routine_2.jpg`,
`d/ticktick/appstore_3.png`.

---

### DP-ADD-05 Inbox or brain dump

**Tag:** core (checklist 13 and 14). **Variations:**
- Structured Inbox: empty state "Your Unstructured Thoughts"; swipe right complete, left delete; drag onto the Timeline tab to place (T 1.4).
- Ellie Brain Dump with Siri (A). Tiimo To-do tab, "Start task" moves it to today (A).
- Akiflow: one inbox for every source (B). Routine: inbox with a count badge (B). Things, Morgen Inbox (D).

**Default variation:** Structured Inbox, a tab of its own.

**What it is.** A list of tasks with no day and time. Each can carry a duration and a deadline.

**Anatomy.**
- Title "Inbox" 34 pt bold on `--bg-header`.
- Rows: white cards 16 pt radius, 64–72 pt tall, 10 pt gaps, 16 pt side margins. Left: the task glyph in the task colour, no bubble. Line 1 (optional) 13 pt `--ink-2`: "30 min", "Due Fri 14 Oct". Line 2: title 17 pt semibold `--ink` [#000000]. Right: "+" 22 pt in the task colour.
- "Completed" section header 13 pt `--ink-2`; rows struck through.
- Inbox editor: DP-ADD-01 step 3 with "2 hrs · Inbox" above the title, chip buttons "Date", "Time", "Deadline".
- Empty state (DP-SET-03): tray glyph 120 pt in `--accent` 40%, headline, one capsule button in `--accent` 15% tint with `--accent` text.

**States.** Empty: headline and button. One, many: list, newest first, then manual order. Past
deadline: the "Due" line in red #FF3B30. Done: in "Completed". Offline: same.

**Interactions.**
- Tap a row: inbox editor. Tap "+": opens DP-ADD-02 step 2 to schedule.
- Swipe right: complete; swipe left: delete (DP-RES-06). Drag vertically: reorder; drag into "Completed": done.
- Drag over the Timeline tab: DP-ADD-06.

**Words.** "Inbox" · "Completed" · "30 min" · "2 hrs · Inbox" · "Due Fri 14 Oct" · "Date" ·
"Time" · "Deadline" · empty: "No Inbox Tasks" / "New Task". Structured's "Your Unstructured
Thoughts" and its body line are not used.

**Data.** A `reminder:` task with no `at`, duration optional. Order kept in `order`. Deadline
(checklist 14) is the task's `deadline` (a date); an inbox task has no `at`, so it notifies nobody.

**Needs.** Page alone. Shell has the local store and sync.

**Edge cases.** 13, 14, 15 (drop never deletes), 51 (offline).

**Tests.**
- Given a task saved with no time, when the Inbox opens, then it is listed and its `reminder:` record has no `at` (no notification).
- Given an inbox task with deadline 14 Oct, when today is 15 Oct, then its "Due" line is red and it is still in the Inbox.
- Given an inbox task, when "+" is tapped and 9:00 chosen, then its `at` is 09:00 that day, and it no longer shows in the Inbox.

**Evidence.** DP-ADD-05; Structured ~21 mentions (RG-C), Ellie 2, Akiflow 2 (loves #8);
Structured board "Deadlines in Inbox" 1.5k; untimed tasks 37 negative hits (E). Screenshots
`agent/lazyweb/lw_inbox.png`, `agent/help/338178_3.png`.

---

### DP-ADD-06 Drag from a list onto a time

**Tag:** core (checklist 15; loves #4). **Variations:**
- TickTick "Arrange Tasks" drawer with an "x" to cancel (D).
- Ellie list → Timebox (A). Readdle Planner (C, D). NotePlan line → timeline (A). Morgen on desktop (D).
- Amie: drag up to a dashed slot "Release to schedule" (D).
- Akiflow: purple outlined drop block and a purple hour label (B).
- Structured: inbox → hover the Timeline tab (T).

**Default variation:** Structured: long-press an inbox row, drag it over the Timeline tab, hover,
the timeline opens, drop at a time.

**What it is.** Time blocking by moving an untimed task onto the day.

**Anatomy.** The lifted row: white card, shadow `0 8px 24px rgba(0,0,0,.12)`, scale 1.03, under
the finger. Over the timeline, a drop preview: a capsule in the task colour at 30% with the time
"8:00–8:30 AM" 13 pt in the task colour, snapped to 15 minutes.

**States.** Lifted. Over the Timeline tab: tab highlight after 600 ms, then the timeline opens.
Over the timeline: preview. Over the all-day row: preview as an all-day bubble. Released outside
any target: the row returns to its place.

**Interactions.** Long-press 500 ms lifts. Near the top or bottom 60 pt of the timeline it
auto-scrolls. Release on the timeline writes the time. Release elsewhere cancels. Motion: lift and
return 200 ms ease-out. No haptic on lift or drop (none available).

**Words.** None new; the preview shows the time range.

**Data.** Writes the task's `at` (day and start) and `timeZone`; `allDay` if dropped on the all-day
row. Its notifications follow `at`.

**Needs.** Page alone for Midas tasks. Dropping onto a calendar to make a real calendar event
(NotePlan, Readdle) needs calendar write: `shell/calendar-access.md`.

**Edge cases.** 15: a cancelled or failed drop leaves the record untouched; the record is
written once, only on a successful drop. 54: the drop is undoable. 6: dropping onto a taken slot
is allowed (overlap).

**Tests.**
- Given an inbox task, when it is dragged over the Timeline tab and dropped at 10:00, then its `at` is 10:00, and an Undo control shows.
- Given an inbox task lifted, when it is released over the tab bar's Settings tab, then the `reminder:` record is byte-identical to before and the row is back in the Inbox.
- Given a drop at 10:00 where 10:00–11:00 is taken, when released, then both tasks exist.

**Evidence.** DP-ADD-06; D 12 praise quotes (TickTick 4, Morgen 4, Todoist 2, Readdle 1, Amie 1),
Ellie 3; Notion events lost while moving (E). Screenshots `d/amie/appstore_1.png`,
`b/appstore/akiflow_4.jpg`.

---

### DP-ADD-07 Create at a place: draggable "+" or tap an empty slot

**Tag:** on request (not a checklist item or leave reason). **Variations:**
- Things Magic Plus (D). Todoist Dynamic Add onto a day, and tap an empty slot for 30 minutes (D).
- Structured: long-press "+" and drag onto the timeline, all-day row or Inbox (T).
- Timepage: drag "+" onto a day (C). Google: tap an empty time (C). Akiflow: tap and drag (B).

**Default variation:** Structured long-press "+" and drag. Tap on an empty slot is not used
(accidental taps while scrolling, Morgen).

**What it is.** The add control is dropped where the new item should go.

**Anatomy.** The "+" button: 60 pt `--accent` circle, white "+" 24 pt, 10 pt right of the tab
pill (navigation block). While dragged it follows the finger at 48 pt with the DP-ADD-06 drop
preview.

**States.** Over the timeline: time preview. Over the all-day row: all-day preview. Over the Inbox
tab: tab highlight. Elsewhere: none.

**Interactions.** Tap "+": DP-ADD-01 at step 1. Long-press 500 ms then drag: drop opens DP-ADD-01
at step 1 with the time, all-day or inbox already set.

**Words.** None new.

**Data.** As DP-ADD-01.

**Needs.** Page alone.

**Edge cases.** 9: the dropped time replaces the default start.

**Tests.**
- Given "+" long-pressed and dropped at 15:15, when the title "Read" is entered and "Create Task" tapped, then start is 15:15.
- Given "+" dropped on the Inbox tab, when created, then the task has no `at`.

**Evidence.** DP-ADD-07; Things 3 loves (D); Morgen accidental taps 1, Todoist "Why is the FAB
draggable?" 1. Screenshots `d/things/appstore_5.png`, `c/gcal/appstore_1.jpg`.

---

### DP-ADD-08 Templates, presets and suggestions

**Tag:** on request (not a checklist item or leave reason; loves #14). **Variations:**
- Llama: Presets grid with "Edit" and "Load" (A).
- Routinery: routines (A).
- Structured: step-1 "Suggestions" with long-press "Never Suggest", and "Copy Tasks From Day" (T; copy is DP-RES-07).
- Fantastical templates (C). Readdle Shortcuts (D).

**Default variation:** Structured step-1 Suggestions, built from the person's own past tasks.

**What it is.** A list under the title field in DP-ADD-01 step 1. Tapping one fills the new task
with that past task's title, colour, icon, duration and time.

**Anatomy.** Section label "Suggestions" 13 pt `--ink-2`. White card 20 pt radius; rows 60 pt:
glyph in the task colour at left, "10:00–10:15 AM (15 min)" 13 pt `--ink-2`, title 17 pt
semibold. At most 8 rows.

**States.** No past tasks: the section is hidden. Typing: filtered to titles containing the text.

**Interactions.** Tap: fills and goes to step 2. Long-press: menu "Never Suggest".

**Words.** "Suggestions" · "Never Suggest". Llama variation: "Presets", "Edit", "Load".

**Data.** Reads `reminder:` tasks (titles grouped, most used first). "Never Suggest" adds the title
to `settings:self.neverSuggest`. The Llama variation uses `preset:<id>` (`planner.preset`, a list
of task templates, records.md 6).

**Needs.** Page alone. Structured's live icon suggestion by machine learning is DP-ITEM-02.

**Edge cases.** None from the checklist.

**Tests.**
- Given 3 past tasks titled "Gym" at 7:00 for 60 min, when step 1 opens, then "Gym" is the first suggestion and tapping it sets duration 60 and start 07:00.
- Given "Gym" marked "Never Suggest", when step 1 opens, then "Gym" is not listed.

**Evidence.** DP-ADD-08; Llama presets 4 of 16 positive (A); Structured board Routines 3.6k
(E); Tiimo removed routines (A, E). Screenshots `a/llama/as_07.png`, `agent/help/338050_2.png`.
