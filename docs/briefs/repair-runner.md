# Brief: repair-runner (Mac mini: runner, Reminders repair agent, intel tool)

Read `docs/briefs/repair-contract.md` first. Dev port 8790.

Founder, 2026-10-13: runs on the founder's always-on Mac mini, Claude Code with the founder's Max
subscription (not an API key). The agent's worktree holds **only the Sidekick being repaired**.
The founder wants to see each request and each fix, and deploys live for now.

Build (after the founder approves your plan):
1. A runner (launchd LaunchAgent, KeepAlive) that claims jobs from the backend (see contract),
   downloads the screenshot, drawing, strokes and transcript, and builds a job folder with only
   that user's current copy of the Sidekick (`index.html`, `manifest.json`) plus the report.
2. Runs `claude -p` headless in that folder: fixed tool allowlist, no network beyond what is
   needed, `--max-turns`, stream-json log kept per job. One job at a time.
3. The Reminders repair agent: its system prompt (what Reminders is, its record shapes, the
   shell's capabilities and limits, SDK calls, CSP and deploy-gate rules, `docs/WRITING.md`),
   and a read-only intel tool that pulls what it needs from midas-intel
   (`docs/research/reminders/ANALYSIS.md`, primitives research, `docs/process/`) into context.
   Propose the shape (MCP server, skill, or a command) in the plan.
4. After the agent: run the Sidekick's tests, then `deploy-sidekick.mjs <id> --env staging
   --user <user_id> --dir <job folder>` (from repair-copies), set status, notify the founder
   on the Mac (macOS notification) with the request, the diff and the live deploy command.
5. Every repair is logged (report, transcript, diff, outcome); no classification yet.
6. Tests: a fake job runs end to end against a local backend with a stub agent; a failing
   Sidekick test stops the deploy; the job folder contains nothing outside the Sidekick.

Owns: new `runner/` folder (or the location you propose), new tests. Ask the lead before touching
backend code. Note in the plan: Anthropic's terms on unattended subscription use are an open
question (research doc, section 2); the founder chose the subscription.
