# jess router: notes for the lead (branch `agent/jess-router`, 2026-10-21)

What this branch needs from the lead session, which the worktree may not edit itself
(`CLAUDE.md`, `docs/PRODUCT.md`, `backend/package*.json`, `backend/wrangler.jsonc`), and what the
founder runs by hand. Plan: midas-intel `docs/plans/2026-10-21-jess-voice-router.md`, sections
10-11; brief: midas-intel `docs/plans/2026-10-21-jess-router-brief.md`. Founder decisions on the
review (2026-10-21) are applied: section 6. Phase 7, jess grows the Sidekick: section 8.

## 1. Founder runs by hand

Nothing was deployed from this branch: `docs/PRODUCT.md` section 6 says the founder approves
every remote migrate, deploy and Sidekick deploy, staging included. To try it on staging first
(from `backend/` on this branch, in this order):

1. `node scripts/migrate.mjs --env staging` (applies 0007 and 0008; backs up first)
2. For phase 7 on staging only: `npx wrangler secret put JESS_GROW --env staging`, value `true`
   (a secret, so `wrangler.jsonc` stays unchanged; live has no JESS_GROW, so the path is off there)
3. `npx wrangler deploy --env staging` (the Worker with POST /voice/jess)
4. `node scripts/deploy-sidekick.mjs reminders --env staging` and the same for
   `care-reminders` (pointers then carry `tools.js`)
5. Restart the Mac mini runner on this branch's runner code (phase 7: it re-runs pending jess
   requests after publishing a repair)
6. Run "Midas Test" on a phone signed in to staging and press the Action button (or the
   Control Center control).

Then, after the merge:

- **Migration 0007 on live** (`backend/migrations/0007_voice_logs_router.sql`, five new nullable
  `voice_logs` columns). Staging only from this branch. After the merge and before the live
  Worker deploy: `cd backend && node scripts/migrate.mjs --env live`. The live Worker writes these
  columns on every POST /voice/jess, so the deploy must not go out before the migration.
- **Deploy the Reminders and care-reminders bases to live after the merge**, so every pointer
  carries `tools.js` (`node scripts/deploy-sidekick.mjs reminders --env live`, same for
  care-reminders; user copies get tools.js on their next upgrade or first load). Until then the
  server offers jess no tools of those Sidekicks and the phone says "Not Done". The server reads
  the agent block from the manifest of each user's own version, so a copy deployed before this
  branch (no `tools.js`) is left out until it is upgraded.
- **Migration 0008 on live** (`backend/migrations/0008_jess_pending.sql`: table
  `jess_pending_requests`, column `voice_logs.pending_id`). Before the live Worker deploy, like
  0007: the jess route writes `pending_id` on every attempt. Turning jess grows the Sidekick on
  for live is `npx wrangler secret put JESS_GROW --env live` with `true`, the founder's call.
- **Review the grow path**: `cd backend && node scripts/jess-grow-log.mjs --env staging` (or
  `--env live`; `--since 24h`, `--limit 50`): every pending request, what was said, what jess found
  missing, the repair it filed, the re-run, and every step with its time.
- **The routing golden set, once, live**: `cd backend && OPENROUTER_API_KEY=sk-or-... node
  scripts/eval-jess.mjs` (phase 6; `backend/scripts/jess-golden.json`, 168 sentences; the six
  snooze sentences now expect Not Done; 12 phase 7 sentences in a context with grow on). Costs one
  DeepSeek v4 Flash call per sentence; writes `jess-eval-<time>.md` with the scores and every
  miss.

## 2. CLAUDE.md (proposed lines)

Under "What is this repo", after the jess line:

> **jess router (2026-10-21):** the Action button ("Ask jess") opens jess listening; the
> sentence goes to POST /voice/jess (DeepSeek v4 Flash, tool calling), which reads each of the
> user's Sidekicks' agent block from the manifest of their own version and picks one tool; the
> phone runs that version's `tools.js` handler in JavaScriptCore and writes through
> `RecordWriter`. Only actions a person can take on the page are tools (snooze is not): each
> names its page controls in `_meta["midas/page-actions"]`. `manifest.json` `agent` describes
> them, `tools.js` implements them, and both travel with every copy and repair; a repair that
> removes a feature removes its tool, handler and test (CONCERNS §15). Cannot act → nothing
> changed, "Not Done" card on the home page. Code: `backend/src/jess.ts`,
> `backend/src/jess-route.ts`, `shell/Midas/JessRouter*.swift`, `shell/Midas/SidekickTools*.swift`.

## 3. docs/PRODUCT.md (proposed changes)

- Section 2 (plan additions): voice now routes to any Sidekick with tools, not only reminders.
  The App Intent, App Shortcut short title and the iOS 18 control are now titled "Ask jess"
  (Siri phrases unchanged; the intent type and control kind keep their ids, so a configured
  Action button keeps working); all open the same Listening screen. Jev set aside; no
  general-model fallback. Snooze is a notification action only, not a voice tool; Apple
  Reminders import stays page-only; care "every 8 hours" stays Not Done (the page has
  2/3/4 hours). (Founder, 2026-10-21.)
