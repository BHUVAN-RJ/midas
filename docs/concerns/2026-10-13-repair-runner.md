# Concerns from the repair-runner agent (2026-10-13)

Out-of-brief findings while planning the Mac mini repair runner. Founder picks these up later if
they turn out to matter. Feature: `docs/PRODUCT.md` section 2, "Plan additions, 2026-10-13:
repair"; contract: `docs/briefs/repair-contract.md`.

## 1. No staging step before a user sees a repair (raised 2026-10-13)

Settled 2026-10-13: Sidekick user copies are not deployed to staging (staging has its own
accounts, so the reporter's user id does not exist there). A repaired page therefore goes from
the Mac mini straight to the reporter's live per-user pointer. The only guards before the user
sees it are: the deploy gate (`bundle-tools.mjs`: no `<script ` with attributes, `import`,
`require`, `WebSocket`; manifest valid), the Reminders tests in `backend/test/reminders-*.test.ts`
run against the fixed page. Since the founder's later decision the same day (the runner publishes
the fix itself, no founder step), nobody reads the diff before the user gets the page, and
nothing runs the fixed page on a phone first. The way back is one command, listed in
`summary.md`: `deploy-sidekick.mjs <id> --env live --user <uid> --from-base`. Revisit if a repair
ever breaks a user's page.

## 2. Network limit on the repair agent is by tool allowlist, not an OS sandbox (raised 2026-10-13)

The agent runs `claude -p` with Bash limited to two commands (`intel`, `check`) and WebFetch,
WebSearch and Agent denied. macOS offers no supported per-process network sandbox for this
(`sandbox-exec` is deprecated). If a stricter boundary is wanted later: run the agent in a
container or a separate macOS user with no credentials.

## 3. Anthropic terms on unattended Max subscription use (raised 2026-10-13)

**Handled (founder, 2026-10-19):** "I am not running it unattended, I will be there." The founder
is present while the runner works.

midas-intel `docs/research/2026-10-13-repair-agent-hosting.md`, section 2: no primary source says
whether the founder's own `claude -p` on Max, started automatically by another user's report, is
"ordinary, individual usage". Founder chose the subscription (2026-10-13). Switching to an API
key is one environment variable (`ANTHROPIC_API_KEY`) in the runner's env file.

## 4. Agent and its tests can read the runner's env file (raised 2026-10-20)

**Built (founder go, 2026-10-22), merged from `agent/repair-data`:** agent file tools limited to
the job folder with secret folders denied (Read, Grep, Bash `cat` refused, shown by the founder's
`check-sandbox.mjs --agent` run, 2026-10-22); the copy's vitest under the macOS sandbox
(`sandbox-exec`: no home reads, no writes outside its sandbox, no network); the runner refuses to
start without a working sandbox. `runner/lib/sandbox.mjs`; check with
`node runner/bin/check-sandbox.mjs [--agent]`.

Before: since 2026-10-20 (`runner/lib/safe-env.mjs`) the agent and the sandbox vitest got their
environment from allow-lists (no `MIDAS_RUNNER_TOKEN` or `CLAUDE_CODE_OAUTH_TOKEN` in
`process.env`), but the agent's file tools had no path limit and a test the agent wrote could read
`~/.midas-runner/env` from disk and print it or send it with `fetch`.

## 5. The runner can go offline unnoticed (raised 2026-10-23)

**To do, founder (2026-10-23): "add these to the to dos and we will come back to it later".**
Goal (founder): live and staging always accept and solve repairs; the runners never go offline.

State on 2026-10-23: one launchd agent (`com.midas.repair-runner`, `KeepAlive`) on the Mac mini
polls live and staging every 30 s, one job at a time; clone updated by hand to `6c15a4c` and
restarted that day (it was 38 commits behind). Live claims returned 500 until 22:40 on 2026-10-22,
cause not found (live D1 not read); none after the restart.

| Gap | Today |
|---|---|
| Unplanned restart (power cut, macOS update) | FileVault on, no auto-login: Mac waits at login, runner offline until the founder logs in |
| macOS installs updates overnight | restarts into the case above |
| Disk full (happened 2026-10-22) | jobs fail, nobody told |
| Runner down or claims failing | only in `~/Library/Logs/midas-runner/runner.log`; the live 500s went unnoticed |
| Clone falls behind main | pulled by hand only |
| Long live job (up to 30 min) | staging waits; jobs queue, nothing lost (accepted) |

Proposed, not started (needs founder go):
1. Offline alert: each claim records "runner last seen" per environment on the server; a
   scheduled Worker check tells the founder when a runner has not been seen for 10 minutes or keeps
   failing. Needs a migration, a route change and a cron trigger: staging then live deploys.
2. Health line: hourly log line (polls OK, free disk, code version); refuse a job under 5 GB free.
3. Stale-code warning when `origin/main` is ahead of the clone; pulling stays by hand.

Founder's own settings: FileVault (off allows auto-login; or `sudo fdesetup authrestart` before a
planned restart) and turning off automatic macOS update installs.
