# Notifications in Midas: how the system works and how a Sidekick uses it

State as of 2026-10-24 (notification levels and layout A, `docs/briefs/notification-levels.md`;
unified data rework 2026-10-15, midas-intel `docs/plans/2026-10-15-unified-data-v2.md`).
This is the reference for anyone building a Sidekick, by hand or with the generator, that needs to
notify its user. It is not specific to the reminders Sidekick: every Sidekick uses the same
mechanism and shares the same budget.

Since 2026-10-15 every record has a type: the Sidekick's `manifest.json` declares one JSON Schema
per key prefix under `types`, every record carries `$type`, and the shell and the server check a
write against that schema (one validator, `shell/sdk/record-schema.js`). The `reminder:` fields
below are what the engine reads; the Sidekick's own schema says what else the record holds.

What else iOS offers (subtitles, images, sounds, badges, buttons, Time Sensitive, Live
Activities, AlarmKit alarms, widgets, controls), with each option's status in Midas, limits,
mockups and sources: midas-intel `docs/research/ios-notifications-reference.md` (checked
2026-10-09 against iOS 26 and 27). Nothing there is decided for Midas until the founder says so.

## 1. The short version

A Sidekick never schedules a notification. It writes a record:

```js
await store.set('reminder:dentist', {
  at: '2026-10-12T16:30:00.000Z',
  title: 'Dentist',
  notes: 'Bring the insurance card',
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
| Record format | `shell/Midas/ReminderRecord.swift` | Parses `reminder:` records for the engine; the shell's own check (`at`, when present, is a date; `title` non-empty; a well-formed `repeat`). |
| Expansion | `shell/Midas/ReminderExpansion.swift` | Turns one record into every notification it stands for: its own time, its hourly times (`everyHours`), its early alerts (`alerts`), under the ids `<id>@HHMM` and `<id>~<rule>`. |
| Writer | `shell/Midas/RecordWriter.swift` | The one way the shell changes a record: read, merge the patch (RFC 7396), check the type, write. `ReminderChange` holds the Done and Snooze patches every writer uses. |
| Calendar math | `shell/Midas/ReminderSchedule.swift` | Occurrences of repeats; which repeats iOS can repeat by itself. |
| Planner | `shell/Midas/ReminderPlanner.swift` | Pure: from all reminders and the time, decides what iOS should hold. |
| Engine | `shell/Midas/NotificationEngine.swift` | Runs the planner, applies only the difference to iOS, remembers state in `Application Support/midas-notification-engine.json`. |
| iOS adapter | `shell/Midas/NotificationBooking.swift` | Content (title, subtitle, body, level), triggers, permission, buttons. |
| Alarm adapter | `shell/Midas/AlarmBooking.swift` | AlarmKit (iOS 26 and later): permission, alarms, Stop and Snooze, alarm ids. |
| Alarm buttons and countdown card | `shell/Shared/AlarmReminderShared.swift`, `shell/MidasWidgets/AlarmCountdownActivity.swift` | Snooze, Done and Stop intents (run in the app); the L7 Live Activity. |
| Buttons | `shell/Midas/ReminderActions.swift` | Done and Snooze, and how each changes the record. |
| Launch, delegate, background refresh, tap to open | `shell/Midas/ShellServices.swift`, `MidasApp.swift` | Wiring. |
| Sidekick helper | `shell/sdk/midas-store.js` | `store.set / get / query / delete` for the Sidekick to paste in. |

## 4. Using it from a Sidekick

### 4.1 Add the helper

Paste `shell/sdk/midas-store.js` into the Sidekick's inline script. Its hash goes into the deploy
like any other script (CSP `script-src`). It defines a global `store`:

| Call | Returns |
|---|---|
| `await store.set(key, value)` | nothing; rejects with the reason if the value does not fit its type (or the shell's reminder check) |
| `await store.get(key)` | the value, or `null` |
| `await store.update(key, patch)` | the record as stored after a JSON Merge Patch (a field set to `null` is removed, an object merged, anything else replaced) |
| `await store.query(prefix)` | `[{ key, value }]`, sorted by key |
| `await store.delete(key)` | nothing |
| `await store.putFile(blob)` | `"file:<id>"`, to put in a record (up to 20 MB; the shell sends the file before the record) |
| `await store.fileUrl(ref)` | a `blob:` URL for the file's bytes (`img-src blob:` is allowed) |

The store is for all of a Sidekick's data, not just notifications. Each Sidekick sees only its
own records. Keys are `type:id`; one type per prefix, declared in the manifest's `types`. A record
holds at most 64 KB; a `data:` URL that pushes a record over the limit is moved to a file by the
shell and the field keeps the reference. Leave a field out instead of writing `null`.

### 4.2 The `reminder:` record

Key: `reminder:<id>`, where `<id>` is anything stable the Sidekick chooses. One record is one
notification, or one repeating series of notifications.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `$type` | string | stamped by the shell | The record's type from the manifest (`reminders.item`, `care.item`). |
| `at` | ISO 8601 string with an offset (as `Date.toISOString()` gives) | no | When it fires. For a repeat, the first occurrence. Without `at` the record is an undated item and notifies nobody. |
| `title` | non-empty string | yes | Notification title. |
| `notes` | string | no | Notification text, in the body after the time on every notification the item makes (its own, snoozes, early alerts, hourly times); see 5. |
| `repeat` | object, see 4.3 | no | Makes it a repeating series. |
| `timeZone` | IANA name, e.g. `"America/New_York"` | no, recommended for repeats | The zone `at` was meant in; see 4.4. Use `Intl.DateTimeFormat().resolvedOptions().timeZone`. |
| `done` | boolean | no | `true` stops all notifications for this record. |
| `completedAt` | date string | no | When a one-time item was done (written with `done`). |
| `snoozedUntil` | date string | no | Written by the shell (Snooze button on the item's own notification); removed by Done. A Sidekick may set it to offer its own snooze. |
| `snoozes` | object, `"~<rule>"` or `"@HHMM"` to date string | no | Written by the shell: Snooze on an early alert's or an hourly time's notification, each its own entry, independent of the others and of `snoozedUntil`; the snoozed notification comes back with that alert's or time's own wording. Done on the event removes the alerts' entries; Done on an hourly time removes that time's. |
| `lastDoneAt` | date string | no | When Done was last tapped on a repeat (any writer), written together with `doneThrough`. |
| `doneThrough` | date string | no | The occurrence through which a repeat is done; Done writes the occurrence it was for. |
| `alerts` | list of rules | no | Early alerts the engine books before the reminder, one notification each: `{ id, kind: "daysBefore", days, time }`, `{ id, kind: "morningOf", time }`, `{ id, kind: "before", minutes }`, each with an optional `text` (`{title}`, `{time}`, `{day}`). For a repeat, the next occurrence's alerts only. Done on an alert completes the event. |
| `everyHours` | 2, 3 or 4 | no | With `repeat: { every: "day" }`: fires every N hours around the clock from `at`'s time. The engine books each time; Done on one writes `slotsDone`. No early alerts. |
| `slotsDone` | `{ "HH:MM": date string }` | no | Written by the shell when Done is tapped on one of an hourly item's times. |
| `reminderType` | `"normal"`, `"timeSensitive"` or `"alarm"` | no; absent is `"timeSensitive"` | How loudly a timed item reaches its person (founder, 2026-10-24; not the record's `$type`). Normal: an Active notification, held by Focus and the Scheduled Summary. Time Sensitive: through Focus and the summary. Alarm: an AlarmKit alarm (iOS 26 and later) that rings through Silent and every Focus; declined, or an older iOS, it is a Time Sensitive notification. Records saved before the field existed are Time Sensitive. Every notification the item makes has its level, except an Alarm's early alerts and missed notice, which are Time Sensitive notifications. See 5. |
| anything else | any JSON | no | Kept as is by every writer. A Sidekick's own fields (list, colour) live in the same record, checked by the Sidekick's schema. |

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
// laundry.snoozedUntil           → user snoozed; the notification comes back then
// standup.doneThrough            → user tapped Done on a repeat: the occurrence it was for
```

