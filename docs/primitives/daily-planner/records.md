# Daily planner records

The record types a daily planner Sidekick keeps through `store`, and how a task's alerts reach the
shell's notification engine. Written 2026-10-12; moved to the current record format (unified data,
`$type` plus a `types` block in the manifest) on 2026-10-23. Docs only; nothing here is approved
to build.

Sources: `docs/PRODUCT.md` section 5 (records, 64 KB, tombstones, query) and "Data format",
`docs/NOTIFICATIONS.md` (the `reminder:` record), `shell/sdk/midas-store.js`,
`shell/sdk/record-schema.js`, `shell/Midas/ReminderRecord.swift`, `ReminderExpansion.swift`,
`ReminderSchedule.swift`, `ReminderPlanner.swift`, `RecordWriter.swift`, `ReminderActions.swift`,
`NotificationBooking.swift`, `SidekickStoreChannel.swift`, `sidekicks/reminders/manifest.json` and
`sidekicks/care-reminders/manifest.json` (the same data stored by the live Sidekicks),
`docs/concerns/`, and midas-intel `docs/research/daily-planner/ANALYSIS.md` (sections 6 and 7) and
`structured-ui-teardown.md`.

## 1. What the store gives a page

| Fact | Source |
|---|---|
| Seven calls: `store.set(key, value)`, `store.get(key)`, `store.update(key, patch)` (JSON Merge Patch: a field set to `null` is removed, an object merged, anything else replaced), `store.query(prefix)`, `store.delete(key)`, `store.putFile(blob)`, `store.fileUrl(ref)`. | `midas-store.js`, NOTIFICATIONS.md 4.1 |
| `query(prefix)` returns `[{ key, value }]` for every record whose key starts with `prefix`, sorted by key. No filter by field, no other sort, no operators, no paging. | `midas-store.js`, `LocalRecordStore.swift` |
| Each Sidekick sees only its own records. Keys are `<prefix><id>`; every prefix is declared in the Sidekick's `manifest.json` under `types`, one JSON Schema per prefix (section 11). A key with no declared prefix is refused (`no record type is declared for <key>`). | NOTIFICATIONS.md 4.1 and 4.6, `record-schema.js` |
| Every record carries `$type`, stamped by the shell from the manifest. The shell and the server check every `set` and `update` against the type's schema; a value that does not fit is refused with the reason and nothing is written. | NOTIFICATIONS.md 4.1, `record-schema.js` |
| Leave a field out instead of writing `null`. Instants are ISO 8601 strings with an offset (`Date.toISOString()`); days are `YYYY-MM-DD` (schema format `date`); times of day are `HH:MM` (format `wall-time`). | NOTIFICATIONS.md 4.1, `record-schema.js` |
| `set` replaces the whole value; `update` changes only the fields in the patch. Last write wins per key. | NOTIFICATIONS.md 4.5, PRODUCT.md 5 |
| A value is at most 64 KB (65,536 bytes), counted as the UTF-8 bytes of the shell's JSON encoding. Over the limit, `set` rejects with `value is over 65536 bytes`. Files (images) go through `putFile` and the record keeps the `"file:<id>"` reference. | `SidekickStoreChannel.swift` (`maxValueBytes`), `RecordSync.valueByteCount`, `midas-store.js` |
| The shell's encoder (`JSONEncoder`) writes `/` as `\/`, so a value can count a few bytes more than `JSON.stringify` gives. | Foundation default; `RecordSync.valueByteCount` |
| Records live on the phone with an outbox and sync to the server per account. A reinstall brought every record back (2026-10-11). | PRODUCT.md 6 |
| `store.delete` writes a tombstone op. `query` and `get` no longer return the record. The op log on the server is append-only; old values stay there for operator recovery. There is no user-facing rollback. | PRODUCT.md 5 (Reversibility), `RecordSync.swift` (`deleted`) |
| No localStorage or IndexedDB. | PRODUCT.md 5 |

**Indexing.** Key order is the only index. A planner reads every task with
`store.query('reminder:')` and builds its own in-memory indexes (by day, by inbox, by repeat). The
other prefixes below exist so that one query returns one kind of thing:
`exception:<taskId>:` returns one task's exceptions.

**Size of a full read.** A typical task is about 430 bytes (example in 2.4). 1,000 tasks are
about 430 KB in one `query` reply; a year at 10 tasks a day (3,650) is about 1.6 MB. The local
channel is tested with a 200 KB body (`LocalChannelWebViewTests`); replies of several MB are not
tested [U].

