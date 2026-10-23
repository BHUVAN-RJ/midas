# Daily planner completeness checklist

The 56 items of midas-intel `docs/research/daily-planner/ANALYSIS.md` section 6 (from
`category-and-completeness.md` 2.7), with the research's numbering and meaning unchanged. Each item
names the patterns (block files) and records (`records.md`) that satisfy it, its Needs bucket, and
the test that proves it. Written 2026-10-12. Docs only; nothing here is approved to build.

**Needs buckets** (ANALYSIS.md 7.3, checked here against the shell code):
- **Page alone:** records plus the Sidekick page.
- **Shell has it:** the notification engine, the local store and sync, sign-in and permissions, or
  platform rules, as built today.
- **Shell lacks it:** a native piece not built; the brief is named.

Where this file's bucket differs from ANALYSIS.md 7.3, the row says why (items 28, 29, 32).

**Tests** are written as given / when / then. Each can fail for the reason the item exists: it
checks the behaviour, not that some value came back. Page tests run in a browser test harness
over a fake `store` with a fixed clock and zone, unless the row says "phone" (needs the iPhone or
the shell's test suite).

Counts: page alone 33, shell has it 15, shell lacks it 8. Same split as ANALYSIS.md 7.3; three
rows carry a note.

## Day view

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 1 | The day opens on today with a visible "now" marker in the right place. | DP-TIME-01, DP-NAV-08 | `settings:self.dayStartsAt` | Page alone | Given the clock at 14:20 on 12 Oct, when the page opens, then the selected day is 12 Oct and the now marker's top equals the timeline's 14:20 position (±1 pt). Given `dayStartsAt` 03:00 and the clock at 01:30 on 13 Oct, then the selected day is 12 Oct. |
| 2 | The item in progress shows how much of it is left. | DP-TIME-02, DP-TIME-03 | task `at`, `duration` | Page alone | Given a task 14:00 to 15:00 and the clock at 14:20, then its row reads "40 min left" and its fill is one third; at 15:00 the label is gone. |
| 3 | Free time between items is visible as free time. | DP-TIME-04 | task `at`, `duration` | Page alone | Given tasks ending 10:00 and starting 10:30, then a gap row "30 min free" sits between them; given back-to-back tasks, then no gap row. |
| 4 | Calendar events and tasks appear on the same timeline. | DP-ITEM-05, DP-DAY-02, DP-DAY-05 | `reminder:` (task); events from `calendar.read` results | Shell lacks it: `shell/calendar-access.md` | Phone. Given full calendar access and an event 11:00 to 12:00 in Calendar, when the page opens on that day, then the event shows at 11:00 styled as an event, beside the page's own tasks. |
| 5 | Two items at overlapping times are both fully readable, side by side or nested. | DP-TIME-08 | `reminder:` (task) | Page alone | Given tasks 9:00 to 10:00 and 9:30 to 10:30, then both titles are fully visible, no element covers another's title, and each block's height matches its duration. |
| 6 | The app never refuses to save an overlap. | DP-TIME-08 | `reminder:` (task) | Page alone | Given a task 9:00 to 10:00, when a second is saved at 9:30, then `store.set` is called and both exist after reload. |
| 7 | All-day items show apart from timed ones and can be turned into timed tasks. | DP-DAY-06 | task `allDay`, `at` | Page alone | Given an all-day task, then it is in the all-day row, not the timeline; when "Adjust Time" sets 15:00, then it has `allDay: false`, `at` at 15:00 that day (read in `timeZone`) and shows on the timeline. |
| 8 | Completed items look visibly done, distinct from those still to do. | DP-ITEM-04, DP-FB-01 | task `done` | Page alone | Given one done and one open task, then their completion controls differ (filled vs ring) and the done title has a different style; toggling back restores the open style. |

## Adding and editing

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 9 | A new task's default time is near now or the next free slot, never midnight. | DP-ADD-01, DP-ADD-02 | `settings:self.defaultDuration` | Page alone | Given the clock at 14:07 and a task 14:00 to 15:00, when "+" is tapped, then the proposed start is 15:00; given an empty day at 14:07, then 14:15; never 00:00 unless now is within 15 min of midnight. |
| 10 | Changing the start time keeps the duration, and the end time can be changed on its own. | DP-ADD-02 | task `at`, `duration` | Page alone | Given 9:00, 45 min, when start becomes 10:00, then duration is still 45 and end 10:45; when end alone becomes 11:30, then start stays 10:00 and duration is 90. |
| 11 | The add flow never advances while the person is still typing. | DP-ADD-01 | none | Page alone | Given the title field focused, when keys are typed with 300 ms between them for 5 s, then the step does not change; it changes only on the next-step button or Return. |
| 12 | A half-typed task is kept if the person leaves the app or picks an icon first. | DP-ADD-01 | task `draft`, no `at` | Page alone | Given "Call d" typed, when `visibilitychange` fires hidden, then a `reminder:` task with `draft: true`, no `at`, title "Call d" exists; when the icon picker opens and closes, then the field still reads "Call d". |
| 13 | A task can be saved with no time and kept in an inbox until placed. | DP-ADD-05 | task without `at` | Page alone | Given a task saved with no day, then its `reminder:` record has no `at` (it notifies nobody), and after reload is in the inbox; when dragged to 16:00, then it has `at` at 16:00 that day and `timeZone`. |
| 14 | An inbox task can carry a deadline without a time slot. | DP-ADD-05 | task `deadline` | Page alone | Given an inbox task with `deadline` 2026-11-01, then it stays in the inbox with the deadline shown, and its record has no `at`, so it notifies nobody. |
| 15 | Dragging an item to a new time keeps it; a failed drop never deletes it. | DP-RES-01, DP-ADD-06 | `reminder:` (task) | Page alone | Given a task at 9:00, when dropped on 11:00, then `at` is 11:00 after reload; when a drop ends outside any target or `store.set` rejects, then the task is still at 9:00 and no `store.delete` was called. |
| 16 | 12-hour and 24-hour display both work and follow the person's setting. | DP-SET-07, DP-ITEM-03 | `settings:self.clock` | Page alone (see note) | Given `clock: "12"`, then a 13:00 task reads "1:00 PM"; given `"24"`, "13:00"; given `"system"`, the format of `Intl.DateTimeFormat` with `hour: 'numeric'`. Note: whether WKWebView's `Intl` follows the iOS 24-hour switch is [U]; a phone check records it. |
| 17 | The week starts on the person's chosen day. | DP-SET-07, DP-NAV-01 | `settings:self.weekStart` | Page alone | Given `weekStart: 0`, then the week strip starts on Sunday; given `1`, Monday; on a Sunday with `weekStart: 1`, the week shown contains that Sunday as its last day and tomorrow is in the next week, reachable in one swipe. |

## When the day changes

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 18 | When an item runs over, everything after it can be shifted in one action. | DP-RES-04 | task `at` | Page alone | Given tasks at 10:00, 11:00, 12:00 and the clock at 10:20 with the first running over, when "Shift" by 20 min is chosen, then the later two have `at` 11:20 and 12:20 after reload, so their notifications move with them. |
| 19 | A shift moves only flexible items; fixed events stay put. | DP-RES-04, DP-RES-05 | task `fixed` | Page alone | Given the 11:00 task has `fixed: true`, when shifting by 20 min, then it stays at 11:00 and the 12:00 task moves; calendar events never move. |
| 20 | Finishing early can end the item now and free the time. | DP-FOC-02, DP-TIME-04 | task `duration`, `done`, `spentMin` | Page alone | Given a task 10:00 to 11:00 and the clock at 10:40, when "Done" is chosen in focus, then `duration` is 40, `done: true` with `completedAt`, and a "20 min free" gap shows. |
| 21 | Extending a running timer updates the plan and the alerts after it, so no wrong alerts fire. | DP-FOC-02, DP-OUT-05 | task `duration` | Shell has it (rewrite moves the notification; note) | Given a task 10:00 to 10:30, when extended by 10 min, then `duration` is 40 and the next task's `at` is unchanged unless shifted; shell test: a rewritten `at` cancels the old identifier and books the new one (`ReminderPlannerTests`, edits). Note: an end alert, which would move with `duration`, is not mapped to the current format (records.md 12). |
| 22 | Unfinished items can move to tomorrow in one action for all. | DP-RES-02, DP-RES-03 | task `at`, `replanCount` | Page alone | Given 3 open and 1 done task today, when "Move to Tomorrow" is chosen, then the 3 open ones have `at` on tomorrow (same time) and `replanCount` +1, the done one is unchanged. |
| 23 | A carried-over item, once done, records the day it was actually done. | DP-RES-03 | task `doneDay`, exception `doneDay` | Page alone | Given a task with `at` on 10 Oct carried to 12 Oct, when ticked on 12 Oct, then `doneDay` is "2026-10-12" and the history for 12 Oct lists it. |
| 24 | Carrying over never silently deletes the backlog. | DP-RES-03 | `reminder:` (task) | Page alone | Given 40 overdue tasks, when roll-over runs, then `store.query('reminder:')` still returns all 40 and no `store.delete` was called. |

## Time and calendar edge cases

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 25 | A task that crosses midnight saves with the right end and shows on its start day. | DP-DAY-01, DP-ITEM-03 | task `at`, `duration` | Page alone | Given start 23:00 and end 01:00, when saved, then `duration` is 120 and `at` is on the start day, and the row reads "11:00 PM–1:00 AM (+1)". |
| 26 | A task that crosses midnight is also visible on the next day. | DP-DAY-01, DP-OUT-01 | `reminder:` (task) | Page alone | Given that task, when the next day opens, then it shows once, from 00:00 to 01:00, marked as started the day before, and is the same record (no second `reminder:` task). |
| 27 | Night owls can set when "today" ends (e.g. 3 AM). | DP-SET-07 | `settings:self.dayStartsAt` | Page alone | Given `dayStartsAt` "03:00" and the clock 02:00 on 13 Oct, then "today" is 12 Oct, a task at 01:30 on 13 Oct shows in it, and roll-over has not run. |
| 28 | A "7 AM" task stays at 7 AM after travel unless pinned to a zone (floating by default). | DP-SET-07, DP-OUT-05 | task `at`, `timeZone`, no `zone` | Shell lacks it: `shell/local-time-alerts.md` (note) | Display: given a task at 07:00 with no `zone`, when the page's zone changes from Los Angeles to New York, then it shows at 07:00. Alert, phone: the one-time alert fires at 07:00 New York time. Note: repeats already float in the engine; a one-time task can float today as a single-occurrence repeat (`shell/local-time-alerts.md`), with limits. |
| 29 | An item pinned to a time zone shows at the correct local time after travel. | DP-SET-07 | task `zone`, `timeZone` | Shell has it, one-time only (note) | Given a task at 09:00 with `zone` and `timeZone` "America/New_York", when the page's zone is Los Angeles, then it shows at 06:00 and its `at` is 13:00 UTC. Note: a pinned repeat cannot be pinned by the engine and is not mapped to the current format (records.md 3.8 and 12; `shell/local-time-alerts.md` question 3). |
| 30 | No item moves or disappears at a daylight-saving change. | DP-OUT-05 | `reminder:` (task); `reminder:` repeats | Shell has it | Given a daily 09:00 task, when days before and after 8 Mar 2026 (US spring forward) are shown, then it is at 09:00 on each; shell test: the repeat's occurrences are 09:00 local on both sides (`ReminderScheduleTests`, DST in LA and NY). |
| 31 | A task at a time that DST skips still appears, at the next valid time. | DP-OUT-05 | `reminder:` (task); `reminder:` | Shell has it | Given a task at 02:30 on 8 Mar 2026 in Los Angeles, then the page shows it (at 03:00) and its alert fires at 03:00; shell test: the skipped time moves to the first valid moment. |
| 32 | Editing one occurrence of a repeat changes only that one. | DP-ADD-01 | `exception:<taskId>:<date>` | Shell lacks it: `shell/repeat-exceptions.md` (note) | Given a daily task, when the 14 Oct occurrence is moved to 10:00, then only `exception:<id>:2026-10-14` is written, 13 and 15 Oct still show the series time, and no alert fires at the old time on 14 Oct. Note: the display is page alone; the alert part is not mapped to the current format (records.md 3.6 and 12) and needs the brief. |
| 33 | "This and future" changes leave past occurrences as they were. | DP-ADD-01 | task `repeat.until`, new `reminder:` task | Shell has it (`until` plus a new record) | Given a daily task since 1 Oct, when "This and Future" on 14 Oct sets 08:00, then the old task has `repeat.until` at the end of 13 Oct, a new task starts 14 Oct at 08:00, and 10 Oct still shows the old time. |
| 34 | A change to "all" occurrences can be undone. | DP-FB-04 | `reminder:` task (previous value in memory) | Page alone | Given a daily task titled "Run", when "All" renames it "Walk" and Undo is tapped, then the record equals the value before the edit, field for field. |
| 35 | Repeating tasks are available at the basic level. | DP-ADD-01 | task `repeat` | Shell has it (repeats at no cost) | Given a new Sidekick with no settings, when a task is set to repeat weekly, then it saves and its `reminder:` record has `repeat`; no setting, flag or lock hides the Repeat control. |

## Calendar access

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 36 | The app works, with its own items, when calendar access is none or denied. | DP-ITEM-05, DP-SET-06 | `reminder:` (task) | Page alone | Given `calendar.status` answers `denied` (or no calendar piece exists), when the page opens, then tasks show, can be added and edited, and no error screen appears. |
| 37 | The app states clearly what write-only access can do, and does not claim "no access". | DP-SET-06 | `request:` (`calendar.status`) | Shell lacks it: `shell/calendar-access.md` | Given access `writeOnly`, then settings shows a write-only state and the timeline shows no "No events" or "No access" text; shell test: `calendar.read` ends `denied`, not `done` with zero events. |
| 38 | Calendar events shown in the planner match the calendar within minutes. | DP-ITEM-05 | `calendar.read` results | Shell lacks it: `shell/calendar-access.md` | Phone. Given an event moved in Calendar at T, when the planner is opened at T + 1 min, then it shows the new time. |
| 39 | If two-way sync is offered, an edit in the planner appears in the calendar and the reverse. | DP-ITEM-05, DP-RES-01 | `calendar.write` request | Shell lacks it: `shell/calendar-access.md` | Phone. Given full access, when an event is dragged to 15:00 in the planner, then Calendar shows it at 15:00; when moved in Calendar to 16:00, the planner shows 16:00 on next open. |
| 40 | Calendar sync is per account, not per device. | DP-SET-06 | all records | Shell has it (records sync per account) | Given a task written on phone A, when the same account signs in on phone B (or reinstalls), then the task is there (PRODUCT.md 6, reinstall test 2026-10-11). Calendar events themselves come from each device's EventKit. |

## Alerts and glanceable surfaces

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 41 | Alerts fire at start (and before or at end, if set) with the app closed. | DP-OUT-05, DP-FOC-05 | task `at`, `alerts` | Shell has it (note) | Page: given a task 9:30 to 11:00 with start-5 and start alerts, then its record has `at` 9:30 and `alerts` `[{ id: "s5", kind: "before", minutes: 5 }]`. Phone: with Midas in the background, both fire, at 9:25 and 9:30 (the D8 phone check is still open, NOTIFICATIONS.md 8). Note: the end alert is not mapped to the current format (records.md 12). |
| 42 | Alerts beyond the iOS 64-pending limit are still delivered. | DP-OUT-05 | `reminder:` | Shell has it, with the known missed-batch limit | Shell test: 100 one-time reminders book 48, and after the first delivers the 49th is booked (`ReminderPlannerTests`, `NotificationEngineTests` top-up). Page: no planner logic caps alerts to fit 64. |
| 43 | Alerts for deleted, moved or inactive items never fire. | DP-OUT-05 | task `at`, `alerts`, `done` | Shell has it (delete cancels, edit moves) | Given a task with alerts, when it is deleted, then `store.get('reminder:<id>')` returns `null`; when moved to the inbox, then its record has no `at` and no `alerts`; when marked done, then it has `done: true`; when moved, then only `at` changed. Shell tests: delete cancels and edit moves (`ReminderPlannerTests`, edits and deletes); an undated item is not a notification (`ReminderRecordTests`). |
| 44 | The widget shows the current and next item and stays correct through the day. | DP-OUT-01, DP-OUT-02 | `reminder:` (task) | Shell lacks it: `shell/planner-widget.md` | Shell test: timeline entries for tasks 9:00 to 10:00 and 10:30 to 11:00 give now/next at 9:30, "Free" at 10:00, now at 10:30, "All done" at 11:00, with Midas not run. |
| 45 | The Lock Screen / Dynamic Island current-task view appears when expected and goes away after. | DP-OUT-03 | `activity:` or `request:` (brief) | Shell lacks it: `shell/live-activity.md` | Phone. Given focus started on a 10:00 to 10:30 task, then a Live Activity shows within 2 s; at 10:30 (with Midas running) it ends; after Done at 10:20 it is gone. |

## Week, month, search

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 46 | Week and month views exist on the phone. | DP-NAV-03, DP-NAV-04 | `reminder:` (task) | Page alone | Given tasks on 3 days of a week, when the week view opens at 393 pt wide, then all 3 days show their tasks; the month view shows a mark on those 3 dates. |
| 47 | The person can search past and future items. | none in catalogue (search) | `reminder:` (task) | Page alone | Given tasks titled "Dentist" on 1 Sep and 1 Dec, when "dent" is searched on 12 Oct, then both are listed with their dates; done tasks are included. |

## States

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 48 | First open lets the person plan today without an account on another device. | DP-SET-01 | `settings:self.onboarded` | Shell has it (name plus passkey on the phone) | Given a fresh account on one iPhone, when the planner opens, then a task can be added to today without visiting any other device or web page. |
| 49 | First open does not demand unrelated permissions. | DP-SET-01 | none | Shell has it (shell asks when first needed) | Given a fresh install, when the planner opens and nothing with an alert is saved, then no permission prompt appears; the notification prompt appears only on the first save that writes a `reminder:`. |
| 50 | An empty day says it is empty and offers to add, distinct from loading or failed. | DP-SET-03 | `reminder:` (task) | Page alone | Given a day with no tasks, then the empty headline and one add button show; while `store.query` is pending, a loading state shows instead; when it rejects, an error title with "Try Again" shows; the three never show together. |
| 51 | Viewing and adding items works offline and syncs later. | all | all records | Shell has it (local store with outbox) | Phone. Given airplane mode, when a task is added and Midas is reopened, then it is there; when the network returns, then the server holds it (`RecordSync` push). |
| 52 | An overloaded day is shown as over capacity. | DP-TIME-06 | task `energy`, `duration`; `settings:self.energyLimit` | Page alone | Given `energyLimit` 10 and tasks worth 12 points (or more than the waking hours of planned time), then the over-capacity signal shows; removing one task under the limit hides it. |

## Trust and recovery

| # | Behaviour | Patterns | Records | Needs | Test |
|---|---|---|---|---|---|
| 53 | No item, page or history is lost by an update, a sign-out, a DST change or an ended subscription. | all | all records | Shell has it (append-only log, versioned bundles, restore after reinstall) | Given tasks saved by bundle version N, when version N+1 of the page opens, then every task reads and renders (every record passes its type in the manifest `types`, and unknown fields are kept on write-back); phone: reinstall restores them (PRODUCT.md 6). |
| 54 | Every delete and move can be undone. | DP-FB-04, DP-RES-01 | previous values in memory | Page alone | Given a task deleted, when Undo is tapped, then the task's `reminder:` record and its `exception:` records are back with equal values; same for a move. |
| 55 | An update never removes a feature people rely on without a way back. | all | none | Shell has it (a Sidekick changes only when its owner asks) | Given bundle version N in use, when no change is requested by the owner, then the current version stays N; an older version stays launchable (PRODUCT.md 5). |
| 56 | Any trial states its length and charge date, and charges no earlier. | none (pricing) | none | Page alone | Given the planner page, then it contains no paywall, trial or price text (Sidekicks sell nothing; ANALYSIS.md 7.3). |