`set` writes the whole record; `update` changes only the fields in the patch. Read before a `set`
if the user may have acted on the notification since, so `done`, `snoozedUntil`, `lastDoneAt` and
`doneThrough` are not lost. Done is the same change for every writer (page, button, widget):
one-time `{ done: true, completedAt, snoozedUntil removed, the alerts' snoozes removed }`; repeat
`{ lastDoneAt, doneThrough: the occurrence, snoozedUntil removed, the alerts' snoozes removed }`; an
hourly time `{ slotsDone: { "HH:MM": now }, its own snooze removed }`.

### 4.6 Errors

A bad `reminder:` value is refused at write time: `store.set` rejects with the reason and nothing
is stored. From the Sidekick's own schema the reason names the type and field, for example
`reminders.item.title must not be empty`, `care.item.at is required`, `reminders.item.at must be
an ISO 8601 date and time with an offset, like 2026-10-15T09:30:00.000Z`, `no record type is
declared for note:1`. From the shell's own reminder check:

- `reminder must be an object`
- `reminder.at must be an ISO 8601 date` (when `at` is present but not a date)
- `reminder.title must be a non-empty string`
- `reminder.notes must be a string`
- `reminder.done must be true or false`
- `reminder.timeZone is not a known time zone`
- `reminder.snoozedUntil must be a date`
- `reminder.repeat.every must be day, week, month or year`
- `reminder.repeat.interval must be a whole number from 1 to 999`
- `reminder.repeat.weekdays applies to weekly repeats only`
- `reminder.repeat.weekdays must be a non-empty list`
- `reminder.repeat.weekdays holds numbers 0 (Sunday) to 6 (Saturday)`
- `reminder.repeat.until must be a date`
- `reminder.reminderType must be normal, timeSensitive or alarm`

