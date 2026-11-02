# The to-do itself (TD-ITEM)

This block covers what opens when a to-do is tapped: the detail card, notes, subtasks, repeats,
date, time and deadline, moving it to another list, and deleting it. Six patterns.

Sources, all in midas-intel `docs/research/todo/`:
- `look-group-a.md` 1.2: the Things card, When picker and notes.
- `look-group-a.md` 3.2: the Reminders New Reminder sheet and iOS 27.
- `look-group-c.md` 3.2 and 4.2: Tiimo and Tweek sheets.
- `look-group-d.md` Part 2: P-new-1 to P-new-12, 23, 24, 29, 30.
- `group-d.md`: P1, P6, #48 to #52 and #56.
- `group-a.md` 3: Things 3.23 repeats.

Template: `docs/primitives/daily-planner/README.md`. Records: `../records.md`. Theme tokens from
`../recipe.md` (not yet written). Values marked [U] are proposals not found in the research.
Written 2026-10-31.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-ITEM-01 | Detail card | core | Things card over the dimmed list; saves as typed, Undo after (no `settings:self` field) |
| TD-ITEM-02 | Notes | core | Plain text under the title, links tappable (no `settings:self` field) |
| TD-ITEM-03 | Subtasks | core | One-level checklist in the card; a ticked subtask stays in place, struck (no `settings:self` field) |
| TD-ITEM-04 | Repeat | core | Things "Regularly" or "After Completion"; each tick writes the next copy (no `settings:self` field) |
| TD-ITEM-05 | Date, time, deadline | core | Things When sheet plus time and deadline in the same sheet (no `settings:self` field) |
| TD-ITEM-06 | Move list, delete | core | List picker in the card footer; delete at once with Undo; a whole list asks first (no `settings:self` field) |

Rules for every pattern here:
- **Every change saves at once** through `store.update` on `todo:<id>`.
- **One record per to-do.** Subtasks live inside it, so a move or delete takes them along
  (P-new-11).
- **64 KB per record.** A write over that size is refused by the store; the field keeps its text
  and the card shows "Can't Save" [U].
