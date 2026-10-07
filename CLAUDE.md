## What is this repo

This is the Midas code: `github.com/BHUVAN-RJ/midas` (private), folder `~/Desktop/Midas/midas`.
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

Dates that govern: build 1 submitted Thu Oct 8, link live Oct 13 (a16z Tech Week), build 2
submitted Thu Oct 22, VC application Nov 2. Build 1 has zero slack: a suggestion that adds scope
before Nov 2 must say which item it displaces.

The founder's full plan and design history, essays, word list for public copy, working rules and
market intel live in the private repo `github.com/BHUVAN-RJ/midas-intel` (folder
`~/code/midas-intel`). Read its `docs/designs/jess-personal-assistant-shell.md` only when
`docs/PRODUCT.md` does not answer a product question, and update `docs/PRODUCT.md` here when a
founder decision changes what is being built.

## How to work with the founder (short version; full rules in midas-intel `CLAUDE.md`)

- Information, not judgment: no unrequested feedback, opinions, threat ratings or recommendations.
  Give facts, dates and sources; the founder decides what they mean. When he asks, be straight.
- Discouraging news only if fatal to the plan (9-10/10): state it plainly, mark FATAL-LEVEL, stop.
- Leave room for his thinking: at most one open question about how Midas would approach something.
- When work drifts, point back neutrally to the next concrete Midas step and its date.

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
