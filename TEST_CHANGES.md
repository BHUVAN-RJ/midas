# Test changes

Every change to or deletion of an existing test is recorded here by the test-guardian agent,
newest first. New tests are not recorded. The git pre-commit hook rejects a commit that changes
or deletes an existing test without also changing this file.

Each entry: date, test, change, reason (the decision, with its date, or the bug), and proof
the test can still fail for the reason it exists.

## 2026-10-25: fake-claude stand-in gains the init event and the Agent calls (ACCEPTED; founder decision)

- Asked by: the lead session (main repo), 2026-10-25.
- Test: `backend/test/helpers/fake-claude.ts` (used by `backend/test/runner-agent-check-attempts.test.ts`
  "every probe tried and refused: all ✓, exit 0" and `backend/test/runner-check-sandbox-script.test.ts`
  "runs the agent check on an env file with only the Claude login"). No assertion in either file changed.
- Reason: founder decision, `docs/PRODUCT.md` "### Plan additions, 2026-10-25: every repair reaches
  test-guardian (founder)": "`check-sandbox --agent` also proves the guardian path: the session has
  the Agent tool and lists test-guardian, the agent reaches the guardian, and Explore and claude are
  refused." Bug behind it: repairs 50ca5522 and 9c699df4 (2026-10-24) could not reach the guardian
  because the runner denied "Task". `runner/bin/check-sandbox.mjs` gained those four checks; the old
  stand-in printed no init event and no Agent calls, so both tests failed with "not tried".
- Change: every mode prints a stream init event first. Its tools come from the `--tools` argument,
  with Agent listed as "Task" and left out when `--disallowedTools` has "Task" or "Agent"; its agents
  are claude, Explore, general-purpose, Plan, statusline-setup, test-guardian. "refused" mode also
  logs Task calls to test-guardian, Explore and claude, each refused only when `--disallowedTools`
  has `Agent(<name>)` (so the guardian goes through); "allowed" logs all three as going through;
  "declined" unchanged. Reading the runner's real arguments, rather than a fixed answer, makes the
  tests fail if the runner denies "Task" again or stops denying a subagent. Header comment updated.
- Before: test-all backend 2 failed / 998 passed (the two tests above); test guard, shell (818),
  midas-intel all passed.
- Proof it can still fail (each run on the two files, then `runner/lib/agent.mjs` restored from a
  copy, `cmp` identical):
  1. Put `"Task",` back in `AGENT_DENIED_TOOLS`: both tests failed; output had "✕ agent's session
     has the Agent tool, lists test-guardian, and denies every other subagent", "✕ agent could not
     reach test-guardian (not tried)", "✕ Explore/claude subagent refused: the agent did not try".
  2. Removed "claude" from `AGENT_DENIED_SUBAGENTS`: both tests failed; output had "subagent claude
     is listed and not denied" and "✕ claude subagent refused: the call went through".
- After: `scripts/test-all.sh` exit 0: test guard 42 OK, backend 1000/1000 (93 files), shell 818
  passed, midas-intel 31 OK.
## 2026-10-24: NotificationNotesTests.testTheNotificationShowsTheNotesUnderTheTitle body is time then notes, for layout A (ACCEPTED)

- Asked by: the shell builder (worktree `midas-worktrees/notif-levels-shell`, branch
  `agent/notif-levels-shell`), 2026-10-24.
- Reason (founder decision): midas-intel `docs/designs/jess-personal-assistant-shell.md`,
  "Notification levels and layout (founder, 2026-10-24)": "Layout A: title = item, subtitle =
  Sidekick name, body = time and notes." Brief `docs/briefs/notification-levels.md` section 2.1
  (commit d593612): "Title = the reminder's title. Subtitle = the Sidekick's name ... Body = the
  time, then the notes." Separator " · " is from the layout A mockup and
  `PlannedBooking.bodySeparator` in `shell/Midas/ReminderPlanner.swift`. Note: that design doc
  section was uncommitted in midas-intel when this was accepted.
- Change, `shell/MidasTests/NotificationNotesTests.swift`: the line
  `XCTAssertEqual(content.body, "Say hi from all of us")` becomes
  `XCTAssertEqual(content.body, sixPM + " · Say hi from all of us", ...)` with
  `sixPM = ReminderExpansion.formatTime(<6 PM Oct 15, Los Angeles>, zone: zone)`, so the exact
  layout A body is checked (time first, then the full notes). `content.title == "Call Amma"` stays.
  Header comment names the layout A decision. The other notes tests (`booking.body` carries the
  notes on every booking) are unchanged.
- Proof it can still fail: NOT RUN. The caller asked that no xcodebuild or suite be run (another
  build was running on the machine; concurrent xcodebuild runs hang). Before the change, the
  caller reported the old assertion failing with `("6:00 PM · Say hi from all of us") is not
  equal to ("Say hi from all of us")`, which shows the assertion compares the full body exactly.
  To be done at the next run: in `shell/Midas/NotificationBooking.swift` set
  `content.body = booking.body` (drops the time) and expect the new assertion to fail with
  `("Say hi from all of us") is not equal to ("6:00 PM · Say hi from all of us")`; then drop
  `body` from `PlannedBooking.notificationBody` (drops the notes) and expect
  `("6:00 PM") is not equal to (...)`; restore both.
- Full suite: not run, same reason; the caller runs `scripts/test-all.sh` next.

## 2026-10-24: jess router, run-once and grow fixtures get `reminderType: null` on reminders__add (ACCEPTED)

- Asked by: the Reminders Sidekick builder (worktree `midas-worktrees/notif-levels-reminders`,
  branch `agent/notif-levels-reminders`), 2026-10-24.
- Reason (founder decision): `docs/briefs/notification-levels.md` "Decisions (founder,
  2026-10-24)" §2.2: "**New record field `reminderType`** on `reminder:` records, values
  `"normal"`, `"timeSensitive"`, `"alarm"`. Absent means `"timeSensitive"`." §2.5: "... and as an
  optional `reminderType` argument of jess's add and edit tools." The deploy gate
  (`backend/scripts/bundle-tools.mjs` `objectSchemaProblems`) requires "every property must be
  required (optional ones are nullable)", so commit c808441 lists `reminderType` as required,
  type `["string","null"]`, on `reminders.add` and `reminders.edit` in
  `sidekicks/reminders/manifest.json`. A made-up model call without the key is now correctly
  refused as `bad-arguments` by `outcomeFromToolCall`.
- Change: `backend/test/jess-router.test.ts`, "checking the model's call": the four
  `call("reminders__add", {...})` argument objects get `reminderType: null`, and the exact
  expected `input` in "passes an add through with its when worked out by the voice resolver" gets
  `reminderType: null` (the router passes input through). `backend/test/jess-run-once.test.ts`:
  `ADD_ARGS` gets `reminderType: null`. `backend/test/jess-grow.test.ts`: `ADD_CALL.args` gets
  `reminderType: null`. No other change; run-once and grow have no exact-input expectation
  (grow uses `toMatchObject` on `input.when` only). No assertion removed or widened.
- Before: backend 951 tests, 12 failed (exactly these: 4 router, 3 run-once, 5 grow).
- Proof it can still fail: (1) `backend/src/jess.ts` `outcomeFromToolCall`: added
  `delete input.reminderType;` after the input copy. Router test "passes an add through ..." failed
  (diff `- "reminderType": null`), 1 failed / 49 passed in the three files. (2)
  `sidekicks/reminders/manifest.json`: `reminderType` on `reminders.add` made `type: "string"` with
  `null` dropped from its enum. All 12 changed tests failed (12 failed / 38 passed). Both files
  restored from scratchpad copies; `git status` shows only the three test files changed.
- After: `cd backend && npx vitest run`: 951 passed (951), twice. `scripts/test-all.sh`: shell
  757 tests 0 failures, midas-intel 31 OK, backend 950/951 with one 5 s timeout in the unchanged
  `repair-data-review-fixes.test.ts` while the shell suite ran alongside; it passed on both
  backend-only reruns.

## 2026-10-24: MakeRecordsTests helper renamed record -> makeRecord, and one epoch constant fixed (ACCEPTED; test is wrong)

- Asked by: the make-shell builder (worktree `midas-worktrees/make-shell`, branch
  `agent/make-shell`), 2026-10-24, for its own new, uncommitted file
  `shell/MidasTests/MakeRecordsTests.swift` (Make approved by the founder 2026-10-24,
  `docs/briefs/make-contract.md`).
- Reason (bugs in the test, not the code):
  1. The file did not compile: inside an `XCTestCase`, `record(` resolves to XCTestCase's own
     instance method `record(_:)`, not the file-level helper `record(_:_:sidekickId:)`. Before the
     change the shell suite failed to build (`MakeRecordsTests.swift:247: cannot infer key path type
     from context`, a follow-on of the same error).
  2. `testTimesRoundTripWithAndWithoutMilliseconds` expected `2026-10-15T09:30:00Z` to parse to
     `1_791_365_400`; the correct epoch is `1_792_056_600` (python3:
     `int(datetime(2026,10,15,9,30,tzinfo=timezone.utc).timestamp()) == 1792056600`).
- Change: helper renamed to `makeRecord` and its 37 call sites renamed (definition plus calls, no
  other line touched); `1_791_365_400` -> `1_792_056_600`. No assertion removed or widened.
- Proof it can still fail: in `shell/Midas/MakeSidekick.swift` `MakeTime.parse`, made the
  fractional-seconds branch add one hour when the text has no milliseconds
  (`return text.contains(".") ? withFraction : withFraction.addingTimeInterval(3600)`). Ran
  `-only-testing:MidasTests/MakeRecordsTests`: 1 failure, `MakeRecordsTests.swift:284
  testTimesRoundTripWithAndWithoutMilliseconds: XCTAssertEqual failed: ("Optional(1792060200.0)") is
  not equal to ("Optional(1792056600.0)")`. Restored the file from a copy (cmp identical); 13/13
  pass. (Note: breaking only the no-fraction fallback on line 184 did not fail the test, because
  `ISO8601FormatStyle(includingFractionalSeconds: true)` already accepts times without
  milliseconds, so that fallback is not reached for this input.)
- Full suite after the change: test guard OK (34); backend FAILED to start (`vitest: command not
  found`, dependencies not installed in this worktree; same before the change); shell 818 tests,
  3 failures, none in MakeRecordsTests (13/13 pass): `JessTileTests.testTheShellOpensTheSameScreenAsTheActionButton`,
  `RepairOrbLevelTests.testBothRepairOrbsAreGivenTheLevel` (1 != 2), `RepairPillWordsTests.testThePillDrawsTheSpokenWords`;
  midas-intel OK (31).

## 2026-10-24: jess-for-everyone "assigns jess to a new user in the same step that creates them" lists ["jess", "make"] (ACCEPTED)

- Asked by: the make-backend builder (worktree `midas-worktrees/make-backend`, branch
  `agent/make-backend`), 2026-10-24.
- Test: `backend/test/jess-for-everyone.test.ts`, describe "jess at sign-up", it "assigns jess to a
  new user in the same step that creates them".
- Change: `expect(await listedIds(env, session.token)).toEqual(["jess"])` becomes
  `.toEqual(["jess", "make"])`. The `jessRows(...)` length 1 assertion stays.
- Reason (founder decision): `docs/PRODUCT.md` section 2, "Plan additions, 2026-10-23": "**Make
  (working title, was "Build"; founder, 2026-10-23 and 24):** a default Sidekick for everyone, like
  jess." `docs/briefs/make.md`: "Everyone gets Make." and "assigned at sign-up (next to jess in
  `auth.ts`)". `docs/briefs/make-contract.md` section 1 (commit f281d37): "Assigned at sign-up
  (second insert next to `assignJess` in `auth.ts`, same batch)" and "Listing order: jess, make,
  make-inbox, then the rest." A new user is now listed jess then make. The Make assignment itself is
  also checked by the new `backend/test/make-routes.test.ts`.
- Before the change: backend 989 passed, 1 failed (this test: received ["jess", "make"]).
- Proof it can still fail: (1) removed `assignMake` from the sign-up `DB.batch` in
  `backend/src/auth.ts`: failed with "expected [ 'jess' ] to deeply equal [ 'jess', 'make' ]";
  (2) removed `assignJess` from the batch: failed with "expected [] to have a length of 1 but got
  +0". `auth.ts` restored from a byte copy each time (cmp identical).
- After: `scripts/test-all.sh` ALL SUITES PASSED (backend 990/990, shell 757 tests 0 failures,
  midas-intel 31 OK).

## 2026-10-23: RepairRimVoiceTests L1 look tests deleted and RepairChromeTests rim widths 3/6 -> 4/8, for G+1 (ACCEPTED; resend of the NEEDS-EVIDENCE entry below)

- Asked by: the repair-polish builder (worktree `midas-worktrees/repair-polish`, branch
  `agent/repair-polish`), through the lead session, 2026-10-23, with the evidence the entry below
  asked for.