## 2. `reminder:<id>`, the task

One task, timed, all-day or in the inbox, is one `reminder:` record of type `planner.item`, the way
the Reminders Sidekick keeps every item, dated or not, as a `reminder:` record (`reminders.item`).
One record per task, so a day never has to be split across records. The shell's notification
engine reads the same record (section 3); there are no separate alert records.

**Key.** `reminder:<id>`. `<id>` is 10 characters from `a-z0-9`, random, made by the page at
creation, never reused, never changed when the task moves. Example: `reminder:k3f9x2ab7q`.

### 2.1 Fields

"Tag" follows the pattern the field serves (core or on request, `../README.md`). A field tagged
on request is absent until its pattern is built; pages treat a missing field as its default. Where
a block file tags its pattern differently, the block file wins. Fields marked "engine" are the
`reminder:` contract of NOTIFICATIONS.md 4.2, read (and some written) by the shell.

| Field | Type | Required | Tag | Meaning |
|---|---|---|---|---|
| `$type` | `"planner.item"` | stamped by the shell | core | The record's type (section 11). |
| `title` | string, 1 to 200 characters | yes | core | The task's name; engine: the notification title. Never empty: the shell refuses an empty `reminder:` title (`reminder.title must be a non-empty string`). |
| `colour` | string `#RRGGBB` | yes | core | The task's colour (DP-ITEM-01). |
| `icon` | string, one emoji | no | core | The task's glyph (DP-ITEM-02). Absent: no glyph. A page has no SF Symbols. |
| `at` | ISO 8601 instant with offset | no | core | Engine. When the task starts: its day and start time, read in `timeZone`. For an all-day task, the day at `settings:self.allDayAlertTime`. For a repeat, the first occurrence. Absent: an inbox task (no day). |
| `allDay` | boolean | no | core | `true`: shown in the all-day row (DP-DAY-06); `at` stands for the day only (its time is the all-day alert time). Absent or `false`: timed. Written only with `at`. |
| `timeZone` | IANA name | no | core | Engine. The zone `at` was meant in. Floating task: the phone's zone at write time (`Intl.DateTimeFormat().resolvedOptions().timeZone`). Pinned task: the task's `zone`. Written with `at`. |
| `zone` | IANA name | no | core | Present only when the task is pinned to a zone (checklist 29); its value equals `timeZone`. Absent: floating, the task keeps its wall-clock time in the phone's current zone (default, checklist 28). |
| `duration` | whole number of minutes, 0 to 1,440 | yes | core | Planned length. `0` is a point in time. `at` plus `duration` past 24:00 ends on the next day (checklist 25, 26). The focus timer is computed from `at` and `duration`; there is no timer record. |
| `draft` | boolean | no | core | `true`: a half-typed task saved to the inbox when the page hides or the person picks an icon first (DP-ADD-01, checklist 12). A draft has no `at` and no `alerts`. Default `false`. |
| `deadline` | string `YYYY-MM-DD` | no | core | A due day without a time slot (DP-ADD-05, checklist 14). Absent: no deadline. |
| `fixed` | boolean | no | core | `true`: never moved by shift-the-rest or auto-schedule (DP-RES-04, DP-RES-05, checklist 19). Default `false`. |
| `order` | number | no | core | Manual order inside the inbox, the all-day row, or a day list. Lower first. Absent: after the ordered ones. |
| `done` | boolean | no | core | Engine. Done; `true` stops every notification of the task. For a repeating task each occurrence's done state lives in `exception:` (section 5) and the series stays `done: false`. Default `false`. |
| `completedAt` | ISO 8601 instant | no | core | Engine (written with `done` by every writer, the shell's Done button included). When it was marked done. |
| `doneDay` | string `YYYY-MM-DD` | no | core | The local day it was actually done, which can differ from the day of `at` after a roll-over (checklist 23). |
| `notes` | string, at most 8,000 characters | no | core | Free text (DP-ADD-01); engine: the notification text, shown under the title on every notification the task makes (its own and its alerts'). |
| `subtasks` | array of `{ title: string (1 to 120), done: boolean }`, at most 50 | no | on request | Inline subtasks (DP-ITEM-06). Order is array order. |
| `repeat` | object | no | core | Engine. See 2.2 (checklist 35). Absent: one-time. |
| `alerts` | array of rules `{ id, kind: "before", minutes, text? }`, at most 3 | no | core | Engine. Early alerts before the start, one notification each. See 3.2. Absent or empty: the task notifies at its start only. |
| `snoozedUntil`, `snoozes` | instant; object of instants | no | core | Engine, written by the shell's Snooze buttons (NOTIFICATIONS.md 4.2). The page keeps them. |
| `lastDoneAt`, `doneThrough` | ISO 8601 instants | no | core | Engine, written by Done on a repeat (any writer). See 3.5. |
| `energy` | `"relaxing"`, `"neutral"`, `"low"`, `"medium"`, `"high"` | no | core | Energy level (Structured's five steps; DP-TIME-06, checklist 52). Points per level are page logic. Absent: none. |
| `source` | `{ kind: string, externalId?: string }` | no | on request | Where the task came from (DP-ITEM-07), as the Reminders Sidekick stores it: `{ kind: "preset" }`, `{ kind: "import", externalId }`, or another short kind the page uses. Absent: typed here. Display only. |
| `replanCount` | whole number | no | on request | How many times the task was carried over or replanned (DP-ITEM-07 replan badge, DP-RES-02). Default `0`. |
| `spentMin` | whole number of minutes | no | on request | Actual time spent, for planned versus actual (DP-TIME-07, DP-FB-03). |
| `intervalsStartedAt` | ISO 8601 instant | no | on request | When focus intervals (DP-FOC-04) started for this task; the page computes the current interval from it. |
| `createdAt` | ISO 8601 instant | yes | core | Display only (client clock). |
| `updatedAt` | ISO 8601 instant | yes | core | Display only (client clock). |

Unknown fields are kept by every writer. A page reading a record it does not fully know keeps the
fields it does not use when it writes the record back; `store.update` with only the changed fields
does this by itself.

Calendar events are not copied into `reminder:` records (DP-ITEM-05). They are read through
`shell/calendar-access.md`, which returns them as its own result records, not as tasks.

The engine reads `at`, `title`, `notes`, `repeat`, `timeZone`, `done`, `snoozedUntil`, `snoozes`,
`doneThrough` and `alerts` from this record (`ReminderRecord.swift`, `ReminderExpansion.swift`);
every other field is the planner's own and is ignored by the engine.

### 2.2 `repeat`

The `reminder:` repeat itself (NOTIFICATIONS.md 4.3), so the task's repeat is the engine's repeat.

```js
repeat: { every: 'day' | 'week' | 'month' | 'year',
          interval: 1,            // optional, 1 to 999
          weekdays: [1, 3, 5],    // optional, weekly only, 0 = Sunday ... 6 = Saturday
          until: '2026-12-31T23:59:00-08:00' }   // optional end, inclusive: the last day's 23:59 in timeZone
```

- The first occurrence is `at`. Occurrences keep the wall-clock time of `at` read in `timeZone`.
- `until` is an instant (format `date-time`). The page writes the last day's 23:59 in the task's
  `timeZone` and shows the day.
- Monthly on a day some months lack (the 31st) skips those months; yearly on February 29 happens
  in leap years only. This is the engine's own calendar (`ReminderSchedule.collectMonthly`,
  `collectYearly`), so the page's day view and the notifications agree.
- A repeating task can be `allDay`. It cannot be in the inbox (it has `at`).

### 2.3 States a task can be in

| State | `at` | `allDay` | `deadline` |
|---|---|---|---|
| Inbox, no day | absent | absent | absent |
| Inbox, with a deadline | absent | absent | set |
| All-day | set (the day at the all-day alert time) | `true` | absent |
| Timed | set | absent or `false` | absent |

Any other combination is invalid. The page refuses to save it.

### 2.4 Examples

```js
// Timed, floating, start notification plus 5 min before
await store.set('reminder:k3f9x2ab7q', {
  title: 'Design review', colour: '#E8735A', icon: '💻',
  at: '2026-10-12T16:30:00.000Z', timeZone: 'America/Los_Angeles', duration: 90,
  done: false,
  notes: 'Bring the mockups',
  subtasks: [{ title: 'Print mockups', done: false }, { title: 'Book room', done: true }],
  alerts: [{ id: 's5', kind: 'before', minutes: 5 }],
  energy: 'medium',
  createdAt: '2026-10-12T08:00:00.000Z', updatedAt: '2026-10-12T08:05:00.000Z',
});
// About 430 bytes with the $type the shell stamps.

// Inbox task with a deadline
await store.set('reminder:p02mz8w1ce', {
  title: 'Renew passport', colour: '#4A90D9', icon: '🛂',
  duration: 30, deadline: '2026-11-01',
  done: false, order: 3,
  createdAt: '2026-10-12T08:10:00.000Z', updatedAt: '2026-10-12T08:10:00.000Z',
});

// Weekday routine, start notification only
await store.set('reminder:r7u1hh30ad', {
  title: 'Morning run', colour: '#5BB974', icon: '🏃',
  at: '2026-10-13T14:00:00.000Z', timeZone: 'America/Los_Angeles', duration: 30,
  done: false,
  repeat: { every: 'week', weekdays: [1, 2, 3, 4, 5] },
  createdAt: '2026-10-12T08:20:00.000Z', updatedAt: '2026-10-12T08:20:00.000Z',
});
```

### 2.5 The 64 KB limit

| Case | Bytes (measured with `JSON.stringify`, UTF-8) |
|---|---|
| Bare task (title, time, one alert) | about 280 |
| Typical task (2.4 first example) | about 430 |
| Largest allowed: 200-character title, 8,000 two-byte characters of notes, 50 subtasks of 120 characters | about 24,000 |
| Same with 8,000 emoji counted as 8,000 `String.length` units (4 bytes per 2 units) | about 16,000 for notes |

With the limits in 2.1 (notes at most 8,000 `String.length` units, at most 50 subtasks of at most
120 characters), the worst case is under 45 KB even if every character takes 3 bytes. One task
never needs splitting.

**If a page kept a whole day in one record instead** (not this format): 65,536 / 430 is about
152 typical tasks, or about 234 bare tasks, before the day must split.

**Check before saving.** The page measures
`new TextEncoder().encode(JSON.stringify(value)).length` plus one byte per `/` in the text, and
refuses above 64,000 bytes with its own message, before the shell does.

## 3. Notifications from a task

The page never schedules a notification. The task record is a `reminder:` record, so the shell
books its notifications from the task itself (NOTIFICATIONS.md 4.2): one at `at`, and one per
early alert in `alerts`. Editing the task moves them; deleting it cancels them.

### 3.1 Ids

| What | Where |
|---|---|
| The task's own notification (at start) | the task, `reminder:<id>` |
| One early alert of a task | the rule in the task's `alerts`, rule id `s<minutes>`: `s5`, `s15` |
| Daily plan prompt (DP-OUT-06) | `reminder:plan` |
| Daily review prompt (DP-OUT-06) | `reminder:review` |

- Nothing is stored per alert. The engine builds each alert's notification in memory under the id
  `<id>~<rule>` (`ReminderExpansion.swift`, NOTIFICATIONS.md 3); a page never writes a key with
  `~` in it.
- Task ids are 10 characters from `a-z0-9`, so `plan` and `review` never collide with one. The
  page leaves those two keys out of the day view. Each holds `title`, `at` (today at the prompt's
  time), `timeZone` and `repeat: { every: 'day' }`.
- The engine's own iOS identifier is `reminder|<sidekickId>|<reminderId>|<kind>|<suffix>`
  (NOTIFICATIONS.md 6.4). Changing `at` changes the identifier, so the old booking is cancelled.

### 3.2 What the engine reads

| Field | Value the page writes |
|---|---|
| `at` | The task's start instant, as `Date.toISOString()`. For a repeat: the first occurrence. All-day: the day at `settings:self.allDayAlertTime` (default `"08:00"`, Structured's default). |
| `title` | The task's `title`: the title of the task's own notification. |
| `notes` | The task's notes: the text line of every notification the task makes. |
| `repeat` | The task's repeat (2.2). |
| `timeZone` | Floating task: the phone's zone at write time. Pinned task: the task's `zone`. |
| `alerts` | One rule per early alert: `{ id: "s<minutes>", kind: "before", minutes }`, `minutes` 1 to 180, before `at`. Optional `text` sets the alert's title line, with `{title}`, `{time}` (the start time) and `{day}`; without it the engine writes `"{title} in 5 min"`. Words: `blocks/outside.md` DP-OUT-05. |
| `done` | `true` when the task is done (one-time). |

An "at start" alert is the task's own notification at `at`; it has no rule. A dated task always
notifies at `at` (NOTIFICATIONS.md 4.2); see section 12 for alerts this format cannot hold.

### 3.3 When the page writes

The page writes the task; the notifications follow it. There is nothing else to recompute or clean
up.

| Change | Notifications |
|---|---|
| Task created or edited (time, duration, day, alerts, title, repeat) | The engine re-plans from the record. A changed `at` moves the notification and its alerts; a changed title or notes re-books them. |
| Running timer extended (DP-FOC-02, checklist 21) | The task's `duration` (or the occurrence's exception) changes. No notification depends on `duration` (section 12). |
| Shift the rest of the day (DP-RES-04, checklist 18) | Every moved task's `at` is rewritten; its notifications move. |
| Task deleted | Its exceptions deleted, then the task: every notification is cancelled. |
| One-time task marked done | `done: true` and `completedAt` (NOTIFICATIONS.md 4.5): every notification of the task stops. |
| Repeating task occurrence marked done or skipped | An `exception:` record is written (section 5); 3.5 and 3.6. |
| Task moved to the inbox | `at`, `allDay`, `timeZone`, `zone`, `repeat` and `alerts` removed (`store.update` with each set to `null`): it notifies nobody. |
| An alert whose instant is at or before now | Not booked by the engine (`ReminderExpansion.earlyAlerts` books only alerts still ahead). |

