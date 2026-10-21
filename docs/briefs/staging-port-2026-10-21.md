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

1. R J's Reminders copy: decided (fix into the base, follow-up below); after the base deploy, the
   `--from-base` reset of R J's copy is the lead's to run.
2. Deletions, if wanted (founder only): the three disposable accounts. Their rows sit in `users`,
   `passkeys`, `sessions`, `assignments`, `ops` (append-only, trigger blocks updates only),
   `voice_logs`. Nothing in R2 belongs to them (no copies).
3. Repair report `13edb182`: corrected (follow-up below).

## Follow-up, same day (lead, founder decisions 2026-10-21)

1. **Title wrap in the base.** PRODUCT.md "Repairs that fix wrong behaviour go to the base": R J's
   repair diff applied to `sidekicks/reminders/index.html` (applies cleanly; `tools.js` untouched,
   bundle and tools checks pass). The copy's three cases are now `backend/test/reminders-title-wrap.test.ts`
   (case 1 fails on the old base, which has `<input id="edit-input"`). Once the lead deploys the
   base to staging, R J's copy holds nothing the base lacks: `deploy-sidekick.mjs reminders --env
   staging --user 9-GAkqjLqjvn6Hyr9-AbTg --from-base` then loses nothing and brings the agent block
   and `tools.js`.
2. **Repair status mismatch.** Cause, from the runner log of `13edb182`
   (`~/Library/Application Support/midas-runner/log/13edb182-…/`): the deploy script wrote the copy
   and `current.json` last and exited 0; the read-back (wrangler, the 2026-10-19 npx-prompt era)
   returned nothing, so `publishFix` returned "could not be read back" and the runner posted
   `failed / deploy failed`. The backend only records what the runner posts (`fix_ready →
   deployed_live` already inserts the user's notice), so the fix is in the runner:
   `runner/lib/deploy.mjs` retries the read-back 3 times; if it never answers but the script exited
   0 and printed `deployed <id> <version> for user <reporter>`, the publish counts (`readBack:
   "unconfirmed"`), the runner posts `deployed_live` (the user's done notice) and says "read-back
   unconfirmed" in `summary.md` and the Mac notification. A pointer naming other files is still a
   failure, and so is a script line naming the other environment (merged with Agent A's
   runner-both). Founder line: PRODUCT.md "A published repair is always marked done (founder,
   2026-10-21)". Tests: `backend/test/runner-publish-readback.test.ts` and
   `runner-publish-readback-env.test.ts` (new); the old case in `runner-deploy.test.ts` that pinned
   "unreadable ends failed" changed through test-guardian (accepted on that founder line; its
   break-the-code proof run was blocked by the permission system, the old suite passing with
   `failed` asserted on the old code is the evidence). `runner/README.md` updated.
4. **Shell suite "TEST FAILED" (two runs):** no test case failed. Run alone on "iPhone 17" with
   its own DerivedData: 610 tests, 0 failures. The next full run after the merge passed too (610,
   0). The two failing runs overlapped other sessions' `xcodebuild` (shared default DerivedData and
   simulator); not reproduced, not checked on main separately.
5. **Suite at commit:** guard 34 OK, backend 851/851, shell 610/0 failures, midas-intel 31 OK.
3. **Staging report corrected:** `UPDATE repair_reports SET status = 'deployed_live', fail_reason =
   NULL` for `13edb182` (was `failed` / `deploy failed`), 2026-10-21 22:25:37 UTC, 1 row. No
   `repair_events` row was added, so no late done notice goes to R J's phone.

## Code changes to consider (not made)

- `backend/scripts/plan-user-copies.mjs` / `user-copy-plan.mjs`: flag a copy whose manifest lacks
  the `agent` block or whose pointer has no `tools.js` while the base has them. Today it says
  "no gaps" for R J's copy.
- (Done in the follow-up above: the runner's read-back failure no longer marks a published copy
  failed.)
- Agent A (`agent/runner-both`) edits the runner too; `runner/lib/deploy.mjs` `publishFix` and
  `run-job.mjs` around the deployed_live post may conflict at merge.
