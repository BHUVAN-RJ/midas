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
5. **Tests (new files only):** `backend/test/runner-one-agent-prompt.test.ts`,
   `runner-one-agent-notes.test.ts`, `runner-one-agent-environment.test.ts`,
   `runner-one-agent-sort-answer.test.ts` (43 tests). Each check was made to fail once by
   breaking the code it guards (path rule removed, unknown Sidekick not routed, cap removed,
   non-fixed results allowed, two-pass fill, notes dropped, D1 text removed, photo field dropped,
   job environment ignored, per-environment variable ignored, `sort` dropped in `normalizeJob`,
   answer left out of the transcript).

## Results

- Backend suite in the worktree: 156 files, 1681 tests, all pass.
- `scripts/test-all.sh`: see the last section.

## How to try it

```bash
cd ~/Desktop/Midas/midas-worktrees/repair-one-agent/backend && npx vitest run test/runner-one-agent-prompt.test.ts test/runner-one-agent-notes.test.ts test/runner-one-agent-environment.test.ts
```

See the one agent's prompt for any Sidekick (writes it to /tmp/todo-repair-prompt.md):

```bash
cd ~/Desktop/Midas/midas-worktrees/repair-one-agent && node -e 'import("./runner/lib/prompt.mjs").then(function show(m){const fs=require("fs");const job={sidekickId:"todo",id:"try",kind:"change",transcript:"hide the search"};fs.writeFileSync("/tmp/todo-repair-prompt.md",m.buildSystemPrompt({job,reportFiles:["transcript.txt"],manifestText:fs.readFileSync("sidekicks/todo/manifest.json","utf8"),agentMode:"shared"}));})'
```

Sizes of the one agent's prompt: To-Do 119 KB (with its primitive), the others 74–77 KB.

## What the lead must add (outside W4's files)

1. **`runner/lib/run-job.mjs`** (needed for notes to be written):
   ```js
   import { appendPersonNoteFromOutcome } from "./person-notes.mjs";
   // in runJob, right before: await backend.postStatus(job.id, "fix_ready", { summary: outcome.summary });
   const noteResult = appendPersonNoteFromOutcome({ jobFolder, reportId: job.id });
   writeFileSync(join(logFolder, "person-note.json"), JSON.stringify(noteResult));
   ```
   and pass `jobFolder` to `buildSystemPrompt({ ..., jobFolder, ...toolPaths })` so the notes are
   in the prompt (without it the prompt tells the agent to read `tests/PERSON_NOTES.md` itself).
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

## Founder decision needed (blocks step 5, not the staging trial)

**Where do the Sidekick facts go that are only in the per-Sidekick files?** Some facts a repair
must keep are in neither the manifest nor a primitive. Only To-Do was built from a primitive, and
its facts are mostly in `docs/primitives/todo/records.md`. For the others, examples:

| Sidekick | Fact only in `runner/agents/<id>.md` |
|---|---|
| Water | A widget tap adds to `water:{today}.ml` only, so `ml` can exceed the drinks listed; never "fix" it. Any write to today's record silences reminders 45 min: write it only when a drink changes. `reminder:water`'s `listen` contract. |
| Money | Amounts are integer cents; USD only; categories added, never removed or renamed (with their colours). |
| Care | `everyHours` is a field next to `repeat`, not inside it. |
| Reminders | `history:` packs many done items in one record. |

Options:
- **A.** A short `repair` list of facts in each Sidekick's base manifest (`sidekicks/<id>/manifest.json`),
  read by the one agent from the platform checkout, so a person's repair cannot edit it and every
  existing copy gets it with no migration.
- **B.** A primitive-style folder per Sidekick (`docs/primitives/<id>/records.md`), read like To-Do's.
- **C.** Drop them; rely on the manifest, the page code and the W1 shield.

Until this is settled, live keeps the per-Sidekick files (the default), so nothing is lost.

## Also flagged

- The one agent's hard rules now include "typed text is never lost" for every Sidekick (it was a
  To-Do rule, founder 2026-11-02), and "no inline event handlers" plus the gate's "import" word
  rule (they were only in To-Do's file; the gate applies them to every page).
- The per-Sidekick files still say "a feature removed removes its tool"; D1 (remove means hide) is
  only in the one agent. I left the per-Sidekick files unchanged since they are removed after W4.
- The hand-back file is `docs/handbacks/agent-repair-one-agent.md` (the branch name with `/` → `-`).
