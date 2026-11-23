# Hand-back: W5, the setting lane (agent/repair-settings)

Brief: `docs/briefs/repair-lanes.md` W5; decision D1 in `docs/PRODUCT.md` "Plan additions,
2026-11-13: repair lanes". Stage reached: **testing** (local suite, `wrangler dev` on 8795 with the
real OpenRouter key). Nothing deployed, nothing merged.

## Timed end to end (local, wrangler dev 8795, real key, 2026-11-13)

| Said (Water) | Lane | Written to settings:self | Reply | + page watch poll (≤1 s) |
|---|---|---|---|---|
| "make the water drop blue" | setting | `drop.colour = "#1E88E5"` | 3.15 s | ≤ 4.2 s |
| "hide the streak" | setting | `streak.show = false` | 0.77 s | ≤ 1.8 s |
| Undo of "hide the streak" | — | `streak.show` removed (never set before) | 0.08 s | ≤ 1.1 s |
| "make the water sparkle like diamonds" | code (queued) | nothing | 4.5 s | — |
| "add a weekly chart" | code (queued) | nothing | 0.29 s | — |

A second undo answers 409 "nothing to undo". Times are `POST /repairs` wall time with curl
(the sort plus the Haiku mapping); the colour case went through the Haiku fallback sort.

## What was built

