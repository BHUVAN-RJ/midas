# DO NOT READ: old record formats (retired 2026-10-15)

**Agents: do not open, read, search or load this file into context** unless the developer
explicitly asks for it by name. Nothing here is current. Reading it makes agents write code for
formats that no longer exist. The current format is the unified data format: JSON records with
`$type`, one JSON Schema per record type inside each Sidekick's `manifest.json` (midas
`docs/PRODUCT.md`, "Data format"; `docs/NOTIFICATIONS.md`).

This file holds every description of the record formats used before the unified data rework
(main `18e777c`), kept only for history and for whoever maintains the upgrade-on-read code and the
one-time migration (`backend/scripts/migrate-records.mjs`, `backend/scripts/record-upgrades.mjs`)
until live data is converted.

Founder, 2026-10-20.

## Backend and scripts

(filled by the backend sweep)

## Shell and Sidekick pages

Moved here by the shell and pages sweep (2026-10-20) from `shell/` and `sidekicks/` comments.

### Where code still reads these shapes (upgrade on read, until the live conversion)

| File | What it reads | Marked by |
|---|---|---|
| `shell/Midas/ReminderRecord.swift` `parseDate` | a number as epoch milliseconds | comment "Upgrade on read" |
| `shell/Midas/ReminderRecord.swift` `parseNotes` | `body` as the notification text when `notes` is not a string | comment "Upgrade on read" |
| `sidekicks/reminders/index.html` | `task:<id>` records, `body` as notes, `settings:sidebar`; drops `body` on write | header above `RemindersLogic`, each spot "Upgrade on read" |
| `sidekicks/care-reminders/index.html` | `reminder:<id>~<rule>` and `reminder:<id>@HHMM` records (folded into the item, then deleted); drops `icon`, `alertRules`, `seriesId`, `kind`, `body` on write | header above `CareLogic`, each spot "Upgrade on read" |

### The old reminder record as the shell's comment described it

`reminder:<id>` → `{ at, title, body?, repeat?, timeZone?, done?, snoozedUntil?, lastDoneAt? }`,
`at` an ISO 8601 string **or epoch milliseconds**; `body` the notification text. No `$type`.
Until 2026-10-20 the engine read only `body` (checked as `reminder.body must be a string`), so
after the pages stopped writing `body` (2026-10-15) their notifications had no text line; since
2026-10-20 it reads `notes` (founder).

### Reminders page (before 2026-10-15)

- Undated items lived under `task:<id>`; an item moved between `task:` and `reminder:` when its
  date was set or cleared. The widget tests said "the Sidekick keeps undated ones under task:".
- `body` was written as a copy of `notes`.
- The sidebar settings lived under `settings:sidebar` (now `settings:self`).

### Care-reminders page (before 2026-10-15)

- Each early alert was its own record `reminder:<itemId>~<ruleId>` (`kind: "care-alert"`,
  `at` the alert's moment, own `title` wording, own `done`, own `snoozedUntil`, `occurrenceAt`
  the occurrence it served). Each extra hourly time was its own record
  `reminder:<itemId>@<HHMM>` (`kind: "care-slot"`, `time: "HH:MM"`, a daily repeat, own
  `lastDoneAt`, own `snoozedUntil`). The item itself had `kind: "care-item"` and `body: ""`;
  earlier still, its own `icon`, its own `alertRules`, and a `seriesId` (2026-10-12).
- A reminder moved to a new time lost its alert and time records' snoozes and Dones.
- Widgets selected items with `where: { kind: "care-item" }` (now `$type: "care.item"`).
- The fold (`foldLegacyRecords`) maps them onto the item: an alert record with `done: true`
  completes a one-time item, or moves a repeat's `doneThrough` to that record's `occurrenceAt`;
  an alert record's `snoozedUntil` (not done) becomes `snoozes["~<ruleId>"]`; a time record's
  `lastDoneAt` becomes `slotsDone["HH:MM"]` and its `snoozedUntil` becomes `snoozes["@HHMM"]`;
  then every such record is deleted (its rows stay in the server's history).

## Docs, briefs and prompts

(filled by the docs sweep)
