# Gestures (TD-GEST)

Gestures are how a to-do is acted on without opening it: swipe a row left or right, hold and drag
to reorder, hold for a menu, and the keyboard on a laptop. Four patterns, from research
`LOOK-ANALYSIS.md` section 1.5, `look-group-d.md` section 1.3 (the gesture table across Things,
Todoist, Reminders, Microsoft To Do and Clear), and the app files `look-group-a.md` to `-c.md`.
Gestures are where to-do apps lose people. Drag to reorder is the most complained-about gesture
(about 20 reviews), and changing a gesture in an update is a leave reason (Todoist swipes, Clear's
2026 navigation), so nothing here changes unless the person changes it (L3). Sizes are in pt.
Colours are theme tokens that `recipe.md` will define. The token names (`--accent`, `--bg-raised`,
`--ink`, `--ink-2`, `--line`, `--ok`, `--danger`, `--move`, `--glass`) are [U] until it does. "Checklist
N" is `group-d.md` section 6. "P-new-N" is `look-group-d.md` Part 2. L1 to L6 are
`LOOK-ANALYSIS.md` section 4. Screenshots are in midas-intel `docs/research/todo/shots/`.
[U] marks anything not in the research.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-GEST-01 | Swipe right / left (configurable) | core | `swipeRight: complete`, `swipeLeft: delete` (Clear) |
| TD-GEST-02 | Drag to reorder | core | Hold to lift, drop line above the finger, drops only into gaps, never nests [U] |
| TD-GEST-03 | Long-press menu | on request | No settings field; hold still to open a menu of date, list and delete actions [U] |
| TD-GEST-04 | Keyboard (laptop) | on request | No settings field; on whenever a hardware key is pressed [U] |

Rules for every pattern here:
- No gesture starts within 20 pt of the left screen edge. The shell owns that swipe (back to the home grid; `daily-planner/recipe.md` section 3). Rows have a leading inset of at least 20 pt [U], so the checkbox and every swipe or hold start point sit outside that zone.
- No haptics. Things and TickTick buzz on pickup, and Clear on check-off. A page has no haptics API, and `PRODUCT.md` lists haptics as "later" native reach. The hidden-switch WebKit trick (`LOOK-ANALYSIS.md` section 5) is not used [U].
- Every destructive or moving gesture can be undone (checklist 49, 50; P-new-22).
- Motion becomes instant under `prefers-reduced-motion: reduce`.
- Gestures must live alongside the shell's own gestures. That is a stage-11 platform check (`LOOK-ANALYSIS.md` section 5).

---

### TD-GEST-01 Swipe right / left (configurable)

