# Old-format sweep, agent B (shell and Sidekick pages): notes for the lead

Branch `agent/legacy-sweep-b`, 2026-10-20. Brief: midas-intel
`docs/plans/2026-10-20-legacy-sweep-brief.md`.

No change needed in `CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`,
`backend/package*.json` or `backend/wrangler.jsonc` from this sweep.

## Open, for the lead (and the founder where marked)

1. **Founder decision: notification text field.** The shell's engine still reads `body` as the
   notification text (`ReminderRecord.body`, `ReminderPlanner`, the shell check
   `reminder.body must be a string`). Both pages write `notes` and no `body`, so their
   notifications have no text line. The unified data plan (section 4) lists `notes` as the
   engine's input. Kept as is (behaviour must not change). Choices: the engine reads `notes`
   (notes then show under the title in every notification; `docs/WRITING.md` applies), or reads
   neither. Test that pins `body`: `ReminderRecordTests.testParsesAFullRecord`
   (`"body":"Leg day"`). Doc: `docs/NOTIFICATIONS.md` 4.2 and 4.6 (agent C's scope).
2. **Epoch milliseconds, after the live conversion.** `ReminderRecord.parseDate` still reads a
   number as epoch ms (marked "Upgrade on read"), and the shell check's message is
   `reminder.at must be an ISO 8601 date or epoch milliseconds`. Kept (live data is still old).
   After the founder runs the conversion: drop the number branch and change the message to
   `reminder.at must be an ISO 8601 date`; tests pinning the message: `MidasStoreScriptTests:94`,
   `RecordTypeGateTests:152`; pinning the read: `ReminderRecordTests.testParsesAllThreeDateForms`;
   doc: `docs/NOTIFICATIONS.md` 4.2 and 4.6.
3. **Upgrade-on-read code inside the pages.** The brief allows old shapes only in the converter,
   the migration script and their tests. Both pages carry their own upgrade on read, which must
   stay until live data is converted (removing it changes behaviour). Kept, each spot marked
   "Upgrade on read", a header above `RemindersLogic` / `CareLogic` pointing to the quarantine
   file. To remove after the conversion:
   - `sidekicks/reminders/index.html`: the `task:` query in `readStoreRecords` and its use in
     `state.items`, the `body` fallback in `itemFromRecord`, `delete value.body` in
     `recordFromItem`, `OLD_SETTINGS_KEY` in `readSettings`.
   - `sidekicks/care-reminders/index.html`: `isAlertKey` / `isSlotKey` filtering in `loadState`
     and `isItemRecord`, `state.legacy*`, `queryLegacyRecordsOf`, `foldLegacyRecords`, the fold in
     `reconcileItem` / `syncAll`, `deleteKeys(await queryLegacyRecordsOf(...))` in
     `removeItemRecords`, the dropped fields in `recordFromItem`.
   - Their tests: `CareRemindersFieldsTests.testOldAlertAndTimeRecordsAreFoldedIntoTheItemAndRemoved`,
     `CareRemindersSnoozeTests.testOldAlertAndTimeSnoozesAreFoldedIntoTheItemsOwnEntries`,
     `CareRemindersSimpleSheetTests.testAnOldRecordWithItsOwnIconAlertsAndSeriesStillLoadsAndUsesItsListsAlerts`.
4. **Kept on purpose:** tests using `task:1` as an undeclared prefix that must be refused
   (`RecordSchemaEngineTests:50,53,61`, `RecordTypeGateTests:76-83`) and
   `RemindersSidekickTests:155-156` (asserts nothing is written under `task:`). They check the
   current refusal; no old shape is accepted.
5. **Fixtures without `$type`, kept.** Many shell engine and widget tests, and the page logic
   tests in `backend/test/reminders-*.test.ts`, build record values without `$type`. They feed
   the engine or the page's pure functions directly, which ignore `$type` (the store stamps it on
   every write), so adding it would change no assertion. Not swept; say if the founder wants
   every fixture stamped.
6. **Overlap with agent A.** `backend/test/reminders-logic.test.ts` tests the Reminders page
   (my scope) but sits in `backend/` (A's). I asked test-guardian for two changes there
   (`task:t1` → `reminder:t1`; an upgrade-on-read comment); check for a clash when merging.
7. **Not a hit:** `LocalRecordStore.swift:316` "old format" is the shell's pre-sync local file
   format, not a record format.
