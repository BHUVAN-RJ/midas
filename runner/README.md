# Repair runner (Mac mini)

Waits for repair requests, runs Claude Code on the user's copy of the Sidekick, checks the result,
publishes it to that user's live copy, checks it landed and marks the repair done. Contract:
`docs/briefs/repair-contract.md`. Only ever the reporter's copy; never the base.

```
launchd (KeepAlive) → runner/bin/runner.mjs
  every 30 s: POST /repairs/jobs/claim
  job → the copy's manifest declares types, else failed "copy has no schema"
      → ~/Library/Application Support/midas-runner/jobs/<id>/
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
        → manifest types only grew (add only, against the baseline the runner holds in memory),
          every literal record write is declared
        → check (deploy gate + every test in tests/, in a sandbox checkout)
        → GET /repairs/<id>/records: no new field or prefix clashes with a stored record, and
          every record the reporter has passes the new schema (records-check.json) → fix_ready
        → deploy-sidekick.mjs <id> --env live --user <reporter> --dir <job>.deploy
          (<job>.deploy = index.html, manifest.json, tests/ staged from the job folder, removed after)
        → read back users/<reporter>/current.json, compare content hash → deployed_live | failed
  log  → ~/Library/Application Support/midas-runner/log/<id>/
          summary.md (request, transcript, outcome, what went live, way back, diff), diff.patch,
          store-helper.txt, records-check.json, manifest-baseline.json (read-only, for the check tool),
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
   # live (default, the everyday Midas) or staging (the "Midas Test" app). Must be the environment
   # of MIDAS_BACKEND_URL's Worker: the runner refuses to start otherwise (records would come from
   # one environment and the fix would go to the other)
   MIDAS_RUNNER_ENV=live
   # optional: MIDAS_RUNNER_MODEL=opus  MIDAS_RUNNER_MAX_TURNS=50  MIDAS_RUNNER_JOB_TIMEOUT_MS=1800000
   # optional: MIDAS_RUNNER_CHECKOUT=<repo path if runner/ is not inside it>
   # optional: MIDAS_RUNNER_TOOL_LINKS=<folder without spaces for the agent's tool link; default ~/.midas-runner>
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

The clone's path has a space ("Application Support"), so the agent reaches its two tools through
a link, `~/.midas-runner/runner-tools` -> `<clone>/runner/tools`, which the runner makes before
each job; the prompt gives the exact commands and the agent's allow rules match them. Every
wrangler call runs from `<checkout>/backend` with `npx --no-install`, so a missing wrangler fails
at once instead of waiting on npx's install prompt; the read-back gives up after 2 minutes.

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
`copy has no schema` (the copy's manifest has no `types`; it needs the schema pass first, see
`plan-user-copies.mjs` below), `schema not backward compatible` (the copy's manifest `types` lost
or narrowed something, a new field is one a stored record already holds, or a new prefix overlaps
an old one or claims stored keys; detail lists each), `schema missing` (the page writes a record
prefix the manifest does not declare), `records unreadable` (the records route did not answer, or
answered 413 `records too large`: over 4 MB of record text), `records do not fit schema` (detail
names the first records and why), `runner error` (also: the checkout lacks the validator or the
store helper).

## Data rules (unified data, founder 2026-10-15 and 2026-10-19)

A repair may add to a copy's schema (optional fields, new types) and must declare them in the
copy's `manifest.json` `types` in the same change. It may never remove, rename, retype or narrow
anything, or add a required field or a `not`, with or without a migration (founder decision
2026-10-19, `docs/PRODUCT.md`): `runner/lib/schema-change.mjs` refuses it, in one function,
`breakingChangeVerdict`. Key order and the order of a `type` list are not changes. A new prefix
may not share a start with an old one (`reminder:a` next to `reminder:`). Before publishing, the
reporter's stored records are checked twice: no record may already hold a field the repair adds
(pages keep unknown fields, so the name may mean something else there) or have a key a new prefix
would claim (both refused through `breakingChangeVerdict`), and every record, as stored, must pass
the new schema (nothing is written). Records still only on a phone that has not synced are not
seen. The records come from `GET /repairs/<id>/records`, runner token only,
that reporter and that Sidekick only, so the Worker with that route must be deployed before the
runner runs. The validator and the store helper come from the checkout the runner
tests and deploys from (`MIDAS_RUNNER_CHECKOUT`, default this clone), never from another repo. The
baseline the add-only check compares with is the copy's manifest before the agent, kept in the
runner's memory; the agent's check tool reads a read-only copy in the log folder.

A copy made before an SDK change holds an older store helper; the runner swaps in today's
`shell/sdk/midas-store.js` before the agent starts so the copy's own tests (which pin it) pass.
The swap is published with the fix and named in `summary.md`, not in the diff.

Existing user copies: `cd backend && node scripts/plan-user-copies.mjs --env staging|live`
(read-only) lists each copy and prints the commands that bring it to today's rules. It prints a
deploy only for a copy whose one gap is an older store helper, after the same schema rules and a
check of that user's records (read from D1) against the copy's types. A copy without `types`
needs the schema pass first: its types written from its page and the user's records (the planner
prints those records against the base's types as a start); the runner refuses it until then.

## Tests move with the copy

The repair agent may add test files in `tests/`, never change or delete one. An existing test
that blocks the user's request goes to the `test-guardian` subagent, which accepts or refuses
and logs in `tests/TEST_CHANGES.md`. The runner compares every pre-existing test byte for byte
after the agent; a change counts only when the log kept every old line and gained a line naming
that file. The tests and the log are deployed with the page (`--dir` reads `tests/`).

Kinds (`bug`, `change`, `feature`, or unknown) are a hint from the phone; the agent decides from
the transcript. A feature the page can hold on the store is built; one that needs the shell or
SDK ends `failed` / `unsupported`.

## What the agent can see

The agent's environment is an allow-list (`runner/lib/safe-env.mjs`): PATH, HOME and the other
plain settings, the job's own variables, the runner's Claude config dir and Claude's own login.
Never `MIDAS_RUNNER_TOKEN` or anything else from `~/.midas-runner/env`. The vitest that runs the
copy's tests, which the agent may write, gets only the plain settings, with no token at all,
whether the runner or the agent's check tool starts it.

## Switching to an API key

Set `ANTHROPIC_API_KEY` in the env file and remove `CLAUDE_CODE_OAUTH_TOKEN`. The runner removes
`ANTHROPIC_API_KEY` from the agent's environment unless `MIDAS_RUNNER_USE_API_KEY=1` is set.