The task's own `at` in the past: a one-time `reminder:` the engine has never seen, with `at` in the
past, is booked as a "missed" notice and fires at once (`ReminderPlanner.plan`, `handledThrough`
defaults to `.distantPast`; concerns 2 and 9 of `docs/concerns/2026-10-11-reminders-and-widgets.md`).
A task created or moved into the past fires that notice unless it is saved as done.

Write with `store.update`: the shell may have written `done`, `completedAt`, `snoozedUntil`,
`snoozes`, `lastDoneAt` or `doneThrough` since the page last read (NOTIFICATIONS.md 4.5). A patch
with only the page's changed fields keeps them. When `at` changes, the page removes
`snoozedUntil`, `snoozes` and `doneThrough` in the same patch, as the Reminders page does.

### 3.4 Repeats

- A repeating task is one repeating `reminder:` record; its early alerts are booked for the next
  occurrence only, after now and after `doneThrough` (`ReminderExpansion.targetOccurrence`).
- An alert that falls before midnight of the task's day (a 00:10 task with a 15-minute alert) is
  computed by the engine from each occurrence; nothing shifts in the record.
- How the engine books the task itself (NOTIFICATIONS.md 6.3): interval 1 with no `until` is one
  iOS repeating notification per trigger (weekly on 5 weekdays is 5); every other repeat is booked
  occurrence by occurrence and competes for the 48 like one-time tasks. Early alerts are one-time
  bookings.

