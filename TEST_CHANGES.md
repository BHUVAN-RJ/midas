# Test changes

Every change to or deletion of an existing test is recorded here by the test-guardian agent,
newest first. New tests are not recorded. The git pre-commit hook rejects a commit that changes
or deletes an existing test without also changing this file.

Each entry: date, test, change, reason (the decision, with its date, or the bug), and proof
the test can still fail for the reason it exists.

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
