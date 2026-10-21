# Staging port to the current rules, 2026-10-21 (Agent B)

Brief: midas-intel `docs/plans/2026-10-21-runner-both-and-staging-port-brief.md`, Agent B.
Checked 2026-10-21 about 22:00 to 22:10 UTC against main `c5b52d1`. Staging only; live was not
touched (one `GET /health` on live, read-only). Nothing was written to staging: no op, no deploy,
no deletion.

## Summary

| Check | Result |
|---|---|
| 1. Records in the current format | ✓ all 106 current records carry `$type` and pass their schema; nothing to convert |
| 2. User copies on current rules | ✕ one: "R J" Reminders copy has no `agent` block and no `tools.js`; **not reset** (it holds a fix the base lacks) |
| 3. D1 migrations | ✓ 0001 to 0008 applied (0007, 0008 at 2026-10-21 21:58:55 UTC) |
| 3. Secrets | ✓ `OPENROUTER_API_KEY`, `REPAIR_RUNNER_TOKEN`, `JESS_GROW` present |
| 3. Worker version | ✓ deployed 21:59:04 UTC, after the last backend commit `6b8bba5` (21:52:29 UTC); its route `POST /repairs/:id/jess-rerun` answers 401 (exists); `/health` ok |
| 3. Base Sidekicks | ✓ `reminders` `20261021T215906678Z-e63ababf` and `care-reminders` `20261021T215928527Z-d3e6d333`: `index.html`, `manifest.json`, `tools.js` byte-identical to main |
| 3. R2 buckets | ✓ `midas-bundles-staging`, `midas-files-staging` exist; no staging record references a `file:` |
| 4. Test accounts | "Test" and both "Voice Check" accounts look disposable (below) |

## 1. Records

