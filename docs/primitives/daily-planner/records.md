# Daily planner records

The record shapes a daily planner Sidekick keeps through `store`, and how a task's alerts become
`reminder:` records for the shell's notification engine. Written 2026-10-12. Docs only; nothing
here is approved to build.

Sources: `docs/PRODUCT.md` section 5 (records, 64 KB, tombstones, query), `docs/NOTIFICATIONS.md`
(the `reminder:` format), `shell/sdk/midas-store.js`, `shell/Midas/ReminderRecord.swift`,
`ReminderSchedule.swift`, `ReminderPlanner.swift`, `ReminderActions.swift`,
`NotificationBooking.swift`, `SidekickStoreChannel.swift`, `docs/concerns/`, and midas-intel
`docs/research/daily-planner/ANALYSIS.md` (sections 6 and 7) and `structured-ui-teardown.md`.

## 1. What the store gives a page

| Fact | Source |
|---|---|
| Four calls: `store.set(key, value)`, `store.get(key)`, `store.query(prefix)`, `store.delete(key)`. | `midas-store.js` |
| `query(prefix)` returns `[{ key, value }]` for every record whose key starts with `prefix`, sorted by key. No filter by field, no other sort, no operators, no paging. | `midas-store.js`, `LocalRecordStore.swift` |
| Each Sidekick sees only its own records. Keys are `type:id`. A key is any non-empty string. | NOTIFICATIONS.md 4.1, `SidekickStoreChannel.swift` |
| `set` replaces the whole value. Last write wins per key. | NOTIFICATIONS.md 4.5, PRODUCT.md 5 |
| A value is at most 64 KB (65,536 bytes), counted as the UTF-8 bytes of the shell's JSON encoding. Over the limit, `set` rejects with `value is over 65536 bytes`. | `SidekickStoreChannel.swift` (`maxValueBytes`), `RecordSync.valueByteCount` |
| The shell's encoder (`JSONEncoder`) writes `/` as `\/`, so a value can count a few bytes more than `JSON.stringify` gives. | Foundation default; `RecordSync.valueByteCount` |
| Records live on the phone with an outbox and sync to the server per account. A reinstall brought every record back (2026-10-11). | PRODUCT.md 6 |
| `store.delete` writes a tombstone op. `query` and `get` no longer return the record. The op log on the server is append-only; old values stay there for operator recovery. There is no user-facing rollback. | PRODUCT.md 5 (Reversibility), `RecordSync.swift` (`deleted`) |
| No localStorage or IndexedDB. | PRODUCT.md 5 |

**Indexing.** Key order is the only index. A planner reads every `task:` record with
`store.query('task:')` and builds its own in-memory indexes (by day, by inbox, by repeat). The
other prefixes below exist so that one query returns one kind of thing:
`exception:<taskId>:` returns one task's exceptions; `reminder:<taskId>~` returns one task's alert
records.

**Size of a full read.** A typical task is about 560 bytes (example in 2.4). 1,000 tasks are
about 560 KB in one `query` reply; a year at 10 tasks a day (3,650) is about 2 MB. The local
channel is tested with a 200 KB body (`LocalChannelWebViewTests`); replies of several MB are not
tested [U].

## 2. `task:<id>`

One task, timed, all-day or in the inbox. One record per task, so a day never has to be split
across records.

**Key.** `task:<id>`. `<id>` is 10 characters from `a-z0-9`, random, made by the page at
creation, never reused, never changed when the task moves. Example: `task:k3f9x2ab7q`.

### 2.1 Fields

"Tag" follows the pattern the field serves (core or on request, `../README.md`). A field tagged
on request is absent until its pattern is built; pages treat a missing field as its default. Where
a block file tags its pattern differently, the block file wins.

