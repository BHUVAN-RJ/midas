# Done (TD-DONE)

Done is everything that happens when a to-do is ticked: the animation, the sound, the haptic, the celebration, where the done item goes, the undo that names it, and the logbook that keeps it. Seven patterns, from research `LOOK-ANALYSIS.md` sections 1.3, 2, 3, 4 and 5 and the group files `look-group-a.md` (A), `look-group-b.md` (B), `look-group-c.md` (C) and `look-group-d.md` (D). Labels, sizes, "Checklist N", "P-new-N", "L1"–"L6", screenshot names and tokens are as in `blocks/look.md`. [U] marks anything not in the research. A Sidekick page has no haptics API; TD-DONE-03 covers the one known trick.

One tick, in order:
1. Same frame as the tap (under 100 ms, L1): the checkbox fills, the strike starts, the sound plays and the haptic fires.
2. The `store.update` write runs in the background.
3. The undo toast appears.
4. If the list is now all done, the celebration plays.
5. 1.5 s after the last tick [U], the done item goes where `doneGoes` says.

| ID | Name | Tag | Default variation |
|---|---|---|---|
| TD-DONE-01 | Tick animation | core | no setting; fill plus strike-through |
| TD-DONE-02 | Tick sound | core | `tickSound: ding` |
| TD-DONE-03 | Haptic | core | `haptic: true` (hidden switch trick where WebKit plays it) |
| TD-DONE-04 | Celebration | core | `celebrate: allDone` |
| TD-DONE-05 | Where done goes | core | `doneGoes: stay` |
| TD-DONE-06 | Undo with name | core | no setting; toast naming the item, with "Undo" |
| TD-DONE-07 | Logbook and done today | core | no setting; Logbook smart list, grouped by day, Today first |

---

### TD-DONE-01 Tick animation

