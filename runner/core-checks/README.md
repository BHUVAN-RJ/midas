# The shield: core checks on every repair

Founder decision D3, 2026-11-13 (`docs/PRODUCT.md`, "Plan additions, 2026-11-13: repair lanes");
brief `docs/briefs/repair-lanes.md` W1.

Midas owns these checks. They run on every repair from the platform checkout (the runner's
`settings.checkoutRoot`), never from the job folder and never copied into the person's copy, so no
repair agent and no Sidekick test guardian can change them: the agent's session may not edit the
checkout (`run-job.mjs agentPathLimits`), and `runner/lib/check.mjs loadShield` imports them from the
checkout only.

| Check | What fails it |
|---|---|
| `page-opens` | The new page, opened in WebKit with the person's records, draws nothing, or shows a console error, uncaught error, unhandled rejection or refused store write the old page did not have. Checked on the first view and on the view after a tap on every page control a tool names. |
| `tools` | A tool from the old manifest is gone (D1: remove means hide); its handler is gone; it answers differently on the person's records and the request does not name it; a page control a tool names is gone from the page. |
| `settings-engine` | A copy that had the settings engine (`set_setting` tool and handler, `settings:` type, `settings:self` on the page) lost any part of it. Once `SETTINGS_ENGINE_IN_EVERY_SIDEKICK` is true (after W5), a copy without it fails too. |
| `records-fit` | A record the person has does not fit the new schema (`runner/lib/user-records.mjs`, the same check the publish step runs). |
| `widget-record` | A `widget:` record the old page wrote is no longer written, or the shell would refuse it. |
| `primitive-blocks` | A block check under `docs/primitives/<primitive>/checks/` fails (none exist yet; format in `primitive-blocks.mjs`). |

Preferences (colour, wording, position, show or hide) never become checks (D3).

## How a page is opened

`webkit-page.swift` is a small macOS program: a `WKWebView` with no window, the same WebKit engine
as the iPhone shell. `page-open.mjs` compiles it once per version with `xcrun swiftc` into
`$TMPDIR/midas-shield/<hash>/` (about 2 s; every runner Mac has Xcode) and runs it. Chosen over
Playwright WebKit (a new npm dependency and a 100 MB browser download, and not Apple's WebKit build)
and over the simulator (the two pool phones would serialise every repair; `scripts/sim.sh`).

Each page is opened several times, each time from a fresh copy of the records:

- `open`: the records as they are.
- `widget`: the records without `widget:` ones, so the page writes its widget records again.
- `view:<control>`: the records as they are, then a tap on `[data-action="<control>"]` for every
  control any tool's `midas/page-actions` names (old manifest or new). A control not on the first
  view is skipped there. Manifests name no views, so these are the views.

`page-prelude.js` is injected before the page's own scripts. It answers the page's store
(`POST /_midas/store`, the protocol of `shell/Midas/SidekickStoreChannel.swift`) from memory, stamps
and checks every write with `shell/sdk/record-schema.js` and `shell/sdk/shell-types.js` like the
shell, refuses all network, records every error, and posts one report carrying a nonce only it
knows: a page cannot post a made-up report. `console.error` is locked so a page cannot swap it out.

An error the old page already had with the same records is not the repair's fault and does not
fail it (line numbers are ignored in the comparison: every edit moves them).

## Tools before and after

`tools-compare.mjs` runs the old and the new `tools.js` in `node:vm` (as on the phone: no network,
no store) with a fixed clock and a seeded `Math.random`, reset before every call, so ids made from
the time and random numbers match. `tool-inputs.mjs` builds a few inputs per tool from its
`inputSchema`, naming titles from the person's own records so handlers do real work. Answers are
compared as JSON with sorted keys.

The tools the request names may change: the agent lists them in `outcome.json` as
`"changedTools": ["todo.search"]` (`runner/lib/check.mjs requestedToolsFromOutcome`); the shield
report lists every tool whose answers changed.

## Running it

- The runner: `runner/lib/check.mjs checkRepair` (gate, then shield, then the copy's tests).
- The agent: `runner/tools/check.mjs`, when the runner sets `MIDAS_JOB_BEFORE_FOLDER` (the copy as
  the job started) and `MIDAS_JOB_RECORDS` (the person's records, a JSON list).
- Tests: `backend/test/repair-shield-*.test.ts`; each check is shown failing for its reason.