**Tag:** core. Every app in the research has row swipes, and accidental or changed swipes are leave
reasons. **Variations** (`look-group-d.md` 1.3, `look-group-a.md` 1.3 and 2.3, `look-group-b.md`):
- Things: right opens When (date); left selects (multi-select), then swipe or tap others to add them.
- Todoist: each side can be Complete, Schedule, Reminders or Delete. Swipe-to-select was removed on iOS in 2026.
- Apple Reminders: right indents (makes a subtask; on a subtask, outdents); left deletes.
- Microsoft To Do: right toggles My Day and left deletes, with confirmation on mobile. Sources disagree on the direction [U].
- Clear: right completes (the row turns green, #00B612 sampled [R], with a ✓ and strike); left deletes. Clear 2 adds swipe-and-hold left for a date and time.
- Superlist: right to left opens details or adds a subtask.
- TickTick: customisable left and right.

**Default variation:** `swipeRight: complete`, `swipeLeft: delete` (Clear). Each side can be set to
`complete`, `tomorrow`, `delete` or `none` in TD-SET-01.

**What it is.** A horizontal swipe on a row does one action without opening the to-do. Each side has
exactly one action, chosen by the person.

**Anatomy.**
- The row slides with the finger. Behind it, a full-height band fills from the side being swiped from:
  - `complete`: `--ok` (green) with a ✓ glyph;
  - `tomorrow`: `--move` [U colour] with a calendar-arrow glyph and the label "Tomorrow";
  - `delete`: `--danger` with a trash glyph and the label "Delete".
- The glyph is 22 pt white and the label 13 pt semibold white [U]. Both sit 20 pt in from the band's outer edge [U].
- Before the threshold, the glyph is at 60% opacity and 0.8 scale. At the threshold it snaps to 100% and 1.0 over 100 ms [U]. This is the visible stand-in for the haptic the page cannot play.
- Done rows (`doneGoes: stay` or `sink`): the `complete` side shows "Reopen" with an undo-arrow glyph [U].

**States.**
- A side set to `none`: no band, and the row does not move that way.
- Done row: `complete` reopens it (`done` false, `completedAt` null) [U].
- A row being edited: swipes off.
- Logbook rows: swipes off [U]. Search results: swipes off [U].

**Interactions.**
- Direction lock: the swipe starts only when |dx| > 10 pt and |dx| > 2·|dy| [U]. Otherwise the list scrolls.
- A touch starting within 20 pt of the left screen edge never starts a row swipe; that is the shell's back swipe.
- Commit when released past 30% of the row width [U]. Todoist users left over a swipe made "unnecessarily long", so the threshold stays short. Released before it, the row springs back over 200 ms ease-out [U].
- One action per side. A longer swipe never triggers a second action (Clear: right "sometimes does that, sometimes deletes it, and sometimes makes a copy").
- On commit:
  - `complete`: the row tints `--ok` and the title is struck within 100 ms of release (L1, P-new-26). It then follows TD-DONE-05 (`doneGoes`, basic `stay`), with sound and celebration per TD-DONE-02 and 04, and undo per TD-DONE-06.
  - `tomorrow`: `when` = tomorrow, and `someday` false. The row leaves Today, collapsing over 200 ms [U]. A toast shows "Moved to Tomorrow" with "Undo".
  - `delete`: the row collapses over 200 ms [U]. A toast shows `Deleted "<title>"` with "Undo" for 5 s [U]. There is no confirmation (`docs/WRITING.md` rule 8: prefer undo).
- The toast sits at the bottom above the + or bar, 48 pt tall on `--glass` [U]. It covers no rows' controls (L6). A new toast replaces the old one, whose action stands.

**Words.** "Tomorrow" · "Delete" · "Reopen" · toasts "Moved to Tomorrow", `Deleted "Call mom"`
(the title, cut to 30 characters with "…" [U]) · "Undo".

**Data.**
- `complete`: `store.update('todo:<id>', { done: true, completedAt: <now ISO> })`. For a repeating to-do, the next copy is written as in `records.md` section 1. A second complete within 2 s does nothing (P-new-4).
- `tomorrow`: `update` with `when` = tomorrow's `YYYY-MM-DD`. Under `todayModel: fresh`, `inToday` is cleared too (TD-DAY-01) [U].
- `delete`: `store.delete('todo:<id>')`. The deleted value is held in page memory for Undo, which writes it back under the same key [U]. There is no trash record in `records.md` (checklist 50 is not met; open for the founder).
- Reads `settings:self.swipeRight` and `.swipeLeft`.

**Needs.** Page alone. The haptic at the threshold and on commit: the shell lacks it (`PRODUCT.md`
"later"). The shell has sync, so a swipe on one device shows on the others (P4).

**Edge cases.**
- L1 / P-new-26: the visible change within 100 ms.
- L2, P-new-22: undo names the item.
- L3: the swipe settings change only in TD-SET-01.
- Checklist 49 (undo a tick), 50 (delete can be undone; trash not mapped), 8 (a refused write puts the row back and shows "Can't Save" with "Try Again" [U]).
- P-new-4 (double complete), P-new-25 (the leading inset keeps grip touches off the checkbox).
- Clear's lost-forever wrong-direction swipe: every action has Undo, and the band names the action before release.

**Tests.**
- Given defaults, when a row is swiped right 40% and released, then within 100 ms the row shows the done style, and the record has `done` true and `completedAt` set.
- Given defaults, when a row is swiped right 20% and released, then the record is unchanged and the row is back in place.
- Given a touch starting at x = 12 pt moving right, then the row does not move.
- Given defaults, when a row is swiped left 40% and "Undo" is tapped within 5 s, then `todo:<id>` exists again with every field equal to before.
- Given `swipeLeft: none`, when a row is swiped left 60%, then no band shows and nothing is written.
- Given `swipeRight: tomorrow` on 2026-10-31, when a Today row is swiped right, then its `when` is "2026-11-01" and it is not in Today.
- Given a daily repeating to-do, when it is swiped complete twice within 1 s (once on the row, once on the next copy), then exactly one new copy exists.
- Given a vertical drag of 80 pt with 15 pt sideways drift, then the list scrolls and no band shows.

**Evidence.**
- `LOOK-ANALYSIS.md` 1.5 and section 3, items 1 and 6.
- `look-group-d.md` 1.3: Todoist complaints 4 ("ruined the swipe function", 2025-09-10; "broke swipe gesture", 2025-12-16; "Bring Back Swipe Left", 2026-03-13; "no feedback when you scroll down to refresh", 2026-04-07). Clear wrong direction 2 (2026-09-08, 2025-01-28).
- `look-group-b.md` table: customisable swipes 0 loves, 5 complaints when Todoist changed them. "Too easy to tick by accident or misdrop": 5 complaints.
- `look-group-a.md` 2.5: "so easy you can delete items accidentally" (2026-07-25).
- Screenshot `clear_iphone_1.png` (swipe-right green row).

---

### TD-GEST-02 Drag to reorder

**Tag:** core. Leave reason 2 in `LOOK-ANALYSIS.md` section 3; P-new-10, P-new-11, P-new-16.
**Variations:**
- Things: tap and hold until the to-do lifts, then drag. It drags all selected to-dos. In Upcoming, dragging onto another day reschedules; the lifted row is a blue-tinted card with a shadow ("re-scheduling is as easy as drag and drop").
- TickTick: a vibration says "ready to move"; users report the drag failing.
- Microsoft To Do: replaced drag in 2026 with a reorder button that moves "ONE SPOT AT A TIME" (complaint).
- Todoist: drag a task to the bottom of Today to postpone it to tomorrow.
- Tweek: long-press and drag to another day (another week since 2026-09). A bug: "If you drop it, it will go all the way to the bottom".
- Clear: tap and hold to drag. Any.do: move up and down to set priority (loved).

**Default variation:** no `settings:self` field. Hold still for 400 ms [U] to lift the row. A drop
line is drawn in the gap above the finger, and a row can drop only into a gap, never onto another
row, so a drag never nests [U].

**What it is.** The person changes the order of to-dos by moving them, and the order stays. It is
loved when it works ("drag and drop tasks as my priorities change throughout the day"), and the most
complained-about gesture when it does not.

**Anatomy.**
- Lifted row:
  - scale 1.03, a soft shadow, `--bg-raised` with a 10% `--accent` tint (Things' blue-tinted card) [U];
  - drawn 40 pt above the finger's contact point [U], so neither the finger nor the row hides the drop line (P-new-10: "The line that indicates where a task will be placed… is buried under the thing you're dragging").
- Drop line: 2 pt `--accent`, the full text width, with an 8 pt `--accent` circle at its leading end [U], in the gap the row will go into. Neighbouring rows slide apart 8 pt around it over 150 ms [U].
- Drop targets:
  - Gaps between open rows in the same list or section.
  - In Today with `dayParts: true`, the part-of-day headers.
  - In Upcoming, the day headers.
- Rows are never targets (no drop-on-row).

**States.**
- One row: nothing to reorder; lifting still works, and dropping changes nothing.
- Done rows (`doneGoes: stay` or `sink`): not draggable, and not targets [U].
- Views sorted by date (Upcoming): reorder within a day; a drop on another day's gap changes `when` [U].
- Logbook and search: off.
- Long list (checklist 55): auto-scroll as below.

**Interactions.**
- Lift: the finger held still (moved less than 8 pt) for 400 ms [U]. Before that:
  - horizontal movement is a swipe (TD-GEST-01);
  - vertical movement is scrolling.
- Held 400 ms and released without moving: the long-press menu (TD-GEST-03), if built [U].
- Held, then moved: the drag.
- Lift animation: 150 ms ease-out [U]. A touch starting within 20 pt of the left edge never lifts.
- Auto-scroll: within 60 pt of the list viewport's top or bottom, the list scrolls, faster nearer the edge, up to 600 pt/s [U].
- Drop: the row settles into the gap over 200 ms [U]. Released outside the list, or on its own gap, the row returns.
- Esc (keyboard) or a second finger touching: cancels [U].
- Keyboard alternative (TD-GEST-04): ⌥↑ / ⌥↓ moves the selected row one place. This is an extra, not a replacement; Microsoft To Do users left when the button replaced drag.
- A subtask is part of its parent's record (`records.md` `subtasks`), so moving a parent moves its subtasks (P-new-11), and a drag can never make a subtask.
- Nesting by gesture (P-new-8) belongs to TD-ITEM-03.

**Words.** None on the row. The undo toast after a drop that changed `when` or `part`: "Moved to
Tue 4 Nov" or "Moved to Evening", with "Undo" [U]. A drop that only reorders gets no toast [U].

**Data.**
- One `store.update('todo:<id>', { order })`, where `order` is the midpoint of the two neighbours in the target gap (fractional; `records.md` section 1).
- If the drop crosses a section, `when` or `part` changes too.
- Every ordered view sorts by `order`, then `createdAt`, every time it renders (checklist 16, P-new-16).
- The shell syncs the record (P-new-16 "syncs across devices": shell has it).

**Needs.** Page alone (pointer events, `touch-action: none` on the lifted row). The haptic on pickup
(Things, TickTick): the shell lacks it.

**Edge cases.**
- P-new-10: a row released while its contact point is over the middle of another row goes into the nearest gap. The drop line shows which gap before release.
- P-new-11: subtasks move with the parent (data model).
- P-new-16: order holds after reload and after moving to another list (TD-ITEM-06 places a moved to-do at the end of the new list's open rows [U], never re-sorting the old list).
- P-new-13: lists reorder with the same mechanics (TD-NAV-03).
- Checklist 16, 55 (drag stays smooth with 500 rows [U]), L3.
- Tweek's drop-to-bottom bug: the test below.

**Tests.**
- Given rows A (1), B (2), C (3), when B is lifted and released with the drop line between C and the end, then only B's record is written, B.`order` > 3, and the order after reload is A, C, B.
- Given rows A, B, C, when B's contact point is released over the vertical middle of C, then B is its own record placed before or after C (as the drop line showed), and C.`subtasks` is unchanged.
- Given a drag in progress, then the drop line's y position is at least 20 pt above the finger's y [U].
- Given a hold at x = 10 pt for 600 ms, then nothing lifts.
- Given a hold of 200 ms then vertical movement, then the list scrolls and nothing lifts.
- Given Today with `dayParts: true`, when a Morning row is dropped into the Evening gap, then its `part` is "evening" and "Moved to Evening" shows with "Undo".
- Given B dropped 4 rows down in a list of 10, when the page reloads, then B is in the same place.

**Evidence.**
- `LOOK-ANALYSIS.md` 1.5 and section 3 item 2 ("about 20").
- `look-group-d.md` 1.3: MS To Do 22, TickTick 15, Todoist 11, Clear 10 mentions of swipe, drag or reorder.
  - Nesting quotes: MS To Do 2025-07-18, TickTick 2026-10-22 and 2026-10-04.
  - Order-not-kept quotes: Reminders 2026-10-06 and 2025-10-06, MS To Do 2025-10-31.
- Pattern table: "Drag to reorder with haptic pickup": 4 loved, ~20 complaints.
- `look-group-c.md`: Tweek drop bug (2025-11-18); Any.do love (2025-11-30).
- No screenshot in `LOOK-ANALYSIS.md` section 6 shows a drag. `look-group-a.md` describes `things_iphone_3.png` (Upcoming drag, in the session scratchpad, not copied to `shots/`).

---

### TD-GEST-03 Long-press menu

**Tag:** on request. Not every app has it, and no checklist item names it. Every action in it is also
reachable from the detail card (TD-ITEM-01), which is the visible way out (leave reason 6).
**Variations:**
- Apple Reminders: a quick options menu [R, review].
- Superlist: long-press gives copy link, inbox, delete; from 2026-06 it starts multi-select [C].
- TickTick: long press opens date options, but not time or repeat [R].
- Things: long press lifts for drag (no menu). In OS 26 its glass buttons "morph into menus when pressed" [R].
- Tweek: long-press and drag to another day.

**Default variation:** no `settings:self` field. When built: hold still for 400 ms and release
without moving, and a menu opens beside the row [U].

**What it is.** A short menu of the actions people do most to a row without opening it: set the
day, move it to a list, add a row below it, delete it.

**Anatomy.**
- The held row lifts (as TD-GEST-02) and the list behind dims 20% [U].
- Menu card below the row, or above if there is no room below: 250 pt wide, 14 pt radius, `--glass` (control layer, HIG) [U].
- Rows 44 pt tall, 17 pt `--ink`, each with a trailing glyph [U]:
  1. "Today"
  2. "Tomorrow"
  3. "Someday"
  4. "Move to List"
  5. "Add Below"
  6. a separator, then "Delete" in `--danger`.
- On a done row: "Reopen" replaces the three date rows [U].
- Opens over 200 ms ease-out from 0.9 scale [U].

**States.** A repeating to-do: the date rows move only this copy [U]. In Logbook: "Reopen", "Delete"
only [U].

**Interactions.**
- Opens on a 400 ms still hold with release (TD-GEST-02 timing). Moving more than 8 pt after the lift turns it into a drag instead and the menu does not open [U].
- Tap a row: does the action and closes. Tap outside or Esc: closes.
- "Move to List": a list picker (TD-ITEM-06).
- "Add Below": opens TD-ADD-06's editable row directly under this one.
- "Delete": deletes with the undo toast of TD-GEST-01.
- Opens only from the person's hold (L6). A touch within 20 pt of the left edge never opens it.

**Words.** "Today" · "Tomorrow" · "Someday" · "Move to List" · "Add Below" · "Delete" · "Reopen" ·
toasts "Moved to Today", "Moved to Tomorrow", "Moved to Someday", `Moved to "Groceries"`,
`Deleted "<title>"` · "Undo".

**Data.**
- `todo:<id>` updates:
  - Today: `when` today, `someday` false.
  - Tomorrow: `when` tomorrow, `someday` false.
  - Someday: `someday` true, `when` removed. In `store.update`, null removes a field (`midas-store.js`), so the schema must read a missing `when` as null [U].
  - Move to List: `list`, and `order` at the end of that list's open rows [U].
  - Reopen: `done` false, `completedAt` removed.
  - Delete: as TD-GEST-01.
- Add Below writes a new `todo:` (TD-ADD-06).

**Needs.** Page alone. Native iOS context menus are not available to the page; it draws its own [U].

**Edge cases.** P-new-30 (a long title cannot hide the date actions: they are in the menu, not on
the row), checklist 49, 50, P-new-22, L3, L6.

**Tests.**
- Given a row held still for 450 ms and released, then the menu shows the six rows in order.
- Given a row held 450 ms then moved 30 pt, then no menu shows and a drag is in progress.
- Given "Someday" is chosen on a row with `when` "2026-11-02", then the record has `someday` true and no `when`, and it is not in Upcoming.
- Given "Delete" is chosen and "Undo" tapped, then the record is back with the same fields.
- Given a done row, then the menu shows "Reopen" and no date rows.

**Evidence.** `look-group-d.md` 1.3 table (long press row), `look-group-c.md` 1.2 (Superlist),
`look-group-b.md` 2.2 (TickTick), `look-group-a.md` 1.3 (Things). No quote counts for the menu itself
were found [U].

---

### TD-GEST-04 Keyboard (laptop)

**Tag:** on request. The research has almost nothing on keyboards. Every key below is [U] unless
marked. Laptop use is the prototype on a laptop through the stand-in store (`records.md` intro), and
an iPad or iPhone with a hardware keyboard [U]. **Variations:**
- Things on Mac: ⌘L "Log Completed" [R].
- al3rez's plain-text list: one file "opened with a hotkey" (`group-a.md` section 7) [C].
- Clear 2: the keyboard "next" key for rapid entry [C].
- Tweek: "press enter" to add on a day [C].
- Apple HIG: "start search immediately when a person types" in the search field [C].

**Default variation:** no `settings:self` field. Keys work whenever focus is in the page and not in
a text field, except Return and Esc, which also work in fields.

**What it is.** Every common action without the mouse or touch: add, move through rows, tick,
reorder, delete, undo, search.

**Anatomy.**
- Selected row: a 10% `--accent` background and a 2 pt `--accent` leading bar [U], shown only after a key is used (`:focus-visible`).
- No on-screen hint bar [U]. A "Keyboard" list in TD-SET-01 shows the keys [U].

| Key | Action |
|---|---|
| N | New to-do through the active `add` method (opens the add card, focuses the bar, or opens the dotted row of the current section) [U] |
| Return (in an add field) | Add, and keep a new empty field (Clear 2, Tweek) [C] |
| Return (row selected) | Open its detail card (TD-ITEM-01) [U] |
| Esc | Close card, menu or search; cancel a drag [U] |
| ↑ / ↓ | Move the selection [U] |
| Space | Tick or reopen the selected row (same path as TD-DONE-01) [U] |
| ⌥↑ / ⌥↓ | Move the selected row one place up or down (one `order` write) [U] |
| T / ⇧T | Set `when` to today / tomorrow [U] |
| Delete (⌫) | Delete the selected row, with the undo toast [U] |
| ⌘Z | Undo the last action: tick, delete, move or edit (P-new-23) [U] |
| / or ⌘F | Open search (TD-NAV-04) with the field focused [U] |
| ⌘1 … ⌘4 | Today, Upcoming, All, Logbook (TD-NAV-02) [U] |

**States.**
- Focus in a text field: only Return, Esc and ⌘Z act; every other key types.
- During IME composition (`isComposing`), Return does not add [U].
- No rows: arrows do nothing.

**Interactions.** Key repeat on ↑/↓ moves continuously [U]. The selection is kept in page memory
only and starts at the first row on each view change [U].

**Words.** In TD-SET-01: "Keyboard" (section title) and each action named as in the table: "New To-Do",
"Complete", "Move Up", "Move Down", "Today", "Tomorrow", "Delete", "Undo", "Search" [U].

**Data.** Same writes as the touch actions they mirror (TD-GEST-01, 02, TD-ADD). The undo stack is
page memory, lost on reload by design (`daily-planner/recipe.md` section 3 rule).

**Needs.** Page alone (`keydown`). Whether the shell's WKWebView passes ⌘ shortcuts on to the page
on iPad, or keeps them for itself, is not checked [U].

**Edge cases.** P-new-23 (undo covers edits), checklist 49, 50, L3 (keys never change without the
person), checklist 56 (long titles: arrows still move by row).

**Tests.**
- Given three rows and the first selected, when ↓ then Space is pressed, then the second row's record has `done` true.
- Given focus in the add field with "Milk", when Space is pressed, then the field reads "Milk " and nothing is ticked.
- Given rows A, B, C with B selected, when ⌥↑ is pressed, then the order is B, A, C after reload and only B was written.
- Given a row deleted with ⌫, when ⌘Z is pressed, then the record exists again.
- Given any list screen, when "/" is pressed, then the search field is focused.

**Evidence.** `look-group-a.md` 1.3 (Things ⌘L) and 2.3 (Clear 2 next key), `look-group-c.md` 4.2
(Tweek), `look-group-d.md` 1.7 (HIG search), `group-a.md` 7 (al3rez hotkey; 1,402 HN points). No quote
counts on keyboard use were found [U]. No screenshot.