- Architecture: add `tools.js` beside `index.html` and `manifest.json` in every bundle, pointer
  and version record (`"tools": "tools.js"`); GET /sidekicks/:id/tools.js; repair asset
  `bundle.tools.js`; `voice_logs` columns from migration 0007.
- Repairs: a repair keeps `tools.js` and the agent block in step with the page; a feature removed
  from the page removes its tool, handler and test, and the runner refuses the repair while the
  page still offers the removed tool's controls (option A, CONCERNS §15; see section 4).
- Voice API: the phone sends each Sidekick's id and records summary only; the server reads the
  agent block from R2 and answers "done" with the version it checked against. One sign-in check
  per /voice request (index.ts).

## 4. The rule for every Sidekick, now and generated later

Write this into the generator's brief when the generator is built (it is not yet):

1. **Every action a person can take on the page is a tool.** The Sidekick ships three files:
   `index.html`, `manifest.json` with an `agent` block (`description`, `notFor`, `rules`,
   `examples`, `tools`), and `tools.js` (`MidasSidekickTools = { context, handlers }`).
2. Tool names are `<sidekick id>.<verb>`; `inputSchema` is strict (every property required,
   nullable where optional, no extra properties); a date or time field is `when` with
   `"_meta": { "midas/when": "when" }` and is resolved by Midas, never by the model.
   **Only actions a person can take on the page are tools** (not a notification's, a widget's or
   the shell's): every tool names the page's controls for it in
   `"_meta": { "midas/page-actions": [...] }` (data-action values, or page function names for a
   drag or press-and-hold), and the deploy gate fails when one is not in `index.html`.
3. `tools.js` handlers reuse the page's own code, copied between
   `/* copied from index.html: begin */` and `/* copied from index.html: end */`; the deploy gate
   and the runner fail when a copied block is not in the page any more.
4. Each Sidekick has `<id>-tools*.test.ts` tests that run every handler on real records; they
   travel with every user copy like the other copy tests.
5. A feature removed from the page removes its tool, its handler and its test in the same change
   (founder 2026-10-21, option A, CONCERNS §15). The gate refuses a tool without a handler and a
   handler without a tool; the copy's tests fail while a test still runs a removed handler; the
   runner refuses the repair while any control the removed tool named is still in the page
   (`agentToolRemovalProblems` in `runner/lib/schema-change.mjs`, refusal reason "voice tool
   removed but its action stays"). The agent block and `tools.js` are never removed. Not handled
   yet (CONCERNS §15): older page versions or phones still using a removed tool.
6. The shape is MCP-compatible (name, description, inputSchema, `_meta`); no MCP server now.

## 5. Nothing needed in package.json or wrangler.jsonc

No new dependency or binding. The router uses the existing `OPENROUTER_API_KEY` and the voice
settings in `backend/src/voice-route.ts`. Phase 7 adds one optional secret, `JESS_GROW` (`true`
turns it on; absent means off), set with `wrangler secret put`, not in `wrangler.jsonc`.

## 6. Founder decisions on the review (2026-10-21), as applied

Written and dated in `docs/PRODUCT.md` ("jess router review, founder 2026-10-21", items 1-8).

1. **"Ask jess"**: the App Intent title, App Shortcut short title and control label/display name
   (`shell/Shared/StartVoiceReminderIntent.swift`, `shell/Midas/MidasShortcuts.swift`,
   `shell/MidasWidgets/VoiceReminderControl.swift`). Siri phrases unchanged. The intent type
   name and the control kind (`com.bhuvanrj.midas.new-reminder`) are unchanged on purpose, so an
   Action button or Control Center already set up keeps working.
2. **Apple Reminders import**: stays page-only, no tool (unchanged; a manifest rule says so).
3. **Snooze tools deleted** (`reminders.snooze`, `care-reminders.snooze`: manifest entries,
   examples, handlers; a rule line says snooze is only on a notification). Every other tool was
   checked against "only actions a person can take on the page" (section 7). Each tool now names
   its page controls (`midas/page-actions`) and the deploy gate checks they exist.
4. **Tool removal allowed** (option A): `agentToolRemovalProblems` replaces
   `agentToolsKeptProblems`; refusal reason "voice tool removed but its action stays". Repair
   agent prompts (`runner/agents/reminders.md`, `runner/agents/care-reminders.md`) updated.
5. **Server reads the manifests**: `currentAgentListing` in `backend/src/sidekicks.ts` (user's own
   pointer, else the base; only when the pointer carries `tools.js`); `offeredSidekicks` in
   `backend/src/jess-route.ts` (assigned Sidekicks only); arguments still checked against those
   schemas. New not-done reason `no-tools` (nothing to offer; the model is not called). The
   "done" answer carries `version`; the phone runs that version's `tools.js`, loading it when it
   differs from the one it had.
6. **One sign-in check**: `app.use("/voice/*", requireSession)` in `backend/src/index.ts`; neither
   `voiceRoutes` nor `jessRoutes` checks again. (Before: a handled /voice/jess request already
   ran one check, but a /voice/jess path with no route ran two.)
7. **Care "every 8 hours"**: stays Not Done (unchanged).

## 7. Tools accept only what the page offers (PRODUCT.md review item 7)

Each tool was checked against its page. Every remaining tool is a page action; where a tool took
more than the page offers, it now refuses (nothing changes, "Not Done"):

- **care-reminders.add / edit**: a repeat must be one of the page's Repeat menu choices (Never,
  Every Day, Weekdays, Weekends, Every Week, Every 2 Weeks, Every Month, Every Year, every 2/3/4
  hours); "every Friday" said for a Friday is Every Week. Else refused `repeat-not-offered`. A
  repeat already stored is left as it is when an edit does not change it.
- **care-reminders.add_list_alert**: days 1-14 and minutes from the page's "How Long" steps (5,
  10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720), as enums in the tool's schema (the server
  answers `bad-arguments`) and checked in the handler (`alert-not-offered`). The steps in
  `tools.js` are a block copied from the page, so the gate catches a change on the page.
