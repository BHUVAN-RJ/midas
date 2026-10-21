# Second old-format sweep, agent B (shell and Sidekick pages): notes for the lead

Branch `agent/legacy-sweep2-b`, 2026-10-20. Brief: midas-intel
`docs/plans/2026-10-21-legacy-sweep-2-brief.md` (file name only; the decision is founder,
2026-10-20, `docs/PRODUCT.md` "Old formats retired").

No change needed in `CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`,
`backend/package*.json` or `backend/wrangler.jsonc` beyond what the lead committed (ede0f55).

## Test changes

The first request was refused (NEEDS-EVIDENCE: the decision was not yet in `docs/PRODUCT.md`).
After the lead recorded "Old formats retired (founder, 2026-10-20)" in `docs/PRODUCT.md` and
CLAUDE.md (main ede0f55, merged into this branch), test-guardian accepted every item, citing that
line. All logged in `TEST_CHANGES.md`.

| # | Test | Change | Answer |
|---|---|---|---|
| 1 | `ReminderRecordTests.testParsesAllThreeDateForms` | renamed `testParsesBothIsoDateFormsAndNoNumber`; a number gives nil | ACCEPTED |
| 2 | `MidasStoreScriptTests:94` | message `reminder.at must be an ISO 8601 date` | ACCEPTED |
| 3 | `RecordTypeGateTests:152` | same message | ACCEPTED |
| 4 | `NotificationNotesTests` | header drops the upgrade clause; body-as-notes test replaced by `testBodyAloneIsNotReadAsNotes` | ACCEPTED |
| 5 | `CareRemindersFieldsTests.testOldAlertAndTimeRecordsAreFoldedIntoTheItemAndRemoved`, `CareRemindersSnoozeTests.testOldAlertAndTimeSnoozesAreFoldedIntoTheItemsOwnEntries`, `CareRemindersSimpleSheetTests.testAnOldRecordWithItsOwnIconAlertsAndSeriesStillLoadsAndUsesItsListsAlerts` | deleted | ACCEPTED |
| 6 | `RemindersWidgetTests:432` | `settings:sidebar` → `settings:self` | ACCEPTED |
| 7 | `backend/test/reminders-logic.test.ts:101-102` | `task:b2` read removed (file in A's folder, tests B's page) | ACCEPTED |
| 8 | `CareRemindersFieldsTests` "...ExpandsTheOldFourReminders" | renamed "...ExpandsItsFourNotifications" | ACCEPTED |
| 9 | `backend/test/legacy-quarantine-shell-pages.test.ts` (new) | date corrected to 2026-10-20 | ACCEPTED |

Left as is: the `CareRemindersSnoozeTests` private helper `reminderKeys` has no caller after
item 5 (Swift does not warn).

## Hits and what was done

| File (before) | What it was | Done |
|---|---|---|
| `shell/Midas/ReminderRecord.swift` `parseDate` | number read as epoch ms | removed: only ISO 8601 text is a date |
| `shell/Midas/ReminderRecord.swift` `parseNotes` | `body` fallback for notification text | removed |
| `shell/Midas/ReminderRecord.swift` `validationError` | `reminder.at must be an ISO 8601 date or epoch milliseconds` | now `reminder.at must be an ISO 8601 date` |
| `sidekicks/reminders/index.html` header above `RemindersLogic` | upgrade-on-read pointer | removed |
| same, `recordKey` / `recordFromItem` comments, `delete value.body` | upgrade notes, body drop on write | removed |
| same, `itemFromRecord` | `body` as notes; `key.indexOf('reminder:')` check (undated `task:` items) | removed; record dates read only as ISO text (`storedInstant`) |
| same, `readStoreRecords` / `applyStoreRecords` | `store.query('task:')` | removed |
| same, `OLD_SETTINGS_KEY` / `readSettings` | `settings:sidebar` fallback | removed |
| same, `writeRecordChange` | "dated and undated items live under different keys" + old-key delete | removed (the old key always equals the new key now) |
| `sidekicks/care-reminders/index.html` header above `CareLogic`, separator comment | upgrade-on-read pointer | removed |
| same, `isAlertKey`, `isSlotKey` (+ exports), `isItemRecord` key check | old alert/time keys | removed |
| same, `recordFromItem` | drops `icon`, `alertRules`, `seriesId`, `kind`, `body` | removed |
| same, `itemFromRecord`, `slotsDoneOfRecord`, `isItemRecord`, `previousAt` | dates read via `instantMs` (accepts numbers) | ISO text only (`storedInstant`) |
| same, `state.legacy*`, `loadState` grouping, `queryLegacyRecordsOf`, `deleteKeys`, `foldLegacyRecords`, legacy loops in `syncAll`, `removeItemRecords` | fold and delete of old records | removed |
| same, `reconcileItem` | the fold also caught a repeat's `doneThrough` up with `lastDoneAt` / `slotsDone` for current records | kept as `catchUpDoneThrough` (behaviour unchanged) |
| `docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md`, B's section | "where code still reads these shapes" | rewritten as removed 2026-10-20 |

Not hits / kept: `LocalRecordStore.swift:316` "old format" (the shell's pre-sync file layout, not
a record format); `Booking.body` / `UNNotificationContent.body` (notification text, filled from
`notes`); HTTP/HTML `body`; `lastDoneAt` (in the current `reminders.item` and `care.item`
schemas); `~`/`@HHMM` snooze keys and engine ids (current); refusal tests
`RecordSchemaEngineTests:50,53,61`, `RecordTypeGateTests:76-83`, `RemindersSidekickTests:155-156`,
`CareRemindersFieldsTests:164-165`, `CareRemindersSimpleSheetTests:155-156` (test-guardian agreed).
Not changed: `cleanRepeat` passes `repeat.until` as stored (a number there is refused on write and
ignored by the shell's `parseDate`).

## New check

`backend/test/legacy-quarantine-shell-pages.test.ts` scans `shell/Midas`, `shell/MidasWidgets`,
`shell/Shared`, `shell/sdk` and `sidekicks/` for old markers: `task:` literals,
`settings:sidebar`, upgrade-on-read wording, the quarantine pointer, epoch, care kinds,
`seriesId`/`alertRules`, `body` read from a record, `legacy`. It passes on this branch. On the code
from before this sweep it fails with 16 hits (ReminderRecord.swift and both pages). It sits in A's
folder; no clash is expected.

## For agent C / the lead

- `docs/NOTIFICATIONS.md` 4.2 and 4.6: the `at` message is now exactly
  `reminder.at must be an ISO 8601 date` (no epoch milliseconds), and `body` is not read at all.
- The quarantine file's header (not B's section) still says it serves the upgrade-on-read code
  and the migration "until live data is converted" (agent A is updating the intro).
