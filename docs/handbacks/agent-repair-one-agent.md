# Hand-back: W4, one repair agent (`agent/repair-one-agent`, 2026-11-13)

Brief: `docs/briefs/repair-lanes.md` W4. Decision: `docs/PRODUCT.md` "Plan additions, 2026-11-13:
repair lanes", D5 = 1 (and D1, which the shared rules carry). Stage: testing only. Nothing deployed.

## What I built

1. **One template, `runner/agents/repair.md`.** Built from what the five per-Sidekick files share
   (they have the same 16 sections; only names, examples and the "what they mean" lines differ).
   Sidekick-specific text is gone from it; in its place, filled at run time:
   - **This Sidekick**, from the copy's `manifest.json`: name, id, `agent.description`, `notFor`,
     `rules`, every tool with its page controls and its `midas/photo` field, `reads`.
   - **Record types** (the copy's `types`, as before) and **Settings** (the manifest's `settings`
     catalogue when W5 adds one; else it points at the `settings:` type).
   - **The primitive**, from `docs/primitives/<id>/`: `manifest.primitive` when the copy names one,
     else a folder with the Sidekick's id (To-Do → `todo`). README, records, recipe and checklist
     whole, plus each block file's opening (intro, rules, pattern table). Full pattern text stays
     out (about 25 KB a block). A manifest value is used only when it is a plain folder name
     (`a-z0-9-`), never as a path.
   - **This person's notes** (below).
   - D1 in the rules: "remove" means hide (a setting turns it off; code and tool stay; the tool
     answers "turned off"); delete for good only when the person says so; `set_setting` and the
     settings engine are never removed. New features go in their own block. Preferences never
     become tests.
   - Same docs as before: WRITING, NOTIFICATIONS §4 and §7, WIDGETS, ICONS.
2. **`runner/lib/prompt.mjs`.** `buildSystemPrompt` now picks the agent:
   - a Sidekick with no file of its own → the one agent (no more `no repair agent for Sidekick X`
     as long as the copy has a manifest);
   - a Sidekick with its own file → that file, unless the mode is `shared`.
   - Mode: `MIDAS_STAGING_REPAIR_AGENT` / `MIDAS_LIVE_REPAIR_AGENT` for the job's own environment
     (`job.environment`, already set at claim), then `MIDAS_REPAIR_AGENT` for both; default
     `per-sidekick`. So staging can run the one agent while live keeps the per-Sidekick files.
   - The template is filled in one pass: text in a transcript or the notes that looks like
     `{{NAME}}` is no longer filled again (the old fill could do that).
   - The per-Sidekick path is unchanged in output (same values, shared helpers).
3. **`runner/lib/person-notes.mjs`.** This person's notes.
   - **Where:** `tests/PERSON_NOTES.md` in the person's copy. The copy's `tests/` already travels
     with every published version (`stageDeployFolder` → `deploy-sidekick.mjs` stores it under
     `<version>/tests/` in R2 → `fetch-sidekick-copy.mjs` brings it back next job), and nothing in
     `tests/` is served to the phone. No storage, backend or deploy change needed.
   - **Who writes it:** the runner, never the agent. The agent puts one line in `outcome.json`
     `"note"`; `appendPersonNoteFromOutcome` adds `- YYYY-MM-DD: <note> (repair <id>)`. Only a
     `fixed` result adds a line (unsupported and no_change publish nothing). No note → the
     summary's first sentence. One line ≤ 200 characters; the log keeps the newest 100 lines.
   - **Guarded:** the agent editing the file fails the job (`compareTests` treats it like any file
     that was in `tests/`; checked in a test).