| Field | Type | Required | Tag | Meaning |
|---|---|---|---|---|
| `v` | number | yes | core | Record version. `1`. |
| `title` | string, 1 to 200 characters | yes | core | The task's name. May be `""` only while `draft` is `true`. |
| `colour` | string `#RRGGBB` | yes | core | The task's colour (DP-ITEM-01). |
| `icon` | string, one emoji, or `""` | yes | core | The task's glyph (DP-ITEM-02). A page has no SF Symbols. |
| `day` | string `YYYY-MM-DD`, or `null` | yes | core | The calendar day the task starts on. `null` only when `inbox` is `true`. |
| `start` | string `HH:MM`, 24-hour, or `null` | yes | core | Wall-clock start on `day`. `null` for all-day and inbox tasks. |
| `duration` | whole number of minutes, 0 to 1,440 | yes | core | Planned length. `0` is a point in time. `start` plus `duration` past 24:00 ends on the next day (checklist 25, 26). The focus timer is computed from `start` and `duration`; there is no timer record. |
| `allDay` | boolean | yes | core | `true`: shown in the all-day row (DP-DAY-06); `start` is `null`. |
| `zone` | IANA name, or `null` | yes | core | `null`: floating, `day` and `start` are read in the phone's current zone (default, checklist 28). A name: pinned, `day` and `start` are read in that zone (checklist 29). Not the same field as `reminder.timeZone` (3.2). |
| `inbox` | boolean | yes | core | `true`: no slot yet (DP-ADD-05, checklist 13). `day` may be `null`. |
| `draft` | boolean | no | core | `true`: a half-typed task saved to the inbox when the page hides or the person picks an icon first (DP-ADD-01, checklist 12). A draft has `inbox: true` and never gets alerts. Default `false`. |
| `deadline` | string `YYYY-MM-DD`, or `null` | no | core | A due day without a time slot (DP-ADD-05, checklist 14). |
| `fixed` | boolean | no | core | `true`: never moved by shift-the-rest or auto-schedule (DP-RES-04, DP-RES-05, checklist 19). Default `false`. |
| `order` | number, or `null` | no | core | Manual order inside the inbox, the all-day row, or a day list. Lower first. |
| `done` | boolean | yes | core | Done. For a repeating task this field is unused; each occurrence's done state lives in `exception:` (section 5). |
| `doneAt` | ISO 8601 instant, or `null` | yes | core | When it was marked done. |
| `doneDay` | string `YYYY-MM-DD`, or `null` | yes | core | The local day it was actually done, which can differ from `day` after a roll-over (checklist 23). |
| `notes` | string, at most 8,000 characters | no | core | Free text (DP-ADD-01). |
| `subtasks` | array of `{ title: string (1 to 120), done: boolean }`, at most 50 | no | on request | Inline subtasks (DP-ITEM-06). Order is array order. |
| `repeat` | object or `null` | yes | core | See 2.2 (checklist 35). |
| `alerts` | array of `{ from: "start" \| "end", minutes: whole number 0 to 180 }`, at most 3 | yes | core | Alert offsets: `minutes` before `from`. `{from:"start", minutes:0}` is "at start". Empty array: no alerts. See section 3. |
| `energy` | `"relaxing"`, `"neutral"`, `"low"`, `"medium"`, `"high"`, or `null` | no | core | Energy level (Structured's five steps; DP-TIME-06, checklist 52). Points per level are page logic. |
| `source` | string, or `null` | no | on request | Where the task came from (DP-ITEM-07): `"midas"` (typed here), `"preset"`, `"import"`, or another short name the page uses. Display only. |
| `replanCount` | whole number | no | on request | How many times the task was carried over or replanned (DP-ITEM-07 replan badge, DP-RES-02). Default `0`. |
| `spentMin` | whole number of minutes | no | on request | Actual time spent, for planned versus actual (DP-TIME-07, DP-FB-03). |
| `intervalsStartedAt` | ISO 8601 instant, or `null` | no | on request | When focus intervals (DP-FOC-04) started for this task; the page computes the current interval from it. |
| `createdAt` | ISO 8601 instant | yes | core | Display only (client clock). |
| `updatedAt` | ISO 8601 instant | yes | core | Display only (client clock). |

Unknown fields are kept by the store. A page reading a record it does not fully know keeps the
fields it does not use when it writes the record back.

Calendar events are not copied into `task:` records (DP-ITEM-05). They are read through
`shell/calendar-access.md`, which returns them as its own result records, not as tasks.

None of these fields reach the notification engine: the engine reads only `reminder:` records
(`ReminderRecord.swift`). A task's fields reach it only through the alert records of section 3.

### 2.2 `repeat`

Same words as the `reminder:` repeat (NOTIFICATIONS.md 4.3), so a task repeat maps to an alert
repeat without translation, except `until`, which is a day here.

```js
repeat: { every: 'day' | 'week' | 'month' | 'year',
          interval: 1,            // optional, 1 to 999
          weekdays: [1, 3, 5],    // optional, weekly only, 0 = Sunday ... 6 = Saturday
          until: '2026-12-31' }   // optional last day, inclusive, local
```

- The first occurrence is `day`. Occurrences keep `start` as wall-clock time.
- Monthly on a day some months lack (the 31st) skips those months; yearly on February 29 happens
  in leap years only. This matches the engine (`ReminderSchedule.collectMonthly`,
  `collectYearly`), so the page's day view and the alerts agree.
- A repeating task can be `allDay`. It cannot be `inbox`.

### 2.3 States a task can be in

| State | `inbox` | `day` | `start` | `allDay` |
|---|---|---|---|---|
| Inbox, no day | true | null | null | false |
| Inbox, with a deadline | true | null | null | false (`deadline` set) |
| All-day | false | set | null | true |
| Timed | false | set | set | false |

Any other combination is invalid. The page refuses to save it.

### 2.4 Examples

```js
// Timed, floating, three alerts (Structured's default plus 5 min before)
await store.set('task:k3f9x2ab7q', {
  v: 1, title: 'Design review', colour: '#E8735A', icon: '💻',
  day: '2026-10-12', start: '09:30', duration: 90, allDay: false,
  zone: null, inbox: false, deadline: null,
  done: false, doneAt: null, doneDay: null,
  notes: 'Bring the mockups',
  subtasks: [{ title: 'Print mockups', done: false }, { title: 'Book room', done: true }],
  repeat: null,
  alerts: [{ from: 'start', minutes: 5 }, { from: 'start', minutes: 0 }, { from: 'end', minutes: 0 }],
  energy: 'medium', order: null,
  createdAt: '2026-10-12T08:00:00.000Z', updatedAt: '2026-10-12T08:05:00.000Z',
});
// About 560 bytes.

// Inbox task with a deadline
await store.set('task:p02mz8w1ce', {
  v: 1, title: 'Renew passport', colour: '#4A90D9', icon: '🛂',
  day: null, start: null, duration: 30, allDay: false,
  zone: null, inbox: true, deadline: '2026-11-01',
  done: false, doneAt: null, doneDay: null,
  repeat: null, alerts: [], order: 3,
  createdAt: '2026-10-12T08:10:00.000Z', updatedAt: '2026-10-12T08:10:00.000Z',
});

// Weekday routine, at start only
await store.set('task:r7u1hh30ad', {
  v: 1, title: 'Morning run', colour: '#5BB974', icon: '🏃',
  day: '2026-10-13', start: '07:00', duration: 30, allDay: false,
  zone: null, inbox: false, deadline: null,
  done: false, doneAt: null, doneDay: null,
  repeat: { every: 'week', weekdays: [1, 2, 3, 4, 5] },
  alerts: [{ from: 'start', minutes: 0 }],
  createdAt: '2026-10-12T08:20:00.000Z', updatedAt: '2026-10-12T08:20:00.000Z',
});
```

### 2.5 The 64 KB limit

| Case | Bytes (measured with `JSON.stringify`, UTF-8) |
|---|---|
| Bare task (title, time, one alert) | about 390 |
| Typical task (2.4 first example) | about 560 |
| Largest allowed: 200-character title, 8,000 two-byte characters of notes, 50 subtasks of 200 characters | about 28,000 |
| Same with 8,000 emoji counted as 8,000 `String.length` units (4 bytes per 2 units) | about 16,000 for notes |

With the limits in 2.1 (notes at most 8,000 `String.length` units, at most 50 subtasks of at most
120 characters), the worst case is under 45 KB even if every character takes 3 bytes. One task
never needs splitting.

**If a page kept a whole day in one record instead** (not this format): 65,536 / 560 is about
117 typical tasks, or about 167 bare tasks, before the day must split.

**Check before saving.** The page measures
`new TextEncoder().encode(JSON.stringify(value)).length` plus one byte per `/` in the text, and
refuses above 64,000 bytes with its own message, before the shell does.

## 3. `reminder:` records made from a task's alerts

The page never schedules a notification. For every alert of a task that can fire, it writes one
`reminder:` record (NOTIFICATIONS.md 4.2). The shell books it.

### 3.1 Id scheme

| Record | Key |
|---|---|
| One alert of a one-time task, or of a repeating task with no future exceptions | `reminder:<taskId>~<alertKey>` |
| A later segment of a repeating task split around exceptions (3.6) | `reminder:<taskId>~<alertKey>~<YYYYMMDD>` (the segment's first day) |
| One moved occurrence of a repeating task (3.6) | `reminder:<taskId>~<alertKey>~m<YYYYMMDD>` (the original day) |
| Daily plan prompt (DP-OUT-06) | `reminder:planner~plan` |
| Daily review prompt (DP-OUT-06) | `reminder:planner~review` |

`<alertKey>` is `s` or `e` (from start or end) followed by the minutes: `s5`, `s0`, `e0`. Example:
`reminder:k3f9x2ab7q~s5`.

- All of one task's alert records: `store.query('reminder:' + taskId + '~')`. The `~` keeps
  `task:abc` from matching `task:abcd`.
- Task ids are 10 characters, so `planner` (7) never collides with one.
- The engine's own iOS identifier is `reminder|<sidekickId>|<reminderId>|<kind>|<suffix>`
  (NOTIFICATIONS.md 6.4). Changing `at` changes the identifier, so the old booking is cancelled.

### 3.2 Fields written

| Field | Value |
|---|---|
| `at` | The alert's instant, as `Date.toISOString()`. For a repeat: the first occurrence's alert instant. |
| `title` | The task's `title`. |
| `body` | Absolute times, so a late or missed delivery stays true: start alert with minutes > 0: `"Starts at 9:30 AM"`; at start: `"9:30–11:00 AM"`; end alert: `"Ends at 11:00 AM"`. Clock format from `settings:planner.clock`. Words: `blocks/outside.md` DP-OUT-05. |
| `repeat` | The task's `repeat`, with `until` turned into the instant of the last occurrence's alert, plus 1 minute. Weekdays shift when the alert falls on the day before the task (3.4). |
| `timeZone` | Floating task: the phone's zone at write time (`Intl.DateTimeFormat().resolvedOptions().timeZone`). Pinned task: the task's `zone`. |
| `done` | Not written by the page for a live alert. Written `true` by the shell's Done button. |
| `taskId` | The task id. Kept by the shell (unknown fields are kept). |
| `alert` | `{ from, minutes }`, a copy of the task's alert. |

### 3.3 When the page writes, rewrites and deletes them

The page recomputes a task's wanted alert records after every change to the task or its
exceptions, reads the existing ones with `store.query('reminder:' + taskId + '~')`, and applies
the difference: `set` what changed, `delete` what is no longer wanted.

| Change | Alert records |
|---|---|
| Task created or edited (time, duration, day, alerts, title, repeat) | Recomputed. A changed `at` moves the notification; a changed title re-books it. |
| Running timer extended (DP-FOC-02, checklist 21) | The task's `duration` (or the occurrence's exception) changes; the end alert's `at` moves. |
| Shift the rest of the day (DP-RES-04, checklist 18) | Every moved task is rewritten; each one's alerts move. |
| Task deleted | All its alert records deleted, then its exceptions, then the task. |
| One-time task marked done | Its alert records deleted. |
| Repeating task occurrence marked done or skipped | An `exception:` record is written; the series is split (3.6). |
| Task moved to the inbox, or `allDay` with no alert time | Its alert records deleted. |
| An alert whose instant is at or before now | Not written, and deleted if present. |

The last row matters: a one-time `reminder:` the engine has never seen, with `at` in the past, is
booked as a "missed" notice and fires at once (`ReminderPlanner.plan`, `handledThrough` defaults
to `.distantPast`; concerns 2 and 9 of `docs/concerns/2026-10-11-reminders-and-widgets.md`).

Read before write: the shell may have written `done` or `snoozedUntil` since the page last read
(NOTIFICATIONS.md 4.5). The page reads each existing alert record before replacing it and keeps
those two fields when the alert's `at` is unchanged.

All-day tasks: an alert `{from:"start", minutes}` is measured from `settings:planner.allDayAlertTime`
(default `"08:00"`, Structured's default). `from:"end"` does nothing on an all-day task.

### 3.4 Repeats

- A repeating task writes one repeating `reminder:` per alert, not one record per occurrence.
- Weekly with weekdays: when an alert falls before midnight of the task's day (a 00:10 task with a
  15-minute alert), each weekday moves back by one (Monday becomes Sunday).
- Monthly and yearly repeats whose alert falls on a different date than the task cannot be
  expressed as one engine repeat (the month-end skip would land on the wrong months). The page
  writes those as one-time records, one per occurrence, for the next 14 days, and tops them up
  when it opens.
- How the engine books them (NOTIFICATIONS.md 6.3): interval 1 with no `until` is one iOS
  repeating notification per trigger (weekly on 5 weekdays is 5); every other repeat is booked
  occurrence by occurrence and competes for the 48 like one-time alerts.

### 3.5 Done and Snooze from the notification

The shell writes into the `reminder:` record, never into `task:` (`ReminderActions.swift`):

| Button | Shell writes | What the page does on next open |
|---|---|---|
| Done, one-time alert | `done: true`, `snoozedUntil: null` | Marks the task done: `done: true`, `doneAt` = the time the page sees it (the shell writes no time), `doneDay` = today. Deletes the task's other alert records. |
| Done, repeating alert | `lastDoneAt` = now; the repeat carries on | Writes `exception:<taskId>:<date>` with `done: true` for the occurrence whose alert is the latest at or before `lastDoneAt`, then splits the series (3.6). |
| Snooze 10 min, 1 hour, until tomorrow | `snoozedUntil` | Nothing. A snooze does not change the task. |

Facts that follow from the engine as built:
- Done on one alert does not stop the task's other alerts. The end alert still fires until the
  page opens and deletes it. The same limit is recorded for care-reminders (PRODUCT.md 6,
  "Known limits of option A").
- On a repeat, the planner reads neither `lastDoneAt` nor `doneThrough`, so ticking does not
  cancel that day's later alerts (concern 3 of `2026-10-11-reminders-and-widgets.md`).
- A tap on the notification opens the Sidekick (NOTIFICATIONS.md 5).

### 3.6 Exceptions and series splitting

The `reminder:` repeat has no per-occurrence exceptions (`ReminderRecord.swift`: `every`,
`interval`, `weekdays`, `until` only). To keep an excepted occurrence from alerting with the
engine as built, the page splits the series:

1. The first segment `reminder:<taskId>~<alertKey>` gets `repeat.until` just before the first
   future excepted occurrence's alert.
2. A new segment `reminder:<taskId>~<alertKey>~<YYYYMMDD>` starts at the next normal occurrence,
   with `until` before the next exception, and so on. The last segment has no `until`.
3. A moved occurrence gets a one-time record `reminder:<taskId>~<alertKey>~m<YYYYMMDD>` at its new
   time.

Costs: every segment with `until` is booked occurrence by occurrence, not as an iOS repeating
notification, so it competes for the 48. Past exceptions need no split. `shell/repeat-exceptions.md`
holds the shell alternative.

### 3.7 Cost against the shared iOS slots

Facts (NOTIFICATIONS.md 6.2): iOS holds 64 pending notifications per app. Midas books at most 48
for reminders, soonest first, across every Sidekick, and keeps 16 for snoozes. Past the 48, Midas
keeps its own queue and tops up when it runs.

| Planner use | Slots |
|---|---|
| One-time task with 3 alerts (Structured's maximum) | 3 while among the soonest 48 |
| 48 / 3 | 16 tasks' alerts fill the whole batch, for every Sidekick together |
| Daily task, 3 alerts, interval 1, no `until` | 3, held for as long as it repeats |
| Weekday task (5 weekdays), 3 alerts | 15 |
| 10 daily routines with 3 alerts | 30, leaving 18 for everything else in Midas |
| Plan and review prompts, daily | 2 |
| Series split around exceptions (3.6) | each `until` segment's occurrences compete one by one |

Known limit (NOTIFICATIONS.md 7): if Midas does not run for long enough, alerts past the booked
batch fire late, once each, as "missed". Interval-1 repeats are not affected. The engine ties are
broken by Sidekick id, then reminder id.

### 3.8 Time zones and daylight saving, as the engine works today

| Case | Behaviour | Source |
|---|---|---|
| One-time `reminder:` | Fires at the exact instant `at`, wherever the phone is. Booked with UTC date components. | NOTIFICATIONS.md 4.4; `NotificationBooking.trigger` |
| Repeating `reminder:` | Each occurrence keeps the wall-clock time of `at` read in `timeZone`, computed in the phone's current zone. | `ReminderSchedule.anchor`, `wallClockDate` |
| Repeat booked as an iOS repeating trigger | iOS fires it at that wall-clock time in whatever zone the phone is in. | `NotificationBooking.trigger` (`.repeating`) |
| Repeat booked occurrence by occurrence | Booked as exact instants. After the phone changes zone, the old instants stay booked until the engine runs again (app opened or brought forward, a record written, a notification acted on, background refresh at most hourly). The shell has no time-zone-change observer. | NOTIFICATIONS.md 6.1; `ShellServices.swift` |
| Time skipped by a DST jump (02:30 on spring-forward night) | Moves to the first valid moment after it. | NOTIFICATIONS.md 4.4; `wallClockDate` |
| Time repeated by a DST fall-back | iOS repeating triggers: the first of the two (`repeatedTimePolicy: .first`). Occurrence-by-occurrence bookings: as `Calendar.date(from:)` gives [U]. | `ReminderSchedule.nextNativeFire` |
| A pinned repeating task (`zone` set) | Cannot be pinned by the engine: repeats always follow the phone's zone. The page writes pinned repeats as one-time records for the next 14 days and tops them up when it opens. | `ReminderSchedule` |

For a floating one-time task (checklist 28), a one-time alert written at home fires at the home
instant after travel, until the page opens and rewrites it. `shell/local-time-alerts.md` covers
this.

The page computes a one-time task's instant with `new Date(y, m - 1, d, hh, mm)` (floating, the
phone's zone) or from the pinned zone. JavaScript also moves a skipped DST time forward, so the
day view and the engine agree (checklist 31).

## 4. `settings:planner`

One record. Key: `settings:planner`.

| Field | Type | Default | Tag | Meaning |
|---|---|---|---|---|
| `v` | number | `1` | core | Record version. |
| `clock` | `"system"`, `"12"`, `"24"` | `"system"` | core | Clock format (checklist 16). `"system"` follows `Intl` in the page. |
| `weekStart` | 0 to 6, or `null` | `null` | core | First day of the week (checklist 17). `null`: the page uses the locale's first day (`Intl.Locale` week info, where the WebKit build has it [U]), else Monday. The iOS setting itself is not exposed to the page [U]. |
| `dayStartsAt` | `HH:MM`, `"00:00"` to `"06:00"` | `"00:00"` | core | When "today" begins for night owls (checklist 27). A task starting before it shows on the previous planner day; its `day` stays the calendar day. |
| `wake` | `HH:MM` | `"07:00"` | core | Wake time (DP-SET-01, DP-SET-02). |
| `sleep` | `HH:MM` | `"23:00"` | core | Bedtime. |
| `defaultDuration` | minutes | `15` | core | Duration of a new task (checklist 9). |
| `durationPresets` | array of minutes | `[1, 15, 30, 45, 60, 90]` | core | Duration chips in the add sheet (DP-ADD-02). |
| `defaultAlerts` | as `task.alerts` | `[{from:"start",minutes:0},{from:"end",minutes:0}]` | core | Alerts of a new task (Structured's default). |
| `allDayAlertTime` | `HH:MM` | `"08:00"` | core | Alert time for all-day tasks (Structured's default). |
| `neverSuggest` | array of strings | `[]` | on request | Titles the person removed from suggestions (DP-ADD-08). |
| `layout` | `"full"`, `"simplified"`, `"minimal"` | `"full"` | on request | Density mode (DP-SET-04). |
| `theme` | `"system"`, `"light"`, `"dark"` | `"system"` | on request | DP-SET-05. |
| `accent` | string `#RRGGBB`, or `null` | `null` | on request | App accent (DP-SET-05); does not recolour tasks. Token names live in `recipe.md`. |
| `font` | `"system"`, or a font name the page ships | `"system"` | on request | DP-SET-05 (for example a dyslexia-friendly font). |
| `sound` | boolean | `true` | on request | Completion sound in the page (DP-FB-01). It does not change notification sounds: the engine plays the default sound only (NOTIFICATIONS.md 5). A page has no haptics API. |
| `confetti` | boolean | `false` | on request | DP-FB-01. |
| `energyLimit` | number, or `null` | `null` | core | Daily energy points before "over capacity" (DP-TIME-06 energy ring, checklist 52). |
| `planPrompt` | `{ on: boolean, time: "HH:MM" }` | `{ on: false, time: "08:00" }` | on request | DP-OUT-06. Written as `reminder:planner~plan`, daily. |
| `reviewPrompt` | `{ on: boolean, time: "HH:MM" }` | `{ on: false, time: "20:00" }` | on request | DP-OUT-06. Written as `reminder:planner~review`, daily. |
| `calendars` | array of calendar ids | `[]` | core | Ids of the calendars shown (DP-SET-06). Used only if `shell/calendar-access.md` is built. |
| `onboarded` | boolean | `false` | core | DP-SET-01 ran. |

A missing field takes its default. The page writes the whole record on each change.

## 5. `exception:<taskId>:<date>`

One occurrence of a repeating task that differs from the series. `<date>` is the occurrence's
original day, `YYYY-MM-DD`. Example: `exception:r7u1hh30ad:2026-10-14`.

All of one task's exceptions: `store.query('exception:' + taskId + ':')`.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `v` | number | yes | `1`. |
| `taskId` | string | yes | The series. |
| `date` | `YYYY-MM-DD` | yes | The original day (same as in the key). |
| `skip` | boolean | no | `true`: this occurrence is deleted. |
| `done` | boolean | no | This occurrence is done. |
| `doneAt` | ISO 8601 instant | no | When. |
| `doneDay` | `YYYY-MM-DD` | no | The local day it was done (checklist 23). |
| `day`, `start`, `duration`, `allDay` | as `task:` | no | This occurrence moved or resized. |
| `title`, `colour`, `icon`, `notes`, `subtasks`, `alerts`, `energy` | as `task:` | no | This occurrence edited (checklist 32). |

A field present overrides the series for that occurrence; a field absent follows the series. An
exception is about 130 bytes.

- **A done occurrence** is `exception:<taskId>:<date>` `{ done: true, doneAt, doneDay }`.
- **Subtasks of a repeating task:** the series' `subtasks` is the list each occurrence starts
  with, all not done. Ticking a subtask of one occurrence writes that occurrence's whole
  `subtasks` array into its exception. Other occurrences are not changed.
- **How a done or skipped occurrence stops its alerts.** The engine cannot do this today: the
  `reminder:` repeat has no exceptions, and the planner reads neither `lastDoneAt` nor
  `doneThrough` (concern 3). The page does it by splitting the series around the occurrence
  (3.6). An engine field for it is the subject of `shell/repeat-exceptions.md`.

Edit spans (checklist 32 to 34):
- **This one:** write or update the exception.
- **This and future:** set the old task's `repeat.until` to the day before, create a new `task:`
  from that day with the new fields, and move later exceptions to the new task id. Past
  occurrences keep the old fields (checklist 33). This mirrors the engine: `until` ends the old
  series; a new record starts the new one.
- **All:** rewrite the task. Exceptions stay. The page keeps the previous value for Undo
  (checklist 34).

Deleting a series deletes its exceptions and alert records.

## 6. `preset:<id>`

Tag: on request (DP-ADD-08, Llama Life presets). A saved task the person can drop into a day.
Key `preset:<id>`, `<id>` 10 characters from `a-z0-9`. All presets: `store.query('preset:')`.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `v` | number | yes | `1`. |
| `name` | string, 1 to 80 characters | yes | The preset's name in the list. |
| `tasks` | array of task templates, at most 50 | yes | Each: `title`, `colour`, `icon`, `duration`, `alerts`, and optional `offset` (minutes after the preset's start time), `notes`, `subtasks`, `energy`. No `day`, `start`, `done` or `repeat`. |
| `order` | number, or `null` | no | Order in the preset list. |

Applying a preset writes one new `task:` per template with `source: "preset"`. A preset never
writes `reminder:` records itself; its tasks do, as any task. A template is about 300 bytes
without notes or subtasks, so 50 plain templates are about 15 KB. Templates with long notes and
subtasks can pass 64 KB; the page checks the size as in 2.5 and refuses to save above 64,000 bytes.

## 7. `day:<YYYY-MM-DD>`

Tag: on request (DP-DAY-07, the day as a text note). One record per day that has a note. Key
`day:2026-10-12`; a month's notes: `store.query('day:2026-10')`, since keys sort by date.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `v` | number | yes | `1`. |
| `note` | string, at most 30,000 characters | yes | The day's text. |
| `updatedAt` | ISO 8601 instant | yes | Display only. |

Shape chosen here: one record per day, the note as plain text, `day` as the calendar day (not the
planner day of `dayStartsAt`). An empty note deletes the record.

## 8. What has no record

Decided in the block files:
- **No timer record.** The focus timer is computed from the task's `start` and `duration`
  (DP-FOC-01, DP-FOC-02). An extension changes `duration` (or the occurrence's exception).
  `spentMin` and `intervalsStartedAt` are the only focus fields stored.
- **Undo is in memory only** (DP-FB-04): it does not survive closing the page.
- **Copy-day is held in page memory** (DP-RES-07) until pasted.
- **Calendar events** are not stored as tasks (2.1).

## 9. Delete, undo and history

- A delete is `store.delete(key)`: a tombstone op on the server, never a removal from the log
  (PRODUCT.md 5). It disappears from `query` at once.
- Undo (DP-FB-04, checklist 54) is page logic, in memory: the page keeps the previous value of
  every record it changed or deleted for the last action and writes it back on Undo. That write is
  a new op. Undo is lost when the page closes.
  The op log is operator-only; there is no user-facing rollback.
- Done tasks are kept, not deleted, so the record of what was done stays (DP-FB-03, checklist 53).

## 10. Order of writes

The store has no transactions. When one action touches several records, the page writes in an
order that leaves no orphan alert if it stops halfway:

1. Delete alert records that are no longer wanted.
2. Write the `task:` and `exception:` records.
3. Write the new or changed alert records.

On every open, the page checks that every `reminder:<taskId>~` record has a live task and deletes
the ones that do not (checklist 43).
