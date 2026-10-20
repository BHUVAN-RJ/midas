# Repair runner (Mac mini)

Waits for repair requests, runs Claude Code on the user's copy of the Sidekick, checks the result,
publishes it to that user's live copy, checks it landed and marks the repair done. Contract:
`docs/briefs/repair-contract.md`. Only ever the reporter's copy; never the base.

```
launchd (KeepAlive) → runner/bin/runner.mjs
  every 30 s: POST /repairs/jobs/claim
  job → ~/Library/Application Support/midas-runner/jobs/<id>/
          sidekick/index.html, manifest.json     the reporter's current copy
          report/transcript.txt, report.json, and when the phone sent them:
          strokes.json, screenshot.png, drawing.png (a feature request may be voice only)
          tests/*.test.ts, tests/TEST_CHANGES.md    the copy's own tests, fetched with the clone's
                                                   fetch-sidekick-copy.mjs (a copy with none stored
                                                   gets the base's tests from the clone)
          .claude/                                  test guard hook + test-guardian, from the clone
        the page gets today's store helper if it holds an older one (store-helper.txt)
        claude -p (opus, 50 turns, 30 min, tools: files + intel + check + Agent(test-guardian))
          prompt: runner/agents/<sidekick id>.md (reminders, care-reminders) with the copy's types
        outcome.json → every pre-existing test byte-identical, or changed with a guardian log entry
        → manifest types only grew (add only), every literal record write is declared
        → check (deploy gate + every test in tests/, in a sandbox checkout)
        → GET /repairs/<id>/records: every record the reporter has, older shapes upgraded in
          memory, passes the new schema (records-check.json) → fix_ready
        → deploy-sidekick.mjs <id> --env live --user <reporter> --dir <job>.deploy
          (<job>.deploy = index.html, manifest.json, tests/ staged from the job folder, removed after)
        → read back users/<reporter>/current.json, compare content hash → deployed_live | failed
  log  → ~/Library/Application Support/midas-runner/log/<id>/
          summary.md (request, transcript, outcome, what went live, way back, diff), diff.patch,
          store-helper.txt, records-check.json,
          agent-stream.jsonl, system-prompt.md, check-output.txt, deploy-output.txt, failure.json
```

## Set up once (Mac mini)

1. Clone the repo somewhere launchd can read (not `~/Desktop`), e.g.
   `git clone https://github.com/BHUVAN-RJ/midas.git ~/Library/Application\ Support/midas-runner/midas`
   and `cd backend && npm install`. Also `~/code/midas-intel` for the intel tool. The deploy
   step runs the checkout's `deploy-sidekick.mjs`, which uses wrangler: `npx wrangler login` once
   on the Mac mini, as the account that owns the live bucket.
2. Claude Code: `CLAUDE_CONFIG_DIR=~/.midas-runner/claude claude setup-token` and put the printed
   token in the env file below. This config dir is the runner's own: none of your plugins, hooks
   or memory load into the repair agent.
3. `~/.midas-runner/env`:

   ```
   MIDAS_BACKEND_URL=https://midas-api.midas-backend.workers.dev
   MIDAS_RUNNER_TOKEN=<runner token, same as the Worker secret>
   CLAUDE_CODE_OAUTH_TOKEN=<from claude setup-token>
   CLAUDE_CONFIG_DIR=/Users/<you>/.midas-runner/claude
   # live (default, the everyday Midas) or staging (the "Midas Test" app); must match MIDAS_BACKEND_URL
   MIDAS_RUNNER_ENV=live
   # optional: MIDAS_RUNNER_MODEL=opus  MIDAS_RUNNER_MAX_TURNS=50  MIDAS_RUNNER_JOB_TIMEOUT_MS=1800000
   # optional: MIDAS_RUNNER_CHECKOUT=<repo path if runner/ is not inside it>
   ```

4. `runner/install.sh` (from that clone). Log: `~/Library/Logs/midas-runner/runner.log`.
   Remove: `runner/install.sh --uninstall`.

Try one job by hand: `node runner/bin/run-once.mjs`.

## When a fix is live

The Mac shows a notification saying what was fixed and that it is live for the reporter. Open
`log/<id>/summary.md`: the user's words, what the agent did, the version that went live, the diff.
Way back, from `backend/` in the runner's clone (puts that user back on the base):

```
node scripts/deploy-sidekick.mjs reminders --env live --user <reporter id> --from-base
```

## Statuses the runner posts

`running` (and every 5 minutes while working, as a heartbeat), then `fix_ready` with the agent's
summary once the check passes, then `deployed_live` with `{ summary, version }` once the reporter's
`current.json` on live names the published files (the backend turns that into the user's notice
and the founder's event), or `failed` with `{ reason, detail }`. Reasons: `unsupported` (detail =
what the user asked for, in their words; what the shell or SDK is missing goes to `summary.md`
and the Mac notification), `no change`, `check failed`, `test changed` (an existing test differs
from what the job started with and `tests/TEST_CHANGES.md` has no test-guardian entry for it, or
a test or log entry was deleted), `deploy failed` (the script failed, or the read-back did not
match), `agent timed out`, `agent exited with an error`, `agent wrote outside the Sidekick`,
`bad outcome`, `bundle missing`, `tests missing` (the fetch script failed), `transcript missing`,
`schema not backward compatible` (the copy's manifest `types` lost or narrowed something; detail
lists each change), `schema missing` (the page writes a record prefix the manifest does not
declare), `records unreadable` (the records route did not answer), `records do not fit schema`
(detail names the first records and why), `runner error`.

## Data rules (unified data, founder 2026-10-15 and 2026-10-19)

A repair may add to a copy's schema (optional fields, new types) and must declare them in the
copy's `manifest.json` `types` in the same change. It may never remove, rename, retype or narrow
anything, or add a required field, with or without a migration (founder decision 2026-10-19,
`docs/PRODUCT.md`): `runner/lib/schema-change.mjs` refuses it, in one function,
`breakingChangeVerdict`. Before publishing, every record the reporter has must pass the new
schema; records still in an older shape are upgraded in memory first with
`backend/scripts/record-upgrades.mjs` (nothing is written). The records come from
`GET /repairs/<id>/records`, runner token only, that reporter and that Sidekick only, so the Worker
with that route must be deployed before the runner runs.

A copy made before an SDK change holds an older store helper; the runner swaps in today's
`shell/sdk/midas-store.js` before the agent starts so the copy's own tests (which pin it) pass.
The swap is published with the fix and named in `summary.md`, not in the diff.

Existing user copies: `cd backend && node scripts/plan-user-copies.mjs --env staging|live`
(read-only) lists each copy and prints the commands that bring it to today's rules.

## Tests move with the copy

The repair agent may add test files in `tests/`, never change or delete one. An existing test
that blocks the user's request goes to the `test-guardian` subagent, which accepts or refuses
and logs in `tests/TEST_CHANGES.md`. The runner compares every pre-existing test byte for byte
after the agent; a change counts only when the log kept every old line and gained a line naming
that file. The tests and the log are deployed with the page (`--dir` reads `tests/`).

Kinds (`bug`, `change`, `feature`, or unknown) are a hint from the phone; the agent decides from
the transcript. A feature the page can hold on the store is built; one that needs the shell or
SDK ends `failed` / `unsupported`.

## Switching to an API key

Set `ANTHROPIC_API_KEY` in the env file and remove `CLAUDE_CODE_OAUTH_TOKEN`. The runner removes
`ANTHROPIC_API_KEY` from the agent's environment unless `MIDAS_RUNNER_USE_API_KEY=1` is set.
