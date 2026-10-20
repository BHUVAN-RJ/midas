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

Code allowed to understand these shapes (each says so in its header): `backend/scripts/record-upgrades.mjs`
(the converter, also used in memory by `runner/lib/user-records.mjs` and the user-copy planner),
`backend/scripts/migrate-records.mjs`, and their tests. The literal-write patterns the copies
planner flags (`RETIRED_WRITE_PATTERNS`) live in `record-upgrades.mjs` too.

Old shapes the converter turns into the unified format:

| Old shape | Sidekick | Becomes |
|---|---|---|
| `task:<id>` key (undated item) | reminders | `reminder:<id>`, plus a tombstone on `task:<id>` (skipped if `reminder:<id>` exists) |
| `settings:sidebar` | reminders | `settings:self`, plus a tombstone |
| `body` on an item | reminders | `notes` (only when `notes` is missing and `body` is not empty); `body` removed |
| Epoch milliseconds in `at`, `snoozedUntil`, `lastDoneAt`, `doneThrough`, `completedAt`, `createdAt`, `finishedAt`, `exportedAt`, `occurrenceAt`, `repeat.until` | all | ISO 8601 text |
| `null` fields (e.g. `list: null`) | all | field removed |
| Record without `$type` | all | `$type` stamped from the manifest's `types` |
| `reminder:<item>~<ruleId>` alert record | care-reminders | folded into the item: `done: true` with `completedAt` from its `lastDoneAt` (one-time), `doneThrough` from its `occurrenceAt` (repeat); its `snoozedUntil` becomes `snoozes["~<ruleId>"]`; record tombstoned |
| `reminder:<item>@HHMM` time record | care-reminders | folded into the item: its `lastDoneAt` becomes `slotsDone["HH:MM"]`, its `snoozedUntil` becomes `snoozes["@HHMM"]`; record tombstoned |
| Care item fields `kind`, `body`, `icon`, `alertRules`, `seriesId` | care-reminders | removed; the list's `alerts` rules copied onto the item as `alerts` (none for an hourly item with `everyHours` 2, 3 or 4 and a daily repeat; `everyHours` removed otherwise) |
| Care list rules | care-reminders | cleaned to their kind's fields: `daysBefore` {days 1-14, time default 18:00}, `morningOf` {time default 08:00}, `before` {minutes, default 60}; `text` kept only when not empty |

Text moved here from code comments (2026-10-20 sweep):

- `runner/lib/user-records.mjs` header: records "still in an older shape (no `$type`, `task:`,
  `body`, epoch ms, care `~rule` / `@HHMM` parts)" are upgraded in memory before the check.
  Its comments used `task:9 -> reminder:9` as the example of a record the upgrade moves to a new
  key, and the failure detail reads `reminder:9 (stored as task:9)` for such a record.
- `runner/lib/schema-change.mjs`: literal reads are not counted as writes because the reminders
  page queries `task:` once on read to move those records forward.

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
