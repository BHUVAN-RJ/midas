# Test changes

Every change to or deletion of an existing test is recorded here by the test-guardian agent,
newest first. New tests are not recorded. The git pre-commit hook rejects a commit that changes
or deletes an existing test without also changing this file.

Each entry: date, test, change, reason (the decision, with its date, or the bug), and proof
the test can still fail for the reason it exists.

## 2026-10-07: SidekickWebViewTests.testFetchToPlatformOriginIsNotACSPViolation

- Change: the assertion checked that no CSP violation of any kind was recorded; it now checks
  that no `connect-src` violation was recorded.
- Reason: test bug. The page deliberately contains an unhashed inline script, whose
  `script-src-elem` violation is expected and is what `testOnlyDeployedScriptsRun` relies on.
  The test is about fetch to the platform origin only.
- Proof it can still fail: changing `connect-src` in `SidekickContentSecurityPolicy.policy` to
  any other origin records a `connect-src` violation for the platform fetch.
- Made by the main agent before the guardian existed, recorded here retroactively.
