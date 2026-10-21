# jess router: notes for the lead (branch `agent/jess-router`, 2026-10-21)

What this branch needs from the lead session, which the worktree may not edit itself
(`CLAUDE.md`, `docs/PRODUCT.md`, `backend/package*.json`, `backend/wrangler.jsonc`), and what the
founder runs by hand. Plan: midas-intel `docs/plans/2026-10-21-jess-voice-router.md`, sections
10-11; brief: midas-intel `docs/plans/2026-10-21-jess-router-brief.md`.

## 1. Founder runs by hand

Nothing was deployed from this branch: `docs/PRODUCT.md` section 6 says the founder approves
every remote migrate, deploy and Sidekick deploy, staging included. To try it on staging first
(from `backend/` on this branch, in this order):

1. `node scripts/migrate.mjs --env staging` (applies 0007; backs up first)
2. `npx wrangler deploy --env staging` (the Worker with POST /voice/jess)
3. `node scripts/deploy-sidekick.mjs reminders --env staging` and the same for
   `care-reminders` (pointers then carry `tools.js`)
4. Run "Midas Test" on a phone signed in to staging and press the Action button (or the
   Control Center control).

Then, after the merge:

- **Migration 0007 on live** (`backend/migrations/0007_voice_logs_router.sql`, five new nullable
  `voice_logs` columns). Staging only from this branch. After the merge and before the live
  Worker deploy: `cd backend && node scripts/migrate.mjs --env live`. The live Worker writes these
  columns on every POST /voice/jess, so the deploy must not go out before the migration.
- **Deploy the Reminders and care-reminders bases to live after the merge**, so every pointer
  carries `tools.js` (`node scripts/deploy-sidekick.mjs reminders --env live`, same for
  care-reminders; user copies get tools.js on their next upgrade or first load). Until then the
  phone leaves those Sidekicks out of jess and says "Not Done".
- **The routing golden set, once, live**: `cd backend && OPENROUTER_API_KEY=sk-or-... node
  scripts/eval-jess.mjs` (phase 6; `backend/scripts/jess-golden.json`, 150 sentences). Costs one
  DeepSeek v4 Flash call per sentence; writes `jess-eval-<time>.md` with the scores and every
  miss.

## 2. CLAUDE.md (proposed lines)

Under "What is this repo", after the jess line:

> **jess router (2026-10-21):** the Action button opens jess listening; the sentence goes to
> POST /voice/jess (DeepSeek v4 Flash, tool calling), which picks one tool of the user's
> Sidekicks; the phone runs that Sidekick's own `tools.js` handler in JavaScriptCore and writes
> through `RecordWriter`. Every action on a Sidekick's page is a tool: `manifest.json` `agent`
> describes them, `tools.js` implements them, and both travel with every copy and repair.
> Cannot act → nothing changed, "Not Done" card on the home page. Code: `backend/src/jess.ts`,
> `backend/src/jess-route.ts`, `shell/Midas/JessRouter*.swift`, `shell/Midas/SidekickTools*.swift`.

## 3. docs/PRODUCT.md (proposed changes)

- Section 2 (plan additions): voice now routes to any Sidekick with tools, not only "New
  Reminder"; Siri phrases, App Intent, App Shortcut and the iOS 18 control are unchanged and
  open the same Listening screen. Jev set aside; no general-model fallback (founder, 2026-10-21).
- Architecture: add `tools.js` beside `index.html` and `manifest.json` in every bundle, pointer
  and version record (`"tools": "tools.js"`); GET /sidekicks/:id/tools.js; repair asset
  `bundle.tools.js`; `voice_logs` columns from migration 0007.
- Repairs: a repair keeps the agent block and every tool, and keeps `tools.js` in step with the
  page (runner refuses otherwise; see section 4).

## 4. The rule for every Sidekick, now and generated later

Write this into the generator's brief when the generator is built (it is not yet):

1. **Every action a person can take on the page is a tool.** The Sidekick ships three files:
   `index.html`, `manifest.json` with an `agent` block (`description`, `notFor`, `rules`,
   `examples`, `tools`), and `tools.js` (`MidasSidekickTools = { context, handlers }`).
2. Tool names are `<sidekick id>.<verb>`; `inputSchema` is strict (every property required,
   nullable where optional, no extra properties); a date or time field is `when` with
   `"_meta": { "midas/when": "when" }` and is resolved by Midas, never by the model.
3. `tools.js` handlers reuse the page's own code, copied between
   `/* copied from index.html: begin */` and `/* copied from index.html: end */`; the deploy gate
   and the runner fail when a copied block is not in the page any more.
4. Each Sidekick has `<id>-tools*.test.ts` tests that run every handler on real records; they
   travel with every user copy like the other copy tests.
5. Repairs only add: never remove or rename a tool or the agent block (`agentToolsKeptProblems`
   in `runner/lib/schema-change.mjs`, refusal reason "voice tools removed"); an action gone from
   the page keeps its tool, whose handler refuses with `cannot-change`.
6. The shape is MCP-compatible (name, description, inputSchema, `_meta`); no MCP server now.

## 5. Nothing needed in package.json or wrangler.jsonc

No new dependency, binding, secret or variable: the router uses the existing
`OPENROUTER_API_KEY` and the voice settings in `backend/src/voice-route.ts`.
