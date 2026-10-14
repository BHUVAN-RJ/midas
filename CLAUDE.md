## What is this repo

This is the Midas code: `github.com/BHUVAN-RJ/midas` (private), folder `~/Desktop/Midas/midas`.
It is one of two repos; the other is midas-intel (see `## Two repos` below).
Three names, do not mix them up:

- **Midas** is the platform: the app builder, the iPhone shell and the backend. This is the product.
- **Sidekicks** are the mini apps Midas builds.
- **jess** is the assistant, an interface layer on top of Midas. Demoted, to be returned to later.

A user asks for a small personal app in their own words, Midas generates it, deploys it
privately (no public URL, no directory), and keeps it working. Target is an iPhone shell
(SwiftUI + WKWebView); the backend is Hono on Cloudflare Workers with D1 and R2 (`backend/`).

**Read `docs/PRODUCT.md` first.** It is the distilled, current "what we are building": builds and
dates, scope in and out, product principles, architecture, current state and next steps. Before
suggesting anything, check it against the decisions there.

**Notifications, Live Activities, alarms, widgets or controls:** before any work on how a Sidekick
reaches its user outside the Sidekick, read `docs/NOTIFICATIONS.md` (the engine as built) and
midas-intel `docs/research/ios-notifications-reference.md` (every option iOS offers on iPhone: what
it looks like, iOS version, what it needs, status in Midas, limits, mockups, sources).

**Any text a person sees** (shell screens, Sidekick pages, notifications, generated Sidekicks): read
`docs/WRITING.md` first and follow it. Say the action and stop; no explaining lines (founder,
2026-10-10).

Dates that govern: build 1 submitted Thu Oct 8, link live Oct 13 (a16z Tech Week), build 2
submitted Thu Oct 22, VC application Nov 2. Build 1 has zero slack: a suggestion that adds scope
before Nov 2 must say which item it displaces.

The founder's full plan and design history, essays, word list for public copy, working rules and
market intel live in the private repo `github.com/BHUVAN-RJ/midas-intel` (folder
`~/code/midas-intel`). Read its `docs/designs/jess-personal-assistant-shell.md` only when
`docs/PRODUCT.md` does not answer a product question, and update `docs/PRODUCT.md` here when a
founder decision changes what is being built.

## Two repos (since 2026-10-07)

Midas lives in two private repos. Each assumes the other exists; pull both before working.

| Repo | Folder (every laptop) | What it holds |
|---|---|---|
| `github.com/BHUVAN-RJ/midas` | `~/Desktop/Midas/midas` | The product code: `backend/` (and the iPhone shell once it exists), `docs/PRODUCT.md` (the distilled current build), a short `CLAUDE.md`. |
| `github.com/BHUVAN-RJ/midas-intel` | `~/code/midas-intel` | Everything of the founder's: the plan and design history (`docs/designs/`), essays, word list, research notes, the week 0 checklist, the full working rules (`CLAUDE.md`), and market intel (`intel/` tooling, `docs/intel/` digests). |

Keeping them in sync:

- The design doc in midas-intel is the source of the plan; `docs/PRODUCT.md` in midas is its
  distilled copy for building. When a founder decision changes what is being built, update both
  in the same session. Code, tests and build files go only in midas; notes, research and intel
  go only in midas-intel.
- Start of a session on any laptop: `git pull` in both folders.
- Intel jobs run on one machine only, the founder's Mac mini (their state is per machine). Other
  laptops never run `intel/install-schedule.sh`. Digests reach other laptops only when the Mac
  mini commits and pushes midas-intel.
- On the Mac mini, do not move either folder: gbrain sources `midas` and `midas-intel` are bound
  to these paths, and launchd cannot read ~/Desktop, so scheduled jobs live in midas-intel only.

First pull on a laptop that still has the old single-repo layout:

1. `git pull` in `~/Desktop/Midas/midas`. `intel/`, `docs/designs/`, `docs/essays/`,
   `docs/intel/`, `docs/research/`, `docs/week0-checklist.md` and `docs/word-list.md` disappear
   there: they moved to midas-intel (their history stays in midas). Copy any uncommitted local
   edits to those files somewhere safe before pulling.
2. `git clone https://github.com/BHUVAN-RJ/midas-intel.git ~/code/midas-intel`, then re-apply those
   edits there.
3. If that laptop ever installed the intel schedule (`launchctl list | grep com.midas`), remove it:
   `launchctl bootout gui/$(id -u)/com.midas.intel-daily; launchctl bootout gui/$(id -u)/com.midas.intel-weekly;
   rm ~/Library/LaunchAgents/com.midas.intel-*.plist`.

## Parallel agents

Several Claude sessions can work on this repo at once. Full procedure and commands:
`docs/PARALLEL-AGENTS.md`. The short version:

- One task = one git worktree = one branch (`agent/<task>`) = one Herdr workspace. Worktrees live
  in `~/Desktop/Midas/midas-worktrees/<task>`. The lead session in `~/Desktop/Midas/midas` (on
  `main`) creates them with `herdr worktree create`, starts Claude in them with `herdr agent start`,
  merges finished branches and removes the worktrees. The founder does not run these by hand.
- Before starting several agents on one feature, settle every shared decision with the founder
  first, or start them plan-only, merge all their questions into one list and ask the founder
  once (`docs/PARALLEL-AGENTS.md`, "Shared decisions before agents start"; founder, 2026-10-13).
- A new worktree starts from the last commit: check `git status` and commit what the new agent
  needs before creating it.
- If you are in a worktree (`git rev-parse --show-toplevel` is under `midas-worktrees/`): edit only
  inside it and only the files your brief names; never edit `CLAUDE.md`, `docs/PRODUCT.md`,
  `docs/PARALLEL-AGENTS.md`, `backend/package*.json` or `backend/wrangler.jsonc`; use your own dev
  port; never merge into `main`; run the full suite (`cd backend && npm test`) before saying done.

## Tests are guarded (since 2026-10-07)

- Run every suite with `scripts/test-all.sh` after every change, and report the result honestly.
- Anyone may add a new test. Only the `test-guardian` agent (`.claude/agents/test-guardian.md`)
  may change or delete an existing test; a PreToolUse hook (`.claude/hooks/guard_tests.py`)
  blocks everyone else. To change a test, delegate to test-guardian with the test, the change,
  and the dated decision or bug that requires it. It may refuse.
- Every test change is logged in `TEST_CHANGES.md`. The git pre-commit hook rejects a commit
  that changes or deletes a test without a log entry. Activate it once per clone:
  `git config core.hooksPath .githooks`.
- The guard files themselves are changed by the founder only, by hand.

## How to work with the founder (short version; full rules in midas-intel `CLAUDE.md`)

- Information, not judgment: no unrequested feedback, opinions, threat ratings or recommendations.
  Give facts, dates and sources; the founder decides what they mean. When he asks, be straight.
- Discouraging news only if fatal to the plan (9-10/10): state it plainly, mark FATAL-LEVEL, stop.
- Leave room for his thinking: at most one open question about how Midas would approach something.
- When work drifts, point back neutrally to the next concrete Midas step and its date.
- Discuss, the founder approves, then build. No code, config, agents or hooks get written until
  the design has been discussed and the founder has explicitly said to build it. "Let's start
  with X" means start the discussion of X, not write X. Reading, research and running existing
  tests need no approval. (Added 2026-10-07.)

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
