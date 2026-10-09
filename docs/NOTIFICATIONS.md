# Notifications in Midas: how the system works and how a Sidekick uses it

State as of 2026-10-08 (branch `agent/notification-engine`). This is the reference for anyone
building a Sidekick, by hand or with the generator, that needs to notify its user. It is not
specific to the reminders Sidekick: every Sidekick uses the same mechanism and shares the same
budget.

## 1. The short version

A Sidekick never schedules a notification. It writes a record:

```js
await store.set('reminder:dentist', {
  at: '2026-10-12T16:30:00.000Z',
  title: 'Dentist',
  body: 'Bring the insurance card',
});
```

The Midas shell sees the record and makes sure iOS notifies the user at that moment. Editing the
record moves the notification; deleting it cancels it. The user's taps on the notification
(Done, Snooze) are written back into the same record.

## 2. Why it works this way

- **No bridge (guideline 4.7.2).** A Sidekick is an HTML/JS page in a WKWebView with no native
  API: no script message handlers, no injected scripts. Native features are reached by *request
  records* that the shell reads and acts on.
- **iOS fires notifications, not the app.** iOS suspends apps in the background, so a
  notification must be booked with iOS ahead of time.
- **iOS keeps at most 64 scheduled notifications per app** and silently drops the rest. Midas is
  one app, so **all Sidekicks share those 64.** A user will have more than 64 upcoming
  reminders, so Midas keeps its own unlimited queue and books only the soonest batch with iOS
  (decided 2026-10-07).
- **Offline first.** Sidekicks must work without a connection (decided 2026-10-08), so records
  live on the phone and the whole system runs on the phone.
- **Permission belongs to the shell.** It is asked once, for Midas, never by a Sidekick.

## 3. The pieces

```
Sidekick page (sidekick://<id>/)
   │  fetch POST  sidekick://<id>/_midas/store      (plain fetch, same origin)
   ▼
SidekickSchemeHandler ──► SidekickStoreChannel ──► LocalRecordStore (JSON file on the phone)
                              │ validates reminder:                 │ change observer
                              ▼                                     ▼
                         400 + reason                     NotificationEngine
                                                            │ ReminderPlanner (pure)
                                                            ▼
                                                  UNUserNotificationCenter (iOS)
```

| Piece | File | Job |
|---|---|---|
| Local channel | `shell/Midas/SidekickStoreChannel.swift`, `SidekickSchemeHandler.swift` | Answers `POST sidekick://<id>/_midas/store`. The Sidekick id comes from the origin, never the body. |
| CSP | `shell/Midas/SidekickContentSecurityPolicy.swift` | `connect-src` allows the platform origin and the Sidekick's **own** origin only, so a Sidekick cannot reach another Sidekick's store. |
| Local store | `shell/Midas/LocalRecordStore.swift` | Records per Sidekick, saved as `Application Support/midas-local-records.json`. |
| Record format | `shell/Midas/ReminderRecord.swift` | Parses and validates `reminder:` records. |
| Calendar math | `shell/Midas/ReminderSchedule.swift` | Occurrences of repeats; which repeats iOS can repeat by itself. |
| Planner | `shell/Midas/ReminderPlanner.swift` | Pure: from all reminders and the time, decides what iOS should hold. |
| Engine | `shell/Midas/NotificationEngine.swift` | Runs the planner, applies only the difference to iOS, remembers state in `Application Support/midas-notification-engine.json`. |
| iOS adapter | `shell/Midas/NotificationBooking.swift` | Content, triggers, permission, buttons. |
| Buttons | `shell/Midas/ReminderActions.swift` | Done and Snooze, and how each changes the record. |
| Launch, delegate, background refresh, tap to open | `shell/Midas/ShellServices.swift`, `MidasApp.swift` | Wiring. |
| Sidekick helper | `shell/sdk/midas-store.js` | `store.set / get / query / delete` for the Sidekick to paste in. |

## 4. Using it from a Sidekick

### 4.1 Add the helper

Paste `shell/sdk/midas-store.js` into the Sidekick's inline script. Its hash goes into the deploy
like any other script (CSP `script-src`). It defines a global `store`:

| Call | Returns |
|---|---|
| `await store.set(key, value)` | nothing; rejects with the reason if the shell refuses the value |
| `await store.get(key)` | the value, or `null` |
| `await store.query(prefix)` | `[{ key, value }]`, sorted by key |
| `await store.delete(key)` | nothing |

The store is for all of a Sidekick's data, not just notifications. Each Sidekick sees only its
own records. Keys are `type:id`.

### 4.2 The `reminder:` record

Key: `reminder:<id>`, where `<id>` is anything stable the Sidekick chooses. One record is one
notification, or one repeating series of notifications.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `at` | ISO 8601 string (as `Date.toISOString()` gives) or epoch milliseconds | yes | When it fires. For a repeat, the first occurrence. |
| `title` | non-empty string | yes | Notification title. |
| `body` | string | no | Notification text. |
| `repeat` | object, see 4.3 | no | Makes it a repeating series. |
| `timeZone` | IANA name, e.g. `"America/New_York"` | no, recommended for repeats | The zone `at` was meant in; see 4.4. Use `Intl.DateTimeFormat().resolvedOptions().timeZone`. |
| `done` | boolean | no | `true` stops all notifications for this record. |
| `snoozedUntil` | date, as `at` | no | Normally written by the shell (Snooze button). A Sidekick may set it to offer its own snooze. |
| `lastDoneAt` | date string | no | Written by the shell when Done is tapped on a repeat. Informational. |
| anything else | any JSON | no | Kept as is. A Sidekick may store its own fields (list, colour, notes) in the same record; the shell's button writes preserve them. |

### 4.3 Repeats

```js
repeat: { every: 'day' | 'week' | 'month' | 'year',
          interval: 1,             // optional, whole number 1 to 999: every N days/weeks/...
          weekdays: [1, 3, 5],     // optional, weekly only: 0 = Sunday ... 6 = Saturday (Date.getDay())
          until: '2026-12-31T23:59:59.000Z' }   // optional end, inclusive
```

| What the user wants | `repeat` |
|---|---|
| Every day | `{ every: 'day' }` |
| Every other day | `{ every: 'day', interval: 2 }` |
| Weekdays | `{ every: 'week', weekdays: [1, 2, 3, 4, 5] }` |
| Weekends | `{ every: 'week', weekdays: [0, 6] }` |
| Every week (same weekday as `at`) | `{ every: 'week' }` |
| Every two weeks on Tuesday | `{ every: 'week', interval: 2, weekdays: [2] }` |
| Every month (same day of month as `at`) | `{ every: 'month' }` |
| Every 3 months | `{ every: 'month', interval: 3 }` |
| Every year (birthdays) | `{ every: 'year' }` |

Rules:
- Every occurrence keeps the wall-clock time of `at` (see 4.4).
- A monthly repeat on a day some months lack (the 31st) **skips** those months. A yearly repeat
  on February 29 fires in leap years only. This matches iOS's own repeating notifications.
- Weekly "every N weeks" counts weeks (Sunday to Saturday) from the week of `at`.

### 4.4 Time and time zones

- **One-time reminder: an exact moment.** `at` is an instant. It fires at that instant wherever
  the phone is: 9:00 in New York is 6:00 in Los Angeles.
