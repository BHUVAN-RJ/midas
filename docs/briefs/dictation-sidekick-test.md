# Brief: Dictation Sidekick (TEST, STAGING ONLY)

> **TEST BUILD. Branch `agent/dictation-test` is NEVER merged into `main` and NEVER shipped to
> live.** The Sidekick is deployed to **staging only** and assigned to **RJ only** (the founder's
> staging user). Never run any script with `--env live`. Founder, 2026-11-13.

## Why

The Dictation Test screen (commit 09cf212, `shell/Midas/DictationTest*.swift`, long-press "Midas")
exists only in the shell. The founder wants it reachable the Midas way: a Sidekick tile on his home
grid, on staging. Read `docs/briefs/dictation-cleanup-test.md` first for what the screen does.

## What to build

1. **Sidekick `dictation`** in `sidekicks/dictation/` (same shape as `sidekicks/hydration`,
   `sidekicks/todo`): manifest with unified `$type` records, page, `tools.js`, widget.
   - Page: jess's orb (DESIGN.md 5a) and one action that opens the native Dictation Test screen.
     Find how a Sidekick page asks the shell to do something native (the request-record pattern used
     by the Apple Reminders import is one) and reuse it; do not invent a second mechanism if one exists.
   - **Results as records:** each cleanup run on the test screen (phrase or spoken; raw, cleaned,
     release→raw ms, cleanup ms, total ms, first/warm, model status, device, iOS) is saved as a record
     of this Sidekick, so timings land in staging and can be read without the founder copying them.
     The page lists the latest runs (newest first) with average and worst cleanup ms.
   - Agent block + `tools.js` (CLAUDE.md "Every Sidekick is agent-connected"): at least a tool to
     list recent runs / summary. Widget (`docs/WIDGETS.md`): small size, last cleanup ms and
     average. If a rule clearly does not fit a test-only Sidekick, say which and why in the report.
   - Words on screen follow `docs/WRITING.md`. Show a small "TEST" tag on the page.
2. **Shell:** wire the page's request to the existing screen and the screen's runs to records.
   Everything stays inside `#if MIDAS_TEST_BUILD`. Extend, do not fork.
3. **Staging:** deploy the Sidekick with `backend/scripts/deploy-sidekick.mjs --env staging` and
   assign it with `backend/scripts/assign-sidekick.mjs "<RJ's staging user name>" dictation --env staging`
   (check the user name in staging first; read-only). D1 commands need the sandbox off.
   Follow `docs/DEPLOY.md` for the staging steps only.
4. Bump nothing else: build number is already 24 on this branch (TestFlight Midas Test is at 23).

## Not now

The keyboard extension (step 2 of the plan) is not part of this brief.

## Tests

New tests for the Sidekick (records, tools, widget, page action) and for the shell wiring.
Existing tests are guarded (test-guardian only). Run the full suite; `scripts/test-all.sh` cannot
run the shell part (looks for a missing "iPhone 17" simulator), so run the shell suite on both
schemes through `scripts/sim.sh` as the previous agent did. Known pre-existing failure under the
Midas Test scheme: `WidgetAppConfigTests.testEntitlementsCarryTheWidgetAppGroup`. Report honestly.

## Done

Committed on `agent/dictation-test`, messages starting `TEST BUILD (do not merge):`. Staging deploy
and RJ assignment done and checked (the Sidekick appears for RJ on staging). Report: files, test
results, staging state, and the founder's steps to install build 24 (each command starts with `cd`).
No TestFlight upload unless the founder asks.
