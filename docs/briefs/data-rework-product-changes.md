# Data rework: state and what the lead must do (builder note, 2026-10-15)

Branch `agent/data-rework`, worktree `midas-worktrees/data-rework`. Plan: midas-intel
`docs/plans/2026-10-15-unified-data-v2.md`. The builder's session hit its usage limit during
phase 4; this file is the handoff.

## State

| Phase | State |
|---|---|
| 1 merge care-repeat + sidekick-widget | committed (05a0f45, 02bc0b4), suite green |
| 2 schemas in manifests, one validator, $type, update, server checks, refused ops kept | committed 7f402c5, suite green |
| 3 pages on new shapes, care alerts/hourly as fields, engine expansion | committed 4f540ac, suite green |
| 4 RecordWriter for every native writer, Done conformance, hourly doses in widgets | **built, uncommitted**. Last full shell run: 466 tests, 3 failures, all in the new `DoneConformanceTests.testCarePageDoneEqualsTheNativeDone`; the care page then gained `lastDoneAt` in `recordFromItem` (the likely cause); a rerun was in progress when the session ended. Next: run `scripts/test-all.sh`; if green, commit with the message in the builder's scratchpad (phase 4 summary below). |
| 5 files (R2) | not started. Needs the lead: `wrangler.jsonc` R2 binding `FILES` to `midas-files-staging` (staging env), `midas-files` (live, founder creates). |
| 7 migration script, upgrade-on-read, staging run | not started (upgrade-on-read for old shapes already exists in both pages: `task:` records, `body`, epoch ms, `~rule`/`@HHMM` folding). |
| 8 docs | not started: `docs/NOTIFICATIONS.md` (sections 4.2, 4.6, 5, 7 stale), `docs/WIDGETS.md` (`where` by `$type`, hourly doses), this file's PRODUCT.md changes. |

## Phase 4, what was built (uncommitted)

- `shell/Midas/RecordWriter.swift`: `RecordWriter.update(sidekickId:key:patch:)` (read, RFC 7396
  merge, store gate, 64 KB, write) and `ReminderChange.donePatch` / `snoozePatch`, the one Done
  and Snooze every writer uses.
- Notification buttons (`NotificationEngine.handle`, `ReminderAction.patch`), the Reminders widget
  tick, the Sidekick widget taps (tick/increment/toggle/set, a tick on `reminder:<id>@HHMM` lands
  on the item), the Apple Reminders import outcome: all through `RecordWriter`.
- Hourly doses expanded for widgets (`ReminderExpansion.slotRecords`, `SidekickWidgetFiller`).
- Pages: Reminders `markDoneChange` moved into `RemindersLogic` (exported); care `markDone` writes
  `lastDoneAt` + `doneThrough` and clears the snooze, like every writer.
- New tests: `RecordWriterTests`, `DoneConformanceTests`, `SidekickWidgetHourlyTests`.
  test-guardian changed (logged): `ReminderActionTests`, `NotificationEngineTests` (snooze removed,
  not null).

## Decisions the builder made (for the lead to confirm)

- Validator: a hand-written JSON Schema subset in `shell/sdk/record-schema.js` instead of
  `@cfworker/json-schema` (plan section 3 named it as a proposal). Reason: no `package.json`
  change allowed, and the shell loads the same file into JavaScriptCore without a bundler; the
  library would need one. Same file runs in the Worker, the shell and tests.
- `at` is optional on `reminder:` for the shell's own check (undated items, `task:` retired); a
  record without `at` notifies nobody.
- Pages stamp `$type` themselves as well as the shell gate (so widgets and tests see it).
- Server: an op without `sidekickVersion` is checked against the user's current version; a
  version without `types` is not content-checked. Old shells pushing records without `$type`
  against a manifest with types are refused and kept on the phone (shown as "N changes not backed
  up"); ship the shell update before deploying the new manifests.
- Snooze on an early alert or hourly time snoozes the item (one `snoozedUntil`).

## PRODUCT.md changes needed (lead)

- Section 5 "Notifications"/"Data model": every record carries `$type`; schemas live in each
  Sidekick's `manifest.json` `types` block; one validator `shell/sdk/record-schema.js`; `store.update`
  (RFC 7396); refused ops never dropped, counted on the home screen; `task:` retired, `body` retired,
  `settings:self`; care early alerts and hourly times are item fields the engine expands.
- Section 2 data format entry: founder answers of 2026-10-15 (manifest schemas, files bucket
  `midas-files-staging`, 20 MB) and the state above.
- `docs/primitives/` is not in git: `daily-planner/records.md` must drop its own `task:` shape and
  `v` field and use `$type` + a `types` block.

## Lead actions

- `backend/wrangler.jsonc`: R2 binding for files (phase 5), staging and live.
- No `package.json` change needed.
- Live: founder creates `midas-files`; migration (phase 7) to be written and run on staging first.
