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
notice. **Open founder question:** should a reminder due earlier *today* and not done still fire
once after sign-in? Agent's recommendation: no.

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

Blocked for the widget too: the change is one line in `RemindersWidgetLayout.isShownBefore`
(`shell/Shared/RemindersWidgetShared.swift`: return `!first.allDay`), but the existing test
`testAllDayComesFirstAsInTheSidekick` asserts the old order, and test-guardian changes it only once
the decision is dated in `docs/PRODUCT.md` (lead session). Suggested line for the Reminders widget
bullet: "Today's order: reminders with a time first, earliest first, then untimed ones (founder,
2026-10-11); the Sidekick's Today follows." Then: test-guardian renames the test to
`testUntimedComesAfterTimedReminders` with order `["reply", "push", "call", "gym", "insurance"]`,
and the code line flips.

## 6. Folder widget: tiles float in the middle

File: `shell/MidasWidgets/FolderWidget.swift`.

The founder saw the Sidekick icons float in the middle of the Folder widget instead of being
clearly spaced over the grid (e.g. four tiles). Same family of bug as the Reminders widget rows
centring in their column (fixed on widget-reminders by pinning rows to the top).