**Tag:** core (L1; P-new-26; leave reason 3 "tick lag"). **Variations:**
- Fill plus strike: Microsoft To Do, Superlist, Any.do, Tiimo, Tweek [C].
- The whole row turns green (#00B612) with a large ✓ and a strike: Clear [R sample, C screenshot].
- Things: the checkbox fills blue with a white check [R]; a third-party guide describes a ~500 ms fill, tick and settle [U].

**Default variation:** fill plus strike. With `checkbox: none` or `look: heat`, the Clear green row.

**What it is.** What the tick looks like, and how fast it answers.

**Anatomy.**
- Checkbox: the fill grows from the centre, then a white ✓ (TD-ROW-01 done mark).
- Title: a strike-through 1.5 pt [U], drawn left to right; the title colour becomes `--ink-2`. The meta line loses its date colours (TD-ROW-03), and the badge fades (TD-ROW-04).
- Green row: the background becomes `--tick-green` with a white ✓ 22 pt at the left [U], plus the strike.

**States.**
- To do; done; done then undone.
- Write failed: the row returns to to do, with the error below.
- Reduced motion: no animation, the change is instant.
- Repeat lock: for 2 s after a repeat tick, taps on that row and on its new copy do nothing (`records.md` section 1).
- A subtask ticked: it stays under its parent, struck (P-new-9).

**Interactions.**
- Tap the checkbox (or swipe to complete, TD-GEST-01): the visual change starts in the same frame, before `store.update` resolves (L1, P-new-26). Fill 150 ms ease-out, strike 200 ms [U].
- Tap a done checkbox: back to to do, the reverse over 150 ms [U], no sound and no haptic.
- Repeat: the tick sets `done` and `completedAt` on the to-do and writes the next copy as a new `todo:` (`records.md` section 1). The ticked copy stays struck; the next copy shows where its `when` puts it.

**Words.** Error (WRITING rule 6): "Can't Save" with "Try Again" [U]. Otherwise nothing; VoiceOver reads the checkbox state.

**Data.** Writes `todo.done: true` and `completedAt` (ISO time of the tap) with `store.update`. Untick: `done: false`, `completedAt: null`. Repeat: a new `todo:<id>` with the next `when`, `done: false`. Subtask: `subtasks[i].done`.

**Needs.** Page alone.

**Edge cases.**
- L1 and P-new-26: under ~100 ms.
- P-new-4: a double tick never finishes the next copy (the 2 s lock).
- Checklist 48: repeats count from the schedule or the tick day.
- Checklist 43: `completedAt` is the real moment of the tap.
- P-new-9: a ticked subtask stays under its parent.
- Checklist 8: a failed write is shown, not hidden.
- Checklist 49: undo in TD-DONE-06.

**Tests.**
- Given `store.update` stubbed to never resolve, when a checkbox is tapped, then in the same event-loop turn the row has `data-done="true"` and the title has `text-decoration-line: line-through`.
- Given a fixed clock of 2026-10-31T10:00:00, when tapped, then `completedAt` is "2026-10-31T10:00:00" (to the second).
- Given a daily repeating to-do ticked at 10:00:00, when its row or the new copy is tapped at 10:00:01, then exactly one new `todo:` exists and it has `done: false`. When the new copy is tapped at 10:00:03, then it becomes done.
- Given `store.update` rejects, then the row returns to not done and "Can't Save" is shown.
- Given reduced motion, then no transition on the row has a duration above 0.
- Given a subtask is ticked, then it stays inside its parent's subtask list, struck, and the parent's `done` is false.

**Evidence.** "500-1000ms delay between tapping a task as complete, and the app reacting… incredibly abrasive" TickTick 1★ 2026-10-21; "a delay when checking an item complete which sometimes resulting in accidentally checking the wrong one" MS To Do 2★ 2026-09-06 (D 1.1). Loves: "it is also very satisfying when you check one of the boxes" and "checking tasks off feels surprisingly satisfying" Todoist (B); "nothing compares to the satisfaction of actually checking off a task. ✅" TickTick (B); Superlist "The animations… all beautiful" (D). Love 2, ~20 quotes. Screenshots: `mstodo-1.png`, `clear_iphone_1.png`, `superlist_3_crop.jpg`, `tiimo_3_crop.jpg`, `tweek_1.jpg`.

---

### TD-DONE-02 Tick sound

**Tag:** core (love 2, ~20 quotes including sound; L1 "an optional sound"). **Variations:**
- `ding`: Microsoft To Do, the Wunderlist ding, with a "Play completion sound" switch [R].
- `chimes`: Clear, "ascending musical chimes"; each quick tick plays a higher note, and leaving the app resets the pitch [C].
- `pop`: Todoist, a "popping sound effect [that] feels oddly satisfying" [R].
- `off`.
- Also: TickTick lets you choose the sound [R]; Superlist's sound "changes each time" [R].

**Default variation:** `ding`.

**What it is.** A short sound at the moment of the tick.

**Anatomy.** No on-screen part. Every sound is made in code with Web Audio, with no file (the daily-planner DP-FB-01 approach) [U]:
- `ding`: one sine note around 1,320 Hz, 5 ms attack, 300 ms decay [U].
- `chimes`: notes stepping up a pentatonic scale, each about 180 ms [U]. A tick within 3 s of the last one goes one step up, to at most 8 steps, then holds [U]. After a 3 s pause the next tick starts at the bottom again [U]. The pitch does not reset just because the page was left, since a Clear user said the reset "really reduces the satisfaction".
- `pop`: a 60 ms downward sine sweep [U].
- Level: peak about −12 dBFS [U], against "too loud" and "jarring and high pitched".

**States.** On; off; AudioContext suspended (resumed inside the tap, which is a user gesture); page hidden (no sound).

**Interactions.**
- Plays on a tick to done, from a tap or a swipe.
- Never plays on untick, on page load, or when another writer completes the item.
- In TD-SET-01, tapping an option plays it once.

**Words.** Setting "Tick Sound": "Ding", "Chimes", "Pop", "Off".

**Data.** Reads `settings:self.tickSound` (missing → `ding`).

**Needs.** Page alone (Web Audio). Behaviour with the iPhone's silent switch on is not checked [U] (`LOOK-ANALYSIS.md` section 5).

**Edge cases.** L1 (optional); the "too loud" complaints (the level above); a sound only for the person's own tick.

**Tests.**
- Given `tickSound: ding`, when a checkbox is tapped, then exactly one oscillator is started (spy on `AudioContext`).
- Given `tickSound: off`, when tapped, then no `AudioContext` is created.
- Given `chimes`, when 3 to-dos are ticked 1 s apart, then the 3 start frequencies strictly increase. When a 4th is ticked 4 s later, then its frequency equals the first one's.
- Given `ding`, when a done to-do is unticked, then no oscillator starts.
- Given a store change from outside the page marks a to-do done, then no oscillator starts.

**Evidence.** 9 positive and 3 negative sound mentions in the corpus (D). Quoted (D 1.1):
- Microsoft To Do, ding: "the little ding when I check something off the list is so satisfying!!" 5★ 2026-08-04; "The ding… helps my anxiety" 5★ 2025-10-30; "Completion sound is too loud" 3★ 2026-01-25.
- Clear, chimes: "heard that delightful little sound, I was hooked" 5★ 2025-03-25; "sound effects are gratifying" 5★ 2026-05-27; the reset complaint.
- Todoist, pop: "I also LOVE the sound effects it has!!!" 5★ 2026-06-10.
- TickTick: "jarring and high pitched" 5★ 2026-04-01.
- Google Tasks wish: "Wish it had a nice sound" 5★ 2025-03-18.

No screenshot.

---

### TD-DONE-03 Haptic

**Tag:** core (L1 "an optional sound and haptic"; love 2). **Variations:**
- Tiimo: haptics with confetti ("encouragement by way of haptics and confetti!") [C].
- Clear: haptics on check-off [R].
- Things: the Taptic Engine on drag pickup and Magic Plus [C]; TickTick vibrates when a drag is ready [R]. These belong to TD-GEST and TD-ADD.
- Apple HIG: use the Notification types for outcomes, "Avoid overusing haptics", "Make haptics optional", match the haptic to the animation [C].

**Default variation:** `haptic: true`. The page tries the hidden switch trick [R] on each tick, and nothing happens where WebKit does not play it.

**What it is.** A light tap felt at the moment of the tick.

**Anatomy.**
- No visible part.
- A visually hidden `<label><input type="checkbox" switch></label>` is placed once in the page, with `aria-hidden="true"`, `tabindex="-1"` and off-screen [U].
- On a tick, the tick's own pointer handler calls the label's `click()`, which makes WebKit play its switch haptic. Sources: ios-haptics npm, Ionic issue #29942 [R]. The trick was introduced in Safari 17.4 or 18; sources disagree [R].
- WebKit bug 285120 proposes requiring a user action for it [R]. Calling it synchronously inside the tap handler keeps it tied to a user action.
- The page cannot choose the haptic type (HIG Notification success); WebKit plays its own [U].
- The switch's checked state means nothing and is never stored.

**States.** On; off; unsupported (no effect, no error). The setting is always shown, because support cannot be detected from the page [U].

**Interactions.**
- One haptic per tick to done.
- None on untick, on bulk changes or on page load (HIG "Avoid overusing haptics").

**Words.** Setting "Haptics" (on/off switch).

**Data.** Reads `settings:self.haptic` (missing → `true`).

**Needs.**
- **Page alone, for the trick.** Whether it works inside the shell's WKWebView is [U]; device check.
- **Shell lacks it, for a real haptic.** A Sidekick page has no haptics API: iOS Safari has no Vibration API [R], and `PRODUCT.md` lists haptics as "later" native reach through a shell bridge [C, ~line 929]. No shell brief is written yet for the to-do primitive (`records.md` section 4).

**Edge cases.**
- L1: optional.
- HIG "Make haptics optional": the setting exists.
- The hidden switch never reaches VoiceOver or the focus order.

**Tests.**
- Given `haptic: true`, when a checkbox is tapped, then the hidden switch label's `click` is called exactly once, synchronously inside the pointer event handler.
- Given `haptic: false`, when tapped, then it is not called.
- Given `haptic: true`, when a done to-do is unticked, then it is not called.
- Given the page's accessibility tree, then the hidden switch is not in it, and pressing Tab never focuses it.
- Given 3 ticks, then exactly 3 calls.

**Evidence.** Clear "Maybe it's the design, or the haptics" 5★ 2025-06-02 (D); Tiimo "encouragement by way of haptics and confetti!" 2026-10-29 (C); TickTick "feel my phone vibrate that it's ready to move" 3★ 2026-01-07 (D); HIG Playing haptics [C]; the trick (D 1.1, `LOOK-ANALYSIS.md` section 5). No screenshot.

---

### TD-DONE-04 Celebration

**Tag:** core (leave reason 5: taking delight away; Tiimo's removed confetti is named as a reason to leave). **Variations:**
- `allDone`: a moment when the list is cleared. Todoist's shareable "#TodoistZero" screen [R]. The UK Government Design System says a cleared list "may be celebratory" and should stay separate from "filter shows nothing" [R].
- `confetti`: Tiimo, confetti on completing a task [C]; Todoist confetti, called "tiny… weak" [R].
- `off`.

**Default variation:** `allDone`.

**What it is.** A small reward: when the last open to-do in the view is ticked (`allDone`), or on every tick plus that moment (`confetti`).

**Anatomy.**
- All-done state (TD-SET-05 owns the empty and all-done states):
  - A ✓ glyph 48 pt in `--accent` and the headline "All Done", 20 pt semibold [U]. Nothing else; the + already on screen is the one action (WRITING rule 7).
  - It sits under the struck rows with `stay` or `sink`, and in place of the list with `hide` or `logbook`.
  - It is inline in the page, never a sheet, alert or modal (L6).
- Confetti:
  - A full-page `<canvas>` with `pointer-events: none`, about 40 pieces from the tapped checkbox, over about 900 ms [U]. That is more than Todoist's "tiny", which a user asked to "go wild".
  - Colours: the accent, the list colour and three palette colours [U].
  - At all done: a bigger burst of about 80 pieces [U].
  - The canvas is removed when the burst ends.

**States.**
- All done, versus empty from the start ("No To-Dos", TD-SET-05), versus search or filter showing nothing: three different states.
- Untick after all done: the state goes away.
- Reduced motion: no confetti; the all-done state shows without animation.

**Interactions.** None of its own. Taps pass through the confetti to the list.

**Words.** "All Done". The exact copy of the loved apps was not found [U].

**Data.** Reads `settings:self.celebrate` (missing → `allDone`) and the open to-dos in the current view (a list or a smart list). Writes nothing.

**Needs.** Page alone.

**Edge cases.**
- L6: no pop-ups over the list.
- Leave reason 5: delight is never removed by an update (L3).
- Leave reason 4: no achievements, streak pop-ups or upsells. Clear's "useless achievement popups" are a complaint.
- Checklist 17: empty and all-done read differently.

**Tests.**
- Given 2 open to-dos and `allDone`, when the first is ticked, then "All Done" is absent; when the second is ticked, then "All Done" is present, and no element has `role="dialog"`.
- Given `celebrate: off`, when the last is ticked, then no "All Done" and no canvas.
- Given `confetti`, when any to-do is ticked, then a canvas exists and is gone within 1 s.
- Given `confetti` and reduced motion, then no canvas is created and "All Done" still shows.
- Given a new list with no to-dos, then "All Done" is absent and the empty state shows.
- Given all done, when one is unticked, then "All Done" is removed.

**Evidence.** Tiimo confetti 4 loves (for example "The little confetti… fuels your dopamine!" 2026-06-08; "the confetti when completing tasks really helps" 2025-12-16), and its removal as a reason to leave: "What happened to the confetti???… gone from being genuinely useful to something utilitarian" 2★ 2026-10-23 (C). Todoist "Confetti is tiny fun… even your confetti is weak" 3★ 2025-03-28 (B). Google Tasks wish "or maybe confetti" (D). Clear achievement pop-ups, −4 (A). Screenshot: `tiimo_3_crop.jpg` (the "🎉 4" count).

---

### TD-DONE-05 Where done goes

**Tag:** core (leave reason 3 "items vanishing with no undo"; L2; checklist 52). **Variations:**
- `stay`: stays in place, struck. Superlist ("Completed tasks stay in their current position" [C]), Any.do, Tiimo, Tweek.
- `sink`: struck and moved to a done area at the bottom. Clear (black area), Google Tasks ("Completed (n)", collapsible, with a completion date line under each since Feb 2025), Microsoft To Do (Completed group), Todoist (opt-in).
- `hide`: hidden behind "Show Completed". Reminders (per list, R), TickTick.
- `logbook`: moved to a separate log. Things Logbook.
- Not offered: gone with no trace (Microsoft To Do complaint) and the graveyard with no way back (TickTick complaint).

**Default variation:** `stay`.

**What it is.** Where a ticked to-do sits after the tick, in its list and in Today.

**Anatomy.**
- `stay`: the struck row keeps its place (`order`).
- `sink`: a "Completed" heading [U] at the list's bottom, then the done rows, newest `completedAt` first [U]. In `look: heat`, the area is #000000 with grey struck text [C]. With more than 20 done rows the area starts collapsed, as "Completed (24)" [U] (Google Tasks).
- `hide`: done rows leave the list. A "Show Completed" row at the bottom reveals them in place, struck, and becomes "Hide Completed" (Reminders [R]). Whether they are shown is kept in page memory per list, and is lost on reload [U].
- `logbook`: done rows leave the list and appear in the Logbook (TD-DONE-07).
- Subtasks: a ticked subtask stays under its parent, struck, under every setting (P-new-9).

**States.**
- No done items: no Completed area.
- Many done items: the area is collapsed and its rows render only when it is opened (checklist 55).
- Done on an earlier day: in Today, a done to-do shows only on the day of its `completedAt` (P-new-28). In a list, `stay` and `sink` keep older done rows, with `sink` collapsed.

**Interactions.**
- After a tick, the row stays in place, struck, until 1.5 s after the last tick in that list [U]. Then every row due to move moves together. Rows never jump under the finger mid-run (MS To Do "accidentally checking the wrong one").
- Motion: `sink` slides 250 ms ease-in-out (FLIP) [U]; `hide` and `logbook` fade and collapse in 200 ms [U]; instant under reduced motion.
- Tap a struck checkbox: back to to do, back at its `order` place.
- Tap "Completed (n)" or "Show Completed" / "Hide Completed": toggles.

**Words.** "Completed", "Completed (3)", "Show Completed", "Hide Completed", "Logbook".

**Data.** Reads `settings:self.doneGoes` (missing → `stay`), `todo.done`, `completedAt` and `order`. `order` is never changed by a tick, so reopening returns the row to its place.

**Needs.** Page alone.

**Edge cases.**
- L2 and P-new-22: the ticked item stays visible long enough to see and undo. The toast of TD-DONE-06 outlasts the 1.5 s, so undo still works after the row has moved.
- P-new-28: old done items never come back into Today.
- Checklist 5: done items are never deleted.
- Checklist 11: every setting keeps a way back.
- Checklist 52: history.
- Checklist 55 and P-new-27: speed with many done.
- P-new-9: subtasks.

**Tests.**
- Given `stay`, when a to-do at index 2 is ticked, then after 3 s it is still at index 2, struck.
- Given `sink`, when ticked, then at 1.0 s it is at its index and at 2.0 s it is under "Completed".
- Given `sink`, when A is ticked and B 1 s later, then both are in place at 2.0 s after A and both are under "Completed" at 2.6 s after A.
- Given `hide`, when ticked, then after 2 s it is not in the list and "Show Completed" is; tapping it shows the row struck, and the label becomes "Hide Completed".
- Given `logbook`, when ticked, then after 2 s it is not in the list and it is in the Logbook.
- Given a to-do completed yesterday and `doneGoes: stay`, then Today does not show it.
- Given a done row is unticked, then it returns to the position its `order` gives.
- Given `sink` and a subtask ticked, then the subtask stays under its parent.

**Evidence.** Five models (`LOOK-ANALYSIS.md` 1.3; D 1.1). Quotes:
- "please keep the completed task with a strikethrough" Todoist 5★ 2025-04-01.
- "it keeps crossed out items means I can revisit the list again and again" Clear 5★ 2026-07-12.
- "I enjoy that the marked off as done tasks disappear, BUT, can be shown" Google Tasks (B).
- "disappears never to be found again. There is no undo." MS To Do 1★ 2025-12-15.
- "completed task graveyard" TickTick 4★ 2026-08-19.
- "They just accumulate in the Completed section" Google Tasks 2026-10-26 (B).
- "drags over 580 completed reminders… into 'today's' list" Reminders 1★ 2026-10-24.
- D pattern table: 2 asks to keep the strike; 3 complaints when done items vanish.

Screenshots: `clear_iphone_1.png`, `mstodo-1.png`, `anydo_2.jpg`, `superlist_3_crop.jpg`.

---

### TD-DONE-06 Undo with name

**Tag:** core (checklist 49; P-new-22; P-new-23; L2). **Variations:**
- Clear: shake to recover the last delete; one user says it is not enough [R].
- TickTick: reversible "as long as you have Show Completed selected" [R].
- Todoist and Google Tasks undo toasts: not verified [U].
- Microsoft To Do: no undo (complaint).

**Default variation:** no setting. After every tick, delete, move and edit, a toast names the item and offers "Undo".

**What it is.** A way back from the last change, which also says which item was just changed.

**Anatomy.**
- A floating toast above the bottom controls: `--ink` at 90% fill, radius 14 pt, height 48 pt, side margins 16 pt [U] (the daily-planner DP-FB-04 values).
- Left: the result, 15 pt white, one line; the item name gets a middle ellipsis (HIG [C]).
- Right: "Undo", 15 pt semibold `--accent`.
- The list gets bottom padding equal to the toast's height, so the toast never covers the last row (Todoist's toast covering tasks was a complaint, D).
- Shake is not used: shake detection needs device motion, which needs a permission prompt in WKWebView [U].

**States.**
- Hidden; shown for 6 s after a change [U]; replaced by the next change's toast.
- The page keeps the last 20 changes in memory [U]. The list's "•••" menu has "Undo" to go further back.
- The stack is lost on reload, because there is no localStorage or IndexedDB (`PRODUCT.md` section 5).
- Offline: works.

**Interactions.**
- Tap "Undo": restores every record the change touched and shows "Undone" for 2 s [U]. Undo of a tick sets `done: false` and `completedAt: null`, and deletes the repeat's next copy if it has not been changed since.
- Swipe the toast down to dismiss it.
- Single deletes never ask; undo covers them. A delete of more than one to-do (clear a list, delete a list with items) asks first (P-new-24).

**Words.**
- "Completed “Buy milk”", "Deleted “Buy milk”", "Moved “Buy milk”", "Updated “Buy milk”".
- "Undo", "Undone".
- Bulk delete alert: "Delete 12 To-Dos?", with "Delete" and "Cancel".

**Data.** Before each change, the page snapshots the old value, or the absence, of every key it will write (`todo:`, `list:`). Undo writes those values back and deletes keys that did not exist before. One person action is one step.

**Needs.** Page alone. The shell's op log is for operator recovery and offers no user rollback.

**Edge cases.**
- Checklist 49: undo a tick at once. A mis-tick from the widget or the Lock Screen is TD-OUT [U].
- Checklist 50: deletes go to the trash (TD-ITEM-06).
- P-new-22: names the item. P-new-23: undo covers edits too. P-new-24: warn on bulk delete only.
- L2: the ticked item stays visible.
- L6: the toast is the one overlay allowed, and blocks taps only on its own area.

**Tests.**
- Given "Buy milk" is ticked, then the toast text contains "Buy milk".
- Given that toast, when "Undo" is tapped, then `todo.done` is false and `completedAt` is null.
- Given a daily repeating to-do ticked, when "Undo" is tapped, then the key of the next copy no longer exists.
- Given a title edited from "Milk" to "Oat milk", when "Undo" is tapped, then the title is "Milk".
- Given one to-do deleted, then no alert appears and the toast reads "Deleted “…”".
- Given a list with 12 to-dos is cleared, then the alert "Delete 12 To-Dos?" appears first.
- Given two to-dos ticked, when "Undo" is used twice (toast, then the "•••" menu), then both are open again.
- Given a 300-character title is ticked, then the toast is one line and its text contains both the first and the last 10 characters of the title.

**Evidence.**
- "Tap something by mistake and it's difficult to know what was tapped" MS To Do 3★ 2026-07-04; "I don't know which one I clicked because just disappears" 3★ 2025-09-09.
- "no undo function or close without saving changes" 2★ 2025-07-19; "very easy to overwrite an entry with an accidental keystroke" Clear 2★ 2025-06-17.
- Bulk deletes with no warning: 3 quotes (Reminders, Todoist, Clear); HIG on warnings [C] (D Part 2, items 22–24).
- "No undo option. Deal breaker." Things 2026-04-15 (group-d P3).
- Clear shake "not enough" 1 (D table).

No screenshot.

---

### TD-DONE-07 Logbook and done today

**Tag:** core (checklist 52; P-new-6; P-new-18; P-new-21). **Variations:**
- Things Logbook: a separate log, in the home list; Quick Find searches it after "Continue Search" [C].
- Reminders: a Completed smart list (all time only); a user asks for "Show Completed Today… see the effort exerted" [R].
- Google Tasks: a completion date line on each done row [R], and a lifetime completed count, praised (older) [R].
- Todoist: completed repeats appear only in the Activity log, not the completed list [C]. This is the gap P-new-6 names.

**Default variation:** no setting. A "Logbook" smart list (TD-NAV-02) groups done to-dos by completion day, newest first, with "Today" and its count at the top. Search covers done items (TD-NAV-04).

**What it is.** The kept record of everything done, with today's done items first.

**Anatomy.**
- Title "Logbook" (TD-LOOK-04 list title size), with a subtitle count "1,449 Done" in `--ink-2` [U] (the Google Tasks lifetime count).
- Day headers, 15 pt semibold: "Today", "Yesterday", then "Monday, Oct 26", with that day's count on the right in `--ink-2` [U].
- Rows: TD-ROW rows in the done state; the meta line adds the list name and "Done 9:14 AM" [U] (Google Tasks completion line).
- The first 100 rows render, and more load on scroll [U] (P-new-27, checklist 55).

**States.**
- Empty: "No Completed To-Dos" [U copy].
- Years of history: lazy rendering, as above.
- A repeating to-do: each ticked copy is its own done `todo:` and is listed (P-new-6).

**Interactions.**
- Tap a row's checkbox: reopens that to-do (`done: false`, `completedAt: null`); it returns to its list at its `order` place, with an undo toast.
- Long press, or the row's detail card: "Add Again" creates a new open to-do with the same title, list, notes, emoji and colour, and no dates. The done one stays in the Logbook (P-new-21, the grocery pattern) [U].
- Delete from the Logbook goes through TD-ITEM-06 (trash).

**Words.** "Logbook", "Today", "Yesterday", "Monday, Oct 26", "Done 9:14 AM", "1,449 Done", "Add Again", "No Completed To-Dos".

**Data.**
- Reads `store.query('todo:')`, filtered to `done: true`, sorted by `completedAt` descending.
- Writes `done` and `completedAt` on reopen; a new `todo:` on "Add Again".
- `completedAt` is kept forever (`records.md` section 1).
- Who completed a to-do (checklist 52) has no field yet. There is one person now; the Claude Code link adds it later [U].

**Needs.** Page alone (`store.query`).

**Edge cases.**
- Checklist 52: a searchable history with completion dates.
- Checklist 5: done items are never deleted.
- Checklist 55, P-new-20 and P-new-27: stays fast with years of data.
- P-new-6: repeats appear in history.
- P-new-18: search finds done items. P-new-21: a done item can be revived.
- P-new-28: the Logbook never feeds Today.

**Tests.**
- Given 3 to-dos done today and 2 yesterday, then the groups read "Today" with 3, then "Yesterday" with 2, in that order.
- Given a daily repeat ticked on 3 days, then the Logbook lists 3 done copies.
- Given a done "Milk", when "Add Again" is tapped, then a new `todo:` titled "Milk" exists with `done: false` and `when: null`, and the original is still done.
- Given a done to-do, when its checkbox is tapped in the Logbook, then it is open and appears in its list.
- Given 5,000 done to-dos, when the Logbook opens, then at most 100 row elements exist until the person scrolls.
- Given a to-do done 3 years ago, then Today does not show it.
- Given search "milk" with one open and two done matches, then all three are found.

**Evidence.**
- Things Logbook [C].
- "I want an option to Show Completed Today… see the effort exerted." Reminders 2026-09-18 (A).
- Google Tasks: "it's satisfying that it tells you the total number of tasks you've ever completed" (older), and "They just accumulate… no time stamp relevance" 2026-10-26 (B).
- "the satisfaction of seeing my completed tasks" MS To Do 2026-09-12 (B).
- Search: "If I search the word 'Milk' it might return 2 results when I easily had 25" Reminders 2★ 2025-12-17. Re-adding: "nothing is suggested… I have to go to the Completed list and try to search" 3★ 2025-12-12 (D).

Screenshot: `things_0.jpg` (Logbook in the Things home list).
