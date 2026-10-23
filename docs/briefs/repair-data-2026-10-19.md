# Brief: repair agent and runner on the unified data rules (2026-10-19)

Founder, 2026-10-19: "update all the old data format", the work listed in `docs/CONCERNS.md` §8,
now, before the first real repair runs. Two reviewers check your work after you finish.

Read first: `CLAUDE.md`, `docs/PRODUCT.md` (section 2 repair, data format), `docs/CONCERNS.md` §8,
midas-intel `docs/plans/2026-10-15-unified-data-v2.md` (sections 2-8 and 14, especially section 6
and the backward-compatibility answer), `docs/briefs/data-rework-product-changes.md` (what the
rework built), `runner/README.md`, `docs/briefs/repair-contract.md`, `docs/WRITING.md`.

## Why now

The unified data rework is on `main` and on staging (records carry `$type`, schemas live in each
Sidekick's `manifest.json` `types` block, one validator `shell/sdk/record-schema.js`, every
reminder item `reminder:` with text in `notes`, `settings:self`, `store.update`, files in R2). The
runner and the repair agent's instructions were left out of it on purpose (plan section 14) and
still describe the shapes from before the rework.
One report is queued on staging (Reminders, "continue to the next line while typing"); it must not
run until this is done.

## What to build (CONCERNS §8, plan section 6)

1. **Repair agent instructions.** `runner/agents/reminders.md`: only the current
   record types and fields from the Reminders manifest; `$type`; `store.update`; files are
   supported (`store.putFile`, `store.fileUrl`, 20 MB); the runner publishes live to the
   reporter's copy. New `runner/agents/care-reminders.md` for care-reminders, and the runner picks
   the prompt by Sidekick id.
2. **Schema with every change.** When the repair agent adds a type or field, it updates the copy's
   `manifest.json` `types` in the same change. Backward compatible by default (founder,
   2026-10-15): add only (optional fields, new types); no rename, no type change, no new required
   field (founder, 2026-10-19: never, with or without a migration; `runner/README.md`, "Data
   rules"). The runner refuses a fix that breaks this rule.
3. **Check the user's records before publishing.** The runner checks that every record the
   reporter has still passes the copy's new schema (the same validator), and does not publish if
   one fails; the report goes to `failed` with the reason. If the runner cannot read the user's
   records today, say how you would give it that (for example a runner-only route) in your plan.
4. **Copies' tests.** The pasted SDK pin in copies' tests (`reminders-bundle.test.ts:30`) is
   updated so a repaired copy passes its own tests on the current SDK; base and copies together
   (test-guardian for existing tests).
5. **Existing copies.** List every user copy on staging and live (read-only) and say which differ
   from the base or hold old shapes. Bringing them to the new shapes is a remote write: prepare it
   (script, dry run, exact commands) and stop; the founder runs or approves it.

Anything else in `runner/` that still assumes the old shapes, find and fix it; list it in your plan.

## Rules

- Your own worktree and branch only (`midas-worktrees/repair-data`, `agent/repair-data`). Never
  edit `CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`, `backend/package*.json`,
  `backend/wrangler.jsonc` or a guard file; write the exact text you need in your report.
- Never merge into `main`; never deploy, migrate, write remote data or put secrets anywhere. Reading
  staging and live is fine. The runner's settings file `~/.midas-runner/env` is the founder's:
  read it only to know the backend URL; never print the tokens.
- Never run `runner/bin/run-once.mjs` or `install.sh` against staging: the queued report is the
  founder's first real repair and runs after the reviewers.
- Changing or deleting an existing test goes through `test-guardian` (start a Claude session in the
  worktree and delegate); new tests you may add. Every fix gets a test that fails without it.
- Your own simulator: `xcrun simctl create "Midas Data" "iPhone 16 Pro"`, then
  `MIDAS_SIMULATOR="Midas Data" scripts/test-all.sh`.
- Before writing code: post a short plan (files, approach, tests) and every open question in one
  list, then wait for the lead.
- Commit with the full suite green. Done = `scripts/test-all.sh` passes and
  `xcodebuild -project shell/Midas.xcodeproj -scheme "Midas Test" -destination generic/platform=iOS build`
  succeeds. Report counts honestly, failures included, and what the reviewers should check.

## Status (2026-10-22)

Built, merged once into `main` (4906003), then fix rounds on `agent/repair-data`, not yet merged:

| Commit | Items |
|---|---|
| `710d490` | Reviewer findings 1–10 |
| `a40f57c` | 11 wrangler from `backend/` with `--no-install`; 12 agent tools at a plain path |
| `24cd209` | 13 agent and sandbox env from allow-lists; 14 `not` loses no entry |
| `a5da2b2` | 15 tool link removes only a symlink; 16 clash check sees failed moved upgrades |

Last run before `a5da2b2`: guard 34 OK, backend 641/641 + typecheck, shell 563/0 on "Midas Data",
midas-intel 31 OK, Midas Test device build OK. One backend test failed once under load (shell build
running alongside), green on 3 reruns. Report for 13–16 sent to the lead.

Note: the item-16 tests in `backend/test/runner-link-and-clash.test.ts` (`reminder:1`) pass without
the fix; they document the in-place case. The fail-without-fix proof is
`backend/test/runner-clash-moved-key.test.ts`.

Next, lead: merge `agent/repair-data` into `main`. Next, founder (not run by this agent):

1. Staging Worker deploy: `cd backend && npx wrangler deploy --env staging`.
2. Live survey: `node scripts/plan-user-copies.mjs --env live`. (The record migration step is gone:
   main retired the old record formats after the live conversion, founder 2026-10-20; merged into
   this branch 2026-10-23.)
3. Runner clone on the Mac mini pulls the merged code, then the first real repair run.

Open security gap: `docs/concerns/2026-10-13-repair-runner.md` §4.

## Decision: close the env-file gap (founder, 2026-10-22)

Founder, in this task's session, 2026-10-22: "yes you can start building", on the plan for
`docs/concerns/2026-10-13-repair-runner.md` §4:

1. The repair agent's file tools read and write only the job folder (`Read(./**)`, `Edit(./**)`
   in place of bare `Read`, `Edit`, `Write`). Reading or editing the runner's env file, Claude's
   config, SSH keys, the wrangler login, the keychain and the founder's code and documents is
   denied outright, and so is editing the job's own `.claude/`.
2. The copy's vitest runs under the macOS sandbox: no reading the home folder except the node
   install and the checkout, no writes outside its sandbox checkout, no network.
3. The runner refuses to start without a working sandbox.

4. Founder, same day: "also the agents should not be able to touch the sandbox". The agent may not
   edit the runner's code or tool link, nor read or edit the logs or the job's sandbox checkout and
   profile; the agent's tests may not rewrite their profile, the checkout or the job folder.

The founder then runs `node runner/bin/check-sandbox.mjs` and `--agent` to see it work.

5. Founder's `node runner/bin/check-sandbox.mjs --agent` run, 2026-10-22, reported "not yet
   fixed": "✕ agent can still read and write inside the job folder", every other line ✓. The log
   shows the API's safety filter flagged the attack-worded steps (`model_refusal_fallback`,
   `[cyber]`, Opus 5.5 to Opus 4.8) and the model declined every step, so the ✓ lines proved
   nothing: no call was made. Fix: the steps are plain and say what they are, and each check
   passes only when the log shows the call tried and refused (`runner/lib/agent-check.mjs`); a
   step not tried is ✕. A `cat` through Bash is probed too, since the run showed a Bash `ls` that
   matched no allow rule going through.