Other store errors: `body is not JSON`, `missing op`, `unknown op <op>`, `missing key`,
`missing value` (status 400), `could not save` (status 500).

## 5. What the user sees

- **Layout A** (founder, 2026-10-24; mockup `docs/mockups/notification-levels-2026-10-24.html`):
  the Midas icon and app name (iOS does not allow a per-Sidekick icon), then the record's `title`,
  then the **subtitle**, the Sidekick's name as on its home tile (the manifest `name` today), then
  the **body**: the time, then the notes, "11:00 PM · Bring the insurance card" (just the time
  without notes). Every notification the item makes has the subtitle and the body: its own,
  snoozes (the time the reminder was for), early alerts, hourly times, missed. Default sound.
  Grouped per Sidekick under Midas. Apple: subtitles "aren't displayed in all cases".
- **Levels** (`reminderType`, 4.2):

  | `reminderType` | What iOS does | Through Focus and the summary | Through Silent |
  |---|---|---|---|
  | `"normal"` | L2 Active notification | no | no |
  | `"timeSensitive"`, or absent | L3 Time Sensitive notification, "Time Sensitive" label | yes | no |
  | `"alarm"` | L5 AlarmKit alarm, full screen, rings until stopped | yes | yes |

  An **Alarm** shows its title on iOS's ringing screen with Stop (drawn by iOS) and **Snooze**.
  Snooze starts **L7, the countdown card**: a Live Activity (`shell/MidasWidgets/AlarmCountdownActivity.swift`)
  on the Lock Screen and in the Dynamic Island with the title, "Reminders · rings again at 11:09
  PM", the time left, **Done** and **Stop**; it rings again 9 minutes after Snooze. Done is the
  notification's Done; Snooze writes `snoozedUntil` (or the time's own `snoozes` entry) 9 minutes
  out, as the notification's Snooze does; Stop ends the alarm or the card and removes that
  pending snooze, nothing else. Changing the record from the page (Done, a new time, another
  level) ends a countdown whose snooze is gone.
  AlarmKit is asked for once, the first time an Alarm reminder needs booking. If the person
  turns Time Sensitive off for Midas in iOS Settings, those arrive as Active; Midas shows nothing.
- **Buttons** (long-press or pull down on the notification), the same for every Sidekick:

  | Button | Effect on the record |
  |---|---|
  | Done | one-time: `done: true`, `completedAt`, the item's snooze and the alerts' snoozes removed. Repeat: `lastDoneAt` now and `doneThrough` the occurrence; the repeat carries on. On an early alert: the same, for the event the alert was for. On an hourly time: `slotsDone["HH:MM"]` and that time's own snooze removed. |
  | Snooze 10 min | now + 10 minutes, into `snoozedUntil` (the item's notification) or `snoozes["~rule"]` / `snoozes["@HHMM"]` (an early alert's or hourly time's) |
  | Snooze 1 hour | now + 1 hour, the same way |
  | Snooze until tomorrow | 9:00 the next morning, phone time, the same way |

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
- **Records are backed up to the server** (since 2026-10-10) and checked against the Sidekick's
  schemas there too (since 2026-10-15). A write the server refuses stays on the phone and in the
  outbox, is tried again on every sync, and the home screen says "N changes not backed up".
- **Cross-Sidekick reading is not local.** The calendar cannot read the reminders Sidekick's
  local records; cross-app read with consent (D7) is a backend feature.
- **Built, fixed for every Sidekick:** the default sound, grouping in Notification Center by
  Sidekick (`threadIdentifier` = Sidekick id), and badge permission (asked with alert and sound).
- **Snooze on an early alert or an hourly time** snoozes that notification only (its own entry in
  `snoozes`), and it comes back with its own wording ("Dentist tomorrow at 1:00 PM", not the item's
  title); several can be pending at once, next to the item's own `snoozedUntil` (founder,
  2026-10-15). A snoozed
  alert that already fired is booked at the snooze time as its own moment.