- **Unknown fields are kept** on every update (JSON Merge Patch, #9).
- **No haptics** unless TD-DONE-03's trick is on.
- **Motion is instant** under `prefers-reduced-motion: reduce`.
- **Gestures ignore a touch that starts within 20 pt of the left screen edge** (the shell's back
  swipe, as the daily-planner rule).

---

### TD-ITEM-01 Detail card

**Tag:** core. P-new-23 (undo covers edits; "no undo function or close without saving changes",
Microsoft To Do 2★) and P-new-30 (controls reachable with a long title).

**Variations:**
- **Things:** a white rounded card "pop[s] out" over the dimmed list. Inside: the checkbox, the
  title, an "✕"; notes in grey; a checklist; a tag pill; calendar and flag icons; a footer with
  the list picker "☐ Inbox" and a blue "Save" pill [C, look-group-a 1.2, `things_iphone_4`].
- **Apple Reminders iOS 26:** a sheet with "✕", "New Reminder", a blue ✓, then "Notes & URL", a
  "Date & Time" group with toggles, and "Urgent" [C]. In iOS 27, metadata (Date, Time, Urgent,
  Repeat, Location, Tag, Flag, Camera) sits in a box around the active reminder [R].
- **Tiimo:** a modal with title, icon and colour, duration, time, date, repeat, subtasks, alarm,
  notes and tags; Save is a ✓ in the corner [R].
- **Tweek:** the sheet takes the to-do's colour as background; a bottom toolbar with share,
  repeat, colour, bell and "⋯" [C].
- **Google Tasks:** an add sheet on the keyboard with details, date and Save [C].

**Default variation:**
- The Things card.
- It saves as typed, so a closed page loses nothing (P1, P5).
- On close, if anything changed, a toast "Edited" with "Undo" restores the record as it was when
  the card opened (P-new-23) [U].
- There is no Save button.

**What it is.** The one place to see and change everything about a to-do.

**Anatomy.**
- The list behind is dimmed by a 30% black scrim [U].
- Card: `--surface`, 16 pt radius, 16 pt inset from the screen sides, 20 pt padding [U].
- Top row: the checkbox (TD-ROW-01 shape), then the title field 20 pt semibold `--ink`, wrapping
  with no line limit (#56, P-new-29). At the right, "✕" 17 pt `--ink-2`, 44 pt target.
- Notes: TD-ITEM-02. Subtasks: TD-ITEM-03.
- Chip row, always under the notes and never beside the title, so a long title never pushes it
  off screen (P-new-30). Chips 32 pt tall, 13 pt `--ink-2` with a glyph [U]:
  - When (TD-ITEM-05);
  - Deadline ⚑;
  - Repeat ↻ (TD-ITEM-04);
  - Emoji (TD-ROW-04) and Colour (TD-ROW-03).
- Footer: the list picker at the left (TD-ITEM-06) and "⋯" at the right (Delete, TD-ITEM-06).

**States.**
- Open; editing (keyboard up, the card scrolls so the caret stays visible).
- Done: the title struck, as in TD-DONE.
- Saving failed: "Can't Save" under the field, the text kept.
- The record was changed by another device while open: the card shows the new values for fields
  not being typed in. The field being typed keeps the person's text and wins on the next save
  (N-10 to N-12 [U]).

**Interactions.**
- Tap a row: the card opens, scaling from the row 250 ms ease-out [U].
- Tap the scrim, "✕", or swipe the card down: it closes.
- Typing in the title or notes: `store.update` 400 ms after the last keystroke, and again on
  close [U].
- Tick in the card: as TD-DONE.

**Words.** "✕" (accessibility label "Close") · "Edited" · "Undo" · "Can't Save" · "Title"
(placeholder) · "Notes" (placeholder).

**Data.**
- Reads and writes `todo:<id>`: `title`, `notes`, `subtasks`, `when`, `time`, `part`,
  `deadline`, `repeat`, `list`, `emoji`, `color`, `done`, `completedAt`, `someday`.
- Undo writes the whole record back as read at open (`store.set`).

**Needs.** Page alone.

**Edge cases.**
- **P-new-23:** edits can be undone.
- **P-new-30:** a fixed chip row.
- **#56 and P-new-29:** the full title shows in the card.
- **#9:** unknown fields kept.
- **P1:** saves as typed.

**Tests.**
- Given a to-do "Buy milk", when the title is changed to "Buy oat milk" and the card closes, then
  the record's `title` is "Buy oat milk" and the page shows "Edited".
- When "Undo" is tapped, then `title` is "Buy milk".
- Given a 300-character title, when the card opens, then every chip in the chip row is within the
  viewport and tappable (its bounding box is inside the screen).
- Given the record holds an extra field `source: "x"`, when the title is edited, then `source` is
  still "x".
- Given typing in the title, when the page is closed 1 s after the last keystroke, then the
  record holds the typed title.
- Given `store.update` rejects, then "Can't Save" shows and the field still holds the typed text.

**Evidence.**
- look-group-a 1.2 (Things [C]), 3.2 (Reminders [C], iOS 27 [R]); look-group-c 3.2 (Tiimo [R]),
  4.2 (Tweek [C]); look-group-d 1.2 (Google Tasks [C]); look-group-d Part 2 P-new-23, 29, 30.
- Screenshot: `shots/things_iphone_4.png`.

---

### TD-ITEM-02 Notes

**Tag:** core. Every loved app has notes on a to-do. "Notes mixed in with tasks" is loved by 3
sources (group-a 9); recfab left Taskwarrior for lack of it.

**Variations:**
- **Things:** notes render Markdown (numbered lists, "–" bullets, *italic*) with the markers
  still visible [C, `things_iphone_6`].
- **Apple Reminders:** "Notes & URL" [C].
- **Superlist:** a list as a Markdown document with to-dos inside: "list with markdown notes"
  [C].
- **Tweek:** notes plus attachments (a file chip, an image) [C].
- **Microsoft To Do:** a note among the task details [R].

**Default variation:** plain multi-line text under the title in the card. Links (http and https)
are tappable [U]. Markdown display (Things) is a variation on request. Attachments are not built:
there is no `todo:` field, and files would use `store.putFile`.

**What it is.** Free text that belongs to a to-do.

**Anatomy.**
- In the card: a `<textarea>` 15 pt `--ink-2`, growing with its content, with placeholder
  "Notes".
- In the row: a small notes glyph after the title when `notes` is not empty (Things) [U],
  shown only with `showMeta` (TD-ROW-02).

**States.** Empty (placeholder); short; long (the card scrolls; the row never shows the notes'
text) [U]; over the record cap ("Can't Save", TD-ITEM-01).

**Interactions.**
- Tap: edit.
- A tap on a link opens it; links open outside the page [U whether WKWebView in the shell
  allows it].
- Saves as TD-ITEM-01.

**Words.** "Notes".

**Data.** `todo:` `notes` (string, optional). Imported Apple notes arrive cut to 20,000 characters
by the shell (`AppleRemindersImport.swift`, `maxNotesCharacters`).

**Needs.** Page alone. Opening a link outside the page: not checked [U].

**Edge cases.**
- **#56:** long text kept in full.
- **#57:** notes text is shown as text, never as HTML (no `innerHTML` with the person's text)
  [U implementation rule].
- **P1.**

**Tests.**
- Given notes "line 1\nline 2", when the card opens, then the textarea's value has both lines.
- Given notes `<img src=x onerror=alert(1)>`, when the card and row render, then no `img`
  element is created.
- Given notes of 20,000 characters, when saved, then `store.get` gives all 20,000.
- Given notes empty, then the row shows no notes glyph; given notes "a" and `showMeta` true,
  then it does.

**Evidence.**
- look-group-a 1.2 (Things notes [C]), 3.2 (Reminders [C]); group-a 5 (Superlist loves [C]),
  9 (notes mixed in, 3 sources); look-group-c 4.2 (Tweek [C]).
- Screenshot: `shots/superlist_3_crop.jpg`.

---

### TD-ITEM-03 Subtasks

**Tag:** core. Reasons:
- P1: Google Tasks "ALL of my subtasks… are GONE".
- P-new-8 to P-new-12.
- P-new-5: subtasks together with repeats.

**Variations:**
- **Things:** a checklist inside the card. Items have circle checkboxes (to-dos have squares); a
  checked item shows a grey ✓ and grey text; a grip "≡" on the right reorders. A "1/24" count
  chip in the row [C].
- **Apple Reminders:** "Swipe right… tap Indent" / "Outdent" nests a reminder one level [C,
  P-new-8].
- **Tweek:** subtasks with round checkboxes in the sheet [C].
- **Todoist:** completed sub-tasks hidden behind "Show Completed Sub-tasks" [C].
- **Google Tasks:** subtasks collapse [R].

**Default variation:**
- A one-level checklist in the card (Things).
- A ticked subtask stays in place, struck (P-new-9).
- The row shows a count chip "1/3" when the to-do has subtasks.
- Indent and Outdent by gesture (Apple) is a variation on request (TD-GEST).

**What it is.** Small steps inside one to-do.

**Anatomy.**
- Under the notes: one row per subtask, 44 pt tall [U]:
  - a 20 pt circle checkbox in `--accent` (circle whatever `checkbox` says, as Things);
  - the title 15 pt `--ink`;
  - a grip "≡" `--ink-2` at the right.
- A ticked subtask: a filled circle with ✓, the title struck in `--ink-2`.
- Last row: "Add Subtask" 15 pt `--accent` with a ⊕.
- Row chip: "1/3" 13 pt `--ink-2` in the meta line (TD-ROW-02).

**States.** None (only "Add Subtask"); some open; all ticked (the parent stays open; ticking the
last subtask does not tick the parent [U, research silent]); the parent ticked (subtasks keep
their own `done`).

**Interactions.**
- Tap "Add Subtask": a new row with the keyboard up. Return adds the next one; Return on an empty
  row ends.
- Tap a circle: toggles that subtask's `done`. Instant, under 100 ms (L1).
- Drag the grip: reorder within the list. The drop line shows above the finger; a drop never
  nests (P-new-10).
- Swipe a subtask left: delete it, with an Undo toast "Deleted" (Things swipes left to delete
  checklist items [C]).
- Long-press the parent in the list: the menu (TD-GEST-03).

**Words.** "Add Subtask" · "1/3" · "Deleted" · "Undo".

**Data.**
- `todo:` `subtasks: [{ id, title, done }]`, in array order.
- The array is rewritten whole on each change (`store.update` with the new array).
- Moving or deleting the parent moves or deletes them (one record).
- A repeat's next copy gets the same subtasks with new ids and `done: false` (TD-ITEM-04).

**Needs.** Page alone.

**Edge cases.**
- **P-new-5:** subtasks reset on each repeat.
- **P-new-9:** a ticked subtask stays under its parent.
- **P-new-10:** no accidental nest.
- **P-new-11:** a parent move takes its subtasks.
- **P-new-12 and P1:** one record, so subtasks cannot be lost apart from their parent.

**Tests.**
- Given a to-do with subtasks A, B, C, when B is ticked, then:
  - `subtasks[1].done` is true;
  - B is still second in the card;
  - the row chip reads "1/3".
- Given all three ticked, then the parent's `done` is still false.
- Given the parent is moved to list `work`, then `store.get` on it has the same 3 subtasks.
- Given a daily repeating to-do with subtasks A (done) and B (done), when the parent is ticked,
  then the new copy has subtasks A and B with `done: false` and ids different from the old ones.
- Given subtask C dragged above A, then the array order is C, A, B and no subtask has its own
  `subtasks` field.

**Evidence.**
- look-group-a 1.2 (Things checklist [C]); look-group-d Part 2 P-new-5, 8 to 12 (Google Tasks
  2★, Microsoft To Do 3★, TickTick 4★ [R]; Apple Indent [C]); look-group-c 4.2 (Tweek [C]);
  group-d P1.
- Screenshot: `shots/things_iphone_4.png`.

---

### TD-ITEM-04 Repeat

**Tag:** core. Reasons:
- P6 and checklist #48 (early tick works, a missed repeat does not duplicate, "after completion"
  counts from the completion day).
- P-new-1 to P-new-7.

**Variations:**
- **Things 3.23 (2026-08-19):** two kinds by name, "Regularly" and "After Completion". Repeating
  to-dos have a regular checkbox and can be completed early. Rescheduling asks "Make Exception" or
  "Update Rule". There is "Create Next Copy", and pause, resume or stop in bulk [C, as reported].
  Future copies change by editing the template; Stop makes a plain to-do [C].
- **Things:** a deadline plus "days earlier" (shows on the 10th, due on the 15th) [C, P-new-3].
- **Tweek:** Daily / Weekly / Weekdays / Biweekly; an "Apply to all future repeats" switch [C].
- **Todoist:** a double tick by accident "will complete for the next day too" [R, P-new-4]. A
  completed repeat is logged only in the Activity log [C, P-new-6]. "Postponing an overdue
  recurring task always moves it to tomorrow" [C].
- **Microsoft To Do:** a repeat missed more than once duplicates [R, older].
- **Obsidian Tasks #609:** "when done" lands on the wrong Sunday [C].

**Default variation:** Things' two kinds, named "Regularly" and "After Completion", with the four
rules records.md allows:

| Rule | Value |
|---|---|
| Every Day | `day` |
| Every Weekday (Monday to Friday) | `weekday` |
| Every Week | `week` |
| Every Month | `month` |

Records.md has no interval ("every 2 weeks") and no yearly rule; both are not mapped.

**What it is.** A to-do that comes back after it is ticked.

**How the next copy is made** (records.md section 1):
- Ticking a repeating to-do sets `done` and `completedAt` on it and writes the next copy as a new
  `todo:`. The copy has the same `title`, `notes`, `list`, `time`, `part`, `repeat`, `emoji`,
  `color`, subtasks reset (TD-ITEM-03), and a new `when`.
- **"Regularly"** (`from: schedule`): the first date of the rule after the later of the old
  `when` and today [U rule].
  - A tick early (before `when`) gives the occurrence after `when` (Things 3.23).
  - A tick days late gives the first occurrence after today, so missed days never pile up as
    copies (#48).
- **"After Completion"** (`from: done`): counted from the tick day.
  - `day` +1; `weekday` the next Monday to Friday; `week` +7; `month` the same day next month.
- **`week`:** the same weekday as the old `when`. **`month`:** the same day of month. In a month
  without that day, the last day of the month [U]. The engine's skip rule (NOTIFICATIONS.md 4.3)
  is for notifications; a to-do should not vanish for a month.
- **No `when` when the repeat is set:** `when` becomes today [U].
- **A second tick within 2 s of the first does nothing** (records.md, P-new-4).
- **The open copy is the template:** editing it edits every future copy (Things "edit the
  template"). Done copies are history and are not changed.
- **"Stop Repeating"** writes `repeat: null` (Things "Stop").

**Anatomy.**
- In the card: the chip "↻ Every Day" (or "↻ Repeat" when none) [U].
- Tapping it opens a sheet (`--surface`, 16 pt top radius):
  - section "Repeat" with rows "Never", "Every Day", "Every Weekday", "Every Week",
    "Every Month", each 44 pt with a ✓ on the chosen one;
  - section with a segmented control "Regularly · After Completion";
  - "Stop Repeating" in `--ink` when a repeat is set.
- In the row's meta line: "↻" (TD-ROW-02), as Things and Reminders.

**States.**
- No repeat.
- Repeating, open.
- Ticked: the old copy is done and goes per `doneGoes`; the new copy shows on its day (in Upcoming
  or Today).
- Stopped.

**Interactions.**
- Choose a rule: writes `repeat` at once.
- Tick: as above. The copy is written in the same handler as the tick; the tick shows first
  (under 100 ms, L1).
- Untick (Undo, TD-DONE-06): reopens the old copy and deletes the copy it wrote, if that copy is
  unchanged [U].
- Several repeating to-dos are rescheduled together with TD-DAY-04 "Move to Today" (P-new-7).

**Words.** "Repeat" · "Never" · "Every Day" · "Every Weekday" · "Every Week" · "Every Month" ·
"Regularly" · "After Completion" · "Stop Repeating".

**Data.**
- `todo:` `repeat: { every, from }`, `when`, `done`, `completedAt`, `subtasks`.
- A tick writes the old record (`done`, `completedAt`) and one new `todo:<newId>`.
- Each copy with a `time` gets its own notification (TD-OUT-01).

**Needs.** Page alone.

**Edge cases.**
- **#48:** early tick, no duplicates, after completion from the tick day.
- **P-new-1:** both kinds by name.
- **P-new-2:** the template is the open copy.
- **P-new-3:** `when` plus `deadline`, set in TD-ITEM-05.
- **P-new-4:** 2 s guard.
- **P-new-5:** subtasks reset.
- **P-new-6:** every done copy keeps `completedAt`, so it shows in the logbook (TD-DONE-07).
- **P-new-7:** bulk move in TD-DAY-04.
- **#46:** day strings.

**Tests.**
- Given `repeat { every: "day", from: "schedule" }` and `when` 2026-10-31, when ticked on
  2026-10-31, then:
  - the record has `done: true`;
  - exactly one new open `todo:` exists with `when` 2026-11-01.
- Given the same with `when` 2026-10-25, when ticked on 2026-10-31, then the new copy's `when` is
  2026-11-01 and only one new copy exists (#48).
- Given `from: "schedule"`, `every: "week"`, `when` 2026-11-06 (Fri), when ticked early on
  2026-10-31, then the new copy's `when` is 2026-11-13.
- Given `from: "done"`, `every: "week"`, `when` 2026-10-26, when ticked on 2026-10-31, then the new
  copy's `when` is 2026-11-07.
- Given `every: "weekday"`, `from: "schedule"`, `when` 2026-10-30 (Fri), when ticked on 2026-10-30,
  then the new copy's `when` is 2026-11-02 (Mon).
- Given `every: "month"`, `when` 2026-01-31, when ticked on 2026-01-31, then the new copy's `when`
  is 2026-02-28.
- Given a repeating to-do, when it is ticked twice within 1 s, then exactly one new copy exists.
- Given a repeating to-do, when "Stop Repeating" is tapped, then `repeat` is null; when it is
  ticked, then no new copy is written.
- Given 3 ticks of a daily to-do on 3 days, when the logbook opens, then it shows 3 done copies
  with 3 different `completedAt` days.

**Evidence.**
- group-a 3 (Things 3.23 [C as reported]); look-group-d Part 2 P-new-1 to 7 (Things 2803564 [C];
  Todoist 4★ [R]; Reminders 4★ [R]); look-group-c 4.2 (Tweek repeat sheet [C]).
- group-d P6 and #48; group-a 4 (Todoist postponing [C]).
- No screenshot in `shots/`.

---

### TD-ITEM-05 Date, time, deadline

**Tag:** core. Today and Upcoming depend on it (TD-DAY), and checklist #45 (floating time).

**Variations:**
- **Things When picker:** shortcuts "Today", "This Evening", "Someday", then a calendar grid, then
  "Clear", which "removes any existing schedules" [C]. The deadline is separate, through the flag.
  Natural language in the picker [C].
  - Complaint: choosing a date closes the picker, so a time needs a second trip ("Let me choose a
    date and reminder time then give me the option to press done", 2025-06-05 [R]).
- **Apple Reminders:** "Date & Time" with two toggles, Date ("Tomorrow") and Time ("7:00 AM")
  [C].
- **Todoist:** dates parsed from the title (TD-ADD-05); `{march 30}` sets a deadline [C].
- **Tweek:** a time typed as a prefix ("10:00 Respond to emails") [C].
- **Things:** deadline plus "days earlier" [C, P-new-3].

**Default variation:**
- One "When" sheet that stays open until "Set": the Things shortcuts, a date picker, plus Time and
  Deadline rows in the same sheet (fixes the Things complaint).
- "This Evening" sets `part: "evening"` (shown as a section only with TD-DAY-02 on).

**What it is.** When a to-do is planned (`when`, `time`, `part`), when it is due (`deadline`), or
that it has no plan yet (`someday`).

**Anatomy.**
- Sheet (`--surface`, 16 pt top radius, half height [U]). Title "When" 17 pt semibold, centred.
- Shortcuts as rows 44 pt with a glyph:
  - "Today" ★;
  - "Tomorrow";
  - "This Evening" ☾;
  - "Someday" (box glyph).
- "Date": `<input type="date">` (opens the iOS picker in WKWebView, as the daily planner).
- "Time": a switch plus `<input type="time">`.
- "Deadline": a switch plus `<input type="date">`, ⚑ glyph.
- Bottom: "Clear" at left in `--ink`, "Set" at right in `--accent` [U].
- In the row: the date or time in the meta line (TD-ROW-02); the deadline right-aligned ("⚑ Fri")
  (Things red ⚑).

**States.**
- No date (`when` null, not someday).
- Today; a later day; with time; with deadline only; Someday.
- Time set with no date: `when` becomes today [U].
- Someday: `when`, `time` and `part` are cleared.

**Interactions.**
- Tap a shortcut: fills the sheet's values; nothing is written until "Set".
- "Set": one `store.update` with `when`, `time`, `part`, `deadline`, `someday`.
- "Clear": `when`, `time`, `part` null and `someday` false, then the sheet closes. The deadline is
  kept, as Things clears schedules only [U].
- Swipe the sheet down: closes without writing.

**Words.** "When" · "Today" · "Tomorrow" · "This Evening" · "Someday" · "Date" · "Time" ·
"Deadline" · "Clear" · "Set" · "⚑ Fri".

**Data.**
- `todo:` `when` (`YYYY-MM-DD` or null), `time` (`HH:MM` or null), `part`, `deadline`
  (`YYYY-MM-DD` or null), `someday` (boolean).
- A change to `time` or `when` on a timed to-do rewrites its notification (TD-OUT-01).

**Needs.** Page alone. Native pickers come from `<input>`, with no bridge.

**Edge cases.**
- **#45:** `time` is a wall-clock time, so 09:00 stays 09:00 after travel. Pinning to a zone has
  no `todo:` field and is not mapped.
- **#46:** day strings.
- **P-new-3:** `when` 2026-11-10 with `deadline` 2026-11-15 shows on the 10th and is due on the
  15th.
- **#11:** an undated to-do stays in its list.

**Tests.**
- Given the sheet, when "Tomorrow" is tapped on 2026-10-31 and then Time 07:00 is set and "Set" is
  tapped, then `when` is 2026-11-01 and `time` is "07:00", and the sheet stayed open between the
  two choices.
- Given a to-do with `when` and `time`, when "Someday" and "Set" are tapped, then:
  - `someday` is true;
  - `when`, `time` and `part` are null;
  - it is not in Today or Upcoming.
- Given "This Evening" and "Set" on 2026-10-31, then `when` is 2026-10-31 and `part` is "evening".
- Given `deadline` 2026-11-15, when "Clear" is tapped, then `when` is null and `deadline` is still
  2026-11-15.
- Given the phone moves from New York to Los Angeles, then a to-do with `time` "09:00" still reads
  9:00 AM.
- Given the sheet swiped down after choosing "Tomorrow", then the record is unchanged.

**Evidence.**
- look-group-a 1.2 (When picker [C]; complaint [R]), 3.2 (Reminders Date & Time [C]).
- look-group-b 1.2 (Todoist symbols [C]); look-group-c 4.2 (Tweek [C]); look-group-d P-new-3.
- group-d #45, #46.
- Screenshot: `shots/things_iphone_2.png` (⚑ deadline in a row).

---

### TD-ITEM-06 Move list, delete

**Tag:** core. Reasons:
- Checklist #50: confirm or undo, plus a trash.
- P-new-24: warn before a bulk delete only.
- P3: Things "No undo option. Deal breaker." and "badly needs a Recently Deleted section".

**Variations:**
- **Things:** the list picker in the card footer ("☐ Inbox") [C].
- **Clear 2:** drag and drop between lists [C]. Users can't find how to move a task between
  lists [R, P-new-32].
- **Microsoft To Do:** "Confirm before deleting" setting [C]; deleted tasks go to Outlook Deleted
  Items [C].
- **Apple Reminders:** Recently Deleted since iOS 18 [R], about 30 days [U]; "Delete List" with
  the safety in Recently Deleted [C, WRITING sources].
- **Apple HIG:** "Warn people when they initiate a task that can cause data loss that's unexpected
  and irreversible… don't warn… when data loss is the expected result" [C].
- **Complaints** [R]:
  - "I accidentally deleted everything once. There is no warning" (Reminders).
  - "deleting a project deleted all of my HUNDREDS of tasks… without even a warning" (Todoist).

**Default variation:**
- The Things list picker in the card footer.
- Delete a to-do at once, with an Undo toast (WRITING rule 8: prefer undo).
- Deleting a whole list asks "Delete List?" first, then also offers Undo.
- Trash: not mapped (see Data).

**What it is.** Putting a to-do in another list, and removing a to-do or a list.

**Anatomy.**
- Card footer, left: the list's emoji or glyph plus its name 15 pt `--ink-2` ("Inbox"). Tap opens
  a sheet listing every list (emoji, name, colour dot), 44 pt rows, ✓ on the current one.
- "⋯" menu: "Delete" in red #FF3B30 (literal colour, not a theme token) [U].
- Toast: bottom, above the add control, `--ink` background, white 15 pt text, "Undo" in
  `--accent`. Shown 5 s [U] (TD-DONE-06).
- List delete alert: the iOS-style alert built in the page, title "Delete List?", buttons
  "Delete" (red) and "Cancel".

**States.** In Inbox (`list: "inbox"`); in a list; deleted (gone, with Undo for 5 s); list delete
asked; list deleted.

**Interactions.**
- Pick a list: writes `list` and `order` = the last position in the target list (one write;
  fractional order) [U]. Toast "Moved to Work" with "Undo" [U].
- "Delete" (menu, or a swipe set to delete in TD-GEST-01):
  - `store.delete('todo:<id>')`, after deleting its `reminder:` if it is timed (TD-OUT-01);
  - toast "Deleted" with "Undo";
  - Undo `store.set`s the kept record (and its reminder) back, unchanged.
- Delete a list (TD-NAV-03 menu):
  - the alert first;
  - "Delete" removes the `list:` record and every `todo:` in it;
  - toast "Deleted" with "Undo", which restores them all.
- No confirmation for one to-do (HIG: expected loss).

**Words.** "Inbox" · "Delete" · "Deleted" · "Undo" · "Moved to Work" · "Delete List?" · "Cancel".

**Data.**
- `todo:` `list`, `order`. `list:<id>` records.
- Delete removes records. Undo keeps the values in page memory for the toast's life.
- **Not mapped:** a trash kept for a stated number of days (#50, N-14). `todo:` has no
  `deletedAt` field, so a delete is final once the toast is gone and the page is closed. The
  server's append-only history holds old rows (PRODUCT.md, import note), but there is no restore
  path for a person. The founder decides whether to add `deletedAt`.

**Needs.** Page alone, except the trash, which records.md lacks.

**Edge cases.**
- **#50:** Undo now, trash not mapped.
- **P-new-24:** list delete warns.
- **P-new-11:** subtasks move with the parent.
- **#6:** nothing removed without a delete action.
- **DP-43:** a deleted to-do never notifies; its reminder is deleted first.
- **P-new-16:** `order` holds after a move.

**Tests.**
- Given a to-do in Inbox, when list "Work" is picked, then `list` is the Work list's id and it is
  last in Work.
- Given a to-do deleted, then `store.get` gives null and "Deleted" shows. When "Undo" is tapped,
  then `store.get` gives the original record with every field equal.
- Given a timed to-do, when it is deleted, then `reminder:todo-<id>` is gone before the `todo:` is
  gone (check the call order on the store spy).
- Given one to-do deleted, then no alert was shown.
- Given list "Work" with 12 to-dos, when Delete is chosen, then "Delete List?" shows. When "Cancel"
  is tapped, then all 12 and the list remain.
- When "Delete" is tapped, then the list and the 12 are gone. When "Undo" is tapped, then all 13
  records are back.

**Evidence.**
- look-group-a 1.2 (Things footer [C]); look-group-d Part 2 P-new-24 (HIG [C]; Reminders,
  Todoist, Clear [R]), P-new-32 (Clear [R]).
- group-d P3 (Things [R]), #50, section 4 (recovery table); WRITING.md rule 8.
- Screenshot: `shots/things_iphone_4.png`.

