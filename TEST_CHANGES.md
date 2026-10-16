# Test changes

Every change to or deletion of an existing test is recorded here by the test-guardian agent,
newest first. New tests are not recorded. The git pre-commit hook rejects a commit that changes
or deletes an existing test without also changing this file.

Each entry: date, test, change, reason (the decision, with its date, or the bug), and proof
the test can still fail for the reason it exists.

## 2026-10-15: backend/test/record-upgrades.test.ts (new, uncommitted): wrong expected instants and a false `DELETE` match (ACCEPTED; bugs in the new test)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Change 1: every `"2026-10-09T08:53:20.000Z"` became `"2025-10-09T08:53:20.000Z"` (lines 64, 135,
  194, 195): `new Date(1760000000000).toISOString()` is 2025-10-09, not 2026. The same hand-computed
  epoch mistake was on three more lines the brief did not name, fixed as the same bug: line 68
  `at` 1760515200000 -> `2025-10-15T08:00:00.000Z`, line 69 `snoozedUntil` 1760518800000 ->
  `2025-10-15T09:00:00.000Z`, line 70 `repeat.until` 1792000000000 -> `2026-10-14T17:46:40.000Z`
  (was `20:26:40`). Each value checked with `node -e 'new Date(n).toISOString()'`.
- Change 2: line 217 `not.toContain("DELETE")` -> `not.toContain("DELETE FROM")`. The old check
  matched the `deleted` column name in the INSERT, so it could never pass; the new one still
  rejects a statement that deletes rows.
- Reason: bugs in a never-run new test, found before first commit. Covers unified data plan
  section 8 (midas-intel `docs/plans/2026-10-15-unified-data-v2.md`, "Moving existing data"),
  builder brief phase 7. Nothing weakened: the instant assertions are exact strings, the SQL check
  still forbids deletion.
- Proof: with `instantText` in `backend/scripts/record-upgrades.mjs` shifted by one hour
  (`new Date(value + 3600000)`), 3 of 10 tests failed (`Expected "2025-10-09T08:53:20.000Z",
  Received "2025-10-09T09:53:20.000Z"`); restored. The `DELETE FROM` check was proven with a stub
  (the permission classifier would not run the suite while app code carried a `DELETE FROM`
  string): the honest INSERT with a `deleted` column passes, `DELETE FROM ops ...; INSERT ...`
  fails. App code unchanged afterwards (`git status`).
- Suite before: record-upgrades 4 failed / 6 passed. After: 10 passed; `scripts/test-all.sh`
  backend 350 passed, shell 479 passed, midas-intel 31 OK, ALL SUITES PASSED.

