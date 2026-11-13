# Brief: repair lanes (founder, 2026-11-13)

Decisions: `docs/PRODUCT.md`, "Plan additions, 2026-11-13: repair lanes". Plan and animations:
`docs/mockups/repair-lanes-2026-11-08.html`, `docs/mockups/repair-ask-back-2026-11-08.html`. Data:
midas-intel `docs/research/2026-11-08-repair-jobs-review.md` (46 jobs, section 6: the sort model test).

Goal: small changes in seconds, unclear requests asked back instead of failing, and no repair ever
breaks a core feature, a primitive or a jess tool.

Order of environments: **testing** (local: `scripts/test-all.sh`, `wrangler dev`, a leased simulator),
then **staging**, then **live** (founder). Nothing goes to live before staging has passed.

## Workstreams

Each workstream is one worktree, one branch `agent/repair-<name>`, one agent. Files each one owns
are listed; touch nothing else. A new npm dependency or a `wrangler.jsonc` change is not made in the
worktree: write it in the hand-back and the lead adds it.

### W1 · Shield (`agent/repair-shield`): first, everything else relies on it

Owns: a new `runner/core-checks/` folder, `runner/lib/check.mjs`, `runner/lib/agent-check.mjs`,
`runner/tools/` check entry, new test files under `backend/test/` named `repair-shield-*.test.ts`.

- Core checks run on every repair, from the platform checkout, never copied into the person's copy.
  No repair agent and no Sidekick guardian can change them (guard hook paths updated by the founder
  by hand if needed: list the paths in the hand-back).
- Page opens: load the copy's `index.html` in WebKit (headless; Playwright WebKit or the simulator,
  agent's choice, say which and why) with the person's own records through a fake store; every view
  the manifest names draws with no console errors.
- Tools before/after: run every manifest tool on a copy of the person's records with the old and the
  new `tools.js`; answers must match unless the repair request names that tool. Every tool's
  `midas/page-actions` still exists on the new page.
- Settings engine present (`set_setting` tool and `settings:self` handling) in every Sidekick.
- Records fit, widget record still written (reuse the existing records check).
- Primitive block checks: where `docs/primitives/<primitive>/` defines block checks, run them.
- Each check must be able to fail for the reason it exists: show one failing case per check.

### W2 · Sort (`agent/repair-sort`): backend

Owns: new `backend/src/repair-sort*.ts`, a new migration, new `backend/test/repair-sort-*.test.ts`.

- When a repair report arrives, the Worker sorts it before any runner can claim it (status
  `sorting`, then the lane's status).
- Jev 1.14 through OpenRouter (`POST https://openrouter.ai/api/alpha/decisions`, model
  `typesafe/jev-1.14`): state = the transcript, the Sidekick's name and description, the drawing
  outline (stroke count and box). Questions: `lane` (choice over the seven lanes, wording as in the
  benchmark) and `guess` (choice over the card guesses).
- Confidence below 0.7 → Claude Haiku 5.5 through OpenRouter Chat Completions
  (`anthropic/claude-haiku-5.5`) with the same lanes, returning lane + up to 3 guesses as JSON.
- Secret `OPENROUTER_API_KEY` (founder sets it at the deploy step). Calls time out at 6 s; on a
  timeout or an error the request goes to `code` (up a lane, never down).
- Store lane, confidence, model used, latency and cost per report (new columns).
- Benchmark harness to reuse for the lane wording and the expected lanes: session scratchpad copy
  in the hand-back of 2026-11-13 (`sort-bench.mjs`); copy it into `backend/scripts/` as a script.

Contract with W3 (the response to a report, and the answer):

```
POST /repairs (existing)  →  { id, lane, question?, message? }
  lane:     "ask_back" | "not_a_request" | "shell_cant" | "jess_command" | "setting" | "look" | "code"
  question: { text: "What should it be?", options: [ { id, label, icon } ] }   (ask_back only)
  message:  one line for not_a_request ("Say or draw what to change.") and shell_cant
POST /repairs/:id/answer  { optionId } | { text }  →  { lane }   (same request, sorted again)
```

Unanswered for 2 minutes → `dropped`, logged. `shell_cant` → push to the founder (existing push).

### W3 · Ask-back cards on the phone (`agent/repair-askback`): shell

Owns: `shell/Midas/Repair*.swift` and a new `shell/Midas/RepairQuestionCard.swift`, shell tests.
Starts against a stub of the W2 contract; switches to staging when W2 is deployed there.

- D4 = A exactly as `docs/mockups/repair-ask-back-2026-11-08.html` column "A · Cards" and
  "A · answered": the tag reads "One question", Make's T2 card with 2–3 picture options above the
  B3 pill, the pill says "Or say it…", a tap fills the pill, Send continues as today.
- Not a request: the pill says the message and keeps listening; no tag change, no job.
- Shell can't: the dark sheet with the message, then repair mode closes.
- Builds use the "Midas Test" scheme; simulators only through `scripts/sim.sh`.

### W4 · One repair agent (`agent/repair-one-agent`): runner

Owns: `runner/lib/prompt.mjs`, `runner/agents/` (new `repair.md` shared template), a new
`runner/lib/person-notes.mjs`, new `backend/test/runner-one-agent-*.test.ts`.

- One shared template for every Sidekick. The prompt adds the Sidekick's manifest (agent block,
  types, settings) and the primitive docs it was built from (`docs/primitives/<primitive>/`).
