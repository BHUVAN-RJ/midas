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
- **The page can already keep an excepted occurrence from alerting** by splitting the series
  around it (`../records.md` 3.6): a segment with `until` before the exception, a new segment
  after, a one-time record for a moved occurrence. This works with the engine as built [C, read
  in code; not run on a phone]. Its costs:
  - every segment with `until` is booked occurrence by occurrence, not as an iOS repeating
    trigger, so its occurrences compete for the 48 and depend on Midas running
    (NOTIFICATIONS.md 6.3, 7);
  - more records per task (one per segment and per moved occurrence);
  - the page must re-split each time an exception is added or passes.

So this brief is about removing those costs, not about making exceptions possible.

## A related gap: done on one occurrence

- The planner reads neither `lastDoneAt` nor `doneThrough`, so ticking a repeat's occurrence does
  not cancel that day's notification (concern 3,
  `docs/concerns/2026-10-11-reminders-and-widgets.md`). `TodayReminderPlanner.swift` (the widget)
  does read both.
- For a planner, a task done at 9:10 still gets its 10:00 end alert that day.
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
   iOS repeating trigger. Moved occurrences stay separate one-time records.
2. **`doneThrough` read by the planner:** occurrences at or before it are not booked. Covers
   "done today" without a split, and concern 3 for the Reminders Sidekick too.
3. **Both.**

Each keeps the record format backwards compatible: records without the field behave as today.

## Open questions for the founder

1. Is the page-side split (records.md 3.6) acceptable for planners, or does the engine take an
   `except` list.
2. Should the planner honour `doneThrough` / `lastDoneAt` (concern 3) as part of the same change.
3. Limit on `except` length per record (each entry about 13 bytes; 64 KB is not the constraint).

## App Review

- **4.7.2** [C] No native API reaches the page; the shell reads one more record field.
- **4.7.3** [C] No new data or permission is shared.
- **5.1.1** [C] No new data is requested.

## How a Sidekick reaches it (records only)

The page writes `except` (or `doneThrough`) into the `reminder:` record it already writes. No
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

The founder approves a plan (or keeps the page split); the change is checked on the iPhone with a
skipped occurrence; NOTIFICATIONS.md 4.3 documents the field; the full suite passes; results
reported honestly.
