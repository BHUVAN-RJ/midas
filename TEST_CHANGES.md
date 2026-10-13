# Test changes

Every change to or deletion of an existing test is recorded here by the test-guardian agent,
newest first. New tests are not recorded. The git pre-commit hook rejects a commit that changes
or deletes an existing test without also changing this file.

Each entry: date, test, change, reason (the decision, with its date, or the bug), and proof
the test can still fail for the reason it exists.

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