### 3.5 Done and Snooze from the notification

The shell writes into the task's record (`RecordWriter.swift`, `ReminderActions.swift`), the same
change every writer makes (NOTIFICATIONS.md 4.5):

| Button | Shell writes | What the page does on next open |
|---|---|---|
| Done, one-time task (its own notification or an early alert) | `done: true`, `completedAt` = now; `snoozedUntil` and the alerts' `snoozes` removed | Shows the task done; sets `doneDay` to the local day of `completedAt`. Every notification of the task has stopped. |
| Done, repeating task | `lastDoneAt` = now, `doneThrough` = the occurrence; the repeat carries on | Writes `exception:<taskId>:<date>` with `done: true` for the occurrence `doneThrough` names, if it is not there yet. |
| Snooze 10 min, 1 hour, until tomorrow | `snoozedUntil` (the task's own notification) or `snoozes["~<rule>"]` (an early alert's) | Nothing. A snooze does not change the task. |

When the person ticks an occurrence in the page, the page writes the exception and the same Done
change (`lastDoneAt` now, `doneThrough` that occurrence, never earlier than the stored one).

Facts that follow from the engine as built:
- `doneThrough` moves a repeat's early alerts to the next occurrence. The task's own repeating
  notification still fires on every occurrence: `ReminderPlanner` does not read `doneThrough`
  (concern 3 of `2026-10-11-reminders-and-widgets.md`).