- **Alarms (since 2026-10-24)** are AlarmKit alarms, not notifications: they do not count against
  the 48 bookings or the 16 reserved. AlarmKit repeats only never or weekly: a daily repeat, or a
  weekly one on chosen weekdays, with interval 1 and no `until`, rings from AlarmKit's own
  schedule (one alarm per weekday, one for daily) and keeps ringing without Midas; every other
  repeat (every N days or weeks, monthly, yearly, `until`) and every one-time alarm is booked as
  one alarm for its next occurrence and re-booked on each engine run. If Midas does not run
  before the one after, that one fires as a Time Sensitive missed notification. Each alarm's
  AlarmKit id is derived from its booking identifier (6.4). A side-button press stops every
  ringing alarm (iOS).
- **Not built:** nag until done, L1 Passive, L4 Critical, layout F (Sidekick tile as a picture), a
  level picker in Care, per-Sidekick buttons,
  custom snooze lengths, custom sounds, images, a badge count, repeat after completion,
  notifications for other members of a shared group (server push, build 2).
- **No remote push exists yet** (2026-10-24). It is being built with Make (founder, 2026-10-23 and
  24; `docs/briefs/make.md`): to the person only for a question card and for "built", to the founder
  for every Make message; repair's "Your app has been repaired." (app closed) follows on the same
  push. Everything above is local notifications only.

## 8. Tests

Run everything with `scripts/test-all.sh`. The notification system's tests, in
`shell/MidasTests/`:

| File | Proves |
|---|---|
| `LocalChannelWebViewTests` | A real fetch POST from a page reaches the shell and is stored (including a 200 KB body); one Sidekick cannot reach another's store; the CSP adds only the Sidekick's own origin. |
| `MidasStoreScriptTests` | `midas-store.js` under the real CSP: set, get, query, delete; a bad reminder is rejected with its reason. |
| `SidekickStoreChannelTests`, `LocalRecordStoreTests` | Store operations, isolation per Sidekick, persistence, bad requests. |
| `ReminderRecordTests` | Date forms, defaults, every validation error; an undated item is accepted and is not a notification. |
| `ReminderExpansionTests`, `CareRemindersFieldsTests` | Early alerts and hourly times from the item's fields: moments, wording, the notification ids `<id>~<rule>` and `<id>@HHMM`, Done on an alert or a time landing on the item. |
| `RecordWriterTests`, `DoneConformanceTests` | One writer for every native change; the page's Done and the native Done give the same record. |
| `RecordSchemaEngineTests`, `RecordTypeGateTests` | The manifest schemas, run in JavaScriptCore, on every write. |
| `ReminderScheduleTests` | Daily, weekdays, every N weeks, monthly on the 31st, yearly on Feb 29, `until`, daylight saving in LA and NY, wall-clock time after a move. |
| `ReminderPlannerTests` | 48 of 100 booked, stable ties, edits and deletes, repeating triggers, missed exactly once, snooze from the reserve, never more than 64. |
| `NotificationEngineTests` | Against a fake iOS: top-up after delivery, no re-booking when nothing changed, foreign notifications left alone, denied permission, state across a relaunch, Done and Snooze, booking on a Sidekick write. |
| `UserNotificationBookingTests` | Exact-moment, repeating and immediate triggers; content, buttons and owner. |
| `BackgroundRefreshConfigTests` | The Info.plist permits the refresh task and background fetch. |
| `NotificationLevelsTests` | `reminderType` read and checked; levels per type; subtitle and "time · notes" body on every notification an item makes; alarms outside the 48, AlarmKit schedules for daily and weekly, one alarm at a time for other repeats; Time Sensitive fallback (declined, no AlarmKit) and missed notices; Snooze, Done and Stop on an alarm and its countdown; old engine state still loads; NSAlarmKitUsageDescription, Live Activities and the Time Sensitive entitlement. |

Not yet checked on a real phone: a reminder two minutes ahead firing with Midas in the
background, and deleting it beforehand cancelling it (D8's done-when). It needs a Sidekick page
that writes reminders and a way for the shell to load it (D5).
