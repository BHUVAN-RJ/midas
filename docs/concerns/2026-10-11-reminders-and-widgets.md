# Open concerns: Reminders and widgets (founder, 2026-10-11)

Raised by the founder while testing the Reminders widget. Each item is outside the
`widget-reminders` worktree's files, so it waits for an agent with a brief that covers it. When the
founder asks "is there anything left?", these are on the list. Mark an item done here (with the
commit) when it ships.

## 1. Untimed reminders: nudges at 11 AM and 9 PM, no 9 AM alert

Files: `shell/Midas/ReminderPlanner.swift`, `ReminderRecord.swift`, `NotificationEngine.swift`
(and the Sidekick only if the record needs a new field; it already writes `allDay: true`).

Now: a reminder added to Today (or tomorrow, or Next 7 Days) without a time is stored with
`allDay: true` and `at` = 9:00 AM local, and the engine fires it at 9:00 AM.

Wanted (founder, 2026-10-11):
- A dated reminder with no time (`allDay: true`), added to Today, tomorrow or Next 7 Days, gets no
  alert at its `at`. On its day it is nudged at **11:00 AM** and again at **9:00 PM**.
- Added after 11 AM on its day: only the 9 PM nudge.
- Done before 9 PM: no 9 PM nudge (done before 11 AM: none at all).
- One notification per reminder, not one combined; iOS decides how they stack on the Lock Screen.
- A reminder in a list with no date (e.g. Groceries, a `task:` record) gets no nudge at all.

## 2. Old reminders refire after signing in on a fresh install

File: `shell/Midas/ReminderPlanner.swift` (`plan`, the `handledThrough` default) and
`NotificationEngine.swift`.

Cause (found 2026-10-11): `plan` treats a one-time reminder it has never seen as
`handledThrough = .distantPast`, so a past, not-done reminder gets a "missed" notice that fires at
once. On a fresh install the ledger is empty, so every past-due reminder restored from the server
fires together.

Proposed fix: reminders that arrive with the first restore after sign-in count as already seen
(ledger mark = now), so nothing past fires; only reminders created afterwards can produce a missed
notice. Founder's answer (2026-10-12): a reminder due earlier today and not done does **not**
fire after sign-in. Nothing past fires on restore.

## 3. Ticking a repeat does not cancel today's notification

Files: `ReminderPlanner.swift`, `ReminderRecord.swift`.

The Sidekick and the Reminders widget record a repeat's occurrence as done with `lastDoneAt` and
`doneThrough`, but the planner reads neither, so today's occurrence still notifies after a tick.
One-time reminders (`done: true`) are cancelled correctly.

## 4. Lists: rename and delete in the Reminders Sidekick

File: `sidekicks/reminders/index.html`.

- Rename a list.
- Delete a list. Empty: delete after a confirm. With reminders inside: a clear warning with two
  choices, "Move reminders to All" (they become reminders with no list) or "Delete reminders too",
  then the list is deleted.

## 5. Today list order in the Sidekick: timed first, untimed after

File: `sidekicks/reminders/index.html` (`compareByMoment` puts all-day first today).

Wanted: in Today, reminders with a time come first, earliest first, then the untimed ones, in both
the Sidekick and the Reminders widget.

Widget: done on `agent/widget-reminders` (2026-10-12), after the decision was dated in
`docs/PRODUCT.md`. The Sidekick's Today is still open.

## 6. Folder widget: tiles float in the middle

File: `shell/MidasWidgets/FolderWidget.swift`.

The founder saw the Sidekick icons float in the middle of the Folder widget instead of being
clearly spaced over the grid (e.g. four tiles). Same family of bug as the Reminders widget rows
centring in their column (fixed on widget-reminders by pinning rows to the top).

## 7. Shell tests crash with "signal kill" when sessions share the simulator

Found 2026-10-12 by the lead. Two runs of the full suite on main failed with one shell test
"crashed with signal kill": the record sync test for a write triggering a sync once, the Sidekick
web view test for fetches to the platform origin once. Each re-run passed. Other sessions were
running tests on the same iOS 27 simulator at the time (a care-reminders run was reported hung
there). A failure that only re-running fixes can hide a real one. Next: the lead or a test agent
decides whether each session gets its own simulator.

## 8. Does the Reminders Sidekick draw a cross when a reminder is ticked?

Founder, 2026-10-12: ticking looks like Apple's Reminders (circle fills, title greys), no cross.
The widget follows this. The widget agent was asked to check `sidekicks/reminders/index.html`
too; the result was not reported. Next: whoever works on the Reminders Sidekick checks it.

## 9. Choosing a time while adding a reminder fired a notification

Founder, 2026-10-12, TestFlight 0.1.0 (2) on the iPhone: while adding a reminder and turning the
native time wheel, a notification fired at once. Rule (founder): a reminder never fires before
its time is set and saved, and never for a time already past when it was saved.

Files: `sidekicks/reminders/index.html` (`applyAccessoryChange`, `finishEditing`,
`commitEditedItem`, the tap handler near "Any tap closes a row", `handleVisibilityChange`) and
`shell/Midas/ReminderPlanner.swift` (`plan`, `missedBooking`).

Likely cause (read from the code, not reproduced):
1. Each stop of the wheel sets the row's time (`acc-time` change). If today's date is empty, the
   date becomes today.
2. The row is saved, with whatever time the wheel shows, as soon as editing ends: a tap anywhere
   outside the keyboard bar (dismissing the wheel can be such a tap), the page going to the
   background, or opening details. So a half-chosen time, such as one earlier today, can be saved.
3. The shell then plans it. A one-time reminder it has never seen counts as handled since
   `.distantPast`, so a time at or before now becomes a "missed" booking with
   `trigger: .immediately`. It fires at once. Same root as item 2.

Fix to discuss: the planner never sends a missed notice for a reminder whose time was already
past when it was first saved (only for times that pass while it exists), and the page saves a
time only when the wheel closes, not on each turn. Needs the founder's go before building.