- A tap on the notification opens the Sidekick (NOTIFICATIONS.md 5).

### 3.6 Exceptions and notifications

The `reminder:` repeat has no per-occurrence exceptions (`ReminderRecord.swift`: `every`,
`interval`, `weekdays`, `until` only), and every `reminder:` record is a task, so a series cannot be
split into extra records without showing extra tasks. With the format as it is:

- A skipped occurrence still notifies at the series time.
- A moved occurrence notifies at the series time, not at its new time.
- A done occurrence: see 3.5.

`shell/repeat-exceptions.md` holds the shell alternative. Section 12 lists this as not mapped.

### 3.7 Cost against the shared iOS slots

Facts (NOTIFICATIONS.md 6.2): iOS holds 64 pending notifications per app. Midas books at most 48
for reminders, soonest first, across every Sidekick, and keeps 16 for snoozes. Past the 48, Midas
keeps its own queue and tops up when it runs.

| Planner use | Slots |
|---|---|
| One-time task, start notification plus 2 early alerts | 3 while among the soonest 48 |
| 48 / 3 | 16 such tasks fill the whole batch, for every Sidekick together |
| Daily task, start notification, interval 1, no `until` | 1, held for as long as it repeats |
| Daily task, plus 2 early alerts | 1, plus 2 one-time bookings for the next occurrence |
| Weekday task (5 weekdays), start notification | 5 |
| 10 daily routines with 2 early alerts | 10 held, plus 20 for the next occurrences, leaving 18 for everything else in Midas |
| Plan and review prompts, daily | 2 |

