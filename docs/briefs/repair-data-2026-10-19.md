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
