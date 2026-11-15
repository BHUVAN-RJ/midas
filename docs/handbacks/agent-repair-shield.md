# Hand-back: W1 Shield (`agent/repair-shield`), 2026-11-13

Brief: `docs/briefs/repair-lanes.md` W1. Decisions: `docs/PRODUCT.md`, "Plan additions, 2026-11-13:
repair lanes" (D1, D3). Stage: testing only. Nothing deployed.

## What was built

The shield: six core checks that run on a repaired copy, from the platform checkout, never from or
into the job folder. Full description: `runner/core-checks/README.md`.

| Check | Fails when | Failing case shown in |
|---|---|---|
| `page-opens` | new page in WebKit, with the person's records, draws nothing or shows a new console error, uncaught error, unhandled rejection or refused store write; on the first view and after a tap on every page control a tool names | `repair-shield-page.test.ts` (throw on open, console.error + rejection, blank page, tap breaks a view, refused write, forged report) |
| `tools` | a tool removed (D1), its handler gone, its answer changed on the person's records without the request naming it, a page control it names gone | `repair-shield-tools.test.ts` |
| `settings-engine` | a copy that had `set_setting` + `settings:` type + `settings:self` loses any part (repair 42396937's change) | `repair-shield-static.test.ts` |
| `records-fit` | a stored record does not fit the new schema (reuses `runner/lib/user-records.mjs`) | `repair-shield-static.test.ts` |
| `widget-record` | a `widget:` record the old page wrote is no longer written | `repair-shield-page.test.ts` |
| `primitive-blocks` | a block check in `docs/primitives/<p>/checks/*.mjs` fails, throws or does not load | `repair-shield-static.test.ts` |

A check that cannot run (WebKit missing, a check throws) fails, never passes
(`repair-shield-runner.test.ts`, "fails closed").

**WebKit choice:** macOS `WKWebView`, headless, from a 180-line Swift program
(`runner/core-checks/webkit-page.swift`) compiled once by `xcrun swiftc` (about 2 s, cached in
`$TMPDIR/midas-shield/<hash>/`). Same engine as the iPhone shell, no npm dependency, no browser
download, no simulator lease (the two pool simulators would queue every repair). About 0.6 s per
page open; a full To-Do shield (16 page controls, old and new page) takes about 20 s.

The page gets a stand-in store injected before its own scripts: the shell's `/_midas/store`
protocol, every write stamped and checked with `shell/sdk/record-schema.js` + `shell-types.js`,
no network. Its report carries a per-step nonce, so a page cannot post a fake "all clear";
`console.error` is locked so a page cannot hide its errors.

## Files

New:
- `runner/core-checks/README.md`, `shield.mjs`, `page-open.mjs`, `page-prelude.js`,
  `webkit-page.swift`, `page-check.mjs`, `tools-compare.mjs`, `tool-inputs.mjs`,
  `settings-engine.mjs`, `records-fit.mjs`, `primitive-blocks.mjs`
- `backend/test/repair-shield-fixtures.ts`, `repair-shield-tools.test.ts`,
  `repair-shield-static.test.ts`, `repair-shield-page.test.ts`, `repair-shield-runner.test.ts`
  (37 tests)

Changed:
- `runner/lib/check.mjs`: new `checkRepair` (gate → shield → copy tests; skips the tests when the
  shield fails), `runShieldForJob`, `loadShield` (from the checkout only), `readCopyFolder`,
  `requestedToolsFromOutcome`. `checkSidekick` unchanged.
- `runner/tools/check.mjs`: runs `checkRepair` and prints the shield report when the runner sets
  `MIDAS_JOB_BEFORE_FOLDER` and `MIDAS_JOB_RECORDS`; otherwise as before.
- `runner/lib/agent-check.mjs`: not changed (nothing needed).

No dependency, `package.json` or `wrangler.jsonc` change. The runner Mac needs Xcode's `swiftc`
(already there: the runner builds the app).

## How to try it

```
cd ~/Desktop/Midas/midas-worktrees/repair-shield/backend && npx vitest run test/repair-shield
```

## What the lead must add (outside W1's files)

The shield is not yet called by `run-job.mjs`, which W1 does not own. Until this lands, real
repairs still go through `checkSidekick` only. The change:

`runner/lib/run-job.mjs`:
```js
import { checkRepair, sandboxRootFor } from "./check.mjs";   // was checkSidekick
// after snapshotSidekickFiles(jobFolder, snapshotFolder), before the agent:
let recordsBefore;
try {
  recordsBefore = await backend.listRecords(job.id);
} catch (error) {
  throw new JobFailure("records unreadable", error.message);
}
const recordsPath = join(logFolder, "records.json");
writeFileSync(recordsPath, JSON.stringify(recordsBefore));
chmodSync(recordsPath, 0o444);
// agentEnvironment({ ..., beforeFolder: snapshotFolder, recordsPath })
// replace the checkSidekick call:
const check = await checkRepair({ checkoutRoot: settings.checkoutRoot, sidekickId: job.sidekickId, jobFolder,
  beforeFolder: snapshotFolder, records: recordsBefore, runTests: deps.runTests });
if (check.shield) {
  writeFileSync(join(logFolder, "shield.txt"), check.shield.report);
}
```

`runner/lib/agent.mjs` `agentEnvironment`: accept `beforeFolder` and `recordsPath`, set
`MIDAS_JOB_BEFORE_FOLDER` and `MIDAS_JOB_RECORDS` (and delete them when not given, as with
`MIDAS_JOB_MANIFEST_BEFORE`). Both paths are in the log folder: the agent's own Read tool is denied
there (`agentPathLimits`), the check tool reads them.

W4 (`runner/agents/repair.md`): one line for the agent: "If the request is meant to change what a
tool answers, list that tool in outcome.json as `"changedTools": ["<id>.<verb>"]`."

After W5 lands the settings engine in Reminders, Care and Water: set
`SETTINGS_ENGINE_IN_EVERY_SIDEKICK = true` in `runner/core-checks/shield.mjs`.

**Guard hook paths:** not needed for repairs. Repair agents and the Sidekick guardian cannot edit
the runner's checkout (`noEditPaths`), and the shield is only ever loaded from it (tested: a shield
planted in the job folder is ignored). If the founder also wants dev sessions blocked from editing
the shield, the paths are `runner/core-checks/` (add to `GUARD_LOCATIONS` and `"runner/core-checks"`
to `GUARD_FRAGMENTS` in `.claude/hooks/guard_tests.py`); that would also block W5/W6 from adding
checks there.