1. **Catalogue per Sidekick** (`settings` key only in each base manifest, so it merges with W4's
   `repair` block): Reminders 44 keys, Care 44, Water 27, To-Do 53 (the 20 Make It Yours fields
   plus the engine's). Each entry: key, label, type (colour, size, show, dateFormat, choice), part,
   default, values, optional selector/css, and for show entries the tools it turns off. Every key
   is also a property of the `settings:` record schema.
2. **Settings engine** `shell/sdk/midas-settings.js` (+ `.d.ts`), pasted into each page after the
   store helper and into tools.js as a copied block (the gate checks they match). It draws
   selector entries as a `<style id="midas-settings">` sheet, hands the rest to the page, reads
   settings:self at start, every 1 s while visible and on return to the page, and redraws only on
   change. Date formats go through `formatDate` ("auto" keeps the page's own).
3. **`<id>.set_setting`** in all four (To-Do's existing tool keeps its own fields and gains the
   engine keys). A hidden part's tools answer "turned-off" (D1: hidden, not deleted). Examples:
   Reminders `circles.show` off → complete/uncomplete off; To-Do `trash.show` off → restore off.
4. **Backend lane** (`src/repair-setting-model.ts`, `src/repair-setting.ts`, in `repair-sort.ts`):
   lane `setting` → Haiku 5.5 (`anthropic/claude-haiku-5.5`, OpenRouter, 6 s timeout) gets the
   words plus the person's current copy's catalogue with current values, answers up to 3
   `{key, value}`; every change is checked against the catalogue (any bad one fails all) → one op
   `setting-<reportId>` on settings:self through the record checker → reply
   `{lane:"setting", message:"Changed", setting:{changes:[{key,label,value}]}}`. No runner job
   (status stays `received`). Haiku can't map, times out or no key → lane `code`, queued, founder
   event, reason in `setting_problem`. `POST /repairs/:id/undo` (reporter only, once) restores the
   old values. Migration `0016_repair_setting.sql` (additive columns on repair_reports).
5. **Shell**: `RepairSortReply.setting`; a setting reply with changes closes repair mode as
   answered (no Editing tag) and calls `recordSync.syncNow()` so the page redraws.
6. **Shield**: `SETTINGS_ENGINE_IN_EVERY_SIDEKICK = true`; a Sidekick whose base has no catalogue
   (Money) is held only to "never lose it" (`baseHasSettingsCatalogue`).
7. **Existing copies**: `backend/scripts/bring-settings-engine.mjs` (below).
8. **jess golden set**: 4 cases for reminders/care-reminders `set_setting` (st-01..04).

## Files

New: `shell/sdk/midas-settings.js`, `shell/sdk/midas-settings.d.ts`,
`backend/src/repair-setting.ts`, `backend/src/repair-setting-model.ts`,
`backend/migrations/0016_repair_setting.sql`, `backend/scripts/settings-engine-tools.mjs`,
`backend/scripts/bring-settings-engine.mjs`, tests `backend/test/{repair-setting-route,
settings-engine-sdk,bring-settings-engine,repair-settings-shield,reminders-settings,
care-reminders-settings,todo-settings}.test.ts`, `shell/MidasTests/RepairSettingLaneTests.swift`.

Changed: `backend/src/repair-sort.ts`, `backend/src/repairs.ts`,
`runner/core-checks/shield.mjs`, `shell/Midas/RepairSort.swift`, `shell/Midas/RepairSession.swift`,
`sidekicks/{reminders,care-reminders,hydration,todo}/{index.html,manifest.json,tools.js}`,
`backend/scripts/jess-golden.json`. Seven existing tests changed by test-guardian (logged in the
test changes log), plus the delimiter fix in the new Swift test.

## How to try it

```
cd ~/Desktop/Midas/midas-worktrees/repair-settings/backend && npx vitest run test/repair-setting-route.test.ts test/settings-engine-sdk.test.ts test/bring-settings-engine.test.ts
```

Local server (`.dev.vars` holds `OPENROUTER_API_KEY`, gitignored; local D1 has user `smoke`,
token `smoke-token`, Water assigned; local R2 has the Water base as version `w5-local`):

```
cd ~/Desktop/Midas/midas-worktrees/repair-settings/backend && npx wrangler dev --port 8795
curl -s -X POST http://localhost:8795/repairs -H 'Authorization: Bearer smoke-token' -F sidekickId=hydration -F kind=change -F "transcript=make the water drop blue"
curl -s -X POST http://localhost:8795/repairs/<id>/undo -H 'Authorization: Bearer smoke-token'
```

## Existing copies script (lead runs it at the deploy step)

```
cd ~/Desktop/Midas/midas/backend && node scripts/bring-settings-engine.mjs --env staging --out /tmp/w5-copies
cd ~/Desktop/Midas/midas/backend && node scripts/bring-settings-engine.mjs --env staging --out /tmp/w5-copies --publish
```

- Dry run by default: reads remote read-only, writes each upgraded copy to
  `<out>/<sidekick>/<user>/` and prints passed / failed with reasons. `--sidekick <id>` limits it.
- Only copies with their own pointer (repaired copies) are touched; copies that follow the base
  get the engine from the base deploy.
- Keeps the person's changes: inserts the engine block, catalogue, generic wiring, tools block and
  `set_setting`; only catalogue entries the copy can still honour are kept (selectors still in the
  page; page-read keys the page still names; e.g. `dates.format` drops for pre-engine copies).
- Runs the deploy gate and the WebKit shield with the person's records; publishes
  (`deploy-sidekick.mjs --user --dir`) only what passed. Failures are listed and left untouched.
- Requires the deployed base to carry the catalogue already: deploy the four bases first.
- Staging only (founder, 2026-11-14): the script refuses `--env live` outright, dry run included
  (`refusalForEnvironment`, test `bring-settings-engine-staging-only`). Lifting it is the founder's call.
- I never ran it against staging.

## For the lead to add

1. **Deploy order (staging only until the founder says live):** migration 0016 (`cd ~/Desktop/Midas/midas/backend && node scripts/migrate.mjs --env staging`)
   before the Worker; the lane writes the new columns. Then the four Sidekick bases, then the
   copies script (dry run, then `--publish`).
2. **Secret:** same `OPENROUTER_API_KEY` as the sort. No dependency, no `wrangler.jsonc` change.
3. **Repo copy of Boomi's Reminders** (`copies/reminders/boomi`) is not upgraded in the repo; tests
   use it as the pre-engine example. The copies script upgrades the deployed one.
4. **Shell:** the page redraw on the phone relies on `recordSync.syncNow()` after a setting reply
   plus the engine's 1 s poll; tried locally against the Worker, not yet on a simulator page.

## Full suite (2026-11-13, worktree)

| Suite | Result |
|---|---|
| test guard | 42 OK |
| backend | 1856 of 1856 passed (166 files) |
| midas-intel | 31 OK |
| shell | 1306 passed, 0 failed (leased simulator), incl. RepairSettingContractTests and RepairSettingSessionTests |

Test-guardian changed 8 existing checks for D1 (7 backend, 1 Swift tool list), each shown to still
fail for its reason, all logged. In Water's tools.js the engine block sits after WaterLogic, so
WaterLogic stays the first copied block (the widget cross-checks read the first one).

## Open questions (founder or lead)

1. **Undo on the phone:** the route is ready; no button or design yet (where it shows, how long).
2. **Dark mode:** a colour the person sets wins in dark mode too.
3. **To-Do presets** do not reset part settings set through the engine.
4. **jess golden case gw-11** ("make the text in care reminders bigger") still expects a repair
   request; with `set_setting` jess could now do it directly. Which is right is a product call.
