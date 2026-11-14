# Repair lanes: leftovers (2026-11-13)

Out-of-brief findings from the repair-lanes build (`docs/briefs/repair-lanes.md`). Hand-backs:
`docs/handbacks/agent-repair-sort.md`, `agent-repair-shield.md`, `agent-repair-askback.md`,
`agent-repair-one-agent.md`.

1. **Deploy gate lets a missing page control through.** `checkBundleFiles` in
   `backend/scripts/bundle-tools.mjs` (and `gateProblems` in `runner/lib/check.mjs`) skip every tools
   problem starting with `manifest.json: `, which also matches `pageActionsMissing`. A manifest that
   names a control the page lacks deploys today. Repairs are covered by the shield's `tools` check;
   `deploy-sidekick.mjs` is not. (W1 hand-back.)
2. **An answer that arrives after the 2-minute drop** gets an error (410); the phone then closes as
   an edit and its tag waits on a dropped report. The Worker could answer a late answer with a lane
   instead. (W3 hand-back.)
3. **Debug stub mode on the phone** (`MIDAS_REPAIR_SORT_STUB=1`): a code-lane close leaves an
   "Editing" tag that never resolves; erase the simulator after. Debug only.
4. **Shield flag after W5:** set `SETTINGS_ENGINE_IN_EVERY_SIDEKICK = true` in
   `runner/core-checks/shield.mjs` once Reminders, Care and Water have the settings engine.
5. **Removing the per-Sidekick agent files** (after the one agent is live): 17 existing tests pin
   them and need test-guardian (list in the W4 hand-back), plus `docs/DEPLOY.md` lines naming
   `TEMPLATE_BY_SIDEKICK`.
6. **Guard paths for `runner/core-checks/`:** not needed for repairs (the runner loads the shield
   only from its own checkout). Adding them to `.claude/hooks/guard_tests.py` would also stop dev
   sessions editing the shield; founder's call, by hand.
7. **jess-made repairs are not sorted** (`queueVoiceRepair`): jess already decided it is a change;
   their `lane` is empty.
8. **The main checkout's uncommitted `runner/lib/prompt.mjs`** (another session, To-Do agent line)
   will meet W4's rewrite of that file when that session commits.
