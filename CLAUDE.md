## What is this repo

This is Midas. Three names, do not mix them up:

- **Midas** is the platform: the app builder, the iPhone shell and the backend. This is the product.
- **jess** is the assistant, an interface layer on top of Midas. Demoted, to be returned to later.
- **Sidekicks** are the mini apps Midas builds.

The product is: a user asks for a small personal app in their own words, Midas generates it,
deploys it privately (no public URL, no directory), and keeps it working. Target is an iPhone
shell (SwiftUI + WKWebView), backend is Hono on Cloudflare Workers with D1 and R2. The repo is
`github.com/BHUVAN-RJ/midas` (private) and the folder is `~/Desktop/midas`. The design doc
filename still says jess, and SUPERSEDED sections of the doc use jess for the whole product.

To resume work, read `## Pick up here` at the top of `docs/week0-checklist.md` first: it holds
the current state, the next step and the questions the founder has not answered.

The plan lives in `docs/designs/jess-personal-assistant-shell.md`. Before answering ANY question
about product, strategy, competitors, scope or architecture, read it in its own read order:

0. `## Architecture Decisions, 2026-10-04: Hand-built Build 1, Cross-app Read, Reversibility` (latest founder calls, wins over the Re-plan where they conflict)
1. `## v1 Re-plan, 2026-09-25: the Nov 2 Deadline` (current build plan, calendar, SDK v0, success criteria)
2. `## Revision, 2026-09-24: From Assistant to Infrastructure` (current thesis)
3. `## Infrastructure: How the Complexity Actually Gets Deleted` (architecture)
4. `## Sidekicks: the Product Noun, 2026-09-29`
5. `## Landscape Update, 2026-10-01: OpenAI DevDay`
6. `## Landscape Update, 2026-10-03: Connectors and Agent-Operated Builders`
7. `## Competitor Record: Wabi, 2026-10-04` (closest competitor, threat analysis)
8. `## GSTACK REVIEW REPORT`

Sections marked SUPERSEDED are history; never build or advise from them. Also read
`docs/week0-checklist.md`.

Dates that govern: build 1 submitted Thu Oct 8, link live Oct 13 (a16z Tech Week),
build 2 submitted Thu Oct 22, VC application Nov 2.

Before suggesting anything, check it against decisions already in the plan. In particular:
v0 has no assistant-driven app actions (the assistant builds and edits apps, it does not drive
them); cross-app read with user consent is in as of 2026-10-04, while cross-app actions, Siri
exposure and MCP exposure are "down the line"; build 1 ships hand-written Sidekicks and the
generator lands after Oct 8, before Nov 2; build 1 has zero slack. A suggestion that adds scope before Nov 2 must say which item it displaces.

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