- **care-reminders.uncomplete**: only a reminder the page shows as done with its "Not Done"
  button (the day it was done); else refused `not-done`.
- **reminders.add / edit**: a repeat interval of 1-99, as the page's Custom repeat; else refused
  `repeat-not-offered`.

Page actions with no tool: Reminders "Import File" and "End Repeat" (never / on a date);
care-reminders alert wording, changing an alert in place (a tool can remove and add), and Undo
after a delete. The Reminders page cannot rename or delete a list, so no tool does either.

## 8. jess grows the Sidekick (phase 7; PRODUCT.md "jess grows the Sidekick", founder 2026-10-21)

Behind `JESS_GROW` (section 1). With it off, nothing changes: no grow tool, the Not Done card as
before, `GET /voice/jess/pending` empty, the runner re-runs nothing.

1. **The decision** (`backend/src/jess.ts`): with the flag on, the model also gets
   `midas.grow_sidekick {sidekick, feature}` and rules: a clear request a Sidekick has no option
   for. Unclear words, questions, cut-off sentences, two matches, snooze ("not a voice action")
   and requests about how a Sidekick looks stay `cannot_act` / `repair_request`.
2. **Filing** (`backend/src/jess-route.ts`, `backend/src/jess-pending.ts`, migration 0008): one D1
   batch writes the repair report (kind `feature`, queued, the founder's `request_received`
   event; transcript = the person's words, then "jess (voice) could not do this yet: <feature>…",
   because the runner gives the agent only `transcript.txt`) and the pending request (`waiting`,
   original now / time zone / locale, report id, log id, steps). Reply
   `{status: "grow", sidekickId, reportId, pendingId, logId}`; the phone shows "Sent to Repair".
3. **The re-run, in the backend** (founder 2026-10-21): right after `deployed_live`, the runner
   (`runner/lib/jess-rerun.mjs`, called from `run-job.mjs` for feature jobs) loads the published
   `tools.js` in `node:vm`, sends its `context()` of the reporter's server records to
   `POST /repairs/:id/jess-rerun` (runner token; `backend/src/jess-rerun.ts`). That claims the
   request (waiting → re-running only while the report is `deployed_live` on that user; one
   statement, so once) and routes the stored words with the stored time, offering only that
   Sidekick as the user now gets it, no grow, no repair. On "done" the runner runs the handler with
   the records and the time now, then `POST /repairs/:id/jess-rerun/ops`: each op goes through
   `/sync/push`'s own checks (`cleanOp`, the schema of the new version, which must still be the
   user's version), op ids `jess-<pendingId>-<n>` (a retry adds nothing), all appended in one
   statement with the request marked done and its line kept for the banner. One bad op, a refusal
   or a changed version appends nothing and fails the request.
4. **The phone**: after each foreground sync, `JessGrowFollowUp` asks `GET /voice/jess/pending`
   and shows each finished request once (done: the handler's line as the banner; failed: what was
   said as the Not Done card), then `POST /voice/jess/pending/:id/seen`. The records themselves
   arrive by the normal pull.
5. **Failures** → failed with the reason, shown as the card: repair failed or refused
   (`repair failed: <reason>`), live but not re-run within 10 minutes, the runner did not finish
   within 10 minutes, the re-run still cannot act, the handler refused, an op did not fit, the
   version changed.
6. **Logged**: every attempt in `voice_logs` (the grow with tool `midas.grow_sidekick`, the re-run
   with `device` "runner"; both with `pending_id`; the re-run's `phone_outcome` is what became of
   its ops), every step in `jess_pending_requests.steps`; `scripts/jess-grow-log.mjs` prints them.

Known limits: the runner runs the handler on the records the server has; edits still in the
phone's outbox at that moment are not seen by it (last write wins by server order, as for any
two devices). A re-run "in 20 minutes" resolved from the original time may now be past, and the
handler then refuses (shown as Not Done).