4. **The ask-back answer (added at the lead's request after W2).** The claimed job's
   `sort.answer` is shown under the person's words in the transcript block:
   `Asked "What should it be?", they answered: "Other icon"`. It goes into both the one agent's
   prompt and the per-Sidekick prompts (those are still the default, and an answered card goes to
   the code lane). The one agent's rules say what the line means. **One change outside W4's
   files:** `runner/lib/backend.mjs` `normalizeJob` dropped every field it does not list, so I
   added `sort` (the object, or null). Without it the answer never reaches the prompt. Existing
   `normalizeJob` tests use `toMatchObject` and still pass.
5. **The W1 shield runs from `runJob` (lead's request, W1 hand-back "What the lead must add").**
   - The person's records are read once, before the agent, and frozen as `records.json`
     (read-only) in the log folder. The reporter-records checks use that same read and run before
     the shield, so a broken copy still fails with the reason those checks give.
   - `checkRepair` (gate → shield → copy tests) replaces `checkSidekick`; the copy tests are
     skipped when the shield fails. `shield.txt` goes to the log folder.
   - `runner/lib/agent.mjs` `agentEnvironment` takes `beforeFolder` and `recordsPath` and sets
     `MIDAS_JOB_BEFORE_FOLDER` / `MIDAS_JOB_RECORDS` for the agent's check tool (removed when not
     given).
   - The page-opens check uses WebKit; `deps.openPageImplementation` (else
     `settings.openPageImplementation`) replaces it in tests.
   - `repair.md` asks for `"changedTools": ["<id>.<verb>"]` in `outcome.json` when a tool is meant
     to answer differently.
   - test-guardian ACCEPTED two existing-test changes (logged in `TEST_CHANGES.md`): the runner
     fixture copies `runner/core-checks` and `runner/lib` into its scratch checkout, and one
     data-job expectation follows the shield order (copy tests not run when the shield fails).
6. **What this Sidekick must keep (founder, 2026-11-13, option A).**
   - Each base `sidekicks/<id>/manifest.json` (all six) has `"repair": { "keep": [...] }`, the
     facts that were only in `runner/agents/<id>.md`: Water's widget tap, 45-minute quiet,
     `reminder:water` shape, per-day `goalMl`, ml storage, Widget button; Money's integer cents,
     USD only, categories added never removed (with colours), `expenseRecord`, the receipt photo
     field, nothing written on open; Care's one record per reminder, `everyHours` next to `repeat`,
     always dated, shell-written fields; Reminders' and reminder-test's packed `history:`, every
     item a `reminder:`, the import handshake, trimmed copies, the widget writer; To-Do's no
     `null`, repeat `nextId` and 2 s double tick, `at` only when timed.
   - `prompt.mjs` reads the block from the checkout (`readBaseManifest`), never the copy, and
     fills "What this Sidekick must keep". A broken base block refuses the job (platform bug)
     rather than running the agent without its facts. A Sidekick the platform does not have gets
     the section with "nothing beyond the rules below".
   - `repairBlockProblems(manifest)` is exported for the deploy gate (lead item 7).
   - New case 9 in "First": a request that can only be met by breaking a kept fact or a protected
     block's behaviour is unsupported.
7. **Protected primitive blocks (founder, 2026-11-13).** The same section lists the core
   patterns (`| TD-… | name | core |` rows) of the primitive the **base** manifest names (else
   the Sidekick's id), so a copy cannot drop them by editing its `primitive`. To-Do: 39 core
   blocks; the others: "None: not built from primitive blocks". The rule: do not change what a
   protected block does (records, voice tool, what its controls do); allowed are a bug fix back to
   its block file, a choice the block offers, how it looks and reads (case 2) and hiding it
   (case 3). A new feature goes in its own marked section of `index.html` with its own functions,
   records and tool, and calls the protected block's functions instead of rewriting them.
8. **Tests (new files only):** `backend/test/runner-one-agent-prompt.test.ts`,
   `runner-one-agent-notes.test.ts`, `runner-one-agent-environment.test.ts`,
   `runner-one-agent-sort-answer.test.ts`, `runner-one-agent-run-job-notes.test.ts`,
   `runner-one-agent-run-job-shield.test.ts`, `runner-one-agent-keep.test.ts` (76 tests). Each
   check was made to fail once by breaking the code it guards: path rule removed, unknown
   Sidekick not routed, cap removed, non-fixed results allowed, two-pass fill, notes dropped, D1
   text removed, photo field dropped, job environment ignored, per-environment variable ignored,
   `sort` dropped in `normalizeJob`, answer left out of the transcript, `checkSidekick` swapped
   back in for `checkRepair`, shield env vars not passed, facts read from the copy, protected
   list read from the copy, on-request rows counted as core, base block not validated, section
   left out of the template, a Water fact removed.

## Results

- `origin/main` merged into this branch twice (W2 Sort `6fd1cd3`; then W1 Shield, W3 ask-back
  and `6089f75`), no conflicts.
- `scripts/test-all.sh` on the final code: see "Final suite run" at the end.

## How to try it

```bash
cd ~/Desktop/Midas/midas-worktrees/repair-one-agent/backend && npx vitest run test/runner-one-agent-prompt.test.ts test/runner-one-agent-notes.test.ts test/runner-one-agent-environment.test.ts test/runner-one-agent-sort-answer.test.ts test/runner-one-agent-run-job-notes.test.ts test/runner-one-agent-run-job-shield.test.ts test/runner-one-agent-keep.test.ts
```

See the one agent's prompt for any Sidekick (writes it to /tmp/todo-repair-prompt.md):

```bash
cd ~/Desktop/Midas/midas-worktrees/repair-one-agent && node -e 'import("./runner/lib/prompt.mjs").then(function show(m){const fs=require("fs");const job={sidekickId:"todo",id:"try",kind:"change",transcript:"hide the search"};fs.writeFileSync("/tmp/todo-repair-prompt.md",m.buildSystemPrompt({job,reportFiles:["transcript.txt"],manifestText:fs.readFileSync("sidekicks/todo/manifest.json","utf8"),agentMode:"shared"}));})'
```

Sizes of the one agent's prompt: To-Do 119 KB (with its primitive), the others 74–77 KB.

## What the lead must add (outside W4's files)

1. ~~`runner/lib/run-job.mjs` wiring~~ **Done in this branch (lead, 2026-11-13).** `runJob` passes
   `jobFolder` to `buildSystemPrompt` (the one agent's prompt shows the copy's notes) and, after
   the records check and right before `fix_ready`, calls `appendPersonNoteFromOutcome` and writes
   `person-note.json` to the log folder. New check `runner-one-agent-run-job-notes.test.ts`
   (3 tests): a fixed run appends the dated line, logs it and the deploy gets it; the shared
   prompt shows the earlier notes; an unsupported run adds and publishes nothing. Made to fail by
   removing the append and by not passing `jobFolder`. Four existing tests pinned the exact job
   folder file list; test-guardian ACCEPTED adding `tests/PERSON_NOTES.md` to them
   (`runner-job`, `runner-copy-tests`, `runner-feature-kind`, `runner-fetch-and-stage`; logged in
   `TEST_CHANGES.md`).
2. **Merge with main's uncommitted `runner/lib/prompt.mjs` work** (the To-Do agent line, another
   session). `TEMPLATE_BY_SIDEKICK` and `templateNameForSidekick` are unchanged here.
3. **Staging trial (deploy step, not now):** set `MIDAS_STAGING_REPAIR_AGENT=shared` where the
   runner's environment is set, restart the runner. Live stays on the per-Sidekick files.
4. **`runner/lib/intel.mjs`** (optional): catalogue entries for the primitive block files, so the
   agent can read a block's full patterns (`intel read todo-look`). Today only each block's
   opening is in the prompt.
5. **When the one agent is live** (one change, per the brief): delete the six per-Sidekick files
   (`reminders`, `care-reminders`, `hydration`, `todo`, `reminder-test`, `money`),
   `TEMPLATE_BY_SIDEKICK` and the mode switch; update `docs/DEPLOY.md` (lines 59–60 and 118–121
   name `TEMPLATE_BY_SIDEKICK`). Existing tests that pin the per-Sidekick files then need
   test-guardian: `runner-todo-prompt`, `runner-money-prompt`, `runner-hydration-prompt`,
   `runner-reminder-test-prompt`, `runner-reminders-widget-prompt`, `runner-home-screen-rule`,
   `runner-loop-config-prompt` ("split" test), `runner-guardian-reach`,
   `repair-data-review-fixes` (§8), `repair-staging-run-fixes`, `runner-repair-data`,
   `icons-light-dark`, `widget-light-dark`, `jess-repair-rules`, `jess-review-decisions`,
   `legacy-sweep-docs` (expects `runner/agents/reminders.md`), `legacy-sweep-2-docs`.
6. No new npm dependency, no `wrangler.jsonc` change.
7. **Deploy gate: validate the `repair` block** (`backend/scripts/bundle-tools.mjs`
   `validateManifest`, not a W4 file). Today the gate accepts any top-level key, so the blocks
   deploy as they are. To validate:
   ```js
   import { repairBlockProblems } from "../../runner/lib/prompt.mjs";
   // at the end of validateManifest, before it returns its problems:
   const repairProblems = repairBlockProblems(manifest);
   problems.push(...repairProblems);
   ```
   (`{ keep: [non-empty one-line strings ≤ 600 characters] }`, no other keys.) The runner already
   refuses a job whose base block is broken.
8. **Base Sidekick deploy:** the six base manifests changed (one added key). New installs' copies
   carry the `repair` key too; the one agent ignores the copy's and says so in its prompt. The
   shell and the gate ignore unknown keys (full suite passes).
9. **For W7 (publish first):** the notes line is appended in `runJob` right before `fix_ready`;
   W7 moves it after the publish. The shield's page-opens check is in `checkRepair`; W7 splits
   the shield into its fast and slow parts.

## Founder decisions applied (2026-11-13)

- **Sidekick facts: A** (`repair` block in each base manifest, read from the checkout). Done, item 6.
- **Protected primitives in the instructions.** Done, item 7.
- Live stays on the per-Sidekick files until the one agent is turned on; the per-Sidekick files
  are not removed (lead item 5 lists the one change that removes them).

## Also flagged

- The one agent's hard rules now include "typed text is never lost" for every Sidekick (it was a
  To-Do rule, founder 2026-11-02), and "no inline event handlers" plus the gate's "import" word
  rule (they were only in To-Do's file; the gate applies them to every page).
- The per-Sidekick files still say "a feature removed removes its tool"; D1 (remove means hide) is
  only in the one agent. I left the per-Sidekick files unchanged since they are removed after W4.
- The hand-back file is `docs/handbacks/agent-repair-one-agent.md` (the branch name with `/` → `-`).
- **My reading, for the founder to confirm:** a request that can only be met by changing what a
  protected block does, or by breaking a kept fact, is answered `unsupported` (case 9), not made
  with a note. Bug fixes, the block's own choices, looks, wording and hiding stay allowed.
- To-Do lists 39 core blocks in its prompt (about 3 KB); every other Sidekick has none.

## Final suite run (2026-11-13, after the last merge of origin/main)

`scripts/test-all.sh`, exit 0: test guard OK; backend 166 files, 1788 tests passed; shell 1301
tests, 0 failures; midas-intel OK.