## 2026-10-15: shell/MidasTests RecordSyncFilesTests (new, uncommitted): two compile fixes (ACCEPTED; bug in the new test)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Change: in `testAQueuedFileWhoseBytesAreGoneIsSkippedSoTheRecordsStillGoUp` and
  `testASyncWithoutFilesBehavesAsBefore`, `XCTAssertTrue(await sync.syncNow())` became
  `let synced = await sync.syncNow()` / `XCTAssertTrue(synced)`. Swift rejects `await` inside
  XCTAssert's autoclosure (`error: 'async' call in an autoclosure that does not support
  concurrency`, seen in `scripts/test-all.sh` before the change). Same assertion, same value.
- Reason: bug in a never-compiled new test, found before first commit. Covers unified data plan
  section 7 (midas-intel `docs/plans/2026-10-15-unified-data-v2.md`, "The upload finishes before
  the record that points to it is pushed"), brief phase 5. Nothing weakened.
- Proof: not run here; the caller asked that the guardian not run xcodebuild (it runs the shell
  suite). The assertion is unchanged, so the test still fails if `syncNow()` returns false.
- Suite before the change: test guard OK, backend 340 passed, midas-intel 31 OK, shell failed to
  compile at RecordSyncFilesTests.swift:148 (this bug). Shell not re-run by the guardian.

## 2026-10-15: shell/MidasTests RecordWriterTests (new, uncommitted): two compile fixes (ACCEPTED; bugs in the new test)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Change 1: `DeniedRemindersSource.readAll` returned a type that does not exist
  (`PhoneRemindersData`). Now returns the protocol's tuple
  `(lists: [PhoneReminderList], reminders: [PhoneReminder])` (`shell/Midas/AppleRemindersImport.swift`
  line 252), value `(lists: [], reminders: [])`. Same stub behaviour: access denied, nothing read.
- Change 2: `testTheWidgetWritersGoThroughTheWriterAndKeepTheSidekicksFields`: removed the unused
  `badTick` action, its `_ = badTick`, and the `isProtectedKey("reminder:call")` precondition that
  duplicated the next assertion. The `badNote` action and its two assertions stay.
- Reason: bugs in a never-compiled new test, found before first commit. Covers unified data plan
  phase 4 (midas-intel `docs/plans/2026-10-15-unified-data-v2.md` section 9, "RecordWriter for
  every native writer"; brief `docs/plans/2026-10-15-data-rework-brief.md`). No assertion weakened:
  the removed precondition asserted a property the kept assertions already prove.
- Proof: not run here. The caller asked that xcodebuild not be run by the guardian (it runs the
  shell suite). The remaining assertions are unchanged, so the test still fails if the import
  writes a non-patch (drops `pageField`/`createdAt`) or the widget writer touches a protected key.
- Suite: test guard 34 OK, backend 331 passed + typecheck OK, midas-intel 31 OK; shell not run.

## 2026-10-15: shell/MidasTests ReminderActionTests.testDoneCompletesAOneTimeReminder, NotificationEngineTests.testDoneOnAOneTimeReminderCompletesItAndCancelsItsSnooze: Done removes `snoozedUntil` instead of storing null (ACCEPTED; founder decision)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Reason: founder decision, midas-intel `docs/plans/2026-10-15-unified-data-v2.md`. Section 0:
  "Leave a field out instead of `null`. Updates follow JSON Merge Patch (RFC 7396)." and "Every
  place that changes a record (page, notification button, widget, voice) changes the same fields
  the same way." Section 2 rule 3: "Leave fields out instead of `null`." Section 9 phase 4:
  "`RecordWriter` for every native writer; Done conformance test." Section 14 ("Founder answers,
  2026-10-15") records the go-ahead and the builder start on this branch; builder brief
  `2026-10-15-data-rework-brief.md`, phase 4. Both tests pinned the old shape, a stored
  `snoozedUntil: null`. On this branch `ReminderChange.donePatch` (`shell/Midas/RecordWriter.swift`)
  is the one Done every writer applies; it is a JSON Merge Patch with `snoozedUntil: null`, and
  `JSONMergePatch.apply` removes the field, so the stored record has no `snoozedUntil`.
- Change, one line in each test, nothing else:
  - `ReminderActionTests.swift`: `XCTAssertEqual(done["snoozedUntil"], .null)` becomes
    `XCTAssertNil(done["snoozedUntil"], "the snooze is removed, not set to null (rule: no null, 2026-10-15)")`.
  - `NotificationEngineTests.swift`: `XCTAssertEqual(storedValue?["snoozedUntil"], .null)` becomes
    `XCTAssertNil(storedValue?["snoozedUntil"], "the snooze is removed, not set to null (rule: no null, 2026-10-15)")`.
  Both tests still check what they exist for (Done cancels the snooze): `done["snoozedUntil"]`
  is `JSONValue?`, so the assertion fails if the snooze date is still there and also fails if a
  literal null is stored.
- Proof it can still fail (the caller runs the shell suite, so this was done in a standalone macOS
  XCTest harness in the scratchpad built from unmodified copies of `shell/Midas/JSONValue.swift`
  and `shell/Midas/JSONMergePatch.swift`, with the one-time Done patch
  `{done: true, snoozedUntil: null}` applied to a snoozed record and the new assertion):
  - Unbroken: `executed 1 failures 0 -> PASSED`.
  - Break 1, the copy of `JSONMergePatch.apply` changed from `resultFields.removeValue(forKey:
    fieldName)` to `resultFields[fieldName] = .null`: `XCTAssertNil failed: "null" - the snooze is
    removed, not set to null (rule: no null, 2026-10-15)` -> FAILED.
  - Break 2, `snoozedUntil: .null` dropped from the Done patch so the snooze stays: `XCTAssertNil
    failed: "string("2026-10-15T10:00:00Z")"` -> FAILED.
  - Restored: the copy compared identical to the repo file with `cmp`; no repo app code was touched.
- Full suite (`scripts/test-all.sh` parts, shell left to the caller by request): test guard 34 OK;
  backend 331 passed, typecheck OK; midas-intel 31 OK. Shell: not run here, the data-rework
  agent runs it.

## 2026-10-15: shell/MidasTests CareRemindersSidekickTests, CareRemindersHourlyRepeatTests, CareRemindersSimpleSheetTests, ReminderExpansionTests: care early alerts and hourly times are fields the engine expands (ACCEPTED; founder decision, plus one bug in a new test)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Reason (items 1-3): founder decision, midas-intel `docs/plans/2026-10-15-unified-data-v2.md`.
  Section 0: "care-reminders early alerts and hourly times become fields on the item; the engine
  expands them." Section 4 table, care-reminders row: `reminder:` is `care.item`, "early alerts and
  hourly times are fields; `~ruleId` and `@HHMM` records retired". Section 9 phase 3: "care early
  alerts and hourly times as fields; engine expands them." Section 14 ("Founder answers,
  2026-10-15") records the go-ahead and the builder start on this branch; builder brief
  `2026-10-15-data-rework-brief.md`, phase 3. The tests below pinned the retired shape: one
  `reminder:<id>~<rule>` record per early alert and one `reminder:<id>@HHMM` record per hourly
  time, and Done written by the shell onto those records. Code on this branch:
  `sidekicks/care-reminders/index.html` writes one record per reminder with `alerts` (the list's
  rules) or `everyHours` (2, 3 or 4) and `$type: 'care.item'`, folds old `~`/`@` records into the
  item on load and deletes them; `shell/Midas/ReminderExpansion.swift` expands a `ReminderRecord`
  into the same reminders under the same ids (`<id>`, then `<id>@HHMM`, then `<id>~<rule>`);
  `ReminderAction.done.apply(to:part:occurrence:now:calendar:)` writes Done onto the item record
  (`.alert` completes the event, `.slot` sets `slotsDone["HH:MM"]`). Each changed test now checks
  the same reminders (ids, moments, wording, zone, rule, done state) through the expansion of the
  one record, so it still fails if the page writes extra records, drops a rule, or the engine
  expands them wrongly. Helper added to the first two classes: `expanded(_:itemId:)` (parse the
  item record, `ReminderExpansion.expand(record, now: Date())`).
- Reason (item 4): bug in a new test, found before its first commit. The expected identifier
  suffixes in `ReminderExpansionTests.testTheEngineIdentifiersAndLedgerKeysAreTheOnesTheOldRecordsHad`
  were computed wrongly (1792440000, 1792371600, 1792422000, 1792436400: each one day late).
  The test's own sibling assertions put the alerts at 2026-10-17T18:00, 2026-10-18T08:00 and
  2026-10-18T12:00 Los Angeles for a 2026-10-18T13:00 event; those moments are 1792285200,
  1792335600, 1792350000 and 1792353600 (checked with `python3 datetime.fromisoformat`).
- Changes, `CareRemindersSidekickTests.swift`:
  a) DELETED `testAppointmentWithThreeRulesWritesFourRecordsTheEngineAccepts` (pinned four records).
     Replaced by `CareRemindersFieldsTests.testAnAppointmentIsOneRecordCarryingItsListsRulesAndTheEngineExpandsTheOldFourReminders`
     (new, this branch): same four reminder ids, same four moments, same three wordings, from the
     expansion of the one record; plus `kind`/`body` absent and the rules stored in order.
  b) `testAnAlertWhoseTimeHasAlreadyPassedIsSkipped`: the final assertion now checks the store holds
     only `reminder:<id>` and the expansion is `[<id>, <id>~p3]` (1 h before and the day before,
     already past, are not booked).
  c) DELETED `testDoneWrittenByTheShellOnOneAlertCompletesTheEventAfterAReload` (wrote Done onto a
     `~a1` record). Replaced by `CareRemindersFieldsTests.testDoneWrittenByTheShellOnAnEarlyAlertCompletesTheEventAndThePageShowsIt`:
     the same Done written as the engine writes it now (`.alert(ruleId: "a1")` onto the item), read
     back by the page after a reload, `done` true, expansion count 1.
  d) `testDoneInThePageCompletesTheEventAndRemovesItsAlerts`: first two assertions kept; added
     expansion count 1 after Done; the last assertion (`reminderKeys.count == 4`) is now
     `expanded(...).count == 4` after Not Done.
  e) DELETED `testEditingAListRuleRewritesTheAlertsOfItsReminders` (read the moved alert from the
     `~e1` records). Replaced by `CareRemindersFieldsTests.testEditingAListRuleRewritesTheRulesOnItsReminders`:
     same list, same two reminders, the rule on each record changed to 30 min, and the expanded
     alert at the same moved moment with the same wording.
  f) `testDeletingAListRemovesItsRemindersAndUndoRestoresThem`: Undo restores `[reminder:<id>]`
     (was `[reminder:<id>, reminder:<id>~d1]`), and the expansion is `[<id>, <id>~d1]` ("Undo lost
     the rule"). Class doc comment updated; unused `storedDate` helper removed.
- Changes, `CareRemindersHourlyRepeatTests.swift` (doc comment updated):
  a) `testEveryTwoThreeAndFourHoursWriteOneValidDailyRecordPerWallClockTime` renamed
     `...WriteOneRecordTheEngineExpandsToOneDailyReminderPerWallClockTime`: one stored record,
     `everyHours == hours`, expansion count 24/hours, and the per-reminder checks (daily rule, zone,
     title, not done, first fire within [start, start+24h)) and the expected-times comparison run
     over the expansion.
  b) `testEveryThreeHoursFromEightIsTheFoundersEightTimes`: times collected from the expansion.
  c) `testSwitchingToNeverRemovesTheExtraRecords` renamed `...RemovesTheHourlyField`: precondition is
     `everyHours == 3` on the record (was 8 records); the rest unchanged.
  d) `testEditingTheTimeRewritesEveryRecord` renamed `...MovesEveryTime`: keys == `[reminder:<id>]`,
     expansion count 6, title "Tablets" and the six times checked over the expansion.
  e) `testDeletingAnHourlyReminderRemovesAllItsRecords`: precondition is expansion count 12.
  f) `testAnHourlyReminderInAListWithAlertsWritesNoEarlyAlerts`: precondition reads the daily
     reminder's `alerts` field; the hourly reminder is one record with no `alerts` and expansion
     12; after the edit to every 3 h, `alerts` absent, `everyHours == 3`, expansion 8.
  g) `testDoneTappedOnOneTimesNotificationIsReadBack`: Done written onto the item record with
     `.item` or `.slot(time:)`; read back through the page's `CareLogic.effectiveDoneThrough`
     (epoch ms) == the latest occurrence (was `doneThrough` on the record).
  Unchanged: the one-row, edit-sheet and over-48 tests.
- Change, `CareRemindersSimpleSheetTests.testAnOldRecordWithItsOwnIconAlertsAndSeriesStillLoadsAndUsesItsListsAlerts`:
  keys == `[reminder:old]` and the item's `alerts` ids == `["r1"]` (Meetings' rule copied onto the
  item on the first load; was `[reminder:old, reminder:old~r1]`).
- Change, `ReminderExpansionTests.testTheEngineIdentifiersAndLedgerKeysAreTheOnesTheOldRecordsHad`:
  expected identifiers now `d1|1792353600`, `d1~a1|1792285200`, `d1~a2|1792335600`,
  `d1~a3|1792350000`.
- Proof the tests can still fail (no xcodebuild at the caller's request; the caller runs the
  shell suite): the new assertions were replayed with `swiftc` against copies of the real
  `ReminderExpansion`, `ReminderActions`, `ReminderRecord`, `ReminderSchedule`, `ReminderPlanner`
  and `JSONValue` (all Foundation-only, no stubs). Unbroken copies: 16 checks pass (item 4
  identifiers; 1b ids `[s1, s1~p3]`; 1d done 1 / not done 4; 2a/2b/2d/2e counts, rule, zone,
  title, done, first-fire window and times for 2, 3 and 4 hours; 2g `slotsDone["12:00"]`).
  Break 1, `earlyAlerts` with the `alertAt > now` guard removed: 1b got `[s1, s1~p1, s1~p2, s1~p3]`.
  Break 2, `alertSeparator` "~" -> "-": item 4 identifiers `d1-a1...` and 1b `s1-p3`, both fail.
  Break 3, `timesOfDay` loop stopping one step early: 2a counts 11/7/5 instead of 12/8/6 and the
  last time missing for every interval, six failures. Break 4, Done on `.slot` writing
  `lastDoneAt` instead of `slotsDone`: 2g got nil. Each break was in its own copy directory;
  `diff -q` of the repo's six engine files against the unbroken copies: identical. The repo's app
  code was not touched. The four edited test files pass `swiftc -parse`.
- Suites (shell suite run by the caller, not here): test guard 34 OK; backend 331 passed,
  typecheck OK; midas-intel 31 OK.

## 2026-10-15: shell/MidasTests RecordTypeGateTests.testTheReservedReminderCheckStillRunsOnUpdate (ACCEPTED; founder decision)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Reason: the same founder decision as the entry below, midas-intel
  `docs/plans/2026-10-15-unified-data-v2.md` section 4 table, reminders row: `reminder:` is
  `reminders.item`, "every item, dated or not; `task:` folded in". `ReminderRecord.validationError`
  on this branch accepts a record without `at`, so the patch `{"at":null}` (which removes `at`
  under RFC 7396) is now a legal update to an undated item and no longer exercises the check. The
  test's purpose, that the reserved check runs on `update` as it does on `set`, is unchanged.
- Change: the patch is now `{"at":"someday"}` (a present but malformed `at`). The three
  assertions are unchanged: 400, `reminder.at must be an ISO 8601 date or epoch milliseconds`,
  stored `at` still `2026-10-15T09:30:00.000Z`.
- Proof it can still fail: the test body was replayed with `swiftc` against copies of the real
  `SidekickStoreChannel`, `LocalRecordStore`, `JSONMergePatch` and `ReminderRecord` (stubs only
  for `RecordSync.valueByteCount`, `PlatformConfig`, `ShellRequests.keyPrefix`; no xcodebuild at
  the caller's request). Real code: passes. Copy 1, the `at` check removed from
  `validationError`: status 200, error nil, stored `at` = "someday", all three assertions fail.
  Copy 2, `handleUpdate` with the `reservedValidationError` call removed: the same three failures.
  Copies restored (`diff -q` against the repo files: identical) and the replay passes again. The
  repo's app code was not touched.
- Suites (shell suite run by the caller, not here): test guard 34 OK; backend 331 passed,
  typecheck OK; midas-intel 31 OK.

## 2026-10-15: shell/MidasTests ReminderRecordTests.testRejectsBadRecordsWithAReason, MidasStoreScriptTests.testBadReminderIsRejectedWithTheReason, RemindersSidekickTests.testEveryRepeatOptionAndAllDayAreAcceptedByTheNotificationEngine (ACCEPTED; founder decision)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Reason: founder decision, midas-intel `docs/plans/2026-10-15-unified-data-v2.md`. Section 2
  rule 2: "One type per key prefix. A record never moves prefix because a field changed (`task:`
  retired)." Section 4 table, reminders row: `reminder:` is `reminders.item`, "every item, dated
  or not; `task:` folded in". Section 14 ("Founder answers, 2026-10-15") records the go-ahead and
  the builder start on this branch; builder brief `2026-10-15-data-rework-brief.md` (scope: plan
  section 9 phases 1-5, 7, 8). The three tests pinned the reversed rule that a `reminder:`
  record must carry `at` and that an undated item is a `task:` record. Code on this branch:
  `ReminderRecord.validationError` accepts a record without `at` (a present `at` must still be a
  date, same message); `ReminderRecord.parse` returns nil for a record without `at`;
  `sidekicks/reminders/index.html` `recordKey` writes every item under `reminder:`.
- Change 1 (`ReminderRecordTests.swift`): removed `#"{"title":"no time"}"#` from `badRecords` in
  `testRejectsBadRecordsWithAReason`; the other fourteen bad records stay. Added
  `testAnUndatedItemIsAcceptedButIsNotANotification`: `{"title":"Buy milk","list":"groceries"}`
  has no `validationError` and `parse` returns nil.
- Change 2 (`MidasStoreScriptTests.swift`): the bad write in `testBadReminderIsRejectedWithTheReason`
  is now `store.set('reminder:bad', { at: 'someday', title: 'bad time' })`; the expected message
  `reminder.at must be an ISO 8601 date or epoch milliseconds` and the not-stored check are unchanged.
- Change 3 (`RemindersSidekickTests.swift`, lines 155-157): the undated item is expected under
  `reminder:undated` and not under `task:undated`, and `ReminderRecord.parse` of it is nil (an
  undated item is not a notification).
