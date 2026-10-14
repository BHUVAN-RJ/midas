# Repair runner (Mac mini)

Waits for repair requests, runs Claude Code on the user's copy of the Sidekick, checks the result
and leaves it for the founder to deploy. Contract: `docs/briefs/repair-contract.md`. Never
deploys; stops at `fix_ready`.

```
launchd (KeepAlive) → runner/bin/runner.mjs
  every 30 s: POST /repairs/jobs/claim
  job → ~/Library/Application Support/midas-runner/jobs/<id>/
          sidekick/index.html, manifest.json     the reporter's current copy
          report/transcript.txt, report.json, and when the phone sent them:
          strokes.json, screenshot.png, drawing.png (a feature request may be voice only)
        claude -p (opus, 50 turns, 30 min, tools: files + intel + check)
        outcome.json → check (deploy gate + backend/test/<sidekick>-*.test.ts) → fix_ready | failed
  log  → ~/Library/Application Support/midas-runner/log/<id>/
          summary.md (request, transcript, outcome, diff, deploy commands), diff.patch,
          agent-stream.jsonl, system-prompt.md, check-output.txt, failure.json
```

## Set up once (Mac mini)

1. Clone the repo somewhere launchd can read (not `~/Desktop`), e.g.
   `git clone https://github.com/BHUVAN-RJ/midas.git ~/Library/Application\ Support/midas-runner/midas`
   and `cd backend && npm install`. Also `~/code/midas-intel` for the intel tool.
2. Claude Code: `CLAUDE_CONFIG_DIR=~/.midas-runner/claude claude setup-token` and put the printed
   token in the env file below. This config dir is the runner's own: none of your plugins, hooks
   or memory load into the repair agent.
3. `~/.midas-runner/env`:

   ```
   MIDAS_BACKEND_URL=https://midas-api.midas-backend.workers.dev
   MIDAS_RUNNER_TOKEN=<runner token, same as the Worker secret>
   CLAUDE_CODE_OAUTH_TOKEN=<from claude setup-token>
   CLAUDE_CONFIG_DIR=/Users/<you>/.midas-runner/claude
   MIDAS_FOUNDER_USER_ID=<your live user id, for the preview step>
   # optional: MIDAS_RUNNER_MODEL=opus  MIDAS_RUNNER_MAX_TURNS=50  MIDAS_RUNNER_JOB_TIMEOUT_MS=1800000
   # optional: MIDAS_RUNNER_CHECKOUT=<repo path if runner/ is not inside it>
   ```

4. `runner/install.sh` (from that clone). Log: `~/Library/Logs/midas-runner/runner.log`.
   Remove: `runner/install.sh --uninstall`.

Try one job by hand: `node runner/bin/run-once.mjs`.

## When a fix is ready

The Mac shows a notification. Open `log/<id>/summary.md`: the user's words, what the agent did,
the diff, and the commands. From `backend/` in the runner's clone:

```
node scripts/deploy-sidekick.mjs reminders --env live --user <your id> --dir <job>/sidekick   # preview on your phone
node scripts/deploy-sidekick.mjs reminders --env live --user <reporter id> --dir <job>/sidekick
```

## Statuses the runner posts

`running` (and every 5 minutes while working, as a heartbeat), then `fix_ready` with the agent's
summary, or `failed` with `{ reason, detail }`. Reasons: `unsupported` (detail = what the user
asked for, in their words; what the shell or SDK is missing goes to `summary.md` and the Mac
notification), `no change`, `check failed`, `agent timed out`, `agent exited with an error`,
`agent wrote outside the Sidekick`, `bad outcome`, `bundle missing`, `transcript missing`,
`runner error`.

Kinds (`bug`, `change`, `feature`, or unknown) are a hint from the phone; the agent decides from
the transcript. A feature the page can hold on the store is built; one that needs the shell or
SDK ends `failed` / `unsupported`.

## Switching to an API key

Set `ANTHROPIC_API_KEY` in the env file and remove `CLAUDE_CODE_OAUTH_TOKEN`. The runner removes
`ANTHROPIC_API_KEY` from the agent's environment unless `MIDAS_RUNNER_USE_API_KEY=1` is set.
