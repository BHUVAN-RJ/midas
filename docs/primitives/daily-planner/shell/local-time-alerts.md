# Brief: local-time (floating) and zone-pinned alerts, 2026-10-12

**Status:** Draft, not approved to build. The founder decides whether and when.

Labels: [C] confirmed on a primary source or read in this repo's code; [R] reported; [U] not
verified.

## How you work

The four steps of `docs/briefs/notification-engine.md`: say the idea back; ask; propose a plan
and wait for "approved"; then build with tests (`CLAUDE.md`).

## Goal

A planner task's alert fires at the task's local wall-clock time after the person travels, unless
the task is pinned to a zone (checklist 28, floating by default), and a pinned task's alert fires
at the pinned zone's time (checklist 29). Pattern DP-OUT-05, DP-SET-07. Leave reason 11 lists
time zones (40 negative hits) and DST (9).

## Finding first: what the engine does today

Read in `shell/Midas/ReminderSchedule.swift`, `ReminderPlanner.swift`, `NotificationBooking.swift`:

| Alert | Engine today | Checklist |
|---|---|---|
| One-time, pinned to a zone | Supported. `at` is an instant; booked with UTC date components, so it fires at that instant wherever the phone is. | 29 (one-time) |
| Repeating, floating | Supported. Each occurrence keeps the wall-clock time of `at` (read in `timeZone`), computed in the phone's current zone. Interval-1 repeats are iOS repeating triggers, which follow the phone's zone by themselves. | 28 (repeats) |
| One-time, floating | Not a field. The page writes an instant from the phone's zone at write time. After travel it fires at the home instant until the page opens and rewrites it. | 28 (one-time) |
| Repeating, pinned to a zone | Not possible. Repeats always follow the phone's current zone. | 29 (repeats) |

So ANALYSIS.md 7.3's "28: not built" holds for one-time alerts only, and its "29: shell has it"
holds for one-time alerts only.

**A one-time floating alert can be expressed with the engine as built** [C, read in code; not run
on a phone]: a repeat with a single occurrence.

```js
// "9:30 local, on 14 Oct, wherever the phone is"
await store.set('reminder:k3f9x2ab7q~s0', {
  at: '2026-10-14T16:30:00.000Z',              // 9:30 in America/Los_Angeles
  timeZone: 'America/Los_Angeles',             // the zone the wall-clock time is read in
  repeat: { every: 'day', until: '2026-10-15T04:30:00.000Z' },  // at + 12 h
  title: 'Design review', body: '9:30–11:00 AM',
});
```

How the engine treats it (code facts):
- The wall-clock time (9:30 on 14 Oct) is read from `at` in `timeZone`, then placed in the
  phone's current zone (`ReminderSchedule.anchor`, `wallClockDate`).
- It has `until`, so it is booked occurrence by occurrence as an exact instant, not as an iOS
  repeating trigger (`nativeRepeatComponents` returns nil). It costs 1 slot, like a one-time alert.
- A new repeat's past occurrences are not reported as missed (`handledThrough` starts at now for
  repeats), unlike a new one-time reminder.
- Done writes `lastDoneAt`, not `done` (`ReminderActions`), which does not matter with one
  occurrence.

Limits of this form:
- The instant is recomputed only when the engine runs: app opened or brought forward, a record
  written, a notification acted on, background refresh at most hourly (NOTIFICATIONS.md 6.1). The
  shell has no time-zone-change observer. Until a run, the old instant stays booked.
- `until` = `at` + 12 h covers travel up to 12 h west. More than 12 h east (Los Angeles to
  Auckland is 20 h), the next day's occurrence can also fall before `until` and fire too.

## What is already decided (with sources)

- One-time reminder: an exact moment. Repeat: a wall-clock time across zones and DST. A time
  skipped by DST moves to the first valid moment (NOTIFICATIONS.md 4.4).
- The engine never touches iOS notifications outside `reminder|` identifiers
  (NOTIFICATIONS.md 6.2).
- Structured tasks are floating by default; a task can be pinned ("Set Timezone"); imported tasks
  are "often set in a fixed time zone" [C, help.structured.app 330946, via
  category-and-completeness.md 2.4].

## Platform facts

- `UNCalendarNotificationTrigger` with date components that carry a time zone fires at that exact
  moment "even if the phone changes zone or its clock is adjusted" [C, code comment in
  `NotificationBooking.trigger`].
- The same trigger with date components and no time zone, `repeats: false`, fires at that
  wall-clock time in the phone's zone at the time [U; this is what a floating field would book].
- A repeating calendar trigger whose components carry a time zone fires at that zone's time [U;
  this is what a pinned repeat would book].
- EventKit models the same split: a `nil` time zone is floating [C, Apple docs, via
  category-and-completeness.md 2.6].
- At most 64 pending notifications per app; Midas books 48 plus 16 reserved
  (NOTIFICATIONS.md 6.2).

## Open questions for the founder

1. **Is the single-occurrence repeat form acceptable for planner pages**, with its two limits, or
   does the engine get a field.
2. **If a field:** a `floating: true` flag on one-time records (booked with zone-less date
   components), and how the planner orders such a booking against the 48 when its instant is not
   fixed.
3. **Pinned repeats (29):** worth a field (for example `pinZone: true`, booking repeating triggers
   with the zone), or left to the page's 14-day one-time window (records.md 3.8).
4. **Re-plan on zone change:** whether the shell observes the system's time-zone change and runs
   the engine (this helps every occurrence-by-occurrence booking, not only floating ones).

## App Review

- **4.7.2** [C] Nothing new is exposed: the page writes a record field; the shell books the
  notification.
- **4.7.3** [C] No new data or permission is shared: notification permission is already asked
  once by the shell (NOTIFICATIONS.md 2).
- **5.1.1** [C] No new data is requested. The page reads the zone through
  `Intl.DateTimeFormat().resolvedOptions().timeZone`, which needs no permission.

## How a Sidekick reaches it (records only)

Today: the single-occurrence repeat above. With a field: the same `reminder:` record plus the
field. No other channel.

## Tests that can fail for their reason

Each runs against the planner and schedule with a fixed clock and a phone calendar whose zone
the test changes.
- A record written in Los Angeles for 9:30 on 14 Oct, phone moved to New York before 9:30: the
  booked fire date is 9:30 New York time, not 12:30.
- The same with the single-occurrence repeat form: the same result, and exactly one occurrence is
  planned on 14 Oct and none on 15 Oct.
- The single-occurrence form, phone moved to Auckland: the test records whether a 15 Oct
  occurrence is planned (it documents the 12 h limit; it fails if the limit changes).
- A pinned one-time record: after moving zones, the fire instant is unchanged.
- A floating record at 02:30 on the spring-forward day in Los Angeles: fires at 03:00.
- A floating record never produces a "missed" notice for a time that was future when written.
- Existing tests still pass: `ReminderScheduleTests` (wall-clock time after a move, DST in LA and
  NY), `UserNotificationBookingTests` (exact-moment triggers).

## Done when

The founder approves a plan (or decides the page form is enough); the chosen behaviour is checked
on the iPhone with a manual zone change; the full suite passes; results reported honestly.
