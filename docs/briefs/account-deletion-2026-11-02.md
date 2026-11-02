# Account deletion carried out in code (founder, 2026-11-02)

Branch `agent/account-deletion`. For the lead: copy the decisions below into `docs/PRODUCT.md`
(build 22, "Settings and delete") and the midas-intel design doc when merging.

## Founder decisions, 2026-11-02

1. **When a person deletes their account (Settings, Delete Account), all their data is deleted
   within 7 days, without breaking anything else.** (Founder goal, 2026-11-02.)
2. **Only that person's data is deleted; nothing else is touched.** (Founder, 2026-11-02.)
3. **The founder is notified when a person asks, notified when the deletion is done, and can check
   that it is in fact deleted.** (Founder, 2026-11-02.)
4. **Account deletion removes the person's rows for real**, including their op log (`ops`): the one
   exception to "the op log is append only" (2026-10-04) and to "the Worker never deletes" (no data
   loss, 2026-10-10). It runs only when the founder carries out a request the person made, through
   the founder's script and a founder-only token; the founder's own account is never deleted
   this way. (Founder approved the plan with this default, 2026-11-02: "Go ahead and build".)
5. **The Cloudflare plan is Workers Free** (founder, 2026-11-02): D1 Time Travel keeps 7 days of
   point-in-time history, Workers Logs 3 days.
6. Defaults the founder approved with the build: the founder runs it with a script
   (`backend/scripts/delete-account.mjs`); a day-6 reminder push (needs a cron trigger in
   `wrangler.jsonc`, lead only).

## What was built

- Migration `0014_account_deletion.sql` (additive): `account_deletions_done` (no name, no foreign
  key; counts, the person's Edit report ids, push outcome, runner clean-up), and `last_error`,
  `reminded_at` on `account_deletion_requests`.
- `backend/src/account-deletion.ts`: founder-token routes `GET /account-deletions` (open and done),
  `GET /account-deletions/:userId` (what the person still has: preview before, check after),
  `POST /account-deletions/:userId/carry-out`; runner-token routes for the Mac mini clean-up; the
  daily reminder.
- `backend/src/account.ts`: a repeat request re-sends an alert that reached no phone.
- `backend/scripts/delete-account.mjs`: the founder's tool.
- `runner/lib/forget.mjs` + the runner loop: removes the person's job folders, logs and Claude
  transcripts on the Mac mini and reports back.

## What it deletes (person U)

D1, matched on U exactly: users, passkeys, sessions, auth_challenges, assignments,
sidekick_removals, ops, voice_logs, jess_requests, jess_pending_requests, repair_reports,
repair_events (by U's report ids), repair_blocked, push_devices, make_events (user or about U),
account_deletion_requests; the founder's `make-inbox` ops whose key's user segment is U (a delete
marker is written first so the founder's phone drops them; the marker keeps the key, no value).
R2: FILES `U/…`; FILES `<founder>/…` with `copiedFrom = U`; BUNDLES `sidekicks/<id>/users/U/…`;
BUNDLES `repairs/<reportId>/…` for U's reports. Mac mini: `jobs/<reportId>`, `log/<reportId>`,
the Claude project folder of each job. Founder's Macs: `~/midas-backups` (see the script).

## Lead-only follow-ups

- `wrangler.jsonc`: `"triggers": { "crons": ["0 15 * * *"] }` on both environments (daily
  reminder). Done by the lead, origin/main 9c1a203.
- `wrangler secret put ACCOUNT_DELETION_TOKEN` (and `--env staging`); the founder keeps the same
  value as `MIDAS_LIVE_DELETION_TOKEN` / `MIDAS_STAGING_DELETION_TOKEN` in his shell for the script.
- `docs/PRODUCT.md` + midas-intel design doc: decisions 1-6 above, dated 2026-11-02. Then
  test-guardian can accept the logged request in `TEST_CHANGES.md` (2026-11-02, NEEDS-EVIDENCE):
  `no-data-loss.test.ts` fails until it allows the 17 statements in `src/account-deletion.ts` only.
- The Mac mini runner picks up `runner/lib/forget.mjs` on its next `git pull` + restart.

## How the founder runs it

```bash
cd ~/Desktop/Midas/midas/backend && node scripts/delete-account.mjs --env live
cd ~/Desktop/Midas/midas/backend && node scripts/delete-account.mjs --env live --user <id>
cd ~/Desktop/Midas/midas/backend && node scripts/delete-account.mjs --env live --user <id> --yes
cd ~/Desktop/Midas/midas/backend && node scripts/delete-account.mjs --env live --user <id> --check
```

The founder is pushed: when a person asks ("Delete Account"); again if that push reached no phone
(next request or the daily cron); on day 6 ("Delete Account Due"); when done ("Account Deleted",
with counts); when a run stops ("Account Deletion Incomplete", items left, run again).

## Limits (true on 2026-11-02, Workers Free)

- D1 Time Travel keeps 7 days of point-in-time history; it cannot be purged. A deleted row can be
  restored from it for up to 7 days after the deletion.
- Workers Logs keep 3 days; the Worker logs ids and error text, not transcripts.
- `~/midas-backups` exports and their R2 copies (`midas-backups/<env>/...`) are rewritten only for
  the exports on the Mac the script runs on; an export taken on another laptop, kept only in R2,
  is not listed (wrangler cannot list R2). Run the script on each laptop that has
  `~/midas-backups`, or remove old exports.
- The person's phone keeps its local copy until the app is deleted.
- The founder's inbox keeps a delete marker per key (`person:<id>`, `req:<id>:<r>`): the key, no
  value.
- OpenRouter's providers and Anthropic follow their own retention.