- Proof the tests can still fail: xcodebuild was not run by the guardian (the data-rework agent
  runs the shell suite, a run was in progress). Static proof against the committed code at
  `7f402c5` (`git show 7f402c5:shell/Midas/ReminderRecord.swift`, `git show
  7f402c5:sidekicks/reminders/index.html`): there `validationError` returns "reminder.at must be
  an ISO 8601 date or epoch milliseconds" for any record without `at`, so the new
  `testAnUndatedItemIsAcceptedButIsNotANotification` fails its first assertion; and `recordKey`
  returns `'task:' + item.id` for an item without a date, so change 3's
  `XCTAssertNotNil(store.get(... "reminder:undated"))` fails with "an undated item is a reminder:
  record too". Change 2 fails with outcome `accepted` if the store channel stops rejecting a
  present-but-unparsable `at`, and `testRejectsBadRecordsWithAReason` still holds
  `{"at":"someday","title":"bad time"}`. Change 3's new `parse` nil check fails if `parse` ever
  books an undated item. The data-rework agent's shell run is the executed result.
- Full suite at the time of the change (`scripts/test-all.sh` minus the shell suite, which the
  guardian did not run): test guard 34 OK; backend 330 passed, 1 failed:
  `test/reminders-logic.test.ts > records > keys dated items as reminder: and undated items as
  task:` (expected `task:b2`, got `reminder:b2`), a test pinning the same reversed rule, not in
  this request; midas-intel 31 OK. Shell: not run here.

## 2026-10-15: backend/test/reminders-logic.test.ts, "keys dated items as reminder: and undated items as task:" (ACCEPTED; founder decision)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Reason: founder decision, midas-intel `docs/plans/2026-10-15-unified-data-v2.md`, section 2 rule 2:
  "One type per key prefix. A record never moves prefix because a field changed (`task:` retired)."
  Section 4 table, reminders row: `reminder:` = `reminders.item`, "every item, dated or not; `task:`
  folded in". Section 14 ("Founder answers, 2026-10-15") records the go-ahead and the builder start.
  Builder brief `docs/plans/2026-10-15-data-rework-brief.md`, phase 3. The old test pinned the
  retired `task:` prefix for undated items; `sidekicks/reminders/index.html` `recordKey` now
  returns `'reminder:' + item.id` for every item, and the test failed with
  `expected 'reminder:b2' to be 'task:b2'`.
- Change: renamed to "keys every item as reminder:, dated or not (task: retired 2026-10-15)";
  second expectation `toBe("task:b2")` became `toBe("reminder:b2")`; added a third line
  `expect(logic.itemFromRecord("task:b2", { title: "Milk" }).date).toBeNull()` so reading an old
  `task:` record is pinned as still working. The later test "round-trips an item through its
  record" still reads `task:t1` and is unchanged. Nothing else in the file changed.
- Proof it can still fail: temporarily changed `recordKey` in `sidekicks/reminders/index.html` to
  `return (item.date ? 'reminder:' : 'task:') + item.id;` (the old behaviour), ran
  `npx vitest run test/reminders-logic.test.ts`: 1 failed, 26 passed, `AssertionError: expected
  'task:b2' to be 'reminder:b2'`. Restored the line; sha256 of the file identical before and after.
  With the real code: 27 passed.

## 2026-10-15: shell/MidasTests/RecordSyncTests.swift, testAnOpTheServerRefusesForGoodLeavesTheOutbox and RemoteRecordSyncAPITests.testPullRequestAndReplies (ACCEPTED; founder decision)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Reason: founder decision, midas-intel `docs/plans/2026-10-15-unified-data-v2.md`, section 0:
  "The server is the source of truth. The phone and the server never disagree. Nothing is ever
  dropped from the phone unless the server accepted it." Section 5: "Refused ops: never dropped.
  The op stays queued, the user sees it is not backed up, and it is reported." Section 1 names
  `RecordSync.swift:134-138` ("still drops refused ops") as the code to change; section 14 records
  the founder's 2026-10-15 answers and the builder start. The old test pinned the reversed
  behaviour (refused op leaves the outbox).
- Change 1: `testAnOpTheServerRefusesForGoodLeavesTheOutbox` renamed
  `testAnOpTheServerRefusesStaysInTheOutboxAndIsCounted`. `XCTAssertEqual(phone.pendingOpCount, 0)`
  became `XCTAssertEqual(phone.pendingOpCount, 1, "the refused op stays queued")`, and two assertions
  were added: `XCTAssertEqual(phone.pendingOps().first?.key, "note:huge")` and
  `XCTAssertEqual(sync.refusedOpCount, 1)`. The other assertions (synced, server stored 1, value
  still on the phone) are unchanged.
- Change 2: in `testPullRequestAndReplies`, the expected push result became
  `PushResult(acceptedOpIds: ["a", "b"], rejectedOpIds: ["c"], rejectionReasons: ["c": "too big"])`
  because `PushResult` now carries the server's reason per refused op and the reply in the test
  has `"error":"too big"` for op c. Asserts more, not less. Nothing else in the test changed.
- Proof (standalone harness, not xcodebuild, at the caller's request; copies of RecordSync.swift,
  LocalRecordStore.swift, JSONValue.swift, PlatformConfig.swift compiled with swiftc for macOS and
  a main that runs the same steps and assertions as both tests; app code in the worktree untouched):
  - Intact: all 7 checks pass.
  - Break 1: in the copy, `removeFromOutbox(opIds: Set(result.acceptedOpIds))` became
    `Set(result.acceptedOpIds + result.rejectedOpIds)` (the old drop). Failed:
    `pendingOpCount == 1 (got 0)` and `first pending key is note:huge`. Note `refusedOpCount`
    stayed 1 under this break (markRefused still records the reason), so the pendingOpCount
    assertion is the one that guards the drop.
  - Break 2: in the copy, `pushResult(from:)` set the reason to the default instead of
    `rejection.error`. Failed: `pushResult carries reason (got rejectionReasons: ["c": "refused by
    the server"])`.
  - Copy restored; `diff` against the worktree file shows no difference.
- Suites: test guard 34 OK; backend 331 passed, typecheck OK; midas-intel 31 OK. Shell suite not
  run here (caller runs xcodebuild).