Known limit (NOTIFICATIONS.md 7): if Midas does not run for long enough, notifications past the
booked batch fire late, once each, as "missed". Interval-1 repeats are not affected. The engine
ties are broken by Sidekick id, then reminder id.

### 3.8 Time zones and daylight saving, as the engine works today

| Case | Behaviour | Source |
|---|---|---|
| One-time `reminder:` | Fires at the exact instant `at`, wherever the phone is. Booked with UTC date components. | NOTIFICATIONS.md 4.4; `NotificationBooking.trigger` |
| Repeating `reminder:` | Each occurrence keeps the wall-clock time of `at` read in `timeZone`, computed in the phone's current zone. | `ReminderSchedule.anchor`, `wallClockDate` |
| Repeat booked as an iOS repeating trigger | iOS fires it at that wall-clock time in whatever zone the phone is in. | `NotificationBooking.trigger` (`.repeating`) |
| Repeat booked occurrence by occurrence | Booked as exact instants. After the phone changes zone, the old instants stay booked until the engine runs again (app opened or brought forward, a record written, a notification acted on, background refresh at most hourly). The shell has no time-zone-change observer. | NOTIFICATIONS.md 6.1; `ShellServices.swift` |
| Time skipped by a DST jump (02:30 on spring-forward night) | Moves to the first valid moment after it. | NOTIFICATIONS.md 4.4; `wallClockDate` |
| Time repeated by a DST fall-back | iOS repeating triggers: the first of the two (`repeatedTimePolicy: .first`). Occurrence-by-occurrence bookings: as `Calendar.date(from:)` gives [U]. | `ReminderSchedule.nextNativeFire` |
| A pinned repeating task (`zone` set) | Cannot be pinned by the engine: repeats always follow the phone's zone. Section 12. | `ReminderSchedule` |

For a floating one-time task (checklist 28), `at` written at home fires at the home instant after
travel, until the page opens and rewrites `at` and `timeZone` to keep the wall-clock time.
`shell/local-time-alerts.md` covers this.

The page computes a task's `at` from the day and start read in the phone's zone (floating) or in
`zone` (pinned), the way the Reminders page does (`wallClockToInstant`). JavaScript also moves a
skipped DST time forward, so the day view and the engine agree (checklist 31).

## 4. `settings:self`

One record of type `planner.settings`. Key: `settings:self` (as the Reminders Sidekick keeps its
settings).

