# Second old-format sweep, agent A (backend, scripts, runner code, guard tests): notes for the lead

2026-10-20, branch `agent/legacy-sweep2-a`. Brief: midas-intel
`docs/plans/2026-10-21-legacy-sweep-2-brief.md`. Decisions: `docs/PRODUCT.md` "Old formats
retired (founder, 2026-10-20)" (main `ede0f55`, `f7dc456`).

## 1. Open question for the founder (test-guardian NEEDS-EVIDENCE, not built)

The server now refuses every save from a stored Sidekick version whose manifest has no `types`
("reminders version v1 has no record schema types"). Two other cases still let a save through
without a check, because the written decision names only untyped versions:

- a save naming a version the server does not hold (`sync-record-types.test.ts`, op-gone-01,
  "a version that is not stored is checked against nothing");
- a save for a Sidekick with no deployed version ("a Sidekick with no deployed version is not
  content-checked, as before schemas").

Agent A first refused both too ("is not deployed", "has no deployed version"). test-guardian
would not change those two tests without a written decision, so the code was narrowed back. If
the founder wants them refused, a dated line in `docs/PRODUCT.md` saying so lets the change go
through (code is a few lines in `backend/src/record-types.ts`).

The header of `backend/test/sync-untyped-version-refused.test.ts` still opens "The server stores
nothing unchecked", which claims more than the code does (see above). A one-word fix through
test-guardian, or it becomes true if the founder answers yes.

Also unchanged: deletes are never content-checked, also from an untyped version. And tests that
give the server no R2 bucket skip content checks (`canReadManifests`), which is test-only.

## 2. Changes outside A's files

- `CLAUDE.md`, `docs/PRODUCT.md`: done by the lead (`ede0f55`, `f7dc456`); nothing more needed.
- Quarantine file intro: updated by A (scripts in `docs/legacy/code/`, live converted).
- For agent C:
  - `runner/README.md:118`: says records are upgraded in memory with
    `backend/scripts/record-upgrades.mjs`. The runner now checks records exactly as stored. The
    summary line is now "- User's records: N checked against the new schema, all fit".
  - `docs/briefs/data-rework-product-changes.md:17, 66-67, 101`: names `record-upgrades.mjs`,
    `migrate-records.mjs` and the `node scripts/migrate-records.mjs --env live` commands.
  - `docs/briefs/data-rework-product-changes.md:79`: "without `types` is not content-checked" no
    longer holds for a stored untyped version.

## 3. Overlap with agent B

- `backend/test/reminders-logic.test.ts:98-102` (B's subject) still tests the page reading an
  old `task:` record. B changes it with its page code. `helpers/runner-fixture.ts` copies that
  file into the runner's scratch checkouts; A changed only the fixture's converter copy line.
- `legacy-retired-2026-10-20.test.ts` checks `shell/sdk` and `sidekicks/` only for the names of
  the two retired scripts. Its "upgrade on read" wording check, like `legacy-quarantine.test.ts`,
  covers only A's paths. After B merges, adding `sidekicks/` and `shell/sdk` to both is a
  test-guardian change.
- The shell's own check (`record-schema.js` `checkRecord`) still passes anything when `types` is
  missing. The founder's decision names the server; any change on the phone is B's.

## 4. Behaviour

- Current-format data: same result. The in-memory upgrade returned every current record
  unchanged (live dry run: 0 writes), so checking as stored gives the same pass/fail and clash
  texts. `records-check.json` loses `upgraded`, failures lose `storedAs`, and the summary loses
  "(N old-shape changes applied in memory only)".
- Copies planner: instead of a list of retired keys, any literal write of a prefix the copy's
  types do not declare is a gap ("writes <prefix> records its types do not declare"). `task:`
  is still caught. The migration dry-run line is gone.
- The runner no longer needs `backend/scripts/record-upgrades.mjs` in its checkout.
- Server: a save from an untyped stored version is refused. The phone keeps the op queued, as
  for any refused op.
