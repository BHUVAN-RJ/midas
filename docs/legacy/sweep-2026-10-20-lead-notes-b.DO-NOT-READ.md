# Old-format sweep, agent B (shell and Sidekick pages): notes for the lead

Branch `agent/legacy-sweep-b`, 2026-10-20. Brief: midas-intel
`docs/plans/2026-10-20-legacy-sweep-brief.md`.

No change needed in `CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`,
`backend/package*.json` or `backend/wrangler.jsonc` from this sweep.

## Open, for the lead (and the founder where marked)

1. **Done: notifications read `notes` (founder decision 2026-10-20).** `ReminderRecord.notes`
   (read from `notes`; `body` only as marked upgrade on read when `notes` is not a string) is the
   text under the title on every booking: the item's own, its snooze, missed, its early alerts
   and its hourly times. The shell check is now `reminder.notes must be a string`; `body` is
   not checked. New tests: `shell/MidasTests/NotificationNotesTests.swift`.
   **Doc change `docs/NOTIFICATIONS.md` needs (agent C's file, not edited here):**
   - 4.2 table: replace the `body` row (`| \`body\` | string | no | Notification text. The
     Reminders page stores \`notes\` instead and writes no \`body\`. |`) with
     `| \`notes\` | string | no | Notification text, shown under the title on every notification
     the item makes (its own, snoozes, early alerts, hourly times). |`
   - 4.2 last row: "A Sidekick's own fields (list, colour, notes)" → "A Sidekick's own fields
     (list, colour)".
   - 4.6 list: `reminder.body must be a string` → `reminder.notes must be a string`.
   - Line 26, the example record: `body: 'Bring the insurance card',` → `notes: 'Bring the
     insurance card',`.
   - Line 244: "the record's `title` and `body`" → "the record's `title` and `notes`".
   (Lines 66, 238 and 331 use "body" for an HTTP body; no change.)
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
