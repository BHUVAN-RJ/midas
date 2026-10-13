# Open concerns: care-reminders Sidekick (founder, 2026-10-12)

Raised by the founder while reviewing the care-reminders build (`agent/care-reminders`). Parked
on purpose ("leave it alone, we'll worry about clearing at a later time"). Mark an item done
here (with the commit) when it ships.

## 1. A later early alert should replace the earlier one, not pile up

Files: `shell/Midas/NotificationEngine.swift`, `ReminderPlanner.swift`, `NotificationBooking.swift`,
`ReminderRecord.swift` (a new record field), and `sidekicks/care-reminders/index.html`.

Now: an appointment with 3 list rules writes 4 `reminder:` records (`reminder:<id>` for its own
time, `reminder:<id>~<ruleId>` per early alert). Each is booked separately, so one event holds
4 of the engine's 48 slots, and each delivered alert stays in Notification Center: the day-before
alert is still there when the morning-of and 1 h alerts arrive. The engine never removes
delivered notifications (`NotificationBooking.cancel` removes pending ones only), and each
booking's identifier carries its own time, so nothing replaces anything.

Wanted (founder, 2026-10-12): the second alert takes the first one's place; the first is cleared.
Alerts must not hog slots.

Facts that bound it:
- iOS keeps a delivered local notification until the app removes it. Midas can remove it only
  while it runs (open, or background refresh: at most hourly, when iOS decides). Nothing clears
  it at the moment the next alert fires.
- Two pending requests cannot share an identifier, so "same identifier replaces it" works for
  one booked alert at a time only.

Options laid out to the founder (no decision yet):
- **A, page only:** one rolling `reminder:<id>~next` record per event (1 slot plus its own time),
  rewritten to the next alert when the page opens. If the page is not opened between alerts, the
  later ones do not fire. The delivered first alert stays.
- **B, shell:** the engine books only the next alert of an event and, on every run, clears that
  event's earlier delivered alerts and books the following one. 1 slot plus its own time; a later
  alert can still be missed if Midas does not run in time, much less likely than A. Needs a
  TestFlight build.
- **C, shell:** keep every alert booked as now (reliable), and clear an event's earlier delivered
  alerts whenever Midas runs. Fixes the pile-up, not the slot use.

In all three the event's own notification at its own time fires.
