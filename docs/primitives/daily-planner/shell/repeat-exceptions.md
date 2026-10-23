# Brief: per-occurrence exceptions in `reminder:` repeats, 2026-10-12

**Status:** Draft, not approved to build. The founder decides whether and when.

Labels: [C] confirmed on a primary source or read in this repo's code; [R] reported; [U] not
verified.

## How you work

The four steps of `docs/briefs/notification-engine.md`: say the idea back; ask; propose a plan
and wait for "approved"; then build with tests (`CLAUDE.md`).

## Goal

When the person edits, moves, skips or completes one occurrence of a repeating planner task, only
that occurrence's alerts change (checklist 32), with no extra cost in notification slots. Pattern
DP-OUT-05, DP-ADD-01, DP-RES-01. Leave reason 11: recurring edits, 60 negative hits.

## Finding first: what is page-only and what is not

- **What the planner shows** for checklist 32, 33 and 34 is page-only: `exception:<taskId>:<date>`
  records, "this and future" as a new task with `until` on the old one, and in-page undo
  (`../records.md` section 5).
- **What the alerts do** is the shell part. The `reminder:` repeat has `every`, `interval`,
  `weekdays`, `until` and nothing else (`ReminderRecord.swift`, `RepeatRule`).
- **The page cannot keep an excepted occurrence from alerting** with the current format
  (`../records.md` 3.6 and 12). The task is itself the `reminder:` record, and splitting the
  series into extra `reminder:` records (segments, a one-time record for a moved occurrence)
  would show each as an extra task. A skipped or moved occurrence notifies at the series time.

So this brief is about making exceptions possible for the notifications.

## A related gap: done on one occurrence

- Done on a repeat writes `lastDoneAt` and `doneThrough` (the occurrence) on the task's record
  (`RecordWriter.swift`). The early alerts move to the next occurrence after `doneThrough`
  (`ReminderExpansion.targetOccurrence`), but `ReminderPlanner` does not read `doneThrough`, so
  ticking a repeat's occurrence does not cancel that occurrence's own notification (concern 3,
  `docs/concerns/2026-10-11-reminders-and-widgets.md`). `TodayReminderPlanner.swift` (the widget)
  reads both.
- For a planner, a daily 10:00 task ticked at 9:10 still notifies at 10:00 that day.
- A fix for concern 3 and an `except` field would touch the same code (`ReminderPlanner.plan`,
  `upcomingBookings`).

## What is already decided (with sources)

- One record is one notification or one repeating series; edit moves it, delete cancels it
  (NOTIFICATIONS.md 1, 6.4).
- Interval-1 repeats with no `until` become iOS repeating notifications, one slot per trigger;
  they keep firing if Midas never runs again (NOTIFICATIONS.md 6.3).
- 48 booked plus 16 reserved, shared by every Sidekick (NOTIFICATIONS.md 6.2).
- "This and future" in EventKit: `futureEvents`; there is no "all" span [C, Apple docs via
  category-and-completeness.md 2.6]. The engine's equivalent is `until` on the old record and a
  new record (ANALYSIS.md 7.3, item 33).

## Platform facts

- An iOS repeating calendar trigger cannot skip one occurrence. To skip one, the app removes the
  repeating request and books occurrences one by one until the skipped date passes, or books
  around it [C, `UNCalendarNotificationTrigger` has no exception list].
- A pending request is replaced by booking the same identifier; a delivered notification stays
  until the app removes it (concern 1, `docs/concerns/2026-10-12-care-reminders.md`).
- Edits to an EventKit repeat apply to `thisEvent` or `futureEvents` only [C].

## Shapes to discuss

1. **`repeat.except`:** a list of occurrence days, `["2026-10-14", ...]`, read as wall-clock days
   in `timeZone`. The planner drops those occurrences. A repeat with an `except` day inside the
   booking horizon is booked occurrence by occurrence until that day passes, then returns to an
   iOS repeating trigger. A moved occurrence would need its new time in the record too (for
   example `repeat.moved`, `{ "2026-10-14": instant }`), since a separate record is a task.
2. **`doneThrough` read by the planner:** occurrences at or before it are not booked. Covers
   "done today" without a split, and concern 3 for the Reminders Sidekick too.
3. **Both.**

Each is an optional field added to the `reminder:` record (add only, `runner/agents/reminders.md`
rules): records without the field behave as today.

## Open questions for the founder

1. Does the engine take an `except` list, or do planners live with a skipped or moved occurrence
   notifying at the series time (records.md 3.6, 12).
2. Should the planner honour `doneThrough` / `lastDoneAt` (concern 3) as part of the same change.
3. Limit on `except` length per record (each entry about 13 bytes; 64 KB is not the constraint).

## App Review

- **4.7.2** [C] No native API reaches the page; the shell reads one more record field.
- **4.7.3** [C] No new data or permission is shared.
- **5.1.1** [C] No new data is requested.

## How a Sidekick reaches it (records only)

The page writes `repeat.except` into the task's own `reminder:` record (and `doneThrough`, which
every writer's Done already writes). The planner's manifest declares the field under `types`. No
other channel.

## Tests that can fail for their reason

- A daily 9:00 repeat with `except: ["2026-10-14"]`: occurrences planned on 13 and 15 Oct, none
  on 14 Oct.
- The same repeat, now 13 Oct: no iOS repeating trigger is booked while 14 Oct is within the
  horizon; occurrence bookings are. On 15 Oct (after a run) the repeating trigger returns and the
  occurrence bookings are gone.
- An `except` day that is not an occurrence (a Tuesday on a Monday-only repeat): no effect.
- `except` read in `timeZone`: after moving zones, the same wall-clock day is skipped.
- `doneThrough` at 9:10 on 14 Oct: the 10:00 occurrence that day is not booked; the 15 Oct one is.
- A record without the new fields books exactly as before (existing `ReminderPlannerTests` and
  `ReminderScheduleTests` pass unchanged).
- Validation: a bad `except` entry is refused at write time with its own message
  (NOTIFICATIONS.md 4.6 style).

## Done when

The founder approves a plan (or keeps today's behaviour); the change is checked on the iPhone with a
skipped occurrence; NOTIFICATIONS.md 4.3 documents the field; the full suite passes; results
reported honestly.