- Reason (founder decision): `docs/briefs/repair-ux-upgrade.md` "Decided" (commit 32dab20 on main,
  merged as a6cf81f), pointed to from `docs/PRODUCT.md` open task 3b: "**Voice glow L1, then G+1
  replaces L1** (founder, 2026-10-23: "for the actual glow, we will go with G1 ... G + 1"; "I could
  not see it clearly, but it has to be more visible"). G+1 silent: 4 pt line, 8 pt ink line (light),
  18 pt blur, glow 85% light / 80% dark. Speaking: 8 pt line, 12 pt ink line, 40 pt blur, glow 100%,
  Volt halo 2.6x the line width at 60%. Smoothing 60/260 ms. Reduce Motion: width fixed, no halo,
  glow only. The L1 values (3 -> 5.5 pt) are retired." The smoothing conflict is settled at 60/260
  ms (the mockup's G+1 now says 60/260 too), so `testTheRimRisesIn60MsAndSettlesIn260Ms` stays.
  The replacement suite `shell/MidasTests/RepairRimGlowPlusTests.swift` (commit ec2b717) checks
  silent (light, dark), full voice (light, dark), half level, the clamp above 1 and Reduce Motion
  with the G+1 numbers, and the halo.
- Change A, `shell/MidasTests/RepairRimVoiceTests.swift`: deleted `testSilenceIsPlainV1`,
  `testAFullVoiceGivesTheThickBrightRim`, `testTheRimGrowsInStepWithTheLevel`,
  `testReduceMotionKeepsTheWidthAndChangesOnlyTheGlow` (they asserted the retired L1 values) and the
  now unused helper `assertLook`; header comment drops the L1 numbers and says the look values are
  checked in RepairRimGlowPlusTests (G+1 replaced L1, founder 2026-10-23, the brief). The other four
  tests are unchanged.
- Change B, `shell/MidasTests/RepairUXUpgradeTests.swift`, `RepairChromeTests`
  `testTheRimIsVoltOnAnInkLineInLightModeOnly`: `RepairRimSpec.lineWidth` 3 -> 4 and
  `RepairRimSpec.keylineWidth` 6 -> 8 (G+1 silent). Volt hex, keyline modes and inset 4 unchanged.
- Coverage note: the deleted L1 Reduce Motion test also checked dark at full voice (0.95); the
  G+1 suite checks Reduce Motion light at full and dark silent only.
- Before: shell 761 tests, 31 failures, all in these 5 tests (the 4 L1 tests and
  testTheRimIsVoltOnAnInkLineInLightModeOnly); test guard, backend, midas-intel passed.
- Proof it can still fail: `shell/Midas/RepairTheme.swift` (builder's uncommitted version, sha1
  632aeaf4) backed up; `RepairRimSpec.lineWidth` 4 -> 3 and `keylineWidth` 8 -> 6 (the retired
  values). Running RepairChromeTests/testTheRimIsVoltOnAnInkLineInLightModeOnly, RepairRimVoiceTests
  and RepairRimGlowPlusTests: 13 tests, 20 failures. The changed test failed with
  `XCTAssertEqual failed: ("3.0") is not equal to ("4.0")` (line 481) and `("6.0") is not equal to
  ("8.0")` (line 483); 4 of the RepairRimGlowPlusTests look tests failed too (for example "silent,
  light: line width" 3.0 vs 4.0), so the drawn rim follows the spec. Restored from the backup, sha1
  632aeaf4 again.
- Result after: test guard 34 OK; backend 919/919 passed (89 files), typecheck clean; shell 757
  tests, 0 failures; midas-intel 31 OK. ALL SUITES PASSED.

## 2026-10-23: RepairRimVoiceTests L1 look values and RepairUXUpgradeTests rim widths, for G+1 (NEEDS-EVIDENCE, not changed)

- Asked by: the repair-polish builder (worktree `midas-worktrees/repair-polish`, branch
  `agent/repair-polish`), through the lead session, 2026-10-23.
- Tests: `shell/MidasTests/RepairRimVoiceTests.swift`, delete `testSilenceIsPlainV1`,
  `testAFullVoiceGivesTheThickBrightRim`, `testTheRimGrowsInStepWithTheLevel`,
  `testReduceMotionKeepsTheWidthAndChangesOnlyTheGlow` and the helper `assertLook`, and update the
  header comment; `shell/MidasTests/RepairUXUpgradeTests.swift`,
  `testTheRimIsVoltOnAnInkLineInLightModeOnly`: `RepairRimSpec.lineWidth` 3 -> 4 and
  `RepairRimSpec.keylineWidth` 6 -> 8.
- Reason given: founder, 2026-10-23, after build 14 on the phone ("the L1 voice glow is not
  visible"), picked G+1 "Thick rim + bloom" (`docs/mockups/repair-feedback-2026-10-23.html`
  section 1d), relayed by the lead session. New G+1 assertions to go in a new suite,
  RepairRimGlowPlusTests.
- Why not accepted: the decision is not written and dated in `docs/PRODUCT.md` or the midas-intel
  design doc. `docs/PRODUCT.md` open task 3b points to `docs/briefs/repair-ux-upgrade.md`, whose
  "Decided" list has V1 but neither L1 nor G+1. The only record of G+1 is an uncommitted edit to
  the mockup (`git diff`: heading "1d · Build 14 fixes · G+1 and B+2 decided", a `// Decided by the
  founder, 2026-10-23 (build 14 on the phone)` pick). A relayed message and an uncommitted mockup
  edit are not accepted sources (same ruling as JessOrbTests, 2026-10-22).
- Conflict to settle in the same entry: the mockup's G+1 spec says "Smoothing: attack 50 ms,
  release 300 ms" (`GLOW_PLUS`, `attackMs: 50, releaseMs: 300`) and "Reduce Motion: width 4 pt
  fixed, no bloom; glow 85% -> 100%"; the request says smoothing stays L1's 60/260 ms and keeps
  `testTheRimRisesIn60MsAndSettlesIn260Ms` unchanged. One of the two is wrong.
- Also: RepairRimGlowPlusTests does not exist yet. The four L1 tests are deleted only once it
  exists and covers silent, full voice, level steps (and the above-1 clamp), and Reduce Motion
  with the G+1 numbers, so no rim look goes unchecked in between.
- Evidence that would change the answer: a dated founder entry in `docs/PRODUCT.md` (for example
  under open task 3b) or in the brief's "Decided" list, referenced from PRODUCT.md, stating G+1's
  numbers (silent 4 pt line, 8 pt ink line, blur 18 pt, glow 85% / 80%; speaking 8 pt, ink 12 pt,
  blur 40 pt, glow 100%; Volt halo 2.6x line width at 60% x level), the smoothing (60/260 or
  50/300) and the Reduce Motion rule; plus RepairRimGlowPlusTests in the worktree. With those in
  place the requested change is the right one and can be resent as is (adjusting the smoothing test
  if the founder's numbers are 50/300).
- Nothing changed in either test file; the suite was not run (no change made; the requester runs it).

## 2026-10-23: backend/test/repair-voice-error.test.ts, "keeps the phone's voice error beside the report and logs it" (ACCEPTED; style only, new uncommitted test)

- Asked by: the repair-voice agent (worktree `midas-worktrees/repair-voice`, branch
  `agent/repair-voice`), 2026-10-23. The file is new (not yet committed) and belongs to the repair
  voice fix (founder request 2026-10-23: make repair voice work; the server stores `voiceError`).
- Reason: founder's global style rule, `~/.claude/CLAUDE.md`: "No inline anonymous functions in
  JS/TS method chains."
- Change: the two inline arrows in `logSpy.mock.calls.map(...)` and `loggedLines.filter(...)`
  became top-level named helpers `firstArgumentText(call: unknown[]): string` and
  `isVoiceErrorLine(line: string): boolean`, passed by name. Same logic; every assertion unchanged.
- Proof it can still fail: `backend/src/repairs.ts` (agent's uncommitted version, sha1 d97f809e)
  backed up; on line 482 the logged event `"repair-voice-error"` changed to `"repair-voice-err"`.
  Result: 1 failed, 2 passed, "AssertionError: expected +0 to be 1" (`voiceLines.length`).
  Restored from the backup, sha1 d97f809e again; the file passes 3/3.
- Result after: test guard 34 OK; backend 919/919 passed (89 files), typecheck clean; shell 721
  tests, 0 failures; midas-intel 31 OK. ALL SUITES PASSED.

## 2026-10-23: backend/test/repairs-feature-shell-runner.test.ts, "records failed with reason unsupported for a feature the platform cannot do, and tells the founder" (ACCEPTED; a failed repair now leaves the reporter one couldnt_fix notice)

- Asked by: the repair-ux builder (worktree `midas-worktrees/repair-ux`, branch `agent/repair-ux`),
  through the lead session, 2026-10-23.
- Reason (founder decision): `docs/PRODUCT.md` on main (commit c60e735), open task 3b, "Repair UX
  upgrade, before the public link (founder, 2026-10-23: "I need this done right now"): Volt rim,
  Repair tag, ... "Already there" instead of "failed". Brief `docs/briefs/repair-ux-upgrade.md`".
  The brief, "Decided": "S2, the tag stays, only on that Sidekick: ... shows the result there", and
  "Defaults the founder did not change (2026-10-23): Couldn't Fix stays until Try Again or closed".
  The tag can only show Couldn't Fix if the reporter's phone learns the repair failed; the old
  `notices == []` was not a founder rule (PRODUCT.md, 2026-10-22: "Known: a plain repair whose
  repair fails stays grey (only "done" notices exist)").
- Change: only the last assertion. `notices` toEqual `[]` became
  `toEqual([expect.objectContaining({ reportId, kind: "couldnt_fix" })])`, with the reply typed
  `{ notices: Array<{ reportId: string; kind: string }> }`. Status failed, fail_reason
  "unsupported", founder events ["request_received", "failed"] and the failed event's failReason
  are unchanged. The assertion is stricter than before (exactly one notice, this report, this kind).
- Proof it can still fail: `backend/src/repairs.ts` (the builder's uncommitted version) backed up
  (sha1 b4e5fbc1) and broken twice, restored from the backup after each. (1) The line in the status
  handler that inserts the user "failed" event (`statements.push(insertEventStatement(c.env.DB,
  reportId, "user", "failed", changedAt))`) replaced by a comment: 1 failed, "expected [] to deeply
  equal [ ObjectContaining{...} ]". (2) In `handleListNotices`, `noticeKind(...)` replaced by
  `"fixed"`: 1 failed, diff `"kind": "couldnt_fix"` vs `"kind": "fixed"`. After restore sha1
  b4e5fbc1 again; the file passes 13/13.
- Before the change: backend 906 passed, 1 failed (this test, against the builder's new notice).
- Result after (both changes): test guard 34 OK; backend 907/907 passed (87 files), typecheck
  clean; midas-intel OK. Shell suite NOT run (no simulator, at the lead's request).

## 2026-10-23: shell/MidasTests/RepairDrawingRendererTests.swift, the pen colour (ACCEPTED; tomato light became Volt)

- Asked by: the repair-ux builder (worktree `midas-worktrees/repair-ux`, branch `agent/repair-ux`),
  through the lead session, 2026-10-23.
- Reason (founder decision): `docs/PRODUCT.md` on main (commit c60e735), open task 3b, "Repair UX
  upgrade ... (founder, 2026-10-23 ...): Volt rim, Repair tag, ...", detailed in
  `docs/briefs/repair-ux-upgrade.md`, "Decided": "Tomato leaves Midas's colours. Volt is the third
  colour, with black and white" and "Glow V1, Volt rim on an ink line (founder, 2026-10-23)". The
  V1 spec in `docs/mockups/repair-feedback-2026-10-23.html` (V1 / V1T, "Decided (founder,
  2026-10-23): V1 plus the M3 "Repair" tag"): "Pen: 5 pt Volt; on white over an 8 pt ink line",
  `VOLT = "#CEFF00"`, `VOLT_PEN = { light: { colour: VOLT, keyline: "#111111" }, dark: { colour:
  VOLT, keyline: null } }`. (The brief's earlier line "pen ... black" in light mode is the mono
  round M1-M4, superseded by the V1 pick.)
- Change: `testStrokePixelsAreTomatoLightOverTheScreenshot` renamed
  `testStrokePixelsAreVoltOverTheScreenshot`; on-stroke pixel expected red 206 (accuracy 3), green
  255 (accuracy 2), blue 0 (accuracy 2), was 255/99/71; off-stroke white unchanged.
  `testPenIsTomatoLightFromTheDesignRecord` renamed `testPenIsVoltFromTheDesignRecord`; hex
  "#CEFF00" and components 0xCE, 0xFF, 0x00, was "#FF6347" / 0xFF, 0x63, 0x47. Class doc comment
  names Volt. `testDrawingKeepsTheScreenshotSize` unchanged. The keyline is not tested here (the
  existing call passes no `keylineColor`, so it draws the Volt stroke only).
- Proof it can still fail: NOT RUN. The lead asked for nothing that needs the simulator. At the
  time of the change `shell/Midas/RepairSession.swift:18-19` still has the tomato pen
  (`colorHex = "#FF6347"`, `UIColor(red: 1.0, green: 99/255, blue: 71/255)`), so on the current
  app code both changed tests must fail (red 255 vs 206, green 99 vs 255, blue 71 vs 0; "#FF6347"
  vs "#CEFF00"). Whoever runs the shell suite first records that failure before the builder's pen
  change, or after it breaks the pen back to tomato, and the pass after.

## 2026-10-22: backend/test/runner-agent-log-flushed.test.ts and runner-agent-log-complete.test.ts, delete (ACCEPTED; deletion NOT yet applied, blocked by the session's permission classifier)

- Asked by: lead session (coordinator) for the builder in worktree `midas-worktrees/repair-data`
  (branch `agent/repair-data`), 2026-10-22.
- What the tests are: three uncommitted drafts of one regression test for one bug: `runAgent`
  resolved before its log stream had written everything, so `check-sandbox.mjs` read a cut-off log
  (a refused Read showed as "the call went through"). Fix in `runner/lib/agent.mjs`: resolve inside
  `logStream.end(function resolveAfterLogFlushed() {...})`.
- Reason (the test is wrong / redundant): `runner-agent-log-flushed` tries to catch the bug by
  printing 20,000 lines to a real file and hoping the write is still pending; whether it can fail
  depends on disk and timing, which a test should not. `runner-agent-log-complete` is the same test
  as `runner-agent-log-written` with a 20 ms instead of 300 ms slow stream. `runner-agent-log-written`
  stays and covers the bug deterministically through the `openLogStream` injection point.
- Change: delete the two files; keep `runner-agent-log-written.test.ts` unchanged. NOT DONE: `rm`
  and `mv` of the two files were both refused by the Claude Code auto-mode classifier ("Irreversible
  Local Destruction", then "Security Test Removal"). The files are still in `backend/test/`. Someone
  with permission (founder) deletes them by hand, or allows the action.
- Proof the kept test can still fail: `runner/lib/agent.mjs` backed up (sha1 6ec9c5c0); in `finish`,
  `logStream.end(function resolveAfterLogFlushed() { resolve(...) })` replaced by `logStream.end();
  resolve(...)`. `npx vitest run runner-agent-log-written`: 1 failed, at
  `expect(written.join("")).toBe("line1\nline2\n")`. Restored from the backup; sha1 6ec9c5c0 again.
- Result after: `npx vitest run runner-agent-log-written` 1/1 passed. `scripts/test-all.sh` NOT run,
  at the coordinator's request (the shell/Xcode suite filled the disk; ~1.3 GB free).

## 2026-10-22: backend/test/runner-check-sandbox-script.test.ts, "runs the agent check on an env file with only the Claude login" (ACCEPTED; a pass now needs the probes tried and refused)

- Asked by: lead session for the builder in worktree `midas-worktrees/repair-data` (branch
  `agent/repair-data`), 2026-10-22.
- Reason: `docs/briefs/repair-data-2026-10-19.md`, "## Decision: close the env-file gap (founder,
  2026-10-22)", point 5 (commit f4e3f1e): "the model declined every step, so the ✓ lines proved
  nothing: no call was made. Fix: [...] each check passes only when the log shows the call tried and
  refused (`runner/lib/agent-check.mjs`); a step not tried is ✕." Under that fix the old fake (only
  `cp inside.txt copied.txt`, no tool calls logged) correctly makes the script exit 1, and the canary
  line was renamed to "✓ agent never saw the note in ~/.midas-runner (job files and log searched)".
- Change: the hand-written fake is replaced by `writeFakeClaude(home, "refused")`
  (`backend/test/helpers/fake-claude.ts`: copies inside.txt and logs a refused Read, Grep, Bash, Write
  and Edit on every path in the prompt); the canary expectation now reads `"✓ agent never saw the note
  in ~/.midas-runner"`; unused `chmodSync`/`writeFileSync` imports dropped. The other expectations
  (not "is not set", "✓ claude ran (exit 0)", "✓ agent can still read and write inside the job
  folder", exit 0) are unchanged. The declined and allowed cases are covered by the new
  `backend/test/runner-agent-check-attempts.test.ts`.
- Proof it can still fail: `runner/bin/check-sandbox.mjs` backed up (sha1 5e92037d) and broken twice,
  restored from the backup after each. (1) `agentSettingsFromEnv()` replaced by `settingsFromEnv()`:
  1 failed, "expected '...' not to contain 'is not set'". (2) `noteUnseen` forced to `false`: 1
  failed, "expected '...' to contain '✓ agent never saw the note in ~/.midas-runner'". After the
  restore, sha1 is 5e92037d again.
- Result after: `npx vitest run runner-check-sandbox-script runner-agent-check-attempts` 9/9 passed.
  `scripts/test-all.sh` exit 0: backend 666/666 (59 files), shell 563 tests with 0 failures,
  midas-intel 31 OK (plus 34 OK in the first python suite). Before the change: backend failed on
  this test (my first full run also caught 3 failures in `runner-agent-check-attempts.test.ts` while
  the builder was still editing the tree; they passed on re-run a minute later with no change of mine).

## 2026-10-22: backend/test/runner-agent.test.ts, "allows file tools and Bash for exactly the intel and check scripts" (ACCEPTED; file tools limited to the job folder)

- Asked by: lead session for the builder in worktree `midas-worktrees/repair-data` (branch
  `agent/repair-data`), 2026-10-22. First answered NEEDS-EVIDENCE the same day: the founder's go
  was then only relayed, and `docs/concerns/2026-10-13-repair-runner.md` section 4 still said "not
  started". Re-asked after the lead committed the decision (2adb863).
- Reason: `docs/briefs/repair-data-2026-10-19.md`, "## Decision: close the env-file gap (founder,
  2026-10-22)": "1. The repair agent's file tools read and write only the job folder (`Read(./**)`,
  `Edit(./**)` in place of bare `Read`, `Edit`, `Write`)." The old assertion pinned the unrestricted
  rules, which let the agent read `~/.midas-runner/env` (`MIDAS_RUNNER_TOKEN`,
  `CLAUDE_CODE_OAUTH_TOKEN`) (concerns section 4, raised 2026-10-20).
- Change: the expected `--allowedTools` list is now `["Read(./**)", "Edit(./**)", "Grep", "Glob",
  "Bash(node /r/tools/intel.mjs:*)", "Bash(node /r/tools/check.mjs:*)", "Agent(test-guardian)"]`;
  added `not.toContain("Read")`, `not.toContain("Edit")`, `not.toContain("Write")` and a one-line
  comment citing the decision. Every other assertion in the test is unchanged; no other test touched.
- Proof it can still fail: `runner/lib/agent.mjs` was backed up (sha1 17d30bef) and
  `agentAllowedTools` was broken twice, with the file restored from the backup after each.
  (1) `Read(./**)`, `Edit(./**)` replaced with bare `Read`, `Edit`, `Write`: 1 failed / 7 passed,
  "expected [ 'Read', 'Edit', 'Write', ...(5) ] to deeply equal [ 'Read(./**)', 'Edit(./**)', ...(5) ]".
  (2) bare `Write` added next to the restricted rules: 1 failed / 7 passed, "expected [ 'Read(./**)',
  'Edit(./**)', ...(6) ] to deeply equal [ ... ...(5) ]". After the restore, sha1 is 17d30bef again.
- Result after: `npx vitest run test/runner-agent.test.ts` 8/8 passed. I did not run the full suite,
  at the lead's request (the lead runs it next). Before this change, `scripts/test-all.sh` gave:
  backend 1 failed (this test) / 640 passed, shell 563 tests with 0 failures, midas-intel 31 OK.

## 2026-10-22: jess's control shows the "Jess" symbol, not the microphone (ACCEPTED, two changes)

- Asked by: jess-look session, worktree `midas-worktrees/jess-look` (branch `agent/jess-look`,
  commit 4110f2e), through the coordinator.
- Change 1 (the test was wrong), `shell/MidasTests/JessSymbolsTests.swift`,
  `testTheControlSymbolIsTheWrittenJess` (line 15): width/height threshold `1.6` became `1.2`.
  The 1.6 was an estimate written before the first run; a symbol `UIImage`'s size includes the J's
  descender and the symbol's alignment padding, so the real "Jess" symbol measures 1.4444. The
  test exists to tell the whole word from the J alone or a microphone (its own comment); 1.2 still
  does that (J alone 0.5, `microphone` 0.84, measured below).
- Change 2 (founder decision), `shell/MidasTests/JessAskTests.swift`,
  `AskJessTitleTests.testTheShortcutAndTheControlSayAskJessAndKeepTheirPhrasesAndIds` (line 37):
  `Label("Ask jess", systemImage: "mic")` became `Label("Ask jess", image: JessSymbols.control)`.
  Decision, `docs/PRODUCT.md` on main (b282bd4): "**jess outside the app (founder, 2026-10-23):**
  the controls (Control Center, Lock Screen, Action button as a control) show the written "Jess"
  as a custom one-colour symbol; ... the label stays "Ask jess"; the microphone symbol is
  retired." Same in `docs/DESIGN.md` §5a. Every other assertion kept.
- Proof they can still fail (one run, `Midas jess-look` simulator): replaced `JessSymbol.svg`
  with a J-only symbol drawn by `jess-symbol.py` with `LETTERS = ["J"]`: JessSymbolsTests.swift:15
  failed with `("0.5") is not greater than ("1.2")`. A temporary probe test measured
  `UIImage(systemName: "microphone")` at `0.8387` (fails `> 1.2`). Put
  `Label("Ask jess", systemImage: "mic")` back in `VoiceReminderControl.swift`: JessAskTests.swift:37
  failed (`XCTAssertTrue failed`). Restored the SVG and the control file from copies (git diff
  clean for both) and deleted the probe.
- Full suite after the change: test guard OK, backend 881 passed, shell 666 tests 0 failures,
  midas-intel 31 OK; ALL SUITES PASSED.

## 2026-10-22: the phone keeps the server's reportId and pendingId on repair and grow replies (ACCEPTED, two changes)

- Asked by: jess-workdesk session, worktree `midas-worktrees/jess-workdesk` (branch
  `agent/jess-workdesk`), through the coordinator.
- Decision (founder, 2026-10-22, `docs/PRODUCT.md`, "jess queue, instant acknowledgement and the
  Workdesk": "jess gets a Workdesk: a log of every task jess has done"), detailed in
  `docs/briefs/jess-workdesk-lead.md` section 2: "Repair is a wait, not done: the card stays with a
  grey core until the repair is live and the server has re-run the request once; then the same
  card turns green or red". The card needs the server's `reportId`/`pendingId` to find its repair,
  so `JessRouteReply.repair` gained `reportId` and `.grow` gained `reportId` and `pendingId`.
- Change 1, `shell/MidasTests/JessRouterTests.swift`, `RemoteJessRouterTests.testReadsDoneRepairAndNotDone`
  (line 293): expected `.repair(sidekickId: "reminders", logId: "l2")` became
  `.repair(sidekickId: "reminders", logId: "l2", reportId: "r1")`.
- Change 2, `shell/MidasTests/JessGrowTests.swift`, `JessGrowRouterTests.testTheServerSaysGrowWithTheSidekick`
  (line 121): expected `.grow(sidekickId: "reminders", logId: "l1")` became
  `.grow(sidekickId: "reminders", logId: "l1", reportId: "r1", pendingId: "p1")`.
  Both request bodies already carried `"reportId":"r1"` (and `"pendingId":"p1"`); the tests now
  also check those values are read. No assertion removed.
- Proof they can still fail: in a scratch copy of the worktree (current app code) both tests
  passed. I then changed `RemoteJessRouter.reply` in the copy to pass `reportId: nil` (repair) and
  `reportId: nil, pendingId: nil` (grow): JessRouterTests.swift:293 failed with `("repair(...,
  reportId: nil)") is not equal to ("repair(..., reportId: Optional("r1"))")` and
  JessGrowTests.swift:121 with `("grow(..., reportId: nil, pendingId: nil)") is not equal to
  ("grow(..., reportId: Optional("r1"), pendingId: Optional("p1"))")`. Restored from a copy
  (`diff -q` identical). App code in the worktree not touched.

## 2026-10-22: JessRouterTests, a cut-off request is `.cutOff`; the Workdesk stays open after routing (ACCEPTED, two changes)

- Asked by: jess-workdesk session, worktree `midas-worktrees/jess-workdesk` (branch
  `agent/jess-workdesk`), through the coordinator.
- Decision (founder, 2026-10-22, `docs/PRODUCT.md`, "jess queue, instant acknowledgement and the
  Workdesk"): "every jess action runs exactly once, through a queue: a request that is cut off (iOS
  ends the time, no network, a timeout) stays in the queue and is retried later until it is done or
  definitely not doable" and "As soon as listening ends, the jess screen shows a small notification
  at its top ... over the circling orb, so the person knows they can leave. jess gets a Workdesk".
  Details: `docs/briefs/jess-workdesk-lead.md` section 2 ("Cut off: grey core, Waiting for
  Connection, sent again by itself"; "Give up after 1 hour"), midas-intel
  `docs/plans/2026-10-22-jess-workdesk-brief.md`.
- Change 1, `shell/MidasTests/JessRouterTests.swift`, `testNotDoneAndNoAnswerChangeNothing`: the
  `.unreachable` answer now expects `.cutOff(transcript: "add milk")` instead of
  `.notDone(transcript: "add milk")`. The question case still expects `.notDone`; no ops applied
  and no outcome reported are unchanged. Name unchanged.
- Change 2, same file, `JessRoutedFlowTests`: renamed
  `testWhatWasSaidGoesOnceToTheRouterAndTheScreenClosesWithNoBanner` to
  `testWhatWasSaidGoesOnceToTheRouterAndTheWorkdeskStaysOpenWithNoBanner`; `await waitFor
  { !harness.flow.isPresented }` replaced by `await waitFor { harness.flow.phase == .ready }`,
  `XCTAssertEqual(harness.flow.phase, .ready)` and `XCTAssertTrue(harness.flow.isPresented, ...)`.
  The explicit phase assertion was added by me because `waitFor` returns silently on timeout.
  Routed once, same transcript, parser not asked, nothing saved, no banner: unchanged.
- Proof they can still fail: the worktree's app code was mid-edit and did not compile, so I proved
  both against the last commit's shell (`git archive HEAD`) in the session scratchpad, with a
  minimal stub of the new behaviour (`case cutOff` routed from `.unreachable`; `case ready` set
  after routing, screen left open). Both tests passed there. Then:
  - Router `.unreachable` sent back to `notDone`: `testNotDoneAndNoAnswerChangeNothing` failed at
    line 253, `("notDone(transcript: "add milk")") is not equal to ("cutOff(transcript: "add milk")")`.
  - Flow put back to closing after routing (`isPresented = false; phase = .listening`): the renamed
    test failed at line 419 `("listening") is not equal to ("ready")` and line 420 "the Workdesk
    stays open; Done closes it".
  Each break was restored from a copy (`diff -q` identical). App code in the worktree not touched.

## 2026-10-22: JessOrbTests listening core is Volt (ACCEPTED, resend of the NEEDS-EVIDENCE request below)

- Asked by: jess-look session, worktree `midas-worktrees/jess-look` (branch `agent/jess-look`).
- Test: `shell/MidasTests/VoiceReminderTests.swift`, `JessOrbTests.testTheCoreAloneCarriesTheResultInBothModes`
  and `JessOrbTests.testNoPurpleAnywhere`.
- Decision (founder, 2026-10-22, `docs/PRODUCT.md`, "jess's look", recorded on main in 78264a1):
  "while jess listens, the orb's core is Volt (`#CEFF00` light, `#E7FF85` dark; core only, crisp;
  idle and thinking stay black/white, done green, not done red)." Same in `docs/DESIGN.md` §5a,
  "Listening colour (founder, 2026-10-22)".
- Change: `.listening` removed from the black (light) / white (dark) core loop, which now covers
  idle and thinking only; two new assertions: `light.coreColor(for: .listening)` is `0xCEFF00` and
  `dark.coreColor(for: .listening)` is `0xE7FF85`. `testNoPurpleAnywhere` now also checks
  `palette.listening`. Added green, failed red, body and ring assertions unchanged.
- Proof it can still fail: in `shell/Midas/JessOrb.swift` I set the light `listening` to `0x000000`
  and the dark `listening` to `0xA020F0` (purple) and ran `-only-testing:MidasTests/JessOrbTests`:
  9 tests, 3 failures: "light core is Volt while listening" (black is not 0xCEFF00), "dark core is
  light Volt while listening" (0xA020F0 is not 0xE7FF85), and `testNoPurpleAnywhere` "JessOrbColor(red:
  0.627..., green: 0.125..., blue: 0.941...) reads as purple". Restored from a copy (byte-identical, `cmp`).
- Full suite after the change (`MIDAS_SIMULATOR="Midas jess-look" scripts/test-all.sh`): test guard
  34 OK, backend 869 passed, shell 637 tests 0 failures, midas-intel 31 OK. Before the change the
  shell suite had 2 failures (the two listening assertions in the old loop).

## 2026-10-22: JessOrbTests listening core colour (NEEDS-EVIDENCE, not changed)

- Asked by: jess-look session, worktree `midas-worktrees/jess-look` (branch `agent/jess-look`).
- Test: `shell/MidasTests/VoiceReminderTests.swift`, `JessOrbTests.testTheCoreAloneCarriesTheResultInBothModes`
  (and `testNoPurpleAnywhere`).
- Change asked for: drop `.listening` from the black (light) / white (dark) core loop; assert the
  listening core is `0xCEFF00` (light) and `0xE7FF85` (dark); add `palette.listening` to the
  never-purple list.
- Reason given: founder, 2026-10-22, in the jess-look session, chose option F2t ("Volt in the
  original jess purple's recipe", `docs/mockups/jess-look-2026-10-22-r6.html`); `shell/Midas/JessOrb.swift`
  already changed (uncommitted).
- Why not accepted: the decision is not written and dated in `docs/PRODUCT.md` or the midas-intel
  design doc. `docs/PRODUCT.md` still says "The orb (jess) is Midas black and white". The only
  other record, `docs/briefs/jess-look-lead.md`, lists "Listening colour" under "Still open", with
  no choice recorded, and a lead brief is not one of the accepted sources in any case.
- Evidence that would change the answer: a dated founder entry in `docs/PRODUCT.md` (or
  midas-intel `docs/designs/jess-personal-assistant-shell.md`) saying the orb core while listening
  is #CEFF00 in light mode and #E7FF85 in dark mode, with idle and thinking staying black/white.
  With that in place the requested change is the right one and the request can be resent as is.
- Nothing changed in the test file; the suite was not run (the requester runs it).

## 2026-10-22: backend sqlite-d1 test helper applies 0003_assignments; JessRoutedFlowTests reworked for the home page card (ACCEPTED, two changes)

- Asked by: jess-bg session, worktree `midas-worktrees/jess-bg` (branch `agent/jess-bg`).
- Decision (founder, 2026-10-22, `docs/PRODUCT.md`, "jess in the background, one result card,
  jess for everyone"): "The result is shown only inside Midas, as one card at the top of the home
  page ... Both kinds stay until dismissed; the separate success banner is replaced by this card."
  and "jess is a Sidekick every user has by default (assigned to existing users and at sign-up)".
  Brief: midas-intel `docs/plans/2026-10-22-jess-background-brief.md`.
- Change 1, `backend/test/helpers/sqlite-d1.ts`: `MIGRATION_URLS` now also applies
  `migrations/0003_assignments.sql` (after 0001), with a comment saying why. No assertion changed.
  Sign-up (`handleRegisterVerify`) now inserts the jess `assignments` row in the same batch as the
  user, passkey and session, so before this change all 6 register/login/me tests in
  `backend/test/auth.test.ts` failed with "no such table: assignments".
  Proof it can still fail: I changed the assignment insert in `backend/src/auth.ts` to bind `null`
  as `sidekick_id` and ran `npx vitest run test/auth.test.ts`: 6 failed, 9 passed, "NOT NULL
  constraint failed: assignments.sidekick_id". Restored from a copy (byte-identical, `cmp`).
- Change 2, `shell/MidasTests/JessRouterTests.swift`, section "The Listening screen with the router"
  (`RoutedFlowHarness`, `JessRoutedFlowTests`): the flow no longer shows jess results (no banner,
  no `notDoneCard`); `route` returns nothing and `JessResults.submit` makes the card.
  - `RoutedFlowHarness`: `route` returns Void and only records the call; `results` and the
    `init(results:)` parameter removed.
  - `testDoneShowsTheSidekicksOwnLineInTheBannerThatLeavesByItself` replaced by
    `testWhatWasSaidGoesOnceToTheRouterAndTheScreenClosesWithNoBanner`: after speaking, the screen
    closes, the router got the transcript exactly once, the old parser was never asked, nothing
    was saved, and `banner` is nil.
  - Deleted `testNotDoneLeavesTheCardOnTheHomePageAndTryAgainSendsTheSameWords` and
    `testTheCardStaysUntilDismissedAndARepairShowsSentToRepair`: the API they drove
    (`notDoneCard`, `retryNotDone`, `dismissNotDone`, `.sentToRepair` banner) no longer exists.
    Their behaviour is checked against `JessResults` in the new
    `shell/MidasTests/JessBackgroundTests.swift`:
    `testTryAgainSendsTheSameWordsAndTheCardShowsTheNewResultAtTheTop` (same words sent again,
    Working while sent, new result at top), `testResultsStackNewestFirstAndStayOnDiskUntilDismissed`
    (nothing leaves by itself, dismiss kept) and `testEachStateHasItsCoreAndWords` (Sent to
    Repair title/body, no action; Not Done red core). I read those tests before deleting.
  - `testTheWordsFollowTheWritingRules` rewritten on `JessResultCard` with the same expectations:
    done title is the Sidekick's line, a done card with no time has an empty body, Sent to Repair
    / "Reminders" / no action, a done card with a time reads exactly like
    `VoiceReminderCopy.whenText` and starts "Tomorrow", Not Done / quoted transcript / "Try Again".
    "Trying…" became "Working…" (the card's word while sent, per the brief).
  - File header and section MARK no longer say the banner shows jess results.
  Proof it can still fail: in `shell/Midas/VoiceReminderFlow.swift` I made `send` set a
  `.notAdded` banner after `route`, and made `cardTitle` return "Not Done" for `.working`, then ran
  `-only-testing:MidasTests/JessRoutedFlowTests`: 2 tests, 2 failures:
  "XCTAssertNil failed: VoiceBanner(... notAdded(transcript: "add bananas to groceries"))" and
  "XCTAssertEqual failed: ("Not Done") is not equal to ("Working…")". Restored from a copy
  (byte-identical, `cmp`).
- Result after both changes: `MIDAS_SIMULATOR="Midas jess-bg" scripts/test-all.sh` exited 0.
  Test guard: 34 OK. Backend: 80 files, 869 tests passed. Shell: 631 tests, 0 failures.
  midas-intel: 31 OK. Before: backend 6 failed (auth.test.ts, above); shell not run before
  the change (the old JessRouterTests used API the code no longer has, so it could not compile).

## 2026-10-22: jess-router "offers every tool of every Sidekick under its wire name, plus repair and cannot-act" (ACCEPTED)

- Asked by: jess-404 session, worktree `midas-worktrees/jess-404`.
- Change in `backend/test/jess-router.test.ts` line 75:
  `expect(request.parallel_tool_calls).toBe(false);` became
  `expect(request).not.toHaveProperty("parallel_tool_calls");`. Nothing else changed.
- Reason (bug, 2026-10-22, staging voice_logs): every POST /voice/jess failed with "HTTP 404: No
  endpoints found that can handle the requested parameters". The test was wrong: it required a
  parameter that no provider of the model accepts. `buildJessRequest` sent
  `parallel_tool_calls: false` with `provider.require_parameters: true`. I checked
  GET https://openrouter.ai/api/v1/models/deepseek/deepseek-v4-flash/endpoints on 2026-10-22:
  0 of 15 endpoints list `parallel_tool_calls` in `supported_parameters` (all 15 list `tools` and
  `tool_choice`), so no provider qualifies. The parameter adds nothing: `toolCallFromMessage`
  reads only `tool_calls[0]`. The lead's note calls the fix founder-directed, but no written,
  dated founder decision covers it. The change is accepted as a wrong test, not as a founder
  decision. `parallel_tool_calls` was removed from `backend/src/jess.ts` by the requesting
  session, not by me.
- Proof it can still fail: I put `parallel_tool_calls: false,` back into `buildJessRequest` in
  `backend/src/jess.ts` and ran `npx vitest run test/jess-router.test.ts`. Result: 1 failed and
  17 passed, with "AssertionError: expected { …(10) } to not have property
  "parallel_tool_calls"". I then restored the file from a copy; `parallel_tool_calls` no longer
  appears in it.
- Result after the change: `scripts/test-all.sh` exited 0. Test guard: 34 OK. Backend: 78 files,
  860 tests passed. Shell: 610 tests, 0 failures. midas-intel: 31 OK. Before the change, backend
  had 1 failure: this assertion, against the already-fixed `jess.ts`.

## 2026-10-21: runner-deploy "an unreadable pointer after the deploy ends failed", resent with evidence (ACCEPTED; failure proof not yet run)

- Asked by: lead session for the staging-port builder, worktree `midas-worktrees/staging-port`,
  resending the NEEDS-EVIDENCE request below.
- Reason: founder decision now written and dated in `docs/PRODUCT.md`, "**A published repair is
  always marked done (founder, 2026-10-21):** when the deploy script reports that a repair was
  published to the user's copy, the repair ends `deployed_live` and the user gets the done
  notice, even if the read-back check after publishing fails (that failure is logged, not
  treated as a failed repair)." It replaces the read-back part of the 2026-10-13 contract rule
  quoted below. Bug: staging repair report `13edb182` (2026-10-20).
- Change in `backend/test/runner-deploy.test.ts`: the case is renamed "an unreadable pointer
  after a clean deploy that reported this user's copy ends deployed_live, never failed". It now
  asserts status `deployed_live`, version `v-test`, statuses exactly running, fix_ready,
  deployed_live (no `failed`), the deployed_live post's summary and version, and the user's notice
  "Fixed and live: reminders" with "read-back unconfirmed". Header line 4 now says a failing
  deploy script or a read-back naming other files posts failed, while a read-back that never
  answers after the script reported this user's copy posts deployed_live. The "wrongHash" and
  "scriptFails" cases are unchanged. `runner-publish-readback*.test.ts` covers the case where the
  script's line names another user or environment, or there is no line.
- Proof it can still fail: NOT RUN. I changed `runner/lib/deploy.mjs` `publishFix` to
  `if (false && reportedVersion !== null)`, which brings back the old "unreadable means failed"
  path. The permission system then blocked the vitest run against that edit, and I restored the
  line at once (line 189 reads `if (reportedVersion !== null) {` again). Expected failure, not
  seen: "expected 'failed' to be 'deployed_live'". Someone still needs to run this proof and
  record it here.
- Result after the change: runner-deploy, runner-publish-readback and runner-publish-readback-env
  passed, 3 files, 17 tests. Full suite not run, at the lead's request (shell suite running on a
  simulator).

## 2026-10-21: runner-deploy "an unreadable pointer after the deploy ends failed" (NEEDS-EVIDENCE)

- Asked by: lead session for the staging-port builder, worktree `midas-worktrees/staging-port`
  (branch `agent/staging-port`).
- Test: `backend/test/runner-deploy.test.ts`, `it("an unreadable pointer after the deploy ends
  failed")` and header line 4 ("A deploy or read-back failure posts failed.").
- Change asked for: make it expect `deployed_live` (statuses running, fix_ready, deployed_live)
  when the read-back never answers but the deploy script exited 0 and printed "deployed
  <sidekick> <version> for user <reporter> to ..."; header to say an unreadable read-back after
  the script reported the publish posts deployed_live (unconfirmed). Matches the new
  `runner/lib/deploy.mjs` `publishFix` ("readBack unconfirmed").
- Bug cited: staging repair report `13edb182` (2026-10-20): copy published, read-back failed,
  report ended failed, no done notice.
- Not changed. The test matches the written founder decision, `docs/briefs/repair-contract.md`,
  "Settled (founder, 2026-10-13)": the runner "checks the deploy landed (reads back the user's
  `current.json` and compares the content hash) and only then posts `deployed_live`. ... A
  failed deploy or check posts `failed`." The decision cited by the lead,
  `docs/PRODUCT.md` "Repairs that fix wrong behaviour go to the base (founder, 2026-10-21)",
  says nothing about the read-back or the status after it. The quoted instruction ("a published
  copy is always marked deployed") is in a lead brief, not written and dated in
  `docs/PRODUCT.md` or the midas-intel design doc. `docs/briefs/staging-port-2026-10-21.md`
  lists this as a "code change to consider (not made)" with two options ("a check of the pointer
  on the next poll" or "a published, read-back failed status").
- State at request: runner-deploy + runner-publish-readback: 1 failed (this test, "expected
  'deployed_live' to be 'failed'"), 15 passed.
- Evidence that would change the answer: a dated founder decision in `docs/PRODUCT.md` (or the
  design doc) that replaces the 2026-10-13 rule, saying a repair whose deploy script reported
  the publish is posted `deployed_live` (with the done notice) even when the read-back after it
  fails. The retry part of the fix (3 read-back attempts) needs no test change.

## 2026-10-21: jess router review, seven requested changes, resent with evidence (ACCEPTED; items 1 and 2 narrower than asked)

- Asked by: lead session for the jess-router builder, worktree `midas-worktrees/jess-router`
  (branch `agent/jess-router`), resending the NEEDS-EVIDENCE request below plus item 7.
- Reason: founder decisions now written and dated in `docs/PRODUCT.md`, "**jess router review,
  founder 2026-10-21:**": "(3) Snooze is not a voice tool: it is a notification action, not a page
  action; the `reminders.snooze` and `care-reminders.snooze` tools are removed. (4) Tool removal is
  allowed: a repair that removes a feature removes its tool, `tools.js` handler and test together
  ... (5) The server reads each Sidekick's manifest (the user's own copy version) for the agent
  block and tools; the phone no longer sends them. ... (7) Tools accept only what the page offers
  (same repeat presets, alert steps, interval range and uncomplete window as the page)." Also in
  the design doc ("Router review, founder 2026-10-21") and the brief's "Founder review, 2026-10-21
  (overrides the above where they differ)": "no snooze tools; tool removal allowed ... the server
  reads the manifests (the phone no longer sends tools)".
- Before: backend 19 failed / 789 passed (5 files). Three of the 19 not named by the request:
  jess-router "queues a repair ...", "does not queue a repair ...", "records what the phone did ...".
- Changes:
  1. `backend/test/jess-repair-rules.test.ts`: NOT deleted whole. Deleted describe "a repair keeps
     every voice tool" (3 tests; the rule is reversed by (4); `agentToolsKeptProblems` is gone;
     jess-review-decisions "a repair may remove a tool ..." covers add, keep, removed agent block,
     runner and agent check). In the prompt test, removed only
     `expect(prompt).toContain("Never remove or rename a tool")` (reversed by (4); jess-review-decisions
     asserts it is absent). Kept its other four prompt assertions (index.html and tools.js move
     together, `<id>.<verb>` naming, the copied-block marker, the tools test name): nothing else
     covers three of them. Header comment and imports updated.
  2. `backend/test/jess-router.test.ts` `describe("POST /voice/jess")`: NOT deleted. Deleting it
     would drop route-level checks nothing else has: the log row's user_id, transcript, model and
     tool_input; the repair report's user_id, kind, status "queued" and the founder's
     request_received event; the outcome endpoint refusing a bad value (400), writing once only,
     and storing "refused:<reason>". Fixed the setup instead, per (5): `BUNDLES` is now a fake R2
     bucket serving reminders v5 and care-reminders c2 manifests (pointers with tools.js); the
     phone body sends `{ id, context }` only (`sidekicksSentByPhone()`); "does not queue a repair
     for a Sidekick the user is not assigned" assigns care-reminders only (with no Sidekick
     assigned the route now stops at "no-tools" before the model, so the unassigned-repair check
     would not be reached). Every assertion unchanged, including `bundle_version: "v5"`. "the request
     to the model" and "checking the model's call" untouched.
  3. `backend/test/reminders-tools.test.ts`: deleted the two snooze tests, "snooze" removed from the
     verb list, describe renamed "reminders.edit and move". Done/edit-clears-snoozedUntil tests kept.
  4. `backend/test/care-reminders-tools.test.ts`: deleted "snoozes with snoozedUntil", "snooze"
     removed from the verb list, describe renamed "care-reminders.edit and delete". (7): "undoes a
     one-time Done" now uses records with the Eye exam (index 6, `reminder:ieyes0001`, checked) done
     today (at 2026-10-20T15:00Z, completedAt 2026-10-20T16:00Z); assertions unchanged.
     jess-page-limits covers the refusal of one done on an earlier day.
  5. `backend/test/sidekick-tools-gate.test.ts`: `simpleTool` carries
     `_meta: { "midas/page-actions": ["add"] }`; "passes when it sets the global ..." passes
     `<button data-action="add"></button>`. No other test needed a change.
  6. `shell/MidasTests/JessRouterTests.swift`: `XCTAssertEqual(second.sidekicks[0].agent, ...)`
     replaced with an assertion that the encoded payload's keys are exactly `["context", "id"]`;
     header comment updated.
- Proof (each break in app code, restored byte-for-byte, `cmp` OK): (a) `jess-route.ts` outcome
  UPDATE without `AND phone_outcome IS NULL`: "records what the phone did, once ..." fails (expected
  200 to be 404). (b) `repairs.ts` founder event kind changed: "queues a repair ..." fails.
  (c) care `uncompleteReminder` never finds an entry to undo: "undoes a one-time Done" and "undoes
  a repeat's Done" fail ('not-done'). (d) `bundle-tools.mjs` `pageOffersAction` returns false:
  "passes when it sets the global ..." fails, plus both real Sidekicks' gate checks. (e) the copied
  block marker removed from `runner/agents/reminders.md` and `care-reminders.md`: both prompt tests
  fail. (f) a `snooze` handler added back to `sidekicks/reminders/tools.js`: "has a handler for every
  tool ..." fails (and the gate check). Swift (6): not run here (caller runs xcodebuild); it fails if
  `JessSidekickPayload` encodes any key besides id and context, e.g. an `agent` field.
- Suite after: backend 70 files, 808/808 passed. Shell and midas-intel not run (caller runs the
  shell suite). `shell/project.yml` shows as modified in the worktree; not touched by this change.

## 2026-10-21: jess router review, six requested changes (NEEDS-EVIDENCE)

- Asked by: lead session for the jess-router builder, worktree `midas-worktrees/jess-router`
  (branch `agent/jess-router`), relaying "founder decisions 2026-10-21, jess router review"
  numbered (3) snooze tools removed and page-actions required, (4) tool removal allowed,
  (5) server reads manifests, phone sends only `{ id, context }`.
- Tests and changes asked for: (1) delete `backend/test/jess-repair-rules.test.ts`; (2) delete
  `describe("POST /voice/jess")` (6 tests) and its helpers from `backend/test/jess-router.test.ts`;
  (3) delete the two snooze tests in `backend/test/reminders-tools.test.ts`, drop "snooze" from its
  verb list, rename a describe; (4) same for `backend/test/care-reminders-tools.test.ts`;
  (5) add `_meta["midas/page-actions"]` and a matching button to fixtures in
  `backend/test/sidekick-tools-gate.test.ts`; (6) replace the `agent` assertion in
  `shell/MidasTests/JessRouterTests.swift` with a keys-are-id-and-context check.
- Nothing changed. Baseline before: backend 18 failed / 782 passed (5 files: the 18 tests above).
- Reason: decisions (3) and (5) are not written and dated in `docs/PRODUCT.md` or the midas-intel
  design doc. The written, dated decision says the opposite: midas-intel
  `docs/plans/2026-10-21-jess-router-brief.md` ("approved by the founder 2026-10-21") lists the
  tools as "add, edit, complete, uncomplete, delete, snooze, move between lists ..." and says
  "The phone sends the transcript, the tools of the user's Sidekicks (from their manifests)".
  The brief's "sections 10 and 11 override the body" refers to sections the plan does not have.
  Decision (4) is written and dated only in midas `docs/CONCERNS.md` §15 ("Founder decision, for
  now: ... option A, allow removal"), not in `docs/PRODUCT.md` or the design doc. A relayed
  message from another agent is not the written decision.
- Also, for item 2 even with evidence: `jess-route-manifests.test.ts` has no route-level case for
  "no key / the model fails twice" or "the model calls midas.cannot_act, logged with why" (it only
  covers the no-tools not-done case). Those two tests would have to be adapted to the new body or
  replaced first, not deleted.
- Evidence that settles it: the founder's 2026-10-21 review decisions (3) snooze is a
  notification action only, every tool names its page controls in `_meta["midas/page-actions"]`;
  (4) option A tool removal replacing "repairs keep every tool"; (5) the server reads each
  Sidekick's manifest (user's copy version), phone sends only `{ id, context }`), written and
  dated in `docs/PRODUCT.md` (and the midas-intel design doc or the brief, correcting the
  snooze tool list and the "phone sends the tools" line).

## 2026-10-21: runner and repair fixtures carry the Reminders tools.js (ACCEPTED)

- Asked by: jess-router builder, worktree `midas-worktrees/jess-router` (branch
  `agent/jess-router`), phase 2.
- Tests: `backend/test/helpers/runner-fixture.ts`, `runner-check-and-intel`,
  `repair-data-review-fixes`, `runner-repair-data-job`, `runner-deploy`, `runner-secrets-and-not`,
  `runner-copy-tests`, `runner-feature-kind`, `runner-job` (all `backend/test/`).
- Change: fixtures only. `remindersBundle()` also returns `toolsText` (`sidekicks/reminders/tools.js`);
  `standardAssets()` serves `"bundle.tools.js"`; new helper `deployedFolderHash(folder)` hashes
  index.html + manifest.json + tools.js when the folder has one, used by `fakeDeployThatLands` and
  runner-deploy's own `readPointer`. runner-check-and-intel `makeJobFolder` writes
  `sidekick/tools.js` and every `gateProblems` call passes `toolsText`; repair-data-review-fixes and
  runner-repair-data-job serve `"bundle.tools.js"`; runner-secrets-and-not copies tools.js into the
  probe job folder. Three exact job-folder listings (runner-copy-tests "a job with stored copy
  tests ...", runner-feature-kind "a voice-only feature request ...", runner-job "builds a job folder
  holding only ...") now list `sidekick/tools.js`; they stay exact. No assertion removed or widened;
  `expect(clean).toEqual([])` and the exact problem lists are unchanged.
- Reason: founder decision, midas-intel `docs/plans/2026-10-21-jess-router-brief.md`, "approved by
  the founder 2026-10-21": "The shell runs `tools.js` ... It travels through every copy, deploy,
  fetch, repair and hash path like `index.html` and `manifest.json`." Commit 13ed918 added
  `agent` to `sidekicks/reminders/manifest.json` and `sidekicks/reminders/tools.js`, so the real
  bundle served as html + manifest only is refused by the gate ("manifest.json has agent tools but
  there is no tools.js") and the read-back hash omitted tools.js. Before: backend 27 failed / 701
  passed (11 files).
- Proof (each break in app code, restored byte-for-byte, `cmp` OK): (a) `buildJobFolder` never
  writes tools.js: 24 failed in 9 files, gate output "manifest.json has agent tools but there is no
  tools.js". (b) `expectedContentHash` drops tools.js: 13 failed (runner-deploy "fix_ready ...
  deployed_live" ends failed, read-back mismatch). (c) `stageDeployFolder` skips tools.js: 13
  failed, same tests. (d) runner never downloads `bundle.tools.js`: 24 failed in 9 files. (e)
  `gateProblems` ignores the given `toolsText`: runner-check-and-intel "the gate rejects ..." fails
  on `clean` with the no-tools.js problem, plus 3 more. Not caught by any test: `buildSandboxCheckout`
  copying only index.html and manifest.json (sandbox omits tools.js) - a coverage gap for a new test.
- Suite after: test guard OK, backend 728/728 (62 files), shell 567/0, midas-intel 31 OK.

## 2026-10-20: retired-script scan lets the name-hunting guard tests hold the names (ACCEPTED)

- Asked by: agent A, worktree `midas-worktrees/legacy-sweep2-a`, after main 5f1875c (all three
  sweep-2 branches) was merged in.
- Test: `backend/test/legacy-retired-2026-10-20.test.ts`, "are named by no code or test that runs
  (the scan sees the runner, the planner and the tests)", renamed "... that runs, and used by none
  (...)".
- Change: added `NAME_HUNTING_GUARD_TESTS` (this file and `backend/test/legacy-sweep-2-docs.test.ts`)
  and a `retiredScriptUses` helper (static import/export from, dynamic import, require, or
  `join(..., "<name>.mjs")`). Files in that list get the use check; every other running file keeps
  the old rule (any mention of either base name fails). This file is no longer skipped: it now gets
  the use check, which is stricter than before. Added `expect(files).toContain` for C's file. New
  test "the use check sees an import, a dynamic import, a require and a join of either script, and
  not a hunted marker (the scan can fail)". One sentence added to the header.
- Reason: the test is wrong as written. The two guard tests contradicted each other on main:
  agent C's `legacy-sweep-2-docs.test.ts` has to hold `migrate-records\.mjs` and
  `record-upgrades\.mjs` as the doc markers it hunts for, and the scan failed on that text
  (`"backend/test/legacy-sweep-2-docs.test.ts: record-upgrades"`, `"...: migrate-records"`).
  Decision this enforces: `docs/PRODUCT.md` "Old formats retired (founder, 2026-10-20)": "no code
  reads or writes an old record shape. The migration scripts are kept only as history in
  `docs/legacy/code/` (not run, not tested)." A marker string in a doc-hunting test does not run or
  test the scripts; an import, require or path join would, and still fails.
- Proof: (a) whole file passes with C's file present, 10/10. (b) appended
  `// from "../scripts/migrate-records.mjs"` to `legacy-sweep-2-docs.test.ts`: failed with
  `"backend/test/legacy-sweep-2-docs.test.ts: uses migrate-records.mjs"`; restored, sha1 222e8f1e
  OK. (c) appended `// record-upgrades` to `runner/lib/summary.mjs`: failed with
  `"runner/lib/summary.mjs: record-upgrades"`; restored, sha1 ea21e332 OK. (d) appended
  `// require("./record-upgrades")` to this test file: failed with
  `"backend/test/legacy-retired-2026-10-20.test.ts: uses record-upgrades.mjs"`; restored, sha1 OK.
- Suite after: backend 653/653 (58 files), shell 567/0, test guard 34 OK, midas-intel 31 OK.
  Before: backend 1 failed / 651 passed (this clash).

## 2026-10-20: old formats retired, two follow-ups from agent A (both ACCEPTED)

- Asked by: agent A (coordinator), worktree `midas-worktrees/legacy-sweep2-a`, after the entry
  below. App change: `backend/src/record-types.ts` narrowed to the written decision (only a save
  from a stored version whose manifest has no types is refused).
- A. `backend/test/sync-untyped-version-refused.test.ts` (new file, untracked, counted as existing
  by the guard): deleted its third test, "refuses a save from a version that is not stored, and one
  for a Sidekick with no deployed version", and dropped ", and so is a save whose version cannot be
  found, so no record reaches the ops table without a schema check" from the header. Reason: the
  test is wrong. It asserts more than the written decision (`docs/PRODUCT.md` "Old formats retired
  (founder, 2026-10-20)": "The server refuses every save that comes from a Sidekick version
  without schema types ..."). This is the same claim logged NEEDS-EVIDENCE below (11b not-stored
  half, 11c). The other two tests are unchanged. Proof: with `record-types.ts` set to
  `git show HEAD:backend/src/record-types.ts`, both failed ("expected [] to deeply equal [ Array(2)
  ]"; "expected [ 'op-oldcopy-1' ] to deeply equal []"). Restored from a copy, sha1 8b6a13df.
  Note: the header still opens with "The server stores nothing unchecked". That is broader than
  what remains, but its removal was not asked for.
- B. `backend/test/repair-data-review-fixes.test.ts`, "never gives a copy without types the base's
  types; it prints the user's records against them for the schema pass": fixture `reminder:1`
  `{ title: "No $type yet", at: 1760000000000 }` (an old shape the retired in-memory upgrade fixed)
  to `{ $type: "reminders.item", title: "Fits", at: "2026-10-20T09:00:00.000Z" }`. It fits the
  schema (checkRecord gives null). Expectations unchanged (1 misfit, reminder:2). Reason:
  `docs/PRODUCT.md` "Old formats retired (founder, 2026-10-20)": "no code reads or writes an old
  record shape". Proof: `checkUserRecords` in `runner/lib/user-records.mjs` made to skip
  reminder:2's failure; the test failed ("expected 'the user's records against the base…' to
  match /^the user's records against the base'…/"). Restored, sha1 8ab81f67.

## 2026-10-20: old formats retired, resubmission of the nine requests plus items 10 and 11 (1-10 ACCEPTED; 11 partly ACCEPTED, partly NEEDS-EVIDENCE)

- Asked by: agent A of the second old-format sweep, worktree `midas-worktrees/legacy-sweep2-a`
  (branch `agent/legacy-sweep2-a`), resubmitting the requests logged NEEDS-EVIDENCE below, plus
  items 10 and 11 (item 11 amended by the coordinator mid-task).
- Reason, items 1-10: `docs/PRODUCT.md` (commit ede0f55, merged): "**Old formats retired
  (founder, 2026-10-20):** live and staging are converted to the unified data format (live dry run
  after the conversion: 0 writes). The upgrade-on-read code, the shell's epoch-millisecond and
  `body` fallbacks and the one-time migration tools are retired: no code reads or writes an old
  record shape. The migration scripts are kept only as history in `docs/legacy/code/` (not run,
  not tested)." `CLAUDE.md` quarantine section says the same. Item 10 also: wrong date in a test
  (2026-10-21 for a decision dated 2026-10-20).
- Reason, item 11: same paragraph, commit f7dc456: "The server refuses every save that comes from
  a Sidekick version without schema types (the bundles from before the unified data rework, build
  2 and older); it no longer lets them through unchecked (founder, 2026-10-20)."
- Baseline before any change: test guard OK; backend 75 failed, 567 passed (642), 19 files failed
  (uncommitted app change); shell TEST FAILED (xcodebuild "Mach error -308 - (ipc/mig) server
  died", simulator launch); midas-intel 31 OK.

1. ACCEPTED. Deleted `backend/test/record-upgrades.test.ts` and
   `backend/test/record-upgrades-snoozes.test.ts`: tests of the converter, retired ("not run, not
   tested"). Proof: not applicable (deletion); `legacy-retired-2026-10-20.test.ts` fails if the
   converter returns to `backend/scripts/` (item 10 proof).
2. ACCEPTED. Deleted `backend/test/runner-clash-moved-key.test.ts`: its subject is a key moved by
   the in-memory upgrade, which no longer exists. Its intent (a stored misfit record still shows its
   clash) is kept by item 4, proof there.
3. ACCEPTED. `backend/test/helpers/runner-fixture.ts`: removed the copy of
   `backend/scripts/record-upgrades.mjs` into the scratch checkout; comment above `makeScratch`
   names only the validator and the store helper. Proof: `loadDataModules` in
   `runner/lib/user-records.mjs` temporarily made to require `backend/scripts/record-upgrades.mjs`
   in the checkout again; `runner-repair-data-job` and `runner-link-and-clash` failed 8 of 12
   ("expected 'runner error' to be 'records do not fit schema'", etc.). Restored from a copy, sha1
   8ab81f67 before and after.
4. ACCEPTED. `backend/test/runner-link-and-clash.test.ts` item 16: fixture
   `OLD_SHAPE_RECORD_WITH_PRIORITY` (no `$type`, epoch-ms `at`) to `STORED_MISFIT_WITH_PRIORITY`
   `{ key: "reminder:1", value: { $type: "reminders.item", title: "", priority: "high" } }` (still a
   misfit: "reminders.item.title must not be empty"); header, fixture comment and describe title to
   "the clash check sees a stored record that does not fit its schema". Expected outputs unchanged.
   Proof: `storedSchemaProblems` in `runner/lib/user-records.mjs` made to `return []`; both tests
   failed ("expected [] to deeply equal [ Array(1) ]"; "expected 'records do not fit schema' to be
   'schema not backward compatible'"). Restored, sha1 8ab81f67.
5. ACCEPTED. `backend/test/repair-data-review-fixes.test.ts`: header items 7 and 9 reworded;
   `completeCheckout` no longer copies `record-upgrades.mjs`, comment names the validator and store
   helper; describe 7 title; describe 9 replaced by one test: `reminder:9` with an empty title gives
   1 failure with keys exactly `["key","problem"]`, detail contains "reminder:9: " and not "stored
   as". The removed `upgraded` count test covers a field that no longer exists. Proof:
   `checkUserRecords` made to add `storedAs` and `recordFailureDetail` to print "(stored as ...)":
   failed ("expected [ 'key', 'storedAs', 'problem' ] to deeply equal [ 'key', 'problem' ]"); with
   only the detail change: failed ("expected '1 of the user's records ...' to contain 'reminder:9:
   '"). Restored, sha1 8ab81f67.
6. ACCEPTED. `backend/test/runner-repair-data-job.test.ts`: records-check
   `toEqual({ checked: 2, failures: [] })`; the old-shape upgrade-and-publish test replaced with
   "does not publish when a record lacks its $type: records are checked as stored" (`reminder:8`
   without `$type`: failed, "records do not fit schema", detail names `reminder:8: reminders.item.$type
   must be "reminders.item"`, no deploy). Proof: `checkUserRecords` made to add a missing `$type`
   before the check: the new test failed ("expected 'deployed_live' to be 'failed'"); made to return
   `upgraded: 0`: the records-check test failed ("expected { checked: 2, upgraded: +0, …(1) } to
   deeply equal { checked: 2, failures: [] }"). Restored, sha1 8ab81f67.
7. ACCEPTED. `backend/test/runner-repair-data.test.ts`: header "as stored"; undeclared-read sample
   `store.query('task:')` to `store.query('mood:')` (mood: is undeclared in Reminders, so the read
   is still one the check must ignore), title "reads of undeclared prefixes"; upgrade test replaced
   with "checks each record as stored: nothing is upgraded before the check" (`toEqual({ checked: 1,
   failures: [{ key: "reminder:8", problem: 'reminders.item.$type must be "reminders.item"' }] })`);
   care test title drops "folded alert records upgrade, ". Proof: the same add-`$type` break failed
   it ("expected { checked: 1, failures: [] } to deeply equal { checked: 1, failures: [ { …(2) } ]
   }"). Restored, sha1 8ab81f67.
8. ACCEPTED. `backend/test/user-copy-plan.test.ts`: header; `retiredWrites` to
   `undeclaredWrites(html, manifest)`; the `task:` copy test to a `tag:` page with gap "writes tag:
   records its types do not declare"; describe `undeclaredWrites`: reads give `[]`, `tag:` update and
   `note:` set give both gap texts, `baseHtml` gives `[]`. The old `settings:sidebar` write check
   is gone with the retired-shape list it tested. Proof: `undeclaredWrites` in
   `backend/scripts/user-copy-plan.mjs` made to find nothing: both tests failed ("expected [] to
   include 'writes tag: records its types do not …'"; "expected [] to deeply equal [ …(2) ]").
   Restored, sha1 235b0266.
9. ACCEPTED. `backend/test/legacy-quarantine.test.ts`: header cites the retirement; allow-list,
   header constant and quarantine-file constant removed; the scan-coverage test expects
   `backend/scripts/user-copy-plan.mjs`; the scan skips no file; the converter-header test deleted
   (its files left the code); the marker test now checks each of the five markers hits its sample
   text exactly once (`toEqual([name])`). Proof: appended `// store.set('task:' + id, v)` to
   `runner/lib/summary.mjs`: "no backend, runner or scripts code names an old shape" failed
   ("expected [ 'runner/lib/summary.mjs: task: key' ] to deeply equal []"). Restored, sha1 ea21e332.
10. ACCEPTED. `backend/test/legacy-retired-2026-10-21.test.ts` (untracked) recreated as
    `backend/test/legacy-retired-2026-10-20.test.ts`, every "2026-10-21" to "2026-10-20" (THIS_FILE,
    the asserted header text), header cites `docs/PRODUCT.md` "Old formats retired (founder,
    2026-10-20)"; old file removed. Nothing else changed. Proof: copied the retired
    `record-upgrades.mjs` back into `backend/scripts/`: 3 of 9 failed ("record-upgrades.mjs: expected
    true to be false"; the name and wording scans). Removed again; 9 of 9 pass.
11. `backend/test/sync-record-types.test.ts`.
    - ACCEPTED (the untyped-version part): header now says a save from a version without a types
      block is refused (founder, 2026-10-20, `docs/PRODUCT.md` "Old formats retired") and a version
      that is not stored is not content-checked; test renamed "an older phone still on a version
      without schemas is refused; a version that is not stored is checked against nothing";
      fixtures `task:5`/`task:6` to `reminder:5`/`reminder:6` with `{ $type: "reminders.item",
      title: "x" }`; `op-old-001` (v1) now expected rejected with "reminders version v1 has no
      record schema types". Proof: in `backend/src/record-types.ts` the refusal was made to pass
      every version through (`return null;`): failed ("expected [ 'op-old-001', 'op-gone-01' ] to
      deeply equal [ 'op-gone-01' ]"); with only the untyped refusal kept, all 6 pass. Restored,
      sha1 2f6747d8.
    - NEEDS-EVIDENCE (not changed): the not-stored half of (b) (`op-gone-01` expected rejected "is
      not deployed") and (c) ("a save for a Sidekick with no deployed version is refused",
      `op-notes-01` rejected "notes has no deployed version"). The written decision names "a
      Sidekick version without schema types (the bundles from before the unified data rework, build
      2 and older)". A version the server does not hold and a Sidekick with no deployed version are
      not those bundles; the requester says this is their own reading. Both tests now fail against
      the uncommitted `record-types.ts`. Evidence that would settle it: the founder's decision,
      written and dated in `docs/PRODUCT.md` or the midas-intel design doc, that saves naming a
      version the server does not hold, and saves for a Sidekick with no deployed version, are
      refused.
- Not requested, still failing: `repair-data-review-fixes.test.ts` "never gives a copy without
  types the base's types; ..." expects 1 misfit, gets 2: its fixture `reminder:1` `{ title: "No
  $type yet", at: 1760000000000 }` was upgraded in memory before. Needs its own request.

## 2026-10-20 (2026-10-21 UTC): converter and migration retired, nine requests (NEEDS-EVIDENCE; nothing changed)

- Asked by: agent A of the second old-format sweep, worktree `midas-worktrees/legacy-sweep2-a`
  (branch `agent/legacy-sweep2-a`). Stated reason for every item: "founder 2026-10-21: live
  converted, migration retired".
- Asked for: (1) delete `backend/test/record-upgrades.test.ts` and
  `backend/test/record-upgrades-snoozes.test.ts`; (2) delete
  `backend/test/runner-clash-moved-key.test.ts`; (3) `backend/test/helpers/runner-fixture.ts`: stop
  copying `backend/scripts/record-upgrades.mjs`; (4) `runner-link-and-clash.test.ts` item 16: old-shape
  fixture to a current-format misfit record; (5) `repair-data-review-fixes.test.ts` items 7 and 9:
  drop the record upgrades from the checkout, replace the `upgraded` / "(stored as task:9)" tests
  with one "names the key as stored" test; (6) `runner-repair-data-job.test.ts`: drop `upgraded: 0`,
  replace "upgrades the reporter's old-shape records in memory and publishes" with "does not
  publish when a record lacks its $type"; (7) `runner-repair-data.test.ts`: header, `task:` read to
  `mood:`, replace "upgrades older shapes in memory first" with "checks each record as stored",
  care test title; (8) `user-copy-plan.test.ts`: `retiredWrites` to `undeclaredWrites`, `task:` page
  to `tag:`; (9) `legacy-quarantine.test.ts`: remove the converter/migration allow-list and header
  test, rewrite the marker test against sample text.
- Why not accepted: every item changes what the suite checks because of one behaviour change (no
  upgrade-on-read in the runner, converter and migration script removed from the codebase). That
  is a founder decision, and it is not written and dated in `docs/PRODUCT.md` (worktree or main)
  or in midas-intel `docs/designs/jess-personal-assistant-shell.md` (searched for "2026-10-21",
  "converted", "retired", "migrat", "record-upgrades", "upgrade on read"). The only written source
  is midas-intel `docs/plans/2026-10-21-legacy-sweep-2-brief.md`, untracked, written 19:06 local,
  eight minutes before this request: "Founder, 2026-10-21: ... the one-time migration tools ... and
  their tests leave the codebase". `CLAUDE.md` still says "The only code that may still understand
  old shapes is the upgrade-on-read converter and the migration script". Supporting but not
  sufficient: live D1 backups `~/midas-backups/live-midas-20261021T014030Z.sql` and
  `...T014343Z.sql` show a live run happened.
- Baseline (backend `npx vitest run`, before any change): 19 files failed, 74 tests failed, 568
  passed (642). Failures follow the uncommitted app change (moved scripts, runner no longer
  upgrading), mostly `helpers/runner-fixture.ts` copying the moved `record-upgrades.mjs`.
- Evidence that would settle it: the decision written and dated in `docs/PRODUCT.md` (by the lead
  on main) or the midas-intel design doc, saying live and staging are converted, the
  upgrade-on-read converter and migration script are retired from code, and their tests are
  removed. With that quoted, the request can be resubmitted unchanged.
## 2026-10-20: shell tests and the Reminders page test for upgrade on read, after the old formats were retired (ACCEPTED; items 1 to 7 and 9 of the second sweep request)

- Asked by: Agent B of the second old-format sweep (worktree `midas-worktrees/legacy-sweep2-b`,
  branch `agent/legacy-sweep2-b`), 2026-10-20, re-sent after the decision was recorded. This
  settles the NEEDS-EVIDENCE entry below.
- Reason: `docs/PRODUCT.md` (commit ede0f55): "**Old formats retired (founder, 2026-10-20):** live
  and staging are converted to the unified data format (live dry run after the conversion: 0
  writes). The upgrade-on-read code, the shell's epoch-millisecond and `body` fallbacks and the
  one-time migration tools are retired: no code reads or writes an old record shape." CLAUDE.md
  quarantine section, same commit: "No code may read or write old shapes".
- Changes:
  1. `shell/MidasTests/ReminderRecordTests.swift`: `testParsesAllThreeDateForms` renamed
     `testParsesBothIsoDateFormsAndNoNumber`, its "Upgrade on read" comment removed; the epoch
     milliseconds assertion is now `XCTAssertNil(ReminderRecord.parseDate(.number(1_791_475_200_000)), "a number is not a date")`.
     Both ISO assertions and the "tomorrow at 9" nil assertion kept.
  2. `shell/MidasTests/MidasStoreScriptTests.swift` `testBadReminderIsRejectedWithTheReason`:
     expected message `reminder.at must be an ISO 8601 date`.
  3. `shell/MidasTests/RecordTypeGateTests.swift` `testTheReservedReminderCheckStillRunsOnUpdate`:
     expected error `reminder.at must be an ISO 8601 date`.
  4. `shell/MidasTests/NotificationNotesTests.swift`: header now says "`body` is not read.";
     `testARecordNotYetConvertedShowsItsBodyAsNotes` (and its comment) replaced by
     `testBodyAloneIsNotReadAsNotes` (title, `body: "Leg day"`, `at`, no `notes` -> notes `""`).
     The other two `body` tests unchanged.
  5. Deleted whole, with their "Upgrade on read" comments:
     `CareRemindersFieldsTests.testOldAlertAndTimeRecordsAreFoldedIntoTheItemAndRemoved`,
     `CareRemindersSnoozeTests.testOldAlertAndTimeSnoozesAreFoldedIntoTheItemsOwnEntries`,
     `CareRemindersSimpleSheetTests.testAnOldRecordWithItsOwnIconAlertsAndSeriesStillLoadsAndUsesItsListsAlerts`.
     They tested the fold of old care records, code the decision retires. Copying a list's rules
     onto items stays covered by `CareRemindersFieldsTests.testEditingAListRuleRewritesTheRulesOnItsReminders`.
     After the deletion the private helper `reminderKeys` in `CareRemindersSnoozeTests.swift`
     (line 100) has no caller; left in place (Swift does not warn on unused private methods).
  6. `shell/MidasTests/RemindersWidgetTests.swift` `testAReminderOrListChangeRepublishes`: the
     "other key of this Sidekick" write uses `settings:self` (the page's current settings key,
     `sidekicks/reminders/index.html` `SETTINGS_KEY`) instead of the retired `settings:sidebar`.
     Assertion unchanged.
  7. `backend/test/reminders-logic.test.ts` "keys every item as reminder:, dated or not": the
     "Upgrade on read" comment and the `itemFromRecord("task:b2", ...)` assertion removed; the two
     `recordKey` assertions stay.
  9. `backend/test/legacy-quarantine-shell-pages.test.ts` (new, uncommitted file of the
     requester): date `2026-10-21` corrected to `2026-10-20` on lines 5, 79 and 97 (two comments
     and the describe title). Nothing else changed (diff checked).
- Proof they can still fail (Xcode suite not run, at the requester's instruction; reasoned from
  `git show HEAD:shell/Midas/ReminderRecord.swift` and the publisher code):
  1. Old `parseDate` read a number as `Date(timeIntervalSince1970: n / 1000)`, so the new
     `XCTAssertNil` fails on it; the ISO assertions still fail if ISO parsing breaks.
  2, 3. Old `validationError` returned "reminder.at must be an ISO 8601 date or epoch
     milliseconds", which fails both exact-message assertions; both also fail if the `at` check
     stops running (the write is accepted or no error comes back).
  4. Old `parseNotes` fell back to `body` and returned "Leg day", which fails the new `""` assertion.
  5. Deletions; nothing to prove.
  6. `RemindersWidgetPublisher.swift` line 71 republishes only for `reminder:` and `list:` keys; if
     that filter accepted every key, the `settings:self` write would make `reloads.count` 3 and the
     assertion fails, as it did with `settings:sidebar`.
  7. A removed assertion; the remaining `recordKey` assertions are unchanged.
  9. Comment and title text only.
- Suite result: `npx vitest run test/reminders-logic.test.ts test/legacy-quarantine-shell-pages.test.ts`
  in `backend/`: 2 files, 30 of 30 passing. Full `scripts/test-all.sh` and the Xcode suite are run
  by the requester.

## 2026-10-20: shell/MidasTests/CareRemindersFieldsTests.swift, appointment expansion test renamed (ACCEPTED; name only)

- Asked by: Agent B of the second old-format sweep (worktree `midas-worktrees/legacy-sweep2-b`,
  branch `agent/legacy-sweep2-b`), 2026-10-20.
- Reason: CLAUDE.md "Old record formats are quarantined (founder, 2026-10-20)": do not
  reintroduce old shapes in tests. The name described the retired four-record shape ("the old four
  reminders"); the test checks one record expanded by the engine into four notifications.
- Change: `testAnAppointmentIsOneRecordCarryingItsListsRulesAndTheEngineExpandsTheOldFourReminders`
  renamed to `testAnAppointmentIsOneRecordCarryingItsListsRulesAndTheEngineExpandsItsFourNotifications`.
  Body unchanged (diff: one line, the `func` name).
- Proof it can still fail: not applicable to a rename; nothing the test executes changed. Xcode
  suite not run by the guardian at the requester's instruction; the requester runs all suites.

## 2026-10-20: shell and Reminders page tests for upgrade on read (NEEDS-EVIDENCE; items 1 to 7 of the second sweep request)

- Asked by: Agent B of the second old-format sweep (worktree `midas-worktrees/legacy-sweep2-b`),
  2026-10-20, with the reason "founder 2026-10-21: live converted, migration retired" (the date
  as first given; the decision was then recorded as founder, 2026-10-20, see the ACCEPTED entry above).
- Tests and changes asked for:
  1. ReminderRecordTests `testParsesAllThreeDateForms`: rename, assert a number `at` parses to nil.
  2. MidasStoreScriptTests `testBadReminderIsRejectedWithTheReason`: message to
     `reminder.at must be an ISO 8601 date`.
  3. RecordTypeGateTests `testTheReservedReminderCheckStillRunsOnUpdate`: same message.
  4. NotificationNotesTests: header comment; replace `testARecordNotYetConvertedShowsItsBodyAsNotes`
     by a test that `body` alone gives empty notes.
  5. Delete CareRemindersFieldsTests `testOldAlertAndTimeRecordsAreFoldedIntoTheItemAndRemoved`,
     CareRemindersSnoozeTests `testOldAlertAndTimeSnoozesAreFoldedIntoTheItemsOwnEntries`,
     CareRemindersSimpleSheetTests `testAnOldRecordWithItsOwnIconAlertsAndSeriesStillLoadsAndUsesItsListsAlerts`.
  6. RemindersWidgetTests `testAReminderOrListChangeRepublishes`: `settings:sidebar` to `settings:self`.
  7. backend/test/reminders-logic.test.ts: delete the `itemFromRecord("task:b2", ...)` assertion.
- Why not accepted: the decision is not written in `docs/PRODUCT.md` or the midas-intel design
  doc. It appears only in midas-intel `docs/plans/2026-10-21-legacy-sweep-2-brief.md`, which is an
  untracked (uncommitted) plan file whose name and text carry 2026-10-21, a date after today
  (2026-10-20). The decision
  that is written and current, CLAUDE.md "Old record formats are quarantined (founder,
  2026-10-20)", still says the upgrade-on-read converter may understand old shapes. These tests
  check that converter; they are right against that decision, and the branch's uncommitted
  changes to `shell/Midas/ReminderRecord.swift`, `sidekicks/reminders/index.html` and
  `sidekicks/care-reminders/index.html` are what they would catch.
- Baseline seen: `backend/test/reminders-logic.test.ts` 27 of 27 passing on the branch as is.
  Xcode suite not run, at the requester's instruction.
- Evidence that would change the answer: the founder decision (live and staging converted, dry
  run 0 writes, upgrade on read and migration retired) written and dated in `docs/PRODUCT.md`
  (or the midas-intel design doc), and the CLAUDE.md quarantine section no longer naming the
  converter as allowed. With that, items 1 to 7 as described are acceptable as asked: 1 and 4b
  fail on the old code (number read as epoch ms; `body` returned as notes), 2 and 3 are exact
  message checks, 5 tests removed code, 6 swaps a retired key for a current one with the same
  assertion, 7 removes a read of a retired prefix.
## 2026-10-20: backend/test/legacy-sweep-2-docs.test.ts, decision date (ACCEPTED; dates only, no assertion changed)

- Asked by: lead session for worktree `midas-worktrees/legacy-sweep2-c` (branch
  `agent/legacy-sweep2-c`), 2026-10-20. The file is new and not yet committed in this branch.
- Reason: the test is wrong about the date. It said the conversion and retirement were decided
  2026-10-21; `docs/PRODUCT.md` (commit ede0f55) dates it "Old formats retired (founder,
  2026-10-20)".
- Change: every `2026-10-21` to `2026-10-20`: header comment line 1, `createdAt` in `promptFor`,
  and the `describe` title. Diff checked: those three lines only.
- Proof it can still fail: with `runner/agents/reminders.md` put back to its HEAD text, the file
  ran 2 failed of 5 ("finds no upgrade-on-read ... text": `expected [ Array(1) ] to deeply equal
  []`; "tells both repair agents ...": `expected '# You repair ...' to contain 'Write only the
  types above.'`). The prompt was then restored byte for byte (cmp checked).

## 2026-10-20: backend/test/legacy-sweep-docs.test.ts, "gives both repair agents only today's shapes" (ACCEPTED; resubmission of the NEEDS-EVIDENCE entry below)

- Asked by: lead session for worktree `midas-worktrees/legacy-sweep2-c` (branch
  `agent/legacy-sweep2-c`), 2026-10-20.
- Reason: the evidence asked for below is now written and dated in `docs/PRODUCT.md` (commit
  ede0f55, merged into this branch): "**Old formats retired (founder, 2026-10-20):** live and
  staging are converted to the unified data format (live dry run after the conversion: 0
  writes). The upgrade-on-read code, the shell's epoch-millisecond and `body` fallbacks and the
  one-time migration tools are retired: no code reads or writes an old record shape." The repair
  prompts `runner/agents/reminders.md` and `runner/agents/care-reminders.md` therefore no longer
  tell the agent to keep the page's upgrade code; they say "Write only the types above."
- Change: line 79 `expect(prompt).toContain("stays as it is; write only the");` replaced by
  `expect(prompt).not.toContain("stays as it is");` and
  `expect(prompt).toContain("Write only the types above.");`.
- Proof it can still fail: (1) with both prompts put back to their HEAD text, the test failed:
  `expected '# You repair one user's copy of the …' not to contain 'stays as it is'`. (2) with
  "Write only the types above." changed to "Keep the types above." in `runner/agents/reminders.md`,
  it failed: `expected '# You repair ...' to contain 'Write only the types above.'`. Both prompts
  restored byte for byte after each run (cmp checked).
- Note: `sidekicks/reminders/index.html` and `sidekicks/care-reminders/index.html` in this
  worktree still hold code marked "upgrade on read"; the decision says that code is retired.
- Suite after the change: test guard 34 OK, backend 656 of 656, shell 570 of 570, midas-intel 31
  OK. (Before the change: backend 655 of 656, this test; shell reported TEST FAILED with no
  failing test case and passed on the next run.)

## 2026-10-20: backend/test/legacy-sweep-docs.test.ts, "gives both repair agents only today's shapes" (NEEDS-EVIDENCE; no change made)

- Asked by: lead session for worktree `midas-worktrees/legacy-sweep2-c` (branch
  `agent/legacy-sweep2-c`), 2026-10-20, second old-format sweep (agent C).
- Change asked for: replace line 79 `expect(prompt).toContain("stays as it is; write only the");`
  with `expect(prompt).not.toContain("stays as it is");` and
  `expect(prompt).toContain("Write only the types above.");`.
- Reason given: "founder 2026-10-21: live converted, migration retired", citing midas-intel
  `docs/plans/2026-10-21-legacy-sweep-2-brief.md` item 1.
- Why not accepted: the decision is not written in `docs/PRODUCT.md` or the midas-intel design
  doc (`docs/designs/jess-personal-assistant-shell.md`); neither mentions retiring upgrade-on-read
  or the migration. The only source is a plan brief that is untracked in midas-intel and dated
  2026-10-21, a day after today (2026-10-20). In this worktree the upgrade-on-read code the old
  sentence describes is still present in `sidekicks/reminders/index.html` and
  `sidekicks/care-reminders/index.html`, so the edited prompts do not yet describe the code.
- Evidence that would settle it: the founder's decision (live and staging converted, upgrade-on-read
  and migration retired), dated, written into `docs/PRODUCT.md` or the midas-intel design doc; or,
  failing that, the founder's own message confirming it. With that, the requested replacement is
  acceptable as written (it still fails on the prompts at HEAD).
- Suite state at the time: backend 655 of 656 (this test fails against the uncommitted prompt
  edits), shell 570 of 570, guard and midas-intel passing.

## 2026-10-20: backend/test/record-upgrades.test.ts and backend/test/record-upgrades-snoozes.test.ts, file header (ACCEPTED; comment only, marks the files where old shapes are allowed)

- Asked by: lead session for worktree `midas-worktrees/legacy-sweep-a` (branch
  `agent/legacy-sweep-a`), 2026-10-20, old-format sweep.
- Reason: CLAUDE.md "Old record formats are quarantined (founder, 2026-10-20)" (commit 995b92f):
  "The only code that may still understand old shapes is the upgrade-on-read converter and the
  migration script, and each says so in its header." These two files test that converter
  (`backend/scripts/record-upgrades.mjs`) and the migration (`backend/scripts/migrate-records.mjs`,
  which calls `upgradeSidekickRecords`), so they are the allowed place for old-shape fixtures.
- Change: a five-line `//` comment added above the first import of each file, saying old shapes
  are allowed only there, naming both scripts and the quarantine file, and saying not to copy the
  fixtures elsewhere. No code, fixture or assertion changed (diff checked: only added comment
  lines and one blank line per file).
- Proof it can still fail: not applicable to a comment; nothing the tests execute changed. Both
  files run 14 of 14 passing after the change, the same as before.

## 2026-10-20: backend/test/record-types-manifests.test.ts, "a manifest with a bad types block fails validateManifest" (ACCEPTED; neutral prefix instead of the retired task: prefix)

- Asked by: lead session for worktree `midas-worktrees/legacy-sweep-a`, 2026-10-20, old-format
  sweep.
- Reason: CLAUDE.md "Old record formats are quarantined (founder, 2026-10-20)": "Do not
  reintroduce old shapes (`task:` keys, `body`, care `~rule` / `@HHMM` records, records without
  `$type`) in code, tests or docs." The fixture declared `"task:"` / `reminders.task` as a type,
  which is not a refusal test of the old shape. The check (a non-object schema fails
  `validateManifest` with that message) is unchanged. The refusal tests in the same file that
  assert `task:` keys are refused were left as they are.
- Change: prefix `"task:"` to `"note:"`, `$type` `"reminders.task"` to `"reminders.note"`, expected
  message to `'types["note:"].schema must be a JSON Schema with "type": "object"'`.
- Proof it can still fail: in `backend/scripts/bundle-tools.mjs` line 116 the non-object schema
  condition was temporarily replaced with `if (false) {`; this test failed ("expected [] to
  deeply equal [ Array(1) ]"), as did the types block gate test. Restored from a copy, sha1
  35b63730 before and after.

## 2026-10-20: backend/test/sync.test.ts, "carries a reminder record exactly as the Sidekick wrote it, extra fields included" (ACCEPTED; fixture in the current record shape)

- Asked by: lead session for worktree `midas-worktrees/legacy-sweep-a`, 2026-10-20, old-format
  sweep.
- Reason: CLAUDE.md "Old record formats are quarantined (founder, 2026-10-20)" (quoted in the
  entry above). The fixture had no `$type`, a `body` field and `snoozedUntil` in epoch
  milliseconds; this test checks sync carries a value exactly, not old shapes.
- Change: fixture only: added `$type: "reminders.item"`, `body: ""` to `notes: ""`,
  `snoozedUntil: 1760000000000` to `"2025-10-09T08:53:20.000Z"` (the same instant). Every other
  field, including `nested: { a: [null, true, 1.5] }` and the extra fields, and both assertions are
  unchanged.
- Proof it can still fail: in `backend/src/sync.ts` `opFromRow` was temporarily made to turn a
  string `snoozedUntil` into epoch milliseconds after `JSON.parse`; this test failed ("expected {
  '$type': 'reminders.item', …(10) } to deeply equal { … }"), as did the reinstall rebuild test.
  Restored from a copy, sha1 87710ac3 before and after.
## 2026-10-20: notification engine reads `notes`, not `body` (sweep B, second batch): five requests, all ACCEPTED

- Asked by: lead session for worktree `midas-worktrees/legacy-sweep-b` (branch
  `agent/legacy-sweep-b`), 2026-10-20. App change (uncommitted in the worktree): `ReminderRecord`
  property `body` renamed `notes`, read from `notes` with upgrade-on-read fallback to `body`; check
  message `reminder.notes must be a string`; planner bookings and expansion carry `record.notes`.
  New tests (not logged): `shell/MidasTests/NotificationNotesTests.swift`.
- Reason, items 1-4: "founder 2026-10-20: notifications read notes". Written sources: CLAUDE.md
  "Old record formats are quarantined (founder, 2026-10-20)": "Do not reintroduce old shapes
  (`task:` keys, `body`, ...) in code, tests or docs"; midas-intel
  `docs/plans/2026-10-15-unified-data-v2.md` section 4 (built and merged `18e777c`, founder answers
  2026-10-15): "The notification engine's documented input: `title`, `notes`, `at`, ..."; brief
  `docs/plans/2026-10-20-legacy-sweep-brief.md`: current format "`notes` (no `body`)". Note for the
  lead: `docs/PRODUCT.md` and midas `docs/NOTIFICATIONS.md` 4.2 still say `body` is the notification
  text; they need the same change.
- Reason, item 5: "founder 2026-10-20, old-format sweep" (CLAUDE.md quote above; the comment
  described the old stored care alert records).
- Baseline before any change: test guard 34 OK; backend 641 passed (54 files), typecheck OK;
  midas-intel 31 OK; shell did not compile (`ReminderPlannerTests.swift:16`,
  `ReminderScheduleTests.swift:20`: extra argument 'body').

1. `shell/MidasTests/ReminderRecordTests.swift`: `testParsesAFullRecord` fixture `"body":"Leg day"`
   -> `"notes":"Leg day"`, assertion `record.body` -> `record.notes`; `testMinimalRecordGetsDefaults`
   `record.body` -> `record.notes` (still `""`); `testRejectsBadRecordsWithAReason` `"body":5` ->
   `"notes":5` (`body` is no longer checked; the same check now runs on the field that is read).
   Same assertions, same values.
2. `shell/MidasTests/ReminderPlannerTests.swift` line 16: init label `body: ""` -> `notes: ""`.
   Compile fix for the rename, same value.
3. `shell/MidasTests/ReminderScheduleTests.swift` line 20: same as item 2.
4. `shell/MidasTests/RecordSyncTests.swift` fixture `dentistReminder`: `"body"` key -> `"notes"`,
   same value. The fixture is an opaque value for sync round trips; no assertion reads the key.
5. `shell/MidasTests/ReminderExpansionTests.swift` header comment: the line saying the expansion
   builds "the same reminders the care-reminders page used to write as records of their own"
   replaced by "builds them in memory under the engine ids `<id>~<rule>` and `<id>@HHMM`; nothing is
   stored under those ids". Comment only.

- Proof (run 2026-10-20, iOS 27 "iPhone 17" simulator 40A6D245, own derived data): in
  `shell/Midas/ReminderRecord.swift` changed `value["notes"]` to `value["notesBROKEN"]` in both
  `parseNotes` and `validationError` (notes not read, notes not checked). Shell suite: 570 tests,
  8 failed: `ReminderRecordTests.testParsesAFullRecord` (notes read as "" instead of "Leg day"),
  `ReminderRecordTests.testRejectsBadRecordsWithAReason` (`"notes":5` accepted and parsed), and 6 in
  `NotificationNotesTests`. Restored the file from a byte copy taken before the break; no
  `notesBROKEN` left. Items 2-4 change no assertion (label or key rename of an unchanged value);
  item 5 is a comment.
- Full suite after the changes (worktree, by hand): test guard 34 OK; backend 641 passed
  (54 files), typecheck OK; midas-intel 31 OK; shell 570 tests, 0 failures (TEST SUCCEEDED).

## 2026-10-20: old-format sweep, agent B (shell and Sidekick pages): eight requests, all ACCEPTED

- Asked by: lead session for worktree `midas-worktrees/legacy-sweep-b` (branch
  `agent/legacy-sweep-b`), 2026-10-20, brief midas-intel
  `docs/plans/2026-10-20-legacy-sweep-brief.md` ("Shared" and "Agent B").
- Reason (applies to every item): CLAUDE.md "Old record formats are quarantined (founder,
  2026-10-20)" (commit 995b92f): "Do not reintroduce old shapes (`task:` keys, `body`, care
  `~rule` / `@HHMM` records, records without `$type`) in code, tests or docs. The only code that may
  still understand old shapes is the upgrade-on-read converter and the migration script, and each
  says so in its header." The brief: "Allowed to keep old shapes: only the upgrade-on-read
  converter, the migration script and their tests". No assertion changed in any item.
- Full suite after the changes (worktree, run by hand because `scripts/test-all.sh` resolves to
  the main checkout's simulator name): test guard 34 OK; backend 641 passed (54 files), typecheck
  OK; shell 563 tests, 0 failures (iOS 27 "iPhone 18 Pro" simulator, own derived data);
  midas-intel 31 OK. Baseline before any change: the same counts, all green.
- Proof limit: for items 1, 2, 3 and 7 the planned mutation runs (break the app code in a scratch
  copy, run, restore) were denied by the session's permission system, both in the worktree and in
  a scratchpad copy, so no Swift failure was observed. The item 8 mutation ran (on a scratch
  copy). For each Swift item below, the mutation that should make it fail is written down. Nobody
  has run those mutations yet.

### 1. shell/MidasTests/SidekickWidgetFillerTests.swift, fixtures `careRecords`, `todaySource`, `testUpcomingIsEachReminderAtItsNextTimeInOrder` `where`

- Change: `list:meds` gains `"$type": "care.list"`; `reminder:vitd`, `reminder:iron`,
  `reminder:fish` use `"$type": "care.item"` in place of `"kind": "care-item"`; `reminder:fish`
  gains `"list": "meds"`; the stored early-alert record `reminder:vitd~early` (`kind: care-alert`)
  replaced by `reminder:walk` (`$type: care.item`, one-time at Oct 13 8:45 AM, `list: "move"`);
  both `where` clauses become `{ "$type": "care.item", "list": "meds" }` (as the page's
  MEDS_TODAY_SOURCE does). Doc comment updated. Counts held: no-`where` today has 3 open (vitd,
  walk, iron); with `where` 2 open / 1 done / 3 total; upcoming 2 (iron, vitd tomorrow);
  `today.items` still Vitamin D, Iron.
- Can still fail: `SidekickWidgetFiller.matches` checks every `where` field by equality. If the
  `list` condition is ignored, `reminder:walk` joins Today (open 3, count 4) and the
  today/upcoming/fill tests fail. If `where` is ignored entirely, they fail the same way. Not run
  (see proof limit).

### 2. shell/MidasTests/RemindersWidgetTests.swift, `testUndatedIsNeverInToday`

- Change: comment `// An undated reminder (no \`at\`) is never in Today.`; the `task:milk` record
  removed; asserts `todayIds([undated]) == []`. The `task:` record stood for the old place of
  undated items; since 2026-10-15 an undated item is `reminder:` without `at`, which `undated`
  already is, so the test still checks what it exists for.
- Can still fail: if `ReminderRecord.parse` gave an undated record a date today (for example a
  fallback `at` on Oct 11), the planner would put `haircut` in Today and the assertion fails. Not
  run (see proof limit).

### 3. shell/MidasTests/AppleRemindersImportTests.swift, `testOrdinaryRecordsDoNotReachTheRequestObserver`

- Change: the ordinary record key `task:r1` becomes `list:r1`. The assertion is unchanged.
- Can still fail: `SidekickStoreChannel.write` calls `requestObserver` only when the key has the
  `request:` prefix, and the channel has no reserved validator for `list:`, so the write succeeds
  and only the prefix check stops it. If that check were `true`, `handleRequestWritten` would see
  `status: pending` with the import kind and set `shownRequest`, so `XCTAssertNil` fails. Not run
  (see proof limit).

### 4. shell/MidasTests/CareRemindersHourlyRepeatTests.swift, class doc comment

- Change: the clause "before which each time was a `@HHMM` record of its own" removed. Comment
  only, nothing executed changed, so the test fails exactly as before.

### 5. shell/MidasTests/SnoozeIndependenceTests.swift, file header comment

- Change: "Before the rework each alert and time was a record with its own `snoozedUntil`; now"
  removed (sentence now starts "The item carries them in `snoozes`"). Comment only.

### 6. Upgrade-on-read tests marked (comment only)

- `CareRemindersFieldsTests.testOldAlertAndTimeRecordsAreFoldedIntoTheItemAndRemoved`,
  `CareRemindersSnoozeTests.testOldAlertAndTimeSnoozesAreFoldedIntoTheItemsOwnEntries`,
  `CareRemindersSimpleSheetTests.testAnOldRecordWithItsOwnIconAlertsAndSeriesStillLoadsAndUsesItsListsAlerts`:
  line above each: `// Upgrade on read: the only test here allowed old shapes
  (docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md).` In the first, the comment "Written by the
  page before 2026-10-15: ..." became "Records not yet converted: an item, its early alert (tapped
  Done) and an hourly time of another item (tapped Done)." In the third, "An item written before
  Change 1: ..." became "A record not yet converted (own icon, own alerts, a series id)".
- `ReminderRecordTests.testParsesAllThreeDateForms`: line above: `// Upgrade on read: epoch
  milliseconds are read only for records not yet converted
  (docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md).`
- Comment only. No fixture or assertion changed.

### 7. shell/MidasTests/ReminderRecordTests.swift, epoch-ms `at` in non-upgrade tests

- Change: in `testMinimalRecordGetsDefaults`, `testRepeatIntervalDefaultsToOne`,
  `testRejectsBadRecordsWithAReason` (12 fixtures) and
  `testKeysOutsideTheReminderPrefixAreNotReminders`, `"at":1791475200000` became
  `"at":"2026-10-08T16:00:00.000Z"` (the same instant). `testParsesAllThreeDateForms` was not
  changed. Every assertion is the same.
- Can still fail: the ISO `at` is valid (the two default tests parse it, so neither can pass by
  rejecting it). Each bad record is still bad only for its own field. If a field check is removed
  (for example `done` type), `XCTAssertNotNil(validationError)` fails for that fixture. If the
  `reminder:` prefix check in `parse` is removed, the `note:1` test fails. Not run (see proof
  limit).
- Note for the requester (not changed, not asked): `testRejectsBadRecordsWithAReason` still has
  `"body":5`, and `testMinimalRecordGetsDefaults` asserts `record.body == ""`. `body` is an old
  field. Whether those belong to upgrade on read is for the sweep to decide.

### 8. backend/test/reminders-logic.test.ts, "round-trips an item through its record" and "keys every item as reminder:, dated or not"

- Change: `itemFromRecord("task:t1", taskValue)` became `itemFromRecord("reminder:t1", taskValue)`
  (an undated item is `reminder:` since 2026-10-15). Above the `task:b2` assertion (the page's
  upgrade on read of `task:` keys, `sidekicks/reminders/index.html` line 2204) one comment line
  was added: `// Upgrade on read: a record not yet converted
  (docs/legacy/LEGACY-RECORD-FORMATS.DO-NOT-READ.md).` No conflicting request from agent A for
  this file (checked agent A's log and diff on `agent/legacy-sweep-a`).
- Proof it can still fail (run on a scratchpad copy of the page and the test; the worktree page
  is unchanged, sha1 6f92e4dd): in `itemFromRecord`, `instantMs(record.at)` became
  `instantMs(record.at || '2026-10-01T00:00:00.000Z')`. The test failed with "expected
  '2026-09-30' to be null". With the old `task:t1` key the same mutation passed (27 of 27), so the
  new fixture covers the `reminder:` path the old one skipped.
## 2026-10-20: backend/test/runner-repair-data.test.ts, "no longer describes task: or body as current shapes, and says to declare new fields in manifest.json" (ACCEPTED; the prompt no longer names task: at all)

- Asked by: Agent C (legacy sweep), worktree `midas-worktrees/legacy-sweep-c` (branch
  `agent/legacy-sweep-c`), retry asked by the lead session 2026-10-20.
- Reason (founder decision, dated): `CLAUDE.md`, "Old record formats are quarantined (founder,
  2026-10-20)": "Do not reintroduce old shapes (`task:` keys, `body`, ...) in code, tests or docs."
  Brief: midas-intel `docs/plans/2026-10-20-legacy-sweep-brief.md` ("Old format markers to hunt:
  `task:` keys, `body` on reminders, ..."). `runner/agents/reminders.md` (commit 5c9df74) replaced
  the "Retired, never write them: `task:` ..." bullet with "Every item, dated or not, is a
  `reminder:` record (undated: no `at`), and its text is `notes`. ...". The old assertion required
  the prompt to name `task:`, which the decision forbids.
- Change: `expect(prompt).toContain("Retired, never write them: \`task:\`")` replaced with
  `expect(prompt).not.toContain("task:")` and
  `expect(prompt).toContain("Every item, dated or not, is a \`reminder:\` record")`. Stricter than
  before: the whole reminders prompt may not contain `task:`, and it must state the current shape.
  No other assertion changed.
- Proof it can still fail: the old "Retired, never write them: `task:` ..." bullet temporarily put
  back into `runner/agents/reminders.md`; the test failed ("expected '# You repair one user's copy
  of the …' not to contain 'task:'" class of failure, test marked ×). Bullet restored with the Edit
  tool; sha1 d0f9bfa3 before and after.

## 2026-10-19: backend/test/user-copy-plan.test.ts, "upgrades a repaired copy with an older helper and no types into a folder for a --user --dir deploy" (ACCEPTED; a copy without types is never mechanical)

- Asked by: lead session for the builder in worktree `midas-worktrees/repair-data` (branch
  `agent/repair-data`), 2026-10-19, citing reviewer finding 1 approved by the founder that day
  ("fix these findings from two reviewers (founder go, 2026-10-19)"; the finding text is in the
  lead's message only, not in a repo doc).
- Reason (the test enshrined behaviour against a dated founder rule): the old test required that a
  repaired copy with no `types` gets the base's types copied in and a `--user --dir` deploy command
  printed, with no add-only check and no check of the user's records. midas-intel
  `docs/plans/2026-10-15-unified-data-v2.md` section 6: "The runner checks, before publishing, that
  every record the user has still passes the new schema; if not, it does not publish", and
  "Backward compatibility (founder, 2026-10-15): ... add only: optional fields, new types; no
  rename, no type change, no new required field". Ordered built in
  `docs/briefs/repair-data-2026-10-19.md` (items 2, 3 and 5). Giving a copy the base's whole
  `types` block is a schema change that was printed for publishing without either check.
- Change: test renamed "never upgrades a repaired copy without types: it needs the schema pass
  first, and no deploy command is printed"; same inputs (old helper, no types). Asserts state
  `repaired`; gaps exactly `["older store helper", "manifest has no types"]`; `upgraded` null;
  `actions[0]` matches `/^needs the schema pass first/`; `actions` is exactly that plus the
  `--from-base` way-back line (records not passed); no action contains `--dir`. The header comment
  now says only an older store helper is mechanical, and only after the schema and records checks
  pass, and that a copy without types needs the schema pass first. The positive and negative
  helper-only cases go in a new file the builder writes. No other test in the file changed.
- Proof it can still fail: `backend/scripts/user-copy-plan.mjs` temporarily replaced with its HEAD
  version (the old mechanical upgrade); the test failed ("expected { ...(3) } to be null").
  Restored from a copy, sha1 4067bc8d before and after.

## 2026-10-19: backend/test/helpers/runner-fixture.ts, `makeScratch` (ACCEPTED; scratch checkout holds the validator, upgrades and store helper)

- Asked by: lead session for the builder in worktree `midas-worktrees/repair-data` (branch
  `agent/repair-data`), 2026-10-19, citing reviewer finding 7 approved by the founder that day
  ("use one root for all of them": validator, upgrades, helper swap and deploy all from
  `settings.checkoutRoot`).
- Reason (the fixture was wrong): the scratch checkout stands in for the runner's checkout, and a
  real checkout holds `shell/sdk/record-schema.js`, `shell/sdk/shell-types.js`,
  `shell/sdk/midas-store.js` and `backend/scripts/record-upgrades.mjs`. The runner on this branch
  loads them from `checkoutRoot` (`runner/lib/user-records.mjs` `VALIDATOR_PATH`/`UPGRADES_PATH`,
  `runner/lib/run-job.mjs` `checkoutHelperPath`), so 34 runner tests ended "runner error: the
  checkout ... has no shell/sdk/record-schema.js" / "has no shell/sdk/midas-store.js" before
  reaching what they test. No assertion changes.
- Change: `makeScratch` also copies those four files from `REPO_ROOT` into the scratch checkout
  (`shell/sdk/` created); the comment names the record validator, the record upgrades and the
  store helper the runner loads from it. Nothing else in the fixture changed.
- Proof it can still fail: in `runner/lib/user-records.mjs` `VALIDATOR_PATH` set to
  `shell/sdk/record-schema-missing.js`; the 7 runner and plan files gave 35 failed / 32 passed
  ("the checkout .../checkout has no shell/sdk/record-schema-missing.js"; statuses `runner error`
  / `failed` where `deployed_live`, `check failed` and others were expected). Restored from a
  copy, sha1 28a52aca before and after.
- Full suite before both changes (`scripts/test-all.sh`, exit 1): test guard 34 OK; backend 35
  failed / 556 passed (48 files: the 34 runner tests above and the old user-copy-plan test); shell
  563 tests 0 failures; midas-intel OK.
- Full suite after both changes (`scripts/test-all.sh`, exit 0): test guard 34 OK; backend
  618/618 (49 files; the builder added a file during this session); shell 563 tests 0 failures;
  midas-intel 31 OK.

## 2026-10-19: backend/test/runner-loop-config-prompt.test.ts, "has a Reminders agent (also for care-reminders) ..." (ACCEPTED; care-reminders gets its own repair prompt)

- Asked by: lead session for the builder in worktree `midas-worktrees/repair-data` (branch
  `agent/repair-data`), 2026-10-19.
- Reason (founder decision): midas-intel `docs/plans/2026-10-15-unified-data-v2.md` section 6:
  "Repair agent prompt updated: no `task:`/`body`, files supported, the runner publishes live,
  care-reminders gets its own prompt." Ordered built by the founder on 2026-10-19 in
  `docs/briefs/repair-data-2026-10-19.md` (commit 5e7faf8), item 1: "New
  `runner/agents/care-reminders.md` for care-reminders, and the runner picks the prompt by Sidekick
  id." Note: the lead cited `docs/CONCERNS.md` section 8, which is not in `docs/CONCERNS.md` on this
  branch or on `main`; the plan file is uncommitted in midas-intel and its status line still says
  "proposed". The committed, dated brief is the record relied on.
- Change: title now "has a Reminders agent and a care-reminders agent, and none for other
  Sidekicks"; `templateNameForSidekick("care-reminders")` expected `"care-reminders"` (was
  `"reminders"`). The `reminders`, `split` (null) and the `split` throw expectations are unchanged.
- Proof it can still fail: in `runner/lib/prompt.mjs` `TEMPLATE_BY_SIDEKICK` set
  `"care-reminders": "reminders"`; the test failed (Expected "care-reminders", Received
  "reminders"; 1 failed / 10 passed in the file). Restored from a copy, sha1 153b7889 before and after.
- Full suite after (`scripts/test-all.sh`, exit 0): test guard 34 OK, backend 573/573 (47 files),
  shell 525 tests 0 failures, midas-intel 31 OK.

## 2026-10-19: backend/test/helpers/runner-fixture.ts, `startFakeBackend` (ACCEPTED; fake backend serves the runner-only records route)

- Asked by: lead session for the builder in worktree `midas-worktrees/repair-data` (branch
  `agent/repair-data`), 2026-10-19.
- Reason (the fixture was wrong): the fake stands in for the Worker, and the Worker on this branch
  now serves `GET /repairs/:id/records` to the runner token only (`backend/src/repairs.ts`,
  `requireRunner, handleListReportRecords`, "founder, 2026-10-19"). The runner checks the
  reporter's records before publishing (unified data plan section 6, 2026-10-15: "The runner
  checks, before publishing, that every record the user has still passes the new schema; if not,
  it does not publish"; ordered built in `docs/briefs/repair-data-2026-10-19.md` item 3) and fails
  closed with "records unreadable". The fake answered 404, so 13 runner tests (runner-copy-tests 4,
  runner-deploy 5, runner-feature-kind 1, runner-fetch-and-stage 2, runner-job 1) ended `failed`
  before reaching what they test. No assertion changes.
- Change: optional third parameter `records: Array<{ key: string; value: unknown }> = []`;
  `GET /repairs/<id>/records` behind the existing `Runner` token check answers 200
  `{ "records": <records> }`; `recordRequests` counter on `FakeBackend` (getter, like `claims`);
  header comment names the records route. Existing callers unchanged (two arguments).
- Proof it can still fail: in `runner/lib/backend.mjs` `listRecords` the path was changed to
  `/record`; `npx vitest run` gave 17 failed / 556 passed: the same 13 runner tests ("records
  unreadable", "records failed: 404") plus 4 in the builder's new
  `draftchecks/runner-repair-data-job.test.ts`. Restored from a copy, sha1 07432fae before and after.
- Full suite after: as in the entry above (exit 0; backend 573/573). Before both changes the
  backend had 14 failed / 519 passed (43 files); the builder added files during this session.

## 2026-10-19: backend/test/helpers/runner-fixture.ts (ACCEPTED; fake backend now expects the Worker's `Runner` auth scheme)

- Asked by: lead session, `main`, 2026-10-19.
- Reason (the test was wrong): the fake backend in `startFakeBackend` accepted only
  `Authorization: Bearer <token>`, but the real Worker accepts the runner only as
  `Runner <token>` (`backend/src/repairs.ts` `RUNNER_PREFIX = "Runner "`, `isRunnerToken`; the
  Worker's own tests use `Runner ` in `test/repairs.test.ts` and `test/helpers/repair-fixtures.ts:74`).
  Because the fake matched the runner client's wrong header, the runner tests passed while the first
  real repair claim on staging was refused with 401 (bug, 2026-10-19). The lead fixed the app code
  (`runner/lib/backend.mjs` now sends `Runner ${token}`) and added
  `backend/test/runner-backend-auth.test.ts`, which drives the real client against the real Worker app.
  After the app fix, and before this change, 31 runner tests failed with "claim failed: 401"
  (runner-job 10, runner-copy-tests 9, runner-deploy 6, runner-feature-kind 3,
  runner-fetch-and-stage 3).
- Change: line 37, `` `Bearer ${RUNNER_TOKEN}` `` changed to `` `Runner ${RUNNER_TOKEN}` ``. Nothing else.
  The check still rejects any other header with 401.
- Proof it can still fail: with the fixture on `Runner`, `runner/lib/backend.mjs` was set back to
  `` Authorization: `Bearer ${token}` ``. `npx vitest run` then gave 33 failed / 496 passed: the same
  31 runner tests with "claim failed: 401", plus 2 in runner-backend-auth.test.ts. The lead's file was
  restored from a copy (same sha1 e6b97257 before and after); `git diff runner/lib/backend.mjs` shows
  only the lead's `Runner` change and its comment.
- Full suite after (`scripts/test-all.sh`, exit 0): test guard 42 OK, backend 529/529 (42 files),
  shell 525 tests 0 failures, midas-intel 31 OK.

## 2026-10-15: shell/MidasTests/CircleDetectorTests.swift, RepairLayerLayoutTests.swift (ACCEPTED; repair gesture is now a three-finger swipe down)

- Asked by: repair owner agent, worktree `midas-worktrees/repair` (branch `agent/repair`),
  2026-10-15. First answered NEEDS-EVIDENCE the same day: the decision was then only relayed, and
  `docs/PRODUCT.md` still said "a circle drawn with one finger". Re-asked after the lead committed
  the decision to `main` (5472d9f) and the worktree was rebased onto it.
- Reason: `docs/PRODUCT.md` repair section (commit 5472d9f, "PRODUCT: repair opens with a
  three-finger swipe down (founder, 2026-10-15)"): "Gesture (changed again 2026-10-15, founder,
  after the phone test): three fingers swipe down anywhere on the Sidekick, replacing the
  one-finger circle of earlier the same day". The code under test (`CircleDetector.swift`,
  `CircleGestureRecognizer.swift`) was removed in the same worktree. Before this entry the shell
  suite did not compile: `CircleDetectorTests.swift:209:26: error: cannot find
  'CircleGestureRecognizer' in scope`.
- Change: `shell/MidasTests/CircleDetectorTests.swift` deleted with `git rm` (22 test methods).
  `shell/MidasTests/RepairLayerLayoutTests.swift` line 211: doc comment "as the app does before
  the circle" changed to "before the swipe"; no code or assertion changed.
- What replaces it: new `shell/MidasTests/ThreeFingerSwipeTests.swift` (23 tests, written by the
  repair owner). It carries over the recognizer-passive check (`cancelsTouchesInView`,
  `delaysTouchesBegan`, `delaysTouchesEnded` false), the web-view wiring check (also asserts
  `CircleGestureRecognizer` is gone), the founder's scribble sample not firing, and
  point-from-array malformed input.
- Proof it can still fail: not applicable. The test file is deleted, not rewritten, and the
  layout-test edit is a comment only.
- Full suite after the change (`scripts/test-all.sh`, exit 0): test guard 34 OK; backend 354/354;
  shell 525 tests, 0 failures; midas-intel 31 OK. Shell also run on the "Midas Repair" simulator
  (E95587D7-48FE-4871-9581-7E6C893F097F): 525 tests, 0 failures, TEST SUCCEEDED.

## 2026-10-15: shell/MidasTests/ScribbleDetectorTests.swift (ACCEPTED; deleted, repair gesture is now a circle)

- Asked by: repair owner agent, worktree `midas-worktrees/repair` (branch `agent/repair`),
  2026-10-15, with the lead's confirmation in that session.
- Reason: founder decision 2 of 2026-10-15, `docs/briefs/repair-owner-2026-10-15.md`: "Gesture: a
  circle, not a scribble. One finger draws a circle anywhere on the Sidekick; that opens repair.
  Replaces the zigzag scribble (`ScribbleDetector`, `ScribbleGestureRecognizer`)." Also
  `docs/PRODUCT.md` section 2 (commit e4502dc): "Gesture (changed 2026-10-15, founder): a circle
  drawn with one finger anywhere on the screen, replacing the 2026-10-13 scribble of two or three
  zigzags." The code under test (`ScribbleDetector.swift`, `ScribbleGestureRecognizer.swift`) was
  removed in the same worktree. Before this entry the shell suite did not compile:
  `ScribbleDetectorTests.swift:154:24: error: cannot find 'ScribblePoint' in scope`.
- Change: whole file deleted with `git rm` (13 test methods: the founder sample recognised and
  firing mid-stroke, fires once, vertical scroll / pull down-up / horizontal swipe / tap / single V
  / tiny zigzag / slow zigzag rejected, fast thumb zigzag recognised, recognizer passive flags,
  point-from-array). `docs/briefs/repair-gesture-sample-2026-10-13.json` stays as history.
- What replaces it: new `shell/MidasTests/CircleDetectorTests.swift`, being written by the repair
  owner (scroll, swipe, tap, zigzag and slow strokes rejected; the founder's scribble sample does
  not fire the circle; recognizer passive, `cancelsTouchesInView` and `delaysTouchesBegan` false;
  point-from-array). Gap: at the time of this entry that file does not exist, so nothing checks that
  the repair gesture recognizer is passive or that scrolls and taps do not open repair.
- Proof it can still fail: not applicable, the test is deleted, not rewritten.
- Full suite after the deletion (`scripts/test-all.sh`, exit 0): test guard OK; backend 303/303;
  shell 360 tests, 0 failures; midas-intel 31 OK.
## 2026-10-15: shell/MidasTests/RecordWriterTests.swift `testTheDonePatchIsTheSameForEveryWriter` and backend/test/record-upgrades-snoozes.test.ts (new, uncommitted) (both ACCEPTED)

- Asked by: data-rework agent (worktree agent/data-rework), 2026-10-15.
- Change 1 (RecordWriterTests.swift, lines 113-114): the expected patch for
  `donePatch(for: daily, part: .slot(time: "12:00"), ...)` lost `"snoozedUntil": .null` and is now
  exactly `{ slotsDone: { "12:00": now } }`, with the message "Done on an hourly time leaves the
  item's own snooze alone (founder, 2026-10-15)". Still an exact equality on the whole patch.
- Reason 1: founder decision 2026-10-15, `docs/briefs/data-rework-product-changes.md` lines 79-84:
  "Snooze on an early alert or hourly time snoozes that notification only: its own entry in the
  item's `snoozes` (`"~rule"` / `"@HHMM"` to date ...); the item keeps `snoozedUntil` for its own.
  Done on the event removes the alerts' entries, Done on an hourly time its own." Also midas-intel
  `docs/plans/2026-10-15-unified-data-v2.md` line 189: "Each alert / hourly time keeps its own
  snooze (as before the rework), so one never replaces another." Before the rework a time record's
  Done never touched the item record; the old assertion encoded the builder's first choice (one
  snooze per item), which this decision replaced. The new semantics (own entry removed, item's
  `snoozedUntil` untouched) are covered by the new SnoozeIndependenceTests.swift.
- Change 2 (record-upgrades-snoozes.test.ts line 32): fixture `reminder:pills@1200`
  `snoozedUntil: 1760556600000` -> `1792092600000`. Bug in a never-run new test: 1760556600000 is
  2025-10-15T19:30:00Z, the assertion on line 47 expects 2026-10-15T19:30:00.000Z
  (= 1792092600000, checked with `node -e 'Date.parse(...)'`). The assertion is unchanged.
- Proof 2: with the slot branch of `backend/scripts/record-upgrades.mjs` shifted by one hour
  (`instantText(slot.snoozedUntil + 3600000)`), the test failed: `expected { '@1200':
  '2026-10-15T20:30:00.000Z' } to deeply equal { '@1200': '2026-10-15T19:30:00.000Z' }`; restored
  from a byte copy, 4 of 4 pass.
- Proof 1: with the old behaviour put back in `ReminderChange.donePatch` (`shell/Midas/RecordWriter.swift`,
  `.slot` case given `patch["snoozedUntil"] = .null` again), RecordWriterTests on the iOS 27.0
  "iPhone 17" simulator: `RecordWriterTests.swift:113: XCTAssertEqual failed: ("object(["snoozedUntil":
  .null, "slotsDone": ...])") is not equal to ("object(["slotsDone": ...])") - Done on an hourly time
  leaves the item's own snooze alone`, 6 tests, 1 failure. Restored from a byte copy (the builder's
  uncommitted diff of the file unchanged, 64+/7-), rerun: 6 tests, 0 failures.
- Full suite not run here: the builder runs scripts/test-all.sh after this change (its request).

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