- **Repeat: a wall-clock time.** "Every day at 9:00" fires at 9:00 local time wherever the phone
  is, including after moving between coasts and across daylight-saving changes. The wall-clock
  time is `at` read in `timeZone` (the phone's zone if `timeZone` is absent). Write `timeZone`
  with repeats so the time survives the phone changing zones between writing and first firing.
- A time skipped by a daylight-saving jump (2:30 on the spring-forward night) moves to the first
  valid moment after it.

### 4.5 Examples

```js
// One-time, in two hours
await store.set('reminder:laundry', {
  at: new Date(Date.now() + 2 * 3600 * 1000).toISOString(),
  title: 'Move the laundry',
});

// Every weekday at 8:30, local time
const firstMorning = new Date(); firstMorning.setHours(8, 30, 0, 0);
await store.set('reminder:standup', {
  at: firstMorning.toISOString(),
  title: 'Standup',
  repeat: { every: 'week', weekdays: [1, 2, 3, 4, 5] },
  timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
});

// Birthday every year at 9:00
await store.set('reminder:birthday-sam', {
  at: '2027-03-14T09:00:00-07:00',
  title: "Sam's birthday",
  repeat: { every: 'year' },
  timeZone: 'America/Los_Angeles',
});

// Edit: write the whole record again under the same key
const standup = await store.get('reminder:standup');
standup.title = 'Standup (moved room)';
await store.set('reminder:standup', standup);

// Stop it without deleting it
standup.done = true;
await store.set('reminder:standup', standup);

// Cancel
await store.delete('reminder:laundry');

// What did the user do from the notification? Read the record back.
const laundry = await store.get('reminder:laundry');
// laundry.done === true          → user tapped Done (one-time)
// laundry.lastDoneAt             → user tapped Done on a repeat occurrence
// laundry.snoozedUntil           → user snoozed; the notification comes back then
```

Write the whole record on every `set` (it replaces the stored value). Read before you write if
the user may have acted on the notification since, so `done` and `snoozedUntil` are not lost.

### 4.6 Errors

A bad `reminder:` value is refused at write time: `store.set` rejects with one of these and
nothing is stored.

- `reminder must be an object`
- `reminder.at must be an ISO 8601 date or epoch milliseconds`
- `reminder.title must be a non-empty string`
- `reminder.body must be a string`
- `reminder.done must be true or false`
- `reminder.timeZone is not a known time zone`
- `reminder.snoozedUntil must be a date`
- `reminder.repeat.every must be day, week, month or year`
- `reminder.repeat.interval must be a whole number from 1 to 999`
- `reminder.repeat.weekdays applies to weekly repeats only`
- `reminder.repeat.weekdays must be a non-empty list`
- `reminder.repeat.weekdays holds numbers 0 (Sunday) to 6 (Saturday)`
- `reminder.repeat.until must be a date`

Other store errors: `body is not JSON`, `missing op`, `unknown op <op>`, `missing key`,
`missing value` (status 400), `could not save` (status 500).

## 5. What the user sees

- The notification shows the Midas icon and app name (iOS does not allow a per-Sidekick icon),
  the record's `title` and `body`, and the default sound. Notifications are grouped per
  Sidekick under Midas.
- **Buttons** (long-press or pull down on the notification), the same for every Sidekick:

  | Button | Effect on the record |
  |---|---|
  | Done | one-time: `done: true`, snooze cleared. Repeat: `lastDoneAt` set to now; the repeat carries on. |
  | Snooze 10 min | `snoozedUntil` = now + 10 minutes |
  | Snooze 1 hour | `snoozedUntil` = now + 1 hour |
  | Snooze until tomorrow | `snoozedUntil` = 9:00 the next morning, phone time |

- **Tapping** the notification opens the Sidekick that wrote the record.
- While Midas is open, notifications still appear as banners.
- The first time any Sidekick writes something that needs booking, Midas asks for notification
  permission. If the user refuses, nothing is booked; if they allow it later, reminders whose
  time passed in between fire once, as missed.

## 6. How the engine decides (for anyone changing it)

### 6.1 When it runs
Every run re-plans from scratch and applies only the difference. It runs when:
the app opens or returns to the foreground; any Sidekick writes or deletes a `reminder:` record;
a notification arrives while Midas is open; the user taps a notification or a button;
background refresh (`com.bhuvanrj.midas.reminders-refresh`, asked for at most hourly, run when
iOS decides). Runs never overlap; a run asked for during another runs right after it.

### 6.2 The budget
- At most **48** bookings for reminders, soonest first. Ties are broken by Sidekick id, then
  reminder id, so the plan never flickers.
- **16** slots reserved: snoozes come out of these (at most 16 snoozes booked at once), and they
  are kept for features to come (nag, decided at 7 slots per reminder, not built).
- The engine only touches iOS notifications whose identifier starts with `reminder|`, so other
  features can book their own.

### 6.3 Repeats and slots
- A repeat with interval 1 and no `until` (daily, weekly on chosen weekdays, monthly, yearly)
  becomes an **iOS repeating notification: one slot each** (weekly on 5 weekdays = 5 slots).
  These keep firing even if Midas is never opened again.
- A repeat whose first occurrence is further away than the repeating trigger's next fire is
  booked occurrence by occurrence until it starts, then switches over on the next run.
- Every other repeat (every N days/weeks/months, or with `until`) is booked **occurrence by
  occurrence**, and those occurrences compete for the 48 like one-time reminders.

### 6.4 Identifiers
`reminder|<sidekickId>|<reminderId>|<kind>|<suffix>`, kind one of `occurrence`, `repeating`,
`snooze`, `missed`; suffix is the occurrence time in epoch seconds, or the trigger index for a
repeating trigger. Re-booking an identifier replaces the notification: that is how a title edit
lands. Changing `at` changes the identifier, so the old one is cancelled.

### 6.5 Missed reminders
The engine keeps a ledger: for each reminder, the time through which every occurrence was
delivered by iOS, shown as missed, or predates the reminder. If an occurrence passes without
having been booked (pushed out by the budget, permission off, the phone not running Midas), the
next run fires **one** notification for the latest such occurrence, right away. A new one-time
reminder written with `at` in the past fires once, right away. A new repeat does not report its
past occurrences.

## 7. Limits and known issues

- **The phone must let Midas run.** If Midas is not opened and iOS gives it no background
  refresh for long enough that more than the booked batch comes due, reminders past the batch
  fire only as one "missed" notification each, late. Repeats with interval 1 are not affected
  (iOS repeats them itself). The fix, server push for anything past the phone's booking window,
  is deferred (2026-10-07).
- **Records are on the phone only.** They are not synced to the backend yet, so they do not
  appear on other devices, and deleting the app deletes them.
- **Cross-Sidekick reading is not local.** The calendar cannot read the reminders Sidekick's
  local records; cross-app read with consent (D7) is a backend feature.
- **Not built:** nag until done, alarm levels (Time Sensitive, AlarmKit), per-Sidekick buttons,
  custom snooze lengths, sounds, images, badges, repeat after completion, notifications for other
  members of a shared group (server push, build 2).

## 8. Tests

Run everything with `scripts/test-all.sh`. The notification system's tests, in
`shell/MidasTests/`:

| File | Proves |
|---|---|
| `LocalChannelWebViewTests` | A real fetch POST from a page reaches the shell and is stored (including a 200 KB body); one Sidekick cannot reach another's store; the CSP adds only the Sidekick's own origin. |
| `MidasStoreScriptTests` | `midas-store.js` under the real CSP: set, get, query, delete; a bad reminder is rejected with its reason. |
| `SidekickStoreChannelTests`, `LocalRecordStoreTests` | Store operations, isolation per Sidekick, persistence, bad requests. |
| `ReminderRecordTests` | Date forms, defaults, every validation error. |
| `ReminderScheduleTests` | Daily, weekdays, every N weeks, monthly on the 31st, yearly on Feb 29, `until`, daylight saving in LA and NY, wall-clock time after a move. |
| `ReminderPlannerTests` | 48 of 100 booked, stable ties, edits and deletes, repeating triggers, missed exactly once, snooze from the reserve, never more than 64. |
| `NotificationEngineTests` | Against a fake iOS: top-up after delivery, no re-booking when nothing changed, foreign notifications left alone, denied permission, state across a relaunch, Done and Snooze, booking on a Sidekick write. |
| `UserNotificationBookingTests` | Exact-moment, repeating and immediate triggers; content, buttons and owner. |
| `BackgroundRefreshConfigTests` | The Info.plist permits the refresh task and background fetch. |

Not yet checked on a real phone: a reminder two minutes ahead firing with Midas in the
background, and deleting it beforehand cancelling it (D8's done-when). It needs a Sidekick page
that writes reminders and a way for the shell to load it (D5).
