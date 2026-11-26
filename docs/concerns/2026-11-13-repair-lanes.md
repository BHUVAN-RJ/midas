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
9. **Flaky shell check in the full run (2026-11-14):** `JessWorklogLinkTests`
   `testThePastedHelperReadsTheFocusAndMarksTheRecordUnderTheRealCSP` failed twice in a row in the
   full suite run on the staging-guards merge (`onScreen` false, expected true), and passed 3 of 3
   run alone. The merge changed no shell or Sidekick page file (runner and backend only); the same
   shell code passed 1306/1306 at `6a7475c`. Looks like timing under load (whether the record is on
   screen when measured). Needs a look by whoever owns jess worklog links; changing the test goes
   through test-guardian.
10. **Staging long poll answers 500/503 now and then (2026-11-22):** after the staging deploys of
    the cancel X and card options, the runner logged `staging: wait failed: 500` (during a deploy)
    and then `wait failed: 503` about once every 30 min (~1 in 70 polls of 25 s). The runner retries
    on the next poll, so a job waits at most one more poll. Look at `GET /repairs/jobs/wait` with
    `wrangler tail --env staging` for the cause (likely the Worker's wall-time limit on a held request).
11. **Founder testing build 46, Reminders, 2026-11-26 (not fixed yet; founder said note it):**
    - "Changed" + Undo stays on the tag indefinitely. Founder: it should stay 2–3 s, then go away.
    - When a new repair starts, whatever the old repair left visible (Changed/Undo, a result) must go;
      the new repair's state replaces it. Seen: job 4f938037 ("To something funny", font) ran as code
      while the tag still showed Changed/Undo from the setting repairs before it.
    - "Titles are not exactly matching" (founder's words; which titles not yet pinned down).
    - "A bit slow": job 4f938037 sort 4.98 s, sent→live 68 s. Setting repairs b1fc674b / 38b01825 /
      b9d16979 sorted in 2.9–5.0 s and finished 14–59 s after send (updated_at).
    - Setting-lane rows stay status `received` after the setting is applied (5 rows on 2026-11-26).
    - Dictation kept only "To something funny"; the start ("change the font") was lost.
    - Question card options: keep the layout, text only, no symbols/pictures (founder decision).