Read every op (320) from `midas-staging`, took the latest op per user, Sidekick and key, and checked
each current value with `shell/sdk/record-schema.js` against the manifest that governs it (the
user's copy where there is one, else the base; `widget:` and `request:` against the shell types).

| Account | Sidekick | Current records | Deleted keys | Without `$type` | Failing schema |
|---|---|---|---|---|---|
| R J | reminders | 88 (79 reminder, 7 list, 1 history, 1 settings) | 70 | 0 | 0 |
| Test | reminders | 10 (8 reminder, 2 list) | 0 | 0 | 0 |
| Test | care-reminders | 8 (5 list, 2 reminder, 1 settings) | 0 | 0 | 0 |

R J's records also pass today's base Reminders schema (the copy's `types` equal the base's).
The retired migration script was not needed and not read.

## 2. User copies

`node scripts/plan-user-copies.mjs --env staging` (read-only) and a direct read of the pointers:

| Account | Sidekick | Pointer | State |
|---|---|---|---|
| R J | reminders | own copy `20261020T055239856Z-b44ec144`, base `20261016T011358074Z-fc82222c` | `types` ✓, `agent` ✕, `tools.js` ✕ |
| Test | reminders | none, follows base | ✓ |
| Test | care-reminders | none, follows base | ✓ |

The planner reports R J's copy as "no gaps": it checks types, writes and the store helper, not the
agent block or `tools.js` (see "Code changes to consider").

**Why R J's copy was not reset.** The repair holds something today's base lacks (repair report
`13edb182`, 2026-10-16, R J's words: "I need the thing to continue to go to the next line while I am
typing the reminder instead of it keep going in the same line"). A reset with `--from-base` would
lose:

- The row title box as a one-row `<textarea>` that wraps and grows while typing (instead of a
  one-line `<input>`): `.row-input` gets `display: block; height: 22px; resize: none; overflow:
  hidden; word-wrap: break-word`, a new `fitEditInputHeight`, pasted line breaks turned into spaces,
  and Return still starting the next reminder. 30 changed lines in `index.html`.
- The copy's own test `tests/reminders-title-wrap.test.ts` (3 cases), the copy's other 7 tests
  and its `TEST_CHANGES.md` are the base's.

Manifest is unchanged by the repair (identical to its base's).

**Carrying the repair onto today's base, checked locally only:** today's base `index.html` with the
repair's diff applied (applies cleanly), plus today's `manifest.json` and `tools.js`, passes
`checkBundleFiles` and `sidekickToolsProblems` with no problems. Not deployed. If the founder wants
it, the deploy would be the founder's or lead's call, e.g. a folder with that page, today's manifest
and `tools.js`, and the copy's tests plus `reminders-title-wrap.test.ts`, then
`node scripts/deploy-sidekick.mjs reminders --env staging --user 9-GAkqjLqjvn6Hyr9-AbTg --dir <folder>`.
The other option is to put the fix into the base Reminders for everyone.

**Repair record mismatch:** report `13edb182` on staging has `status = failed`,
`fail_reason = deploy failed` (updated 2026-10-20 06:22 UTC), yet R J's pointer names the copy made
from it (`20261020T055239856Z`, 05:52 UTC). The copy went up; the read-back after it failed (same
day as the npx hang fixed in `backend/scripts/wrangler.mjs`). R J got no "done" notice for it.

## 3. Environment

- D1 `midas-staging`: migrations 0001 to 0008, same as `backend/migrations/` on main. Tables
  include `voice_logs`, `jess_pending_requests` (empty).
- Worker `midas-api-staging`: latest deployment `7e53d916-faa2-4c78-8c31-b843a6938074`
  (2026-10-21 21:59:04 UTC). Wrangler cannot download a deployed script, so "matches main" rests on
  timing and the route probe above, not a byte comparison.
- Secrets: the three named, all `secret_text`. Their values were not read; `JESS_GROW` must be the
  text `true` for the grow path (`backend/src/jess-pending.ts`).
- R2: both buckets exist. Wrangler here has no object listing, so the files bucket's contents were
  not listed.

## 4. Test accounts

| Account | Id | Created | Holds | Looks |
|---|---|---|---|---|
| R J | `9-GAkqjLqjvn6Hyr9-AbTg` | 2026-10-11 | founder's staging account, 274 ops, the repaired copy | keep |
| Test | `CvzHMhmR2LDba5E-cm3nhA` | 2026-10-12 | 1 passkey, seed reminders ("Reply to a16z invite", "Gym"...) plus typed junk ("Jhvjhv", "Kkjhhvkjv"), care-reminders seed lists plus "Hi" and one expletive; last op 2026-10-16 | disposable, unless it is the account the staging runner tests are meant to use |
| Voice Check mvg0cwqz | `Xx6gVz6xx80MgWxaOXqVSg` | 2026-10-20 01:32 | 1 passkey, 1 session, 3 `voice_logs` rows, no ops, no assignments | disposable |
| Voice Check mvg0d62z | `cnHa3lV-FAJ6V-qW1rJqlw` | 2026-10-20 01:32 | same | disposable |

## Left for the founder

1. R J's Reminders copy: keep as is (jess cannot route to it: no tools), carry the wrap fix onto
   today's base (checked above), move the fix into the base, or reset and lose it.
2. Deletions, if wanted (founder only): the three disposable accounts. Their rows sit in `users`,
   `passkeys`, `sessions`, `assignments`, `ops` (append-only, trigger blocks updates only),
   `voice_logs`. Nothing in R2 belongs to them (no copies).
3. Repair report `13edb182`: status says failed while the fix is on R J's copy; whether to correct
   it is the founder's call (it is a record, so an update by hand).

## Code changes to consider (not made)

- `backend/scripts/plan-user-copies.mjs` / `user-copy-plan.mjs`: flag a copy whose manifest lacks
  the `agent` block or whose pointer has no `tools.js` while the base has them. Today it says
  "no gaps" for R J's copy.
- The runner's read-back failure leaves a published copy marked failed; a check of the pointer on
  the next poll (or a "published, read-back failed" status) would keep the record true.