| Field | Type | Default | Tag | Meaning |
|---|---|---|---|---|
| `clock` | `"system"`, `"12"`, `"24"` | `"system"` | core | Clock format (checklist 16). `"system"` follows `Intl` in the page. |
| `weekStart` | 0 to 6 | absent | core | First day of the week (checklist 17). Absent: the page uses the locale's first day (`Intl.Locale` week info, where the WebKit build has it [U]), else Monday. The iOS setting itself is not exposed to the page [U]. |
| `dayStartsAt` | `HH:MM`, `"00:00"` to `"06:00"` | `"00:00"` | core | When "today" begins for night owls (checklist 27). A task starting before it shows on the previous planner day; its `at` stays on the calendar day. |
| `wake` | `HH:MM` | `"07:00"` | core | Wake time (DP-SET-01, DP-SET-02). |
| `sleep` | `HH:MM` | `"23:00"` | core | Bedtime. |
| `defaultDuration` | minutes | `15` | core | Duration of a new task (checklist 9). |
| `durationPresets` | array of minutes | `[1, 15, 30, 45, 60, 90]` | core | Duration chips in the add sheet (DP-ADD-02). |
| `defaultAlerts` | as the task's `alerts` | `[]` (start notification only) | core | Early alerts of a new task. Structured's default is "at start" plus "at end"; the end alert is not mapped (section 12). |
| `allDayAlertTime` | `HH:MM` | `"08:00"` | core | The time of an all-day task's `at`, so its notification time (Structured's default). |
| `neverSuggest` | array of strings | `[]` | on request | Titles the person removed from suggestions (DP-ADD-08). |
| `layout` | `"full"`, `"simplified"`, `"minimal"` | `"full"` | on request | Density mode (DP-SET-04). |
| `theme` | `"system"`, `"light"`, `"dark"` | `"system"` | on request | DP-SET-05. |
| `accent` | string `#RRGGBB` | absent | on request | App accent (DP-SET-05); does not recolour tasks. Absent: the default accent. Token names live in `recipe.md`. |
| `font` | `"system"`, or a font name the page ships | `"system"` | on request | DP-SET-05 (for example a dyslexia-friendly font). |
| `sound` | boolean | `true` | on request | Completion sound in the page (DP-FB-01). It does not change notification sounds: the engine plays the default sound only (NOTIFICATIONS.md 5). A page has no haptics API. |
| `confetti` | boolean | `false` | on request | DP-FB-01. |
| `energyLimit` | number | absent | core | Daily energy points before "over capacity" (DP-TIME-06 energy ring, checklist 52). Absent: no limit. |
| `planPrompt` | `{ on: boolean, time: "HH:MM" }` | `{ on: false, time: "08:00" }` | on request | DP-OUT-06. Written as `reminder:plan`, daily. |
| `reviewPrompt` | `{ on: boolean, time: "HH:MM" }` | `{ on: false, time: "20:00" }` | on request | DP-OUT-06. Written as `reminder:review`, daily. |
| `calendars` | array of calendar ids | `[]` | core | Ids of the calendars shown (DP-SET-06). Used only if `shell/calendar-access.md` is built. |
| `onboarded` | boolean | `false` | core | DP-SET-01 ran. |

A missing field takes its default. The page changes a setting with `store.update('settings:self', patch)`.

## 5. `exception:<taskId>:<date>`

One occurrence of a repeating task that differs from the series, type `planner.exception`.
`<date>` is the occurrence's original day, `YYYY-MM-DD`. Example: `exception:r7u1hh30ad:2026-10-14`.

All of one task's exceptions: `store.query('exception:' + taskId + ':')`.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `taskId` | string | yes | The series (the id in `reminder:<id>`). |
| `date` | `YYYY-MM-DD` | yes | The original day (same as in the key). |
| `skip` | boolean | no | `true`: this occurrence is deleted. |
| `done` | boolean | no | This occurrence is done. |
| `completedAt` | ISO 8601 instant | no | When. |
| `doneDay` | `YYYY-MM-DD` | no | The local day it was done (checklist 23). |
| `at`, `duration`, `allDay` | as the task | no | This occurrence moved or resized. |
| `title`, `colour`, `icon`, `notes`, `subtasks`, `alerts`, `energy` | as the task | no | This occurrence edited (checklist 32). |

A field present overrides the series for that occurrence; a field absent follows the series. An
exception is about 150 bytes. The engine does not read `exception:` records.

- **A done occurrence** is `exception:<taskId>:<date>` `{ done: true, completedAt, doneDay }`.
- **Subtasks of a repeating task:** the series' `subtasks` is the list each occurrence starts
  with, all not done. Ticking a subtask of one occurrence writes that occurrence's whole
  `subtasks` array into its exception. Other occurrences are not changed.
- **How a done, skipped or moved occurrence reaches the notifications:** 3.5 and 3.6.

Edit spans (checklist 32 to 34):
- **This one:** write or update the exception.
- **This and future:** set the old task's `repeat.until` to the end of the day before, create a new
  `reminder:` task from that day with the new fields, and move later exceptions to the new task id.
  Past occurrences keep the old fields (checklist 33). This mirrors the engine: `until` ends the old
  series; a new record starts the new one.
- **All:** rewrite the task. Exceptions stay. The page keeps the previous value for Undo
  (checklist 34).

Deleting a series deletes its exceptions and the task.

## 6. `preset:<id>`

