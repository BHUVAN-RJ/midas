# Brief: the Midas backend, 2026-10-10

You are the agent for Midas's backend (Hono on Cloudflare Workers, D1, R2). You work in your own
git worktree on branch `agent/backend` (`~/Desktop/Midas/midas-worktrees/backend`). The founder
talks to you directly in your Herdr tab. Your dev port is **8789**.

## How you work: four steps, in order, no skipping

1. **Go through the idea.** Read this brief and the sources below. Then tell the founder, in
   plain words, what you understood the problem and the goal to be.
2. **Ask the founder questions.** Ask what you need to know before planning, a few at a time.
   The founder gives directions. Do not write code.
3. **Propose a plan and get it approved.** Tables, routes, scripts, shell changes, what is tested
   and how, and what is left out. Wait for an explicit "approved" / "build it". Changes to the
   plan go back to the founder.
4. **Build the approved plan.** Only now write code, with tests (see Rules).

Never start a later step before the earlier one is done. "Discuss, the founder approves, then
build" is the project rule (`CLAUDE.md`).

## The rule that drives everything: no data loss

Decided 2026-10-10: **from now on no user data may be lost.** Records currently live only on the
phone (the shell answers `/_midas/store` locally since 2026-10-09), so a lost phone or a reinstall
would lose them. Backing records up to the server is part of this work.

Also decided 2026-10-10:

- **Only the founder runs database operations that delete.** Allowed in code without him: deleting
  a sign-in challenge the moment it is used (already in `backend/src/auth.ts`), and a scheduled
  cleanup of expired challenges and sessions. Everything else that would delete (unassigning a
  Sidekick, account deletion) is the founder's to run. See `docs/CONCERNS.md`.
- **Sidekicks are assigned per person** (one small assignments table).
- **Staging first:** backend changes go to a staging Worker before the live one.
- **D3 per-Sidekick tokens: decided later** (`docs/CONCERNS.md`, concern 3). Do not build them.

## What the lead session proposed and the founder approved as the outline

The founder approved this outline on 2026-10-10; your detailed plan (step 3) fills it in and may
question it.

**Phase 1, target Oct 11 to 12: staging, bundles, catalog, assignment**

- Staging Worker `midas-api-staging` with its own D1 and R2. `backend/wrangler.jsonc` is a shared
  file: tell the lead session exactly what to add; the lead edits it. Passkeys are bound to the
  domain, so staging needs its own association file and its own `webcredentials:` entitlement,
  and the shell a build setting that picks staging or live.
- `GET /sidekicks/:id/bundle` requires a session (`requireSession` in `backend/src/auth.ts`) and
  that the Sidekick is assigned to the user (D5: "a bundle cannot be fetched without a valid
  token").
- Versions stay launchable; each version records the op-log sequence it was deployed at (D5).
- Deploy uploads a `manifest.json` (id, name, SF Symbol, background color, `reads`) next to each
  version. The reminders agent already wrote a manifest for its page; read
  `sidekicks/reminders/` on branch `agent/reminders-app` before designing the format.
- `GET /sidekicks` returns the signed-in user's assigned Sidekicks with their manifests; the
  shell reads it instead of the hardcoded `shell/Midas/SidekickCatalog.swift`.
- `assignments (user_id, sidekick_id, assigned_at)`; an assign command that only inserts.
- `backend/scripts/deploy-sidekick.mjs` gains staging/live, and refuses live unless staging has
  the same version.

**Phase 2, target Oct 13 to 14: records backed up to the server (D4, append only)**

- An ops table: `op_id` unique, server-assigned sequence, user, Sidekick, key, value, tombstone.
  Server tables are never deleted from; a store delete is a new op.
- `POST /sync/push` (duplicates by `op_id` applied once) and `GET /sync/pull?after=<seq>`.
- Shell: the local store keeps an outbox and pushes on launch, on foreground and after writes;
  after sign-in on a fresh install it pulls everything before showing Sidekicks.
- This changes `shell/Midas/LocalRecordStore.swift`, which the reminders agent builds on. Agree
  the order with the lead session before touching it; the reminders record format stays as is.
- Done when: the same op sent twice is stored once; delete the app, reinstall, sign in with the
  passkey, and every record is back; no SQL in `backend/src` deletes from the ops table.

**Phase 3, after Oct 14:** usage metrics (D9), sign-out, the cleanup cron, a scheduled D1 export
to R2.

## Safety rails (required)

- Migrations only add tables and columns. A test fails if any file in `backend/migrations/`
  contains `DROP`, `DELETE` or `ALTER ... DROP`.
- A test fails if any SQL in `backend/src` deletes outside the two allowed cases above.
- Before every remote migration the database is exported to a `.sql` file (to R2 and to the
  founder's Mac, outside both repos). This backup plan is redone at 100 users (`docs/CONCERNS.md`).
- **You never run anything against live or staging Cloudflare yourself:** no
  `wrangler d1 ... --remote`, no `wrangler deploy`, no `wrangler r2 ... --remote`, no
  `deploy-sidekick.mjs`. Give the founder the exact command and what it changes, or ask the lead
  session to run it; the founder approves each one, every time.

## Sources to read

- `docs/PRODUCT.md`: build 1 (D2 to D6, D9), section 5 (architecture, the 2026-10-08 to 10-10
  decisions), section 6 (current state).
- `docs/CONCERNS.md`: deletion, backups, D3.
- `backend/` (all of it: `src/index.ts`, `src/auth.ts`, `migrations/`, `scripts/`, `test/`,
  including `test/helpers/sqlite-d1.ts`, the D1 stand-in that runs the real migrations).
- `shell/Midas/LocalRecordStore.swift`, `SidekickStoreChannel.swift`, `SidekickCatalog.swift`,
  `SidekickBundleLoader.swift`, `AuthModel.swift`; `shell/sdk/midas-store.js`.
- `docs/NOTIFICATIONS.md` (the `reminder:` record format the sync must carry unchanged).
- `CLAUDE.md` (working rules, "Tests are guarded"), `docs/PARALLEL-AGENTS.md` (worktree rules).

## Rules

- Stay inside your worktree. Edit only files your approved plan names. Shared files
  (`CLAUDE.md`, `docs/PRODUCT.md`, `docs/PARALLEL-AGENTS.md`, `backend/package.json`,
  `backend/package-lock.json`, `backend/wrangler.jsonc`) are changed only by the lead session.
- Every piece you build gets tests that can fail for the reason they exist. Run all suites after
  every change and report results honestly. From inside the worktree the test guard allows:
  `cd backend && npm test`, `cd shell && xcodebuild test ...`,
  `python3 -m unittest discover -s tests/guard`, and in midas-intel
  `python3 -m unittest discover -s intel/tests`. Avoid `2>&1` or other redirects in those
  commands; the guard reads `>` as a write. The first shell test run after `xcodegen generate`
  sometimes dies with "Test crashed with signal kill before establishing connection" before any
  test runs; rerun once before treating it as a failure.
- You may add new tests. Changing or deleting an existing test goes through the test-guardian
  agent; a hook enforces this.
- Commit small and often on your branch. Never merge into `main`; the lead session merges after
  review.
- If you are blocked on a question or an approval, ask the founder in your tab and wait.
