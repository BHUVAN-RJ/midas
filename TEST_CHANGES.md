# Test changes

Every change to or deletion of an existing test is recorded here by the test-guardian agent,
newest first. New tests are not recorded. The git pre-commit hook rejects a commit that changes
or deletes an existing test without also changing this file.

Each entry: date, test, change, reason (the decision, with its date, or the bug), and proof
the test can still fail for the reason it exists.

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
