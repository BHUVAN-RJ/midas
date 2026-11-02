# To-Do Sidekick: build brief (2026-10-31)

Founder, 2026-10-31: "I have added everything, my selections. Let's implement that. It's
primitives, so the user can change however he wants." Then: "You can start building."

Build the to-do list Sidekick `sidekicks/todo/` from the to-do primitive. Page-only: **no shell
change** (a shell change means a new app build; memory rule). Everything below is decided; where
the code disagrees with a doc, the built code wins and you note it in the hand-back.

## 1. Read first

- `docs/primitives/todo/` (README, records.md, recipe.md, checklist.md, blocks/*.md): the spec.
- `docs/mockups/todo-primitive-2026-10-31.html`: the clickable reference. **Port it**: its logic
  (queries, natural language, repeats, today models, done modes, gestures, drag, undo, presets,
  Make It Yours panel) is the behaviour to ship. Keep its look and words.
- `sidekicks/hydration/` (index.html, manifest.json, tools.js) and `docs/briefs/hydration-sidekick.md`:
  how a current Sidekick is built (manifest `types` and `agent` block, the `copied from index.html`
  block in tools.js and the deploy gate that checks it, widget records, tests).
- `docs/PRODUCT.md` section 5, `docs/NOTIFICATIONS.md`, `docs/WIDGETS.md`, `docs/WRITING.md`,
  `CLAUDE.md` (tests are guarded; every Sidekick is agent-connected; legacy formats quarantined:
  never read `docs/legacy/`).

## 2. Decided

**Default settings = the founder's own selections** (read from the prototype on 2026-10-31). These
replace the Basic preset as the starting `settings:self`:

```json
{"look":"notebook","theme":"auto","accent":"#2F6FEB","textSize":"m","density":"comfy","font":"system",
 "checkbox":"end","showMeta":true,"dateColors":true,"tickSound":"chimes","haptic":true,
 "celebrate":"allDone","doneGoes":"stay","add":"row","parse":true,"swipeRight":"complete",
 "swipeLeft":"delete","home":"tabs","todayModel":"carry","dayParts":false}
```

Every field stays changeable on the page (Make It Yours, reached from a button in the top bar) and
through agent tools. The presets (Basic, Paper, Notebook, Soft, Wallpaper, Heat) stay as in the
prototype; "Basic" in the panel resets to the values above, labelled "Mine" [proposal: the
founder's set is the person's own start].

**Records** (founder defaults from the 2026-10-31 decision list):
1. A to-do is a `reminder:<id>` record (`$type` `todo.item`), so the notification engine, the tick
   from a notification and the widget's Today source work as built. Fields from
   `docs/primitives/todo/records.md` section 1, plus the engine fields when timed (`at`,
   `timeZone`, `alerts`; `docs/NOTIFICATIONS.md`). Check in the engine code that a `reminder:`
   without `at` (an untimed to-do) is accepted and never notifies; if not, untimed to-dos must stay
   valid another way without a shell change; say which in the hand-back. Update
   `docs/primitives/todo/records.md` to match what you build.
2. `list:<id>` and `settings:self` as in records.md sections 2 and 3.
3. Trash: a deleted to-do gets `deletedAt` and stays 30 days, with a Trash view (Restore, Delete
   Now); older ones are removed on open.
4. Apple Reminders import match key: `externalId` field on the to-do, matched on import (only if the
   existing import path can reach this Sidekick without a shell change; otherwise record the field
   in the schema and list import as left for later).
5. Repeats: day, weekday, week, month, from schedule or done (as built). Yearly / every N / chosen
   weekdays / end dates: later, on request.

**Haptics:** the hidden `<input type="checkbox" switch>` trick, as in the prototype.
**Storage:** no localStorage, no IndexedDB; the prototype's stand-in store is replaced by
`shell/sdk/midas-store.js` pasted in.

## 3. Build

| Step | Work | New tests (each must fail without the change) |
|---|---|---|
| 1 | `manifest.json`: id `todo`, name "To-Do", SF Symbol (e.g. `checklist`), tile colour; `types` for `reminder:`, `list:`, `settings:`, (`widget:` if used) | Schemas accept every record the page writes and refuse wrong shapes |
| 2 | `index.html`: the prototype ported onto `store`, CSP-safe as hydration's page is | Logic tests in `backend/test/todo-logic.test.ts`: the 22 prototype checks (scratchpad `proto-test/test.mjs`, path in section 5) rewritten against the real logic: natural language, repeat next copy and double-tick guard, undo, four done modes, four today models, search incl. done, order between, list delete asks first, escaping, trash |
| 3 | `tools.js` with the copied block; `agent` block: add, complete, uncomplete, move (when/list), edit, delete, restore, search, list today, change setting | `backend/test/todo-tools.test.ts`: every tool against real-shaped records; the tools gate passes |
| 4 | Widget record (Today list with tick) if the widget builder's `reminder:` Today source fits | Widget record passes the shell checker |
| 5 | Repair agent `runner/agents/todo.md` + entry in `TEMPLATE_BY_SIDEKICK` (`runner/lib/prompt.mjs`), modelled on the hydration one (every Sidekick has repair) | Template lookup finds `todo`; a repair job builds its prompt |
| 6 | Docs: `docs/PRODUCT.md` (Sidekick list), primitive records.md | — |

Run the full suite (`scripts/test-all.sh`) after every step; it leases a simulator itself. Do not
edit existing tests (only test-guardian may). Do not deploy, do not commit: the lead reviews,
the founder deploys (`docs/DEPLOY.md`).

## 4. Hand-back

What was built, file list, test results (full suite output, honestly, with anything failing),
every place the code disagreed with the docs, and what is left for later.

## 5. Paths

Prototype checks: `/private/tmp/claude-501/-Users-bhuvanrj-Desktop-Midas/9e9bef2b-aa98-4653-abbd-466308174e52/scratchpad/proto-test/test.mjs`.
