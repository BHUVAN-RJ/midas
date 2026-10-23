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

## 4. Agent and its tests can still read the runner's env file (raised 2026-10-20)

**Built (founder go, 2026-10-22), on `agent/repair-data`:** agent file tools limited to the job
folder with secret folders denied; the copy's vitest under the macOS sandbox (no home reads, no
writes outside its sandbox, no network); runner refuses to start without a working sandbox.
`runner/lib/sandbox.mjs`; check with `node runner/bin/check-sandbox.mjs [--agent]`. Still open: the
agent's permission rules are proved only by the founder's `--agent` run, not by the suite.

Item 13 (`24cd209`) keeps tokens out of the agent's and sandbox vitest's environment only. The
agent's file tools (Read, Write, Edit) have no path limit, and tests the agent writes run in vitest
with full file and network access. Either could read `~/.midas-runner/env` (`MIDAS_RUNNER_TOKEN`,
`CLAUDE_CODE_OAUTH_TOKEN`) and a test could send it out. Closing it needs a file-path deny rule for
the agent plus an OS boundary for the tests (separate macOS user with no access to the env file, or
a container). Offered to the lead as a next item; not started. Pick up before the runner works on
reports from anyone but the founder.
