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
run against the fixed page, and the founder reading the diff in the job's `summary.md` before
running the live deploy command. Nothing runs the fixed page on a phone first. Known way to
preview with no new mechanism: deploy the fix to the founder's own live user id first, then to
the reporter's (same command, two user ids); the runner's `summary.md` lists the commands in that
order. Revisit if a repair ever breaks a user's page.

## 2. Network limit on the repair agent is by tool allowlist, not an OS sandbox (raised 2026-10-13)

The agent runs `claude -p` with Bash limited to two commands (`intel`, `check`) and WebFetch,
WebSearch and Agent denied. macOS offers no supported per-process network sandbox for this
(`sandbox-exec` is deprecated). If a stricter boundary is wanted later: run the agent in a
container or a separate macOS user with no credentials.

## 3. Anthropic terms on unattended Max subscription use (raised 2026-10-13)

midas-intel `docs/research/2026-10-13-repair-agent-hosting.md`, section 2: no primary source says
whether the founder's own `claude -p` on Max, started automatically by another user's report, is
"ordinary, individual usage". Founder chose the subscription (2026-10-13). Switching to an API
key is one environment variable (`ANTHROPIC_API_KEY`) in the runner's env file.