## 2026-10-15: shell/MidasTests/SidekickDirectoryTypesTests.swift, testRefreshKeepsTypesAndVersionsAndCachesThemForTheNextLaunch (ACCEPTED; compile fix in an uncommitted new test)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Reason: bug in the test, found before its first commit. It called `SharedSidekickListWriter(fileURL: nil)`,
  an initializer that does not exist; the only one is `init(fileURL:now:reloadWidgets:)`
  (shell/Midas/SharedSidekickListWriter.swift line 13). The test covers midas-intel
  `docs/plans/2026-10-15-unified-data-v2.md` section 3 ("Phone validation needs each user's copy
  schemas on the phone") and section 9 phase 2; brief `docs/plans/2026-10-15-data-rework-brief.md`.
- Change: that line became `SharedSidekickListWriter(fileURL: nil, now: Date.init, reloadWidgets: Self.reloadNothing)`
  and the class gained `nonisolated private static func reloadNothing() {}` after `tearDown`
  (`nonisolated` because the class is `@MainActor` and the closure must be `@Sendable`). No assertion changed.
- Proof: not re-proven here (test never compiled before this change, and the guardian does not run
  xcodebuild in this worktree); the assertions on `types(forSidekickId:)` and `version(forSidekickId:)`
  are unchanged and fail when SidekickDirectory drops types or versions. The data-rework agent runs
  the shell suite.

## 2026-10-15: TEST_CHANGES.md merge conflict, agent/care-repeat into agent/data-rework (ACCEPTED; log-only, no test changed)

- Request: during `git merge --no-commit agent/care-repeat` in the data-rework worktree, resolve the
  conflict markers in this file by keeping both sides in full (HEAD entries first, then the
  agent/care-repeat entry "2026-10-12: CareRemindersHourlyRepeatTests.swift (hourly repeat, Change 2)"),
  then the common tail. Asked by the data-rework agent.
- Reason: midas-intel `docs/plans/2026-10-15-unified-data-v2.md`, section 0 ("Merge `agent/care-repeat`
  and `agent/sidekick-widget` first, keeping their behaviour") and section 9 phase 1 line 1 ("Merge
  `agent/care-repeat` (conflict: `TEST_CHANGES.md` only)"); brief `docs/plans/2026-10-15-data-rework-brief.md`,
  Phase 1.
- Change: removed the three marker lines, kept every entry from both sides verbatim, one blank line
  between entries. No test file was changed or deleted; `git status` showed no conflicted test file.
- Proof: not applicable (no test behaviour changed). Full suite not run for this log-only edit; the
  merging agent runs it before committing.

## 2026-10-15: shell/MidasTests/RepairCopyTests.swift, RepairSessionTests.swift, RepairFeatureRequestTests.swift (ACCEPTED; repair permission screen removed, Midas asks at launch)

- Asked by: lead session (main checkout), 2026-10-15.
- Reason: founder decision, 2026-10-15, `docs/PRODUCT.md` repair section: "Permissions (founder,
  2026-10-15): Midas asks for the microphone and speech recognition when it opens, not at the first
  repair, so the repair layer never stops for prompts. The repair layer's own permission screen is
  removed. If either is declined, repair still works by typing." Before this entry the shell suite
  did not compile: `RepairSessionTests.swift:83:212: error: extra argument 'permissionState' in call`.
- Change:
  - RepairCopyTests: deleted `testPermissionScreen` (the four strings no longer exist); removed
    `permissionTitle`, `continueButton`, `notNowButton`, `openSettingsButton` from the
    `testNoPeriodsOnTitlesOrButtons` labels list. The five remaining layer labels are still checked.
  - RepairSessionTests: `makeSession` lost the `permission:` parameter and the
    `permissionState: permission` argument; deleted `testPermissionScreenShowsUntilGrantedOrDeclined`
    (the screen, `isPermissionScreenShown` and `declinePermissions` no longer exist).
    `testNoOnDeviceSpeechStillAllowsDrawingAndTyping` stays.
  - RepairFeatureRequestTests: dropped `permissionState: .granted` from the `RepairSession` init.
- What replaces it: new `shell/MidasTests/VoicePermissionsTests.swift` (asks at launch, microphone
  first, answered prompts are never shown again, and a check that no repair file asks or shows
  `RepairPermissionScreen`). Gap: the deleted test's "must not listen before permission" assertion
  now lives only in app code, `OnDeviceSpeechTranscriber.start` (`guard VoicePermissions.state() ==
  .granted else { throw RepairSpeechError.notAuthorized }`, RepairSpeechTranscriber.swift line 50).
  No test covers that guard yet.
- Proof it can still fail (founder approved the temporary breaks, 2026-10-15): one break at a time
  in a scratchpad copy of `shell/`, `xcodebuild test` on the "Midas Lead" simulator. The copy has no
  files from outside `shell/`, so 19 tests fail there on every run (sidekick `index.html`, backend
  `auth.ts`, the gesture sample JSON); only failures beyond those are listed. Each break was restored
  from the main checkout and checked (sha1 RepairSession.swift `96f09968...`).
  (1) `RepairCopy.textPlaceholder` = "What to fix.": `RepairCopyTests.testNoPeriodsOnTitlesOrButtons`
  "XCTAssertFalse failed - What to fix. ends with a period" (and `testLayerButtons`).
  (2) `isListening = true` in the `startListening` catch:
  `RepairSessionTests.testNoOnDeviceSpeechStillAllowsDrawingAndTyping` line 200 "XCTAssertFalse failed".
  (3) `canSend` also requiring a stroke: `RepairFeatureRequestTests.testVoiceOnlyRequestIsSentWithoutAStroke`
  line 82 "words alone must be enough; a feature request has no drawing" (plus 86, 87, 89),
  `RepairSessionTests.testNoOnDeviceSpeechStillAllowsDrawingAndTyping` line 202 and
  `testSpokenWordsEnableSend` line 125.
  (4) Removing `await VoicePermissions.askAtLaunch()` from MidasApp.swift (for
  `VoicePermissionsTests`, not an edited test): BLOCKED by the Claude Code auto mode classifier, not run.
  No main-checkout app file changed (RepairSession.swift `96f09968...`, MidasApp.swift `8778d122...`).
- Full suite after the change (MIDAS_SIMULATOR="Midas Lead"): test guard 42 OK, backend 303/303,
  shell 350/350, midas-intel 31 OK.

## 2026-10-14: tests/guard/test_release_config.py::test_every_build_uses_the_one_production_entitlements_file (ACCEPTED; Midas Test may use its own -Test entitlements file)

- Asked by: lead session (main checkout), 2026-10-14.
- Reason: founder decision, 2026-10-14, `docs/PRODUCT.md` section 6 "Shell" (commit `09ca726`):
  "**Midas Test, a second app on the same phone (founder, 2026-10-14):** "create a new bundle (for
  the shell midas test) so that I can have 2 installs on my phone at the same time" [...] its own
  entitlements files `Midas-Test.entitlements` and `MidasWidgets-Test.entitlements` (same
  production-mode passkey domains, test App Group). [...] Debug and Release are unchanged."
  Before this entry the test failed: `project.yml` now has four `CODE_SIGN_ENTITLEMENTS` lines and
  each target folder two `.entitlements` files.
- Change: added `TEST_TARGET_ENTITLEMENTS` and `entitlements_assignments()`, which returns each
  `CODE_SIGN_ENTITLEMENTS` in `project.yml` together with its enclosing YAML keys. The test now requires
  exactly these four, in order: `targets/<T>/settings/base` = the production file and
  `targets/<T>/settings/configs/Test` = `<T>/<T>-Test.entitlements`, for Midas and MidasWidgets. Nothing
  else may set it, so Debug and Release (the everyday app) must take the production file from base.
  On disk, each target folder must hold exactly the production file and its -Test file. The
  -Test files' contents are checked by the new `tests/guard/test_test_app_config.py`.
- Proof it can still fail: these breakages were each made in `shell/project.yml` (or on disk), run, and
  restored (sha1 `eac9c1d6...` before and after). Each failed with `AssertionError: Lists differ`:
  (1) app `configs/Release` set to `Midas/Midas-Test.entitlements`: extra
  `(('targets','Midas','settings','configs','Release'), ...)`; (2) widgets `configs/Debug` set to
  `MidasWidgets/MidasWidgets-Test.entitlements`: extra `...'configs','Debug'...`; (3) app base switched to
  `Midas/Midas-Test.entitlements`: base value differs; (4) project-wide `settings/configs/Release` set to
  `Midas/Other.entitlements`: extra `(('settings','configs','Release'), ...)`; (5) stray
  `shell/Midas/Midas-Dev.entitlements` created: file list differs (`: Midas`).

## 2026-10-14: backend/test/runner-copy-tests.test.ts, runner-deploy.test.ts, runner-job.test.ts, runner-feature-kind.test.ts, helpers/runner-fixture.ts (copy tests come down by fetch, go up by --dir)

- Reason: founder decision, 2026-10-13, `docs/briefs/repair-contract.md` "Settled", bullet "Tests move
  every copy forward": "Each user copy has its own tests and its own `TEST_CHANGES.md`, stored in R2
  with that copy's version (`.../users/<uid>/<version>/tests/`; never served to the phone). [...] A
  repair job gets them in `tests/` [...] The tests and log are deployed together with the page."
  Realised by agent/repair-copies, merged to main 2026-10-14 (`2e91757`, code in `d3ac331`): a copy's
  tests come down with `scripts/fetch-sidekick-copy.mjs <id> --env live --user <uid> --out <dir>` into
  `<dir>/tests/` plus an `index.json`, and `deploy-sidekick.mjs --dir <path>` reads `<path>/index.html`,
  `manifest.json` and `<path>/tests/`. There is no intake `tests.json` asset and no `--tests` flag.
  Runner code changed to match (`runner/lib/copy-tests.mjs`: `parseTestsAsset` and `TESTS_ASSET_NAME`
  gone, `fetchCopyTests({ runFetch })` added; `deploy.mjs`: `deployArgs({ sidekickId, userId, deployFolder })`,
  `deployFolderFor(jobFolder)`, `publishFix` stages and removes `<job>.deploy`; `run-job.mjs`: `deps.runFetch`,
  fetch before the agent, failure reason `tests missing`). Before this entry 26 tests in the four
  files failed: every `runJob` without `runFetch` ran the real fetch script (absent from the scratch
  checkout) and failed `tests missing`, and `deployArgs` was called with `jobFolder`.
- helpers/runner-fixture.ts: added `fakeFetchWithStoredTests(storedTests)` and
  `fakeFetchWithoutStoredTests()` returning `{ runFetch, calls }`; the stub writes what the real fetch
  script writes into `--out` (`index.html`, `manifest.json`, `version.json`, `tests/<files>`,
  `tests/index.json`). No existing export changed.
- runner-job.test.ts (`runWith`), runner-feature-kind.test.ts (`runFeatureJob` and the `bundle missing`
  test), runner-deploy.test.ts (`runWithDeploy` and `a failing check never reaches the deploy`): every
  `runJob` call passes `runFetch: fakeFetchWithoutStoredTests().runFetch`, so the job falls back to the
  two base tests already in the scratch checkout and every other assertion (job-folder listings,
  statuses, summary, deploy user) is unchanged.
- runner-deploy.test.ts, `builds the live user deploy for the reporter from the job folder` renamed
  `... from the staged deploy folder`: `deployArgs({ sidekickId, userId, deployFolder: "/jobs/rep-9.deploy" })`
  equals `[..., "--dir", "/jobs/rep-9.deploy"]`; added `not.toContain("--tests")`. `refuses to build a
  command without a valid reporter id`: the four user-id/Sidekick-id cases now pass `deployFolder`
  (same throws), plus `deployFolder: ""` throws `/no deploy folder/`. E2E `fix_ready, then deploy ...`:
  `--dir` value is `deployFolderFor(result.jobFolder)` instead of `<job>/sidekick`; added
  `not.toContain("--tests")` and the staged folder is gone after the job. Summary assertions unchanged.
- runner-copy-tests.test.ts: `copyTestsAsset()` replaced by `storedCopyTests()` (same two copy tests and
  `COPY_LOG`) handed to `fakeFetchWithStoredTests`; `runWithTests` takes `runFetch` instead of `assets`
  and always serves `standardAssets()`. Deleted `parses the tests asset and refuses paths and non-text`
  (`parseTestsAsset` no longer exists; the bad-name refusal is covered by runner-fetch-and-stage.test.ts
  `a failing fetch script throws ... and a bad file name is refused`). `a job with a tests asset holds
  those tests ...` renamed `a job with stored copy tests holds those tests ...`, same assertions except
  the deploy check: `--dir` value is `deployFolderFor(result.jobFolder)` and args contain no `--tests`.
  `without a tests asset the job runs the base tests` renamed `a copy with no stored tests runs the base
  tests from the checkout`, using `fakeFetchWithoutStoredTests`; same assertions. `an unreadable tests
  asset fails the job before the agent runs` renamed `a failing fetch fails the job before the agent
  runs`, stub resolves `{ ok: false }`; reason stays `tests missing`, added detail contains
  `fetch-sidekick-copy failed`. `deploy carries the tests > adds --tests <job>/tests after --dir` replaced
  by `points --dir at the staged deploy folder, which holds the tests, and adds no --tests flag` (kept
  rather than deleted: it is the only `deployArgs` check in this file's contract).
- Proof: with `runner/lib/deploy.mjs` `deployArgs` changed to append `"--tests", deployFolder` and
  `runner/lib/run-job.mjs` `copyTestsFor` changed to swallow a fetch error and return the base tests,
  5 tests failed: runner-deploy `builds the live user deploy ...` (toEqual, received extra
  `"--tests", "/jobs/rep-9.deploy"`), runner-deploy `fix_ready, then deploy ...` (args include `--tests`),
  runner-copy-tests `a job with stored copy tests ...` (args include `--tests`), runner-copy-tests
  `a failing fetch fails the job before the agent runs` (expected `failed`, received `deployed_live`),
  runner-copy-tests `points --dir at the staged deploy folder ...` (toEqual). Both files restored from
  a byte copy (md5 verified). After the restore: `npx vitest run test/runner-` 9 files, 83 tests, all
  passing. `scripts/test-all.sh` not run (brief: runner suite only; worktree agent/repair-runner).

## 2026-10-14: shell/MidasTests, three repair tests follow the strokes part becoming a JSON array

- Tests: `RepairReportEncoderTests.testStrokesJSONKeepsPointsAndView` (renamed to
  `testStrokesJSONIsTheArrayIntakeAccepts`), `RepairSessionTests.testSendStopsListeningDismissesAndUploadsTheReport`
  (one line), `RepairFeatureRequestTests.testVoiceOnlyRequestIsSentWithoutAStroke` (one line).
- Change: the encoder test no longer asserts `view.width/height/scale/units/pointFormat` or
  `sessionStartedAt` on the decoded document; it asserts the decoded `[RepairStroke]` equals the
  points given to the builder, and adds a check that the raw `strokesJSON` parses as
  `[[[Double]]]`. In the other two tests `RepairStrokesJSON.decode(...).strokes` becomes
  `RepairStrokesJSON.decode(...)` (decode now returns `[RepairStroke]`); the assertions on count,
  points and `== []` after each line are unchanged.
- Reason: repair intake merged to main 2026-10-13/14 (`backend/src/repairs.ts`, `jsonArrayPart`,
  "strokes must be a JSON array", 400) rejects the object `{view, sessionStartedAt, strokes}` the
  shell used to send; the backend fixture `backend/test/helpers/repair-fixtures.ts` `STROKES` is
  `[[[10,20,0],[30,40,50]],[[100,100,900]]]`, one point list per stroke. The old encoder test was
  asserting a payload the server refuses, so it checked the wrong thing; `shell/Midas/RepairReport.swift`
  `RepairStrokesJSON` now encodes that array and `decode` returns `[RepairStroke]`.
- Proof it can still fail: xcodebuild was not run here (the caller runs the shell suite). A stub
  copy of `RepairStrokesJSON` and `RepairStroke` with the new assertions was run under `swift`
  twice: with the real encoder all four checks pass; with the encoder swapped for the old object
  shape `{view, sessionStartedAt, strokes}` the check "intake requires a JSON array of point lists"
  fails (`parsed as? [[[Double]]]` is nil), exit 1. The points assertion fails on its own if the
  encoder drops or reorders points. No app code was changed for the proof.

## 2026-10-13: backend/test/runner-agent.test.ts, runner-job.test.ts, runner-feature-kind.test.ts, runner-check-and-intel.test.ts, runner-deploy.test.ts, helpers/runner-fixture.ts (tests move every copy forward)

- Reason: founder decision, 2026-10-13, `docs/briefs/repair-contract.md` "Settled", bullet
  "Tests move every copy forward": "Each user copy has its own tests and its own `TEST_CHANGES.md`
  [...] A repair job gets them in `tests/`; the repair agent may **add** tests but never change or
  delete one: the runner fails the job if any existing test file differs from what the job started
  with, unless test-guardian changed it. [...] the agent delegates to test-guardian [...] The tests
  and log are deployed together with the page." Code: `runner/lib/copy-tests.mjs` (new),
  `check.mjs` (`runSidekickTests` replaced by `runCopyTests` over a sandbox checkout), `job-folder.mjs`
  (tests/ and the three `.claude/` guard files allowed), `agent.mjs` (`Agent(test-guardian)` allowed,
  built-in subagents denied by name), `deploy.mjs` (`--tests <job>/tests`), `run-job.mjs`.
- helpers/runner-fixture.ts, `makeScratch()`: the scratch checkout now also holds the three guard
  files (`.claude/settings.json`, `.claude/hooks/guard_tests.py`, `.claude/agents/test-guardian.md`,
  exported as `GUARD_FILES`) and two base Reminders tests, `reminders-logic.test.ts` and
  `reminders-wording.test.ts` (exported as `baseRemindersTestFiles()`; a fixed pair so the exact
  listings below hold and the new `runner-copy-tests.test.ts`, which seeds the same two, agrees).
  Without them every `runJob` test fails "runner error: checkout has no .claude/settings.json".
- runner-agent.test.ts, `allows file tools and Bash for exactly the intel and check scripts`: the
  exact allowed list gains `"Agent(test-guardian)"` as its last entry; added: allowed contains
  `"Agent(test-guardian)"` and no bare `"Agent"` / `"Agent(*)"` rule. `denies web, subagents and loads
  no MCP servers, skills or user settings` renamed `denies web and every built-in subagent, and loads
  no MCP servers, skills or user settings`: `toContain("Agent")` became `toContain("Agent(Explore)")`,
  plus `toContain("Agent(Plan)")`, `toContain("Agent(general-purpose)")` and
  `not.toContain("Agent(test-guardian)")`. The `toEqual(AGENT_DENIED_TOOLS)` and flag assertions are unchanged.
- runner-job.test.ts, `builds a job folder holding only the Sidekick, the report and outcome.json`
  renamed `builds a job folder holding only the guard, the Sidekick, the report, the copy's tests and
  outcome.json`: the exact listing gains `.claude/agents/test-guardian.md`, `.claude/hooks/guard_tests.py`,
  `.claude/settings.json` at the front and `tests/TEST_CHANGES.md`, `tests/reminders-logic.test.ts`,
  `tests/reminders-wording.test.ts` at the end (the last two via `baseRemindersTestFiles()`, asserted
  non-empty). Nothing else in the file changed.
- runner-feature-kind.test.ts, `a voice-only feature request runs to deployed_live without a drawing
  or strokes`: the same listing change (no drawing/strokes entries). Nothing else changed.
- runner-check-and-intel.test.ts: `copies the repaired page into the checkout for the tests and
  restores the original, pass or fail` (used the removed `runSidekickTests`) replaced by `runs the
  tests in a sandbox that holds the repaired page, leaves the checkout's page untouched and removes
  the sandbox, pass, fail or crash`, against `runCopyTests`: inside `runTests` the page at
  `<sandboxBackend>/../sidekicks/reminders/index.html` contains `<title>Repaired</title>` and the
  sandbox (`sandboxRootFor(jobFolder)`) exists; after pass, fail and a thrown error the checkout's
  `sidekicks/reminders/index.html` equals the original and the sandbox is gone. `a Sidekick the
  checkout does not have cannot pass` deleted: `buildSandboxCheckout` copies the job's page for any
  id, so there is no "checkout has no sidekicks/<id>/" refusal in the code any more; the behaviour
  it checked no longer exists. The gate and `checkSidekick` tests are unchanged.
- runner-deploy.test.ts, `builds the live user deploy for the reporter from the job folder`: the
  exact `deployArgs` expectation gains `"--tests", "/jobs/rep-9/tests"` at the end. The e2e
  `args.slice(0, 4)` / `--user` / `--dir` assertions are unchanged.
- Proof (each break in app code, run, restored byte-identical, checked with `cmp`):
  removing `` `Agent(${GUARDIAN_AGENT})` `` from `agentAllowedTools` in `agent.mjs` fails the
  allowed-list test (`expected [...(7)] to deeply equal [...(8)]`, 1 failed / 7 passed);
  removing `args.push("--tests", ...)` in `deploy.mjs` fails the deployArgs test
  (`[...(8)] to deeply equal [...(10)]`, 1 failed / 10 passed);
  making `buildSandboxCheckout` in `check.mjs` copy the checkout's page instead of the job's fails
  the new sandbox test (`expected '<!doctype html>...' to contain '<title>Repaired</title>'`,
  1 failed / 6 passed); making `writeAgentSettings` in `copy-tests.mjs` copy nothing fails both
  job-folder listing tests (`[ 'outcome.json', ...(8) ] to deeply equal [ ...(12) ]`, 2 failed / 14 passed).
- Result: `npx vitest run test/runner-` 7 files, 69 tests, all passing (runner-agent,
  runner-check-and-intel, runner-copy-tests, runner-deploy, runner-feature-kind, runner-job,
  runner-loop-config-prompt). `scripts/test-all.sh` not run in this session (the shell step hangs
  on this machine; the lead runs the suites).

## 2026-10-13: backend/test/runner-job.test.ts, runner-feature-kind.test.ts, helpers/runner-fixture.ts (the runner publishes the fix itself)

- Tests: `runJob end to end > runs a fake job to fix_ready: statuses, diff, summary with the live
  command, notifications` (runner-job.test.ts), renamed `... runs a fake job to deployed_live: statuses,
  diff, summary with the live version, notifications`; `feature kind > a voice-only feature request runs
  to fix_ready without a drawing or strokes` (runner-feature-kind.test.ts), renamed `... runs to
  deployed_live ...`; the shared fixture `makeScratch` in helpers/runner-fixture.ts.
- Change, runner-job.test.ts: `runWith()` builds `fakeDeployThatLands()` and passes its `runDeploy` /
  `readPointer` into `runJob`, and returns `deploy`. In the renamed test: `result.status` expected
  `"deployed_live"` (was `"fix_ready"`); status names expected `["running", "fix_ready", "deployed_live"]`
  (was `["running", "fix_ready"]`); `statuses[1].summary` assertion kept; added
  `statuses[2]` equals `{ status: "deployed_live", summary: "Renamed the page title to My Reminders.",
  version: "v-test" }`; added `deploy.deployCalls` has length 1, its `--user` value is `"user-77"` and
  it does not contain `--from-base`. The three summary assertions on
  `node scripts/deploy-sidekick.mjs reminders --env live --user user-77 --dir <job>/sidekick`,
  `--user founder-live-id --dir <job>/sidekick` and the founder-before-reporter ordering were replaced by:
  summary contains `Version v-test is live for user user-77`, contains
  `node scripts/deploy-sidekick.mjs reminders --env live --user user-77 --from-base`, and does not
  contain `founder-live-id`. Notification titles expected `["Repair request: reminders",
  "Fixed and live: reminders"]` (was `"Fix ready: reminders"`). Diff, agent-stream, system-prompt and
  testRuns assertions unchanged.
- Change, runner-feature-kind.test.ts: `runFeatureJob()` passes `runDeploy` / `readPointer` from
  `fakeDeployThatLands()`; in the renamed test `result.status` expected `"deployed_live"` and the status
  names `["running", "fix_ready", "deployed_live"]`. Everything else in the file unchanged.
- Change, helpers/runner-fixture.ts: removed `founderUserId: "founder-live-id"` from `makeScratch`
  settings (the setting no longer exists in runner/lib/config.mjs); added exported `DeployCall` type and
  `fakeDeployThatLands()` (runDeploy records `{checkoutRoot, args}` and resolves ok with
  `deployed reminders v-test for user <uid> to live`; readPointer returns version `v-test` with the
  `bundleContentHash` of index.html + manifest.json from the `--dir` folder of the last deploy call);
  imports `bundleContentHash` from `../../scripts/bundle-tools.mjs`.
- Reason: founder decision, 2026-10-13 (later the same day), `docs/briefs/repair-contract.md` "Settled"
  on main: "The runner publishes the fix itself ... replaces 'the runner never deploys'. After the gate
  and the Sidekick's tests pass, the runner (its own Node code, not the Claude session) runs
  `deploy-sidekick.mjs <id> --env live --user <uid> --dir <job folder>` for the reporter's copy only,
  never a base deploy, then checks the deploy landed (reads back the user's `current.json` and compares
  the content hash) and only then posts `deployed_live`. ... A failed deploy or check posts `failed`. No
  founder step." The founder preview step (`--user founder-live-id`) and the `--dir` deploy commands in
  summary.md are gone from the runner; the way back is `--from-base`. Before the change both tests
  failed with `expected 'failed' to be 'fix_ready'` (with no injected deploy the runner ran the real
  deploy script, which failed). After: `npx vitest run test/runner-` gives 6 files, 54 passed.
- Proof it can still fail (app code broken, run, restored from a copy and checked with `diff`):
  1. runner/lib/run-job.mjs: the final `postStatus(..., "deployed_live", ...)` and the returned status
     changed to `"fix_ready"` (the deploy step skipped in effect). Both renamed tests failed:
     `expected 'fix_ready' to be 'deployed_live'` (2 failed | 14 passed).
  2. runner/lib/summary.mjs: `--from-base` removed from the way-back command. runner-job test failed:
     `expected '# Repair rep-1: reminders ...' to contain 'node scripts/deploy-sidekick.mjs remi…'`
     (1 failed | 9 passed).
  3. runner/lib/run-job.mjs: `publishFix` called with `userId: "someone-else"` instead of `job.userId`.
     runner-job test failed on the reporter-only check: `expected 'someone-else' to be 'user-77'`
     (1 failed | 9 passed).

## 2026-10-13: backend/test/runner-agent.test.ts "runAgent > runs the command in the job folder and keeps its output in the log" (macOS temp-dir symlink)

- Test: `runAgent > runs the command in the job folder and keeps its output in the log` (line 97).
- Change: `realpathSync` added to the `node:fs` import; the assertion `expect(logged.cwd).toBe(scratch)`
  became `expect(realpathSync(logged.cwd)).toBe(realpathSync(scratch))`, with a one-line comment. Nothing
  removed or widened: the test still requires the child's working directory to be the job folder.
- Reason: test bug, not a runner bug. The test was written 2026-10-13 for the repair runner
  (`docs/briefs/repair-runner.md`, step 2) and had never passed. On macOS `mkdtempSync(tmpdir())` returns
  `/var/folders/...` while the child reports `process.cwd()` as `/private/var/folders/...` (the `/var` ->
  `/private/var` symlink), so the string comparison failed although the runner spawns in the job folder
  (`runner/lib/agent.mjs` line 73, `cwd: jobFolder`). Comparing real paths checks the intended thing.
- Proof it can still fail: with the edited test, `npx vitest run runner-agent` gave 8 passed. Then
  `runner/lib/agent.mjs` line 73 was changed from `cwd: jobFolder` to `cwd: tmpdir()`; the run gave
  "1 failed | 7 passed", this test failing with Expected `/private/var/.../T/runner-agent-zmRk4i`,
  Received `/private/var/.../T`. The runner file was restored from a copy and checked with `cmp`.

## 2026-10-13: backend/test/repairs.test.ts, describe "repair log" > "never deletes a report" (deleted)

- Test: `describe("repair log")` with its one test `it("never deletes a report")`, the last block
  of `backend/test/repairs.test.ts` (new, uncommitted file from the repair-intake agent). It
  asserted that `DELETE FROM repair_reports WHERE id = ?` throws `/never deleted/` and leaves the
  row. Nothing else in the file changed (16 tests remain, none edited).
- Change: the whole describe block removed.
- Reason: bug found 2026-10-13 running `scripts/test-all.sh`. The test depended on a
  `CREATE TRIGGER repair_reports_are_never_deleted BEFORE DELETE ON repair_reports ... RAISE(ABORT,
  'repair reports are never deleted')` in `backend/migrations/0005_repairs.sql`. The existing
  guard `backend/test/no-data-loss.test.ts` "migrations only add: no DROP, DELETE, REPLACE or
  TRUNCATE in any migration" flags the `DELETE` token in that trigger (`migrationViolations` on the
  trigger text returns `["DELETE"]`), so the trigger cannot live in a migration. Decision behind
  that guard: `docs/PRODUCT.md` section 5, "2026-10-10, backend: **no user data may be lost, from
  now on** ... **Only the founder runs database operations that delete**; agents never run deleting
  statements against a remote database." The repair-intake agent removed the trigger from the
  migration (its comment now reads "The log is never shortened: the no-data-loss suite forbids any
  statement that removes rows here, in Worker code, scripts and migrations alike"); without it the
  test failed with `expected [Function] to throw error matching /never deleted/ but got 'FOREIGN
  KEY constraint failed'`. The guarantee it checked (no repair report is ever deleted) is already
  enforced by the same suite's Worker-code scanner (only `DELETE FROM auth_challenges WHERE id = ?`
  is allowed in `backend/src/*.ts`) and script scanner (no delete at all in `backend/scripts/*.mjs`),
  so the removed test duplicated an existing guard with a mechanism that guard forbids.
- Proof the remaining guard can still fail for this reason: appended
  `export const PURGE_SQL = "DELETE FROM repair_reports WHERE id = ?";` to `backend/src/repairs.ts`;
  `no-data-loss.test.ts` > "the Worker deletes only a used sign-in challenge and never rewrites
  rows by replace" failed with `{ ".../backend/src/repairs.ts": ["DELETE FROM repair_reports WHERE
  id = ?"] }` not equal to `{}`. File restored from a copy and checked with `cmp`. Also ran
  `migrationViolations` on the removed trigger text from a scratch test: `["DELETE"]`, confirming
  the trigger and the migration guard cannot coexist.

## 2026-10-13: shell/MidasTests/RepairOutboxTests.swift and RepairSessionTests.swift (Swift 6 locking shape in two stubs)

- Tests: every test in `RepairOutboxTests` and `RepairSessionTests` (both files new today, uncommitted,
  on branch `agent/repair-shell`, never run green). No test method, assertion or fixture changed.
- Change: in the test stubs only. `StubRepairUploadAPI.upload` (RepairOutboxTests) now calls a new
  synchronous `takeNextOutcome(for:)` that holds the lock and does what `upload` did inline.
  `RecordingUploadAPI.upload` (RepairSessionTests) now calls a new synchronous `record(_:)` that holds
  the lock around `reports.append`. Behaviour of both stubs is identical; only the lock calls moved out
  of the `async` body.
- Reason: bug in the tests. Swift 6 language mode rejects `NSLock.lock()`/`unlock()` directly inside an
  `async` function ("instance method 'lock' is unavailable from asynchronous contexts; Use async-safe
  scoped locking instead") at RepairOutboxTests.swift:17-18 and RepairSessionTests.swift:38,40, so the
  shell test target did not compile.
- Proof it can still fail: not run by the guardian; the requesting agent asked that xcodebuild not be run
  here and runs the shell suite itself. The assertions (`pendingCount`, `uploadedIds` order, restored
  report equality, `reports` contents, expectation fulfilment) are untouched, so they fail for the same
  reasons as before the edit. The shell suite result belongs to the requesting agent's run.

## 2026-10-12: shell/MidasTests/CareRemindersHourlyRepeatTests.swift (hourly repeat, Change 2)

- Test: `testAnHourlyReminderShowsAsOneRowAtItsNextTime` (new this session, uncommitted, edited before
  first commit at the care-repeat agent's request).
- Change: the row detail was checked with `contains("Tomorrow 09:00")`. The page formats times with the
  device locale and zone (`Intl.DateTimeFormat(undefined, ...)`), so the Simulator shows
  "Tomorrow 9:00 AM". The script now also returns `CareLogic.whenText(<tomorrow 09:00 Los Angeles in ms>,
  Date.now(), CareLogic.deviceTimeZone())`, and the test asserts the trimmed row detail equals it
  (exact equality, stronger than the old `contains`). The expected instant is computed in Swift by the
  file's `instant(daysFromToday: 1, hour: 9, minute: 0)` helper, not by the page.
- Reason: bug in the test, a hard-coded 24-hour, locale-specific string. Failure seen before the change:
  `XCTAssertTrue failed - the row is not at its next time: Tomorrow 9:00 AM`. Behaviour covered is from the
  founder decision of 2026-10-12 (`docs/PRODUCT.md`, care-reminders change 2; brief `CHANGE-2.md`: "The
  reminder shows as a single row", "One row, shown at its next due time").
- Proof it can still fail: the edited test passed alone (`-only-testing:` this test, TEST SUCCEEDED). Then
  in `sidekicks/care-reminders/index.html` `whenOf`, `entry.shown.at` was changed to
  `entry.shown.at + 2 * 3600000`. The test failed at line 202: `XCTAssertEqual failed: ("Tomorrow 11:00 AM")
  is not equal to ("Tomorrow 9:00 AM") - the row is not at its next time`. The page was restored from a
  copy and checked byte-identical with `cmp`.

## 2026-10-12: shell/MidasTests/CareRemindersSidekickTests.swift (Add Reminder simplified, Change 1)

- Tests: `testEveryTwoHoursFromEightToTenWritesEightDailyRepeats` deleted. Call shape adapted in
  `createAppointment` (used by `testAppointmentWithThreeRulesWritesFourRecordsTheEngineAccepts`,
  `testDoneWrittenByTheShellOnOneAlertCompletesTheEventAfterAReload`,
  `testDoneInThePageCompletesTheEventAndRemovesItsAlerts`), `testAnAlertWhoseTimeHasAlreadyPassedIsSkipped`,
  `testEditingAListRuleRewritesTheAlertsOfItsReminders` and `testDeletingAListRemovesItsRemindersAndUndoRestoresThem`.
- Change: in the JS passed to `CareApp.saveReminder`, `times: [...]` became `time: '...'`, and `icon` and
  `alertMode: 'list'` were removed. `saveReminder` now returns one item id, so `ids[0]`, `first[0]` and
  `second[0]` became the returned id. No Swift assertion was changed, removed or widened. The deleted test
  covered several times a day (`CareLogic.timesEvery`, multi-time `times`), which no longer exists.
- Reason: founder decision, 2026-10-12, written in `docs/PRODUCT.md` section 6, "care-reminders Sidekick,
  2026-10-12 (founder)" (commit 4ce9e60): "Add/Edit Reminder (founder, 2026-10-12, change 1): title, Date,
  Time, Repeat only. No icon (a reminder shows its list's icon), no list field (added from inside a list),
  no own alerts, no several-times-a-day. Tests for the removed behaviour go." Brief: `CHANGE-1.md`.
  New tests for the new behaviour are in `shell/MidasTests/CareRemindersSimpleSheetTests.swift`.
- Proof it can still fail: with the edited tests, all 8 tests in the class passed. Then, in
  `sidekicks/care-reminders/index.html` `saveReminderTask`, the new-item branch was changed from
  `time: draft.time` to `time: '06:00'`. `-only-testing:MidasTests/CareRemindersSidekickTests` gave
  "Executed 8 tests, with 11 failures". 5 tests failed: Appointment (line 190 keys missing `~a2`;
  line 198 `2026-10-15 13:00` not `20:00`), AlertAlreadyPassed (line 234 `~p3` missing),
  DoneWrittenByTheShell (line 243 `3` not `4`), DoneInThePage (line 269 `3` not `4`), EditingAListRule
  (line 296 "the alert of Mum in 30 min did not move"). The page was restored from a copy and checked with `cmp`.

## 2026-10-12: shell/MidasTests/RemindersWidgetTests.swift testAllDayComesFirstAsInTheSidekick renamed testUntimedComesAfterTimedReminders (Today's order)

- Test: `TodayReminderPlannerTests.testAllDayComesFirstAsInTheSidekick` (line 155), now
  `testUntimedComesAfterTimedReminders`.
- Change: name; expected order `["insurance", "reply", "push", "call", "gym"]` becomes
  `["reply", "push", "call", "gym", "insurance"]`; a comment added citing the decision. Fixture
  unchanged (reply 9:00, push 14:00, call 18:00, gym 19:30 daily, insurance all-day at 9:00), and
  it implies exactly this timed-first order. Still one exact-value assertion.
- Reason: founder decision, 2026-10-11, `docs/PRODUCT.md` section 6, Reminders widget (line 572,
  merged in bbc4dca): "Today's order: reminders with a time first, earliest first, then untimed
  ones (founder, 2026-10-11); the Sidekick's Today follows." Production change (made by the
  caller, not here): `RemindersWidgetLayout.isShownBefore` returns `!first.allDay`. Before the
  test change it failed against that code: `("["reply", "push", "call", "gym", "insurance"]") is
  not equal to ("["insurance", "reply", "push", "call", "gym"]")`.
- Proof it can still fail: in `shell/Shared/RemindersWidgetShared.swift` `isShownBefore`, changed
  `if first.allDay != second.allDay {` to `if false && first.allDay != second.allDay {`;
  `-only-testing:MidasTests/TodayReminderPlannerTests` failed `RemindersWidgetTests.swift:160:
  XCTAssertEqual failed: ("["insurance", "reply", "push", "call", "gym"]") is not equal to
  ("["reply", "push", "call", "gym", "insurance"]")` (the all-day reminder ties reply at 9:00 and
  sorts first by id without the rule). File restored from a copy and checked with `cmp`.

## 2026-10-11: shell/MidasTests/RemindersWidgetTickQueueTests.swift testAFailedWriteStaysQueuedForTheNextTry (setup did not force a failed save)

- Test: `testAFailedWriteStaysQueuedForTheNextTry` (new, uncommitted file from the widget-reminders agent).
- Change: setup only. The store path `missing-folder/records.json` is replaced by a path under a
  plain file (`not-a-folder/records.json`), and the first `set` is now `XCTAssertThrowsError`
  instead of `try?`, so the test proves its saves fail. The three assertions after
  `publisher.tick(...)` are unchanged.
- Reason: bug in the test. `LocalRecordStore.save()` calls `createDirectory(withIntermediateDirectories: true)`,
  so `missing-folder` was created, the save succeeded and the queue emptied; the test failed with
  `("nil") is not equal to ("Optional(2026-10-12 01:00:00 +0000)")` against correct code. Behaviour
  covered: founder, 2026-10-11 (`docs/PRODUCT.md` section 6, Reminders widget): a widget tick stays
  queued in the App Group until the record write succeeds.
- Proof it can still fail: in `shell/Midas/RemindersWidgetPublisher.swift` `writeTick`, changed the
  `catch` branch from `return false` to `return true`; `-only-testing:MidasTests/RemindersWidgetTickQueueTests`
  failed `RemindersWidgetTickQueueTests.swift:87: XCTAssertEqual failed: ("nil") is not equal to
  ("Optional(2026-10-12 01:00:00 +0000)")`. File restored from a copy and checked with `cmp`.
  With the code restored, all 3 tests in the class pass.

## 2026-10-11: shell/MidasTests/FolderWidgetLayoutTests.swift testTheWidgetUsesOnlyTheFourApprovedPhrases (widget renamed)

- Test: `testTheWidgetUsesOnlyTheFourApprovedPhrases`, line 11.
- Change: `XCTAssertEqual(FolderWidgetCopy.displayName, "Folder")` now expects `"Sidekicks"`.
  The other three phrase assertions are unchanged; the check is still one exact value.
- Reason: founder decision, 2026-10-11, written in `docs/PRODUCT.md` section 6 under "Sidekicks
  outside the shell": "Widget gallery name is "Sidekicks", not "Folder" (founder, 2026-10-11): no
  name that borrows an Apple Home Screen feature." Same decision in midas-intel design doc,
  "### Mission and Sidekicks outside the shell, 2026-10-11", item 6. `docs/briefs/widget-extension.md`
  lines 19 and 47 updated to match. Before the change the test failed against the renamed code:
  `("Sidekicks") is not equal to ("Folder")`.
- Proof it can still fail: set `FolderWidgetCopy.displayName` back to `"Folder"` in
  `shell/Shared/FolderWidgetLayout.swift`; `xcodebuild test -only-testing:MidasTests/FolderWidgetLayoutTests`
  failed `FolderWidgetLayoutTests.swift:11: XCTAssertEqual failed: ("Folder") is not equal to
  ("Sidekicks")`. File restored from a copy and checked with `cmp`.

## 2026-10-11: tests/guard/test_release_config.py, two tests (widget extension target)

- Tests: `test_info_plist_takes_version_and_build_from_project_settings` and
  `test_every_build_uses_the_one_production_entitlements_file`.
- Change: both tests now cover every signed target listed in a new `TARGET_ENTITLEMENTS` map
  (`Midas` -> `Midas.entitlements`, `MidasWidgets` -> `MidasWidgets.entitlements`). The first
  test checks `shell/Midas/Info.plist` and `shell/MidasWidgets/Info.plist` with the same plistlib
  check (`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`) and requires project.yml to hold
  exactly two `CFBundleShortVersionString` and two `CFBundleVersion` lines, every one equal to
  those variables. The second test requires `CODE_SIGN_ENTITLEMENTS` in project.yml to equal
  `["Midas/Midas.entitlements", "MidasWidgets/MidasWidgets.entitlements"]` (project.yml order)
  and each of `shell/Midas/` and `shell/MidasWidgets/` to hold only its one entitlements file.
  Nothing the tests checked before is checked less strictly; the widget target is added.
- Reason: founder plan approved 2026-10-11, `docs/PRODUCT.md` section 6 "Sidekicks outside the
  shell (founder, 2026-10-11)" and `docs/briefs/widget-extension.md` step 1: a second target
  `MidasWidgets` (app-extension, `com.bhuvanrj.midas.widgets`) with its own entitlements file
  `MidasWidgets/MidasWidgets.entitlements` (App Group `group.com.bhuvanrj.midas`) and an `info`
  block whose version and build must come from the same project settings as the app's (an
  extension whose version differs from the app's fails App Store upload). Before the change both
  tests failed on the worktree (`['$(MARKETING_VERSION)', '$(MARKETING_VERSION)'] !=
  ['$(MARKETING_VERSION)']` and the two-element `CODE_SIGN_ENTITLEMENTS` list).
- Proof it can still fail (worktree `agent/widget-extension`, each file restored and checked with
  `cmp` afterwards): (1) hard-coded `0.1.0` in `shell/MidasWidgets/Info.plist`: first test failed
  `'0.1.0' != '$(MARKETING_VERSION)'`. (2) `CFBundleVersion: "7"` in project.yml: first test failed
  `['7', '7'] != ['$(CURRENT_PROJECT_VERSION)', '$(CURRENT_PROJECT_VERSION)']`. (3) widget target's
  `CODE_SIGN_ENTITLEMENTS` pointed at `Midas/Midas.entitlements`: second test failed `Lists differ:
  ['Midas/Midas.entitlements', 'Midas/Midas.entitlements'] != [...]`. (4) stray
  `shell/MidasWidgets/Debug.entitlements`: second test failed `['Debug.entitlements',
  'MidasWidgets.entitlements'] != ['MidasWidgets.entitlements']`; file removed.

## 2026-10-11: midas-intel intel/tests/test_notifications_reference.py test_urgent_section_ties_to_alarm_options_and_its_files_exist (added)

- Change: one new test method added to an existing midas-intel test file
  (`~/code/midas-intel/intel/tests/test_notifications_reference.py`); no existing assertion
  changed or removed. It requires the section `### Apple Reminders "Urgent"` in
  `docs/research/ios-notifications-reference.md` to exist, to name A01 and A02, that both are
  option blocks in the reference, and that every local `docs/...` file it cites exists. Written
  by the notification-mockups agent; logged here because midas-intel has no TEST_CHANGES.md.
- Reason: the doc gained the sections "On the Lock Screen, before and after long-press" and
  "Apple Reminders "Urgent", and how the same is built" on 2026-10-11 from the founder's questions
  (midas-intel commit ec8a5b8). This is a stricter check that matches the committed doc.
- Proof it can still fail: in a scratch copy of midas-intel at ec8a5b8 with the new test file, the
  test passed; then replaced "A01" with "Axx" in the Urgent section and it failed with
  `'A01' not found in '### Apple Reminders "Urgent"...'`; restored the doc and deleted
  `docs/research/reminders/group-a.md` and it failed with `missing file
  docs/research/reminders/group-a.md`. The real repo was not touched.

## 2026-10-10: ShellDesignTests.swift testWelcomeButtonsUseTheChosenWording (returning-user button, W5)

- Change: `shell/MidasTests/ShellDesignTests.swift`, expected `WelcomeCopy.returningUserButton`
  "I've used Midas before" becomes "Sign In"; the MARK comment "Welcome wording (option B)"
  becomes "Welcome wording (WRITING.md, 2026-10-10)". Still an exact-equality check.
- Reason: founder decision, `docs/PRODUCT.md` section 5, entry "2026-10-10, wording" (commit
  4ba78bc): "Welcome screen: "Get Started" and **"Sign In"** (W5, replacing option B "I've used
  Midas before", chosen earlier the same day)". This settles the W5 item left open in the entry
  below.
- Proof it can still fail: in a scratch copy of the shell at commit 34d1ee2 with the changed test
  file, the test passed; then changed `returningUserButton` in `Midas/WelcomeView.swift` from
  "Sign In" to "Sign in" and it failed at ShellDesignTests.swift:12 `("Sign in") is not equal to
  ("Sign In")`. File restored (`cmp` identical to the worktree's). Working tree app code not
  touched.

## 2026-10-10: ShellDesignTests.swift testWelcomeButtonsUseTheChosenWording (new-user button only), AppleRemindersImportTests.swift testRemindersPermissionTextIsTheFoundersWording

- Change: `shell/MidasTests/ShellDesignTests.swift`, expected `WelcomeCopy.newUserButton`
  "Get started" becomes "Get Started". `shell/MidasTests/AppleRemindersImportTests.swift`,
  expected `NSRemindersFullAccessUsageDescription` becomes "Midas imports your Apple Reminders
  lists and reminders into your Reminders Sidekick." Still exact-equality checks.
- Reason: founder decision, `docs/WRITING.md` ("Founder, 2026-10-10"), adopted in
  `docs/PRODUCT.md` section "Few words on screen (2026-10-10)". Rule 11: "buttons and fragment
  titles in Title Case"; swap table: "Continue with a passkey | (the action itself: "Get
  Started")". Rule 10 gives the permission sentence verbatim: "Midas imports your Apple Reminders
  lists and reminders into your Reminders Sidekick." Founder approval of mockup rows W4 and P1
  (`docs/mockups/wording-2026-10-10.html`) reported by the lead session.
- Not changed: the `returningUserButton` assertion ("I've used Midas before", row W5, "Sign In").
  "Sign In" is not in `docs/WRITING.md` or `docs/PRODUCT.md`, and the mockup marks W5 UNSURE and
  lists it under "Questions for the founder". Needs a written, dated founder decision first.
- Proof it can still fail: in a scratch copy of the shell at commit ea76871 (old app strings:
  "Get started" and the old permission sentence) with the two changed test files, ran both tests
  on the iPhone 17 simulator. Both failed: ShellDesignTests.swift:11 `("Get started") is not
  equal to ("Get Started")`; AppleRemindersImportTests.swift:258 old sentence not equal to the
  new one. Working tree app code not touched.

## 2026-10-10: LocalChannelWebViewTests.swift, testLargeBodyArrivesWhole

- Change: `shell/MidasTests/LocalChannelWebViewTests.swift`. The 200,000-character set is kept,
  but it is now expected to be refused: the reply is parsed as JSON and must have `ok == false`
  and an `error` containing "65536" (the size refusal, which is only reached when the whole body
  parsed; a cut body gives "body is not JSON"), and nothing is stored under `note:big`. Added a
  60,000-character set (`note:large`, several 16,384-byte chunks, under the cap): reply must be
  `{"ok":true}` and the stored value must read back at 60,000 characters and equal to what was
  sent. Added a small `parseReply` helper (the reply's key order is not stable).
- Reason: founder decision, `docs/PRODUCT.md` section 5: "2026-10-10, records: **one record may
  hold at most 64 KB** (the record's JSON text), on the phone and on the server, so every record
  the phone accepts can be backed up." Implemented as `SidekickStoreChannel.maxValueBytes`
  (65,536); the old test expected the 200,000-character value to be stored and failed at lines
  104-105 with `{"error":"value is over 65536 bytes","ok":false}`.
- Proof it can still fail: in `shell/Midas/SidekickSchemeHandler.swift` `readBody`, changed
  `return bodyData` to `return bodyData.prefix(16_384)` (body cut after one chunk). The test
  failed 4 times: line 119 (`error` was "body is not JSON"), line 126 (reply not `{"ok":true}`),
  lines 128-129 (nothing stored). File restored from a copy (`cmp` clean).
- Observed: a first break that cut only the `httpBodyStream` loop after one chunk did not fail
  the test, because in the iPhone 17 simulator WebKit delivered these bodies (up to 200,000 bytes)
  as `httpBody`. The stream branch of `readBody` is therefore not exercised by this test (it was
  not by the old one either). The test comment no longer claims it is.

## 2026-10-10: RecordSyncTests.swift, FakeSyncServer.push (test double, style only)

- Change: `shell/MidasTests/RecordSyncTests.swift`, in the fake server's `push`, the duplicate
  check `if !storedOps.contains(where: { $0.op.opId == op.opId }) {` becomes
  `if !storedOpIds().contains(op.opId) {` (the existing helper). Same behaviour: an op_id already
  stored is skipped. No assertion changed.
- Reason: founder style guide (`~/.claude/CLAUDE.md`: no inline anonymous functions in method
  chains, no chained one-liner calls). Not a behaviour change.
- Proof it can still fail: replaced the check with `if true {` (every push stored, no dedup):
  `RecordSyncTests.testAPushWhoseReplyWasLostIsResentAndStoredOnce` failed at line 234,
  `XCTAssertEqual failed: ("2") is not equal to ("1")`. File restored byte-for-byte from a copy
  (`cmp` clean).

## 2026-10-10: AuthTests.swift, EntitlementsTests.testAssociatedDomainMatchesPlatformOrigin

- Change: `shell/MidasTests/AuthTests.swift`. The single assertion
  `PlatformConfig.platformOrigin.host == "midas-api.midas-backend.workers.dev"` is replaced by
  three: the app's platform host is one of `PlatformConfig.liveHost` / `PlatformConfig.stagingHost`;
  `PlatformConfig.liveHost == "midas-api.midas-backend.workers.dev"`; and `backend/src/auth.ts`
  (read from disk) still contains `export const RELYING_PARTY_ID = "<liveHost>";`. Purpose kept:
  the app's passkey domain is the backend's relying party id. Which host a Debug build uses, the
  unknown-host fallback to live, and the entitlements listing both domains are covered by the new
  `PlatformConfigTests` in `shell/MidasTests/SidekickDirectoryTests.swift`.
- Reason: founder decision, 2026-10-10. `docs/briefs/backend.md` (outline approved 2026-10-10),
  phase 1: "Staging Worker `midas-api-staging` with its own D1 and R2. ... Passkeys are bound to
  the domain, so staging needs its own association file and its own `webcredentials:`
  entitlement, and the shell a build setting that picks staging or live." `docs/PRODUCT.md`
  section 5, 2026-10-10: "Backend changes go to a **staging Worker** before the live one."
  Implemented in `shell/project.yml` (Debug: staging, Release: live). Tests run as Debug, so the
  host is now the staging host and the old literal failed.
- Proof it can still fail: (1) set `liveHost` in `shell/Midas/PlatformConfig.swift` to
  `midas-api-v2.midas-backend.workers.dev`: the test failed twice, `XCTAssertEqual failed:
  ("midas-api-v2.midas-backend.workers.dev") is not equal to ("midas-api.midas-backend.workers.dev")`
  and the auth.ts `XCTAssertTrue failed`. (2) set `platformOrigin` to `https://evil.example`: the
  test failed with 1 failure (the one-of-two-hosts assertion). File restored byte-for-byte from a
  copy after each break.

## 2026-10-10: bundle-route.test.ts, describe "GET /sidekicks/:id/bundle"

- Change: `backend/test/bundle-route.test.ts`, the four tests "serves the current version's html
  with its script hashes", "returns 404 for a sidekick that was never deployed", "rejects ids
  that could escape the sidekick prefix" and "returns 500 when the pointer names a version that
  is not stored" are replaced by one test, "refuses a request with no session": GET
  `/sidekicks/reminders/bundle` with no Authorization header answers 401 and the body is not the
  bundle html. The CORS and /health describes are unchanged. The four behaviours are re-covered,
  with a real session and assignment on a migrated SQLite D1, in the new file
  `backend/test/sidekicks-catalog.test.ts` (same names, same or stronger assertions; the 200 case
  also checks Content-Type, version and hashes header and body), plus a new test that a deployed
  but unassigned Sidekick answers 404.
- Reason: founder decision, 2026-10-10. `docs/briefs/backend.md`, outline approved 2026-10-10:
  "`GET /sidekicks/:id/bundle` requires a session (`requireSession` in `backend/src/auth.ts`) and
  that the Sidekick is assigned to the user (D5: "a bundle cannot be fetched without a valid
  token")." `docs/PRODUCT.md` D5 done-when: "a bundle cannot be fetched without a valid token";
  section 5, 2026-10-10: "Sidekicks are **assigned per person**". The old tests sent no session
  and their fake DB could hold neither sessions nor assignments, so all four got 401.
- Proof it can still fail: (1) removed `sidekickRoutes.use("*", requireSession);` from
  `backend/src/sidekicks.ts`; "refuses a request with no session" failed with `expected 500 to
  be 401`. (2) Broke each re-covered behaviour in `backend/src/sidekicks.ts`, one at a time, and
  ran `sidekicks-catalog.test.ts`: hashes joined with "," failed the 200 test; the never-deployed
  404 changed to 200 failed "answers 404 for an assigned Sidekick that was never deployed"
  (`expected 200 to be 404`); the id pattern check disabled failed "rejects ids..." (`expected
  404 to be 400`); the missing-version 500 changed to 404 failed "returns 500..." (`expected 404
  to be 500`); the assignment check disabled failed "answers 404 for a deployed Sidekick that is
  not assigned to the user" (`expected 200 to be 404`). After each break the file was restored
  from a copy taken before the change (`cmp` identical).

## 2026-10-10: auth.test.ts "lets the Midas app use passkeys for this domain"

- Change: `backend/test/auth.test.ts:236`, the pinned app ID literal changed from
  `"YJ76245TM4.com.bhuvanrj.midas"` to `"ZQ2JPFYL98.com.bhuvanrj.midas"`. Nothing else in the
  test changed. It still checks that the apple-app-site-association response lists exactly
  `[APPLE_APP_ID]` and pins that constant to one exact value.
- Reason: founder decision, 2026-10-10, recorded in `docs/PRODUCT.md` section 5 ("2026-10-10:
  the shell is signed by the paid team `ZQ2JPFYL98` (bhuvanrj83), not `YJ76245TM4`;
  `DEVELOPMENT_TEAM` in `shell/project.yml` and the apple-app-site-association app ID
  (`ZQ2JPFYL98.com.bhuvanrj.midas`, `backend/src/auth.ts`) follow it.") and in midas-intel
  `docs/designs/jess-personal-assistant-shell.md`, "Signing team and backend data rules,
  decided 2026-10-10", item 1.
- Proof it can still fail: I set `APPLE_APP_ID` in `backend/src/auth.ts` back to
  `"YJ76245TM4.com.bhuvanrj.midas"`. The test failed with `AssertionError: expected
  'YJ76245TM4.com.bhuvanrj.midas' to be 'ZQ2JPFYL98.com.bhuvanrj.midas'`. I then restored the
  file from a copy taken before the change (`cmp` identical).

## 2026-10-08: ReminderPlannerTests.testBooksOnlyTheSoonest48Of100

- Change: style only. The expected id list `r000`..`r047` is now built with a `for` loop
  instead of `(0..<48).map { ... }` with an inline closure. Both assertions (48 bookings; the
  booked ids are exactly `r000`..`r047` in order) are unchanged.
- Reason: the notification-engine agent wrote the inline closure by mistake, against the
  founder's style rules in `~/.claude/CLAUDE.md` ("No inline anonymous functions in JS/TS method
  chains", "Never write chained one-liner JS calls"). Those rules name JS/TS; applied here to
  Swift at the agent's request. The test was created the same session and never committed.
- Proof it can still fail: changed `regularCandidates.prefix(budget)` to
  `regularCandidates.suffix(budget)` in `shell/Midas/ReminderPlanner.swift`; the test failed
  with `XCTAssertEqual failed: ("["r052", ... "r099"]") is not equal to ("["r000", ... "r047"]")`.
  Restored the file from a copy taken before the change (`cmp` identical).

## 2026-10-07: SidekickWebViewTests.testFetchToPlatformOriginIsNotACSPViolation

- Change: the assertion checked that no CSP violation of any kind was recorded; it now checks
  that no `connect-src` violation was recorded.
- Reason: test bug. The page deliberately contains an unhashed inline script, whose
  `script-src-elem` violation is expected and is what `testOnlyDeployedScriptsRun` relies on.
  The test is about fetch to the platform origin only.
- Proof it can still fail: changing `connect-src` in `SidekickContentSecurityPolicy.policy` to
  any other origin records a `connect-src` violation for the platform fetch.
- Made by the main agent before the guardian existed, recorded here retroactively.