Tag: on request (DP-ADD-08, Llama Life presets). Type `planner.preset`. A saved task the person
can drop into a day. Key `preset:<id>`, `<id>` 10 characters from `a-z0-9`. All presets:
`store.query('preset:')`.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `name` | string, 1 to 80 characters | yes | The preset's name in the list. |
| `tasks` | array of task templates, at most 50 | yes | Each: `title`, `colour`, `duration`, and optional `icon`, `alerts`, `offset` (minutes after the preset's start time), `notes`, `subtasks`, `energy`. No `at`, `done` or `repeat`. |
| `order` | number | no | Order in the preset list. |

Applying a preset writes one new `reminder:` task per template with `source: { kind: "preset" }`.
A preset notifies nobody itself; its tasks do, as any task. A template is about 150 bytes without
notes or subtasks, so 50 plain templates are about 7.5 KB. Templates with long notes and subtasks
can pass 64 KB; the page checks the size as in 2.5 and refuses to save above 64,000 bytes.

## 7. `day:<YYYY-MM-DD>`

Tag: on request (DP-DAY-07, the day as a text note). Type `planner.day`. One record per day that
has a note. Key `day:2026-10-12`; a month's notes: `store.query('day:2026-10')`, since keys sort by
date.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `note` | string, at most 30,000 characters | yes | The day's text. |
| `updatedAt` | ISO 8601 instant | yes | Display only. |

Shape chosen here: one record per day, the note as plain text, the key's day as the calendar day
(not the planner day of `dayStartsAt`). An empty note deletes the record.

## 8. What has no record

Decided in the block files:
- **No timer record.** The focus timer is computed from the task's `at` and `duration`
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

The store has no transactions. A task and its notifications are one record, so most actions are
one write. When one action touches several records, the page writes in an order that leaves no
exception without its task if it stops halfway:

1. Write the `reminder:` task.
2. Write or delete its `exception:` records.

Deleting a task goes the other way: its exceptions first, then the task. On every open, the page
deletes `exception:` records whose task no longer exists.

## 11. The manifest `types` block

Every prefix above is declared in the planner's `manifest.json` under `types`, one JSON Schema
each, as `sidekicks/reminders/manifest.json` does. The `reminder:` schema reuses the Reminders
Sidekick's definitions of the engine fields (`$defs.instant`, `$defs.repeat`) and care-reminders'
alert rule (`$defs.alert`); the planner's own fields follow 2.1.

| Prefix | `$type` | Required | Formats |
|---|---|---|---|
| `reminder:` | `planner.item` | `title` (the page writes every field 2.1 marks required on a task; the plan and review prompts hold only `title`, `at`, `timeZone` and `repeat`) | `at`, `completedAt`, `snoozedUntil`, `lastDoneAt`, `doneThrough`, `intervalsStartedAt`, `createdAt`, `updatedAt`: `date-time`; `timeZone`, `zone`: `time-zone`; `deadline`, `doneDay`: `date` |
| `exception:` | `planner.exception` | `taskId`, `date` | `date`, `doneDay`: `date`; `at`, `completedAt`: `date-time` |
| `settings:` | `planner.settings` | none | `dayStartsAt`, `wake`, `sleep`, `allDayAlertTime`, `planPrompt.time`, `reviewPrompt.time`: `wall-time` |
| `preset:` | `planner.preset` | `name`, `tasks` | none |
| `day:` | `planner.day` | `note`, `updatedAt` | `updatedAt`: `date-time` |

Every schema has `"type": "object"` and `"$type": { "type": "string" }` among its properties, and
every text field a `maxLength` (2.1 limits). No two prefixes share a start.

## 12. Not mapped to the current format

What the planner had before 2026-10-23 that the current `reminder:` record cannot hold. Listed, not
designed; each needs a founder decision or a shell change.

| What | Why it does not map |
|---|---|
| Alerts measured from the end of a task ("at end", "5 min before end"; Structured's default includes "at end") | Early alert rules are `before`, `morningOf` and `daysBefore`, all measured back from `at` (`ReminderExpansion.alertMoment`). Nothing is measured from `at` plus `duration`. |
| A dated task with no "at start" notification (only early alerts, or none) | A `reminder:` record with `at` always notifies at `at` (NOTIFICATIONS.md 4.2). There is no field to keep a dated task silent. |
| Notification text with the task's times ("9:30–11:00 AM" under the title of the start notification) | The text line is `notes`, the person's own text. An early alert's `text` can carry `{time}` (the start time, phone locale), not the end time, and only for early alerts. |
| Clock format of notification times (`settings:self.clock`) | The engine formats `{time}` with the phone's locale. |
| A draft with an empty title | The shell refuses a `reminder:` record whose title is empty. |
| A skipped or moved occurrence's notification (the old series split) | 3.6: the repeat has no exceptions, and extra `reminder:` records would be extra tasks. |
| A pinned repeating task (`zone` set) | Repeats follow the phone's zone (3.8). The old 14-day one-time records would be extra tasks. |