## Open questions

1. **"Every view the manifest names":** no manifest names views. The shield treats the views as
   the first view plus the view after a tap on each page control a tool's `midas/page-actions`
   names (a control not on the first view is skipped). If views should be named in the manifest,
   that is a new manifest field (founder).
2. **"Unless the repair request names that tool":** decided by the agent through
   `outcome.json` `changedTools`; every tool whose answers changed is listed in the shield report
   for the founder. A stricter rule (matched against the transcript) would need a decision.
3. **Errors the page already had:** not blamed on the repair (otherwise a broken page could never
   be repaired). Say if the founder wants zero errors regardless.

## Found while building (not fixed, not W1's files)

- The deploy gate drops every "page control not on the page" problem: `checkBundleFiles` in
  `backend/scripts/bundle-tools.mjs` (and the runner's copy, `gateProblems` in `check.mjs`) skip all
  tools problems starting with `manifest.json: `, meant to skip agent-block duplicates, which also
  matches `pageActionsMissing`. A manifest naming a control the page lacks deploys today. The
  shield's `tools` check catches it on repairs; the deploy script still lets it through.

## Test results

`scripts/test-all.sh` in this worktree, 2026-11-13, after the last code change: ALL SUITES PASSED.
- test guard: 42 tests OK
- backend: 157 files, 1680 tests passed (37 of them new shield tests); typecheck clean
- shell: 1264 tests, 0 failures
- midas-intel: 31 tests OK
