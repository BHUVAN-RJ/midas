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

## 2. Handoff from `agent/care-repeat` to the lead session (2026-10-12)

Branch `agent/care-repeat`, all committed, full suite passing (test guard 28, backend 156,
shell 307, midas-intel 31). Commits: `ad42cbf` (Every 2/3/4 Hours), `b99fb59` (its tests),
`ebdd734` (icon). Not merged; the lead merges.

Founder decisions in that session, to copy into `docs/PRODUCT.md` (lead only; a worktree may not
edit it) and the midas-intel design doc:
- Icon: mockup "2 · Size by urgency" (`docs/mockups/care-reminders-icon-2026-10-12.html`). Drawn
  by the shell (`shell/Shared/SidekickIcon.swift`, `SidekickArtwork.careUrgencyTiles`), since a
  manifest holds only an SF Symbol and a colour. The "Open: icon" line goes; display name stays open.
- Deployed to staging `20261013T052959528Z-596a1d4c` and live `20261013T053859761Z-596a1d4c`
  (founder asked for both; the Change 2 brief had said "don't deploy").
- Assigned on live to Amogh (`assign-sidekick.mjs "amogh" care-reminders --env live`).

Still to do:
- Merge `agent/care-repeat`, then a TestFlight build with a higher `CURRENT_PROJECT_VERSION`
  (now 2). Until then live phones, Amogh's included, show the manifest's pill symbol on sage.

## 3. Found during Change 2, outside its brief (2026-10-12)

- The all-suites script keeps only the last 3 lines of xcodebuild output, so a failing shell
  test's name is hidden ("** TEST FAILED **" only). Found it by reading the newest `.xcresult`
  with `xcrun xcresulttool get test-results tests`. A guarded file; founder decides.
- Done in the page on a repeat (daily or hourly) marks the occurrence done but does not stop that
  occurrence's notification if it has not fired yet. Existing behaviour, unchanged by Change 2.
- Sidekick versions: no rollback script (going back = pointing `current.json` at an old version
  by hand), no command listing past versions, no git commit stored with a version. Told to the
  founder as facts; no decision.