- Person's notes: a short dated log kept with the person's copy ("Search tab hidden, Nov 7. Search
  stays in the top bar."); each repair reads it and appends one line. Agent decides where it is
  stored with the copy; say where in the hand-back.
- The per-Sidekick files stay until W4 is live, then are removed in one change.
- Note: the main checkout has uncommitted work on `runner/lib/prompt.mjs` (another session, the
  To-Do agent line); expect a merge on that file.

### W5 · Settings lane (after W1)

Every Sidekick's manifest gets a `settings` catalogue (key, type, allowed values, default, the page
part it changes). `set_setting` is core in Reminders, Care, Water and To-Do (restore it on the copy
from repair `42396937`). The setting lane maps the words to `{ key, value }` with Haiku and writes
`settings:self`; the page redraws live; Undo puts the old value back. Colour, size, show/hide and
date format for every named part.

### W6 · Look lane (last)

Named page parts (`data-part`) and a per-person style and words record; the agent edits only that
record. Checks: CSS parses, no `url()`, every part exists, the page still opens (W1).

### W7 · Publish first (founder, 2026-11-13; after W1 and W4 are merged)

Goal: the fixed copy reaches the person as fast as possible; everything that does not protect them
runs after the publish. Start by timing every step of a real repair locally (pickup, setup, agent,
gate, shield parts, copy checks, upload, pointer flip, notices) and write the table in the
hand-back; then split.

**Before the person sees it** (protects them, all fast):
- Deploy gate (about 0.2 s).
- Shield, fast part: records fit, settings engine, every jess tool before/after, primitive block
  checks, the page opens on its first view in WebKit (about 1–2 s, old and new page in parallel).
- The copy's own checks (about 0.2 s).

**In parallel with those:** upload the new version to R2 (the person still gets the old one); the
pointer flips to the new version the moment the fast checks pass.

**After publishing** (the person already has the update):
- Shield, slow part: tap every page control a tool names, and the widget record (about 20 s for
  To-Do). If it fails: put the person's pointer back on the previous version at once, push the
  founder, mark the repair failed with the reason.
- Person's notes line, summary, founder push, jess re-run of a pending request, log files,
  guardian log, saving the built feature for reuse.

**Also:** the runner gets new jobs pushed (or long-polls) instead of a 30 s poll; the job folder and
the shield's WebKit program are prepared ahead, not per job.

Done: the timing table before and after on the same three past requests (a colour change, a
hide, a small feature), all suites passing, and a forced slow-check failure showing the roll back.

## Done

- Full suite passes (`scripts/test-all.sh`) in the worktree and after the merge.
- Each workstream's new checks can fail for the reason they exist.
- On staging: the 46 past requests replayed through the sort give the lanes in the research note
  (45/46 or better); a colour change through the setting lane is live in under 5 s; "Hey can you
  change this" shows the card; a feature request still goes through the code lane with the shield.
