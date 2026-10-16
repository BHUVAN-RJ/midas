# Data rework: what was built, what the lead must do (builder report, 2026-10-15)

Branch `agent/data-rework`, worktree `midas-worktrees/data-rework`. Plan: midas-intel
`docs/plans/2026-10-15-unified-data-v2.md`; brief `docs/plans/2026-10-15-data-rework-brief.md`.
Every phase is committed on the branch with `scripts/test-all.sh` green. Final suite: test guard 34,
backend 350 (37 files) + typecheck, shell 479, midas-intel 31.

## Phases

| Phase | Commit | What |
|---|---|---|
| 1 | 05a0f45, 02bc0b4 | `agent/care-repeat` and `agent/sidekick-widget` merged, behaviour kept. |
| 2 | 7f402c5 | Schemas in both manifests (`types`), one validator `shell/sdk/record-schema.js` (Worker, shell via JavaScriptCore, tests), shell types `shell/sdk/shell-types.js` (`widget:`, `request:`), `$type` on every record, `store.update` (RFC 7396), server checks against the version that wrote the op, refused ops kept in the outbox with the reason and shown as "N changes not backed up". |
| 3 | 4f540ac | Reminders page: every item `reminder:` (`task:` retired, read and moved on next write), no `body`, `settings:self`. care-reminders: one record per reminder with `alerts`, `everyHours`, `slotsDone`; `~rule`/`@HHMM` retired and folded in on load; `ReminderExpansion` builds the same notifications under the same ids (engine state carries over). |
| 4 | 5ea76de | `RecordWriter` for every native writer (notification buttons, both widgets, import); `ReminderChange.donePatch` the one Done; Done conformance test page vs native; hourly doses in widgets. |
| 5 | 69c199d | Files: `POST /files`, `GET /files/:id` (owner, 20 MB on the bytes, idempotent ids), `FileStore`, `store.putFile` / `store.fileUrl`, files uploaded before the records that point to them, the `data:` URL safety net, files backup in `backup-db.mjs`. |
| 7 | 0274400 | `record-upgrades.mjs` + `migrate-records.mjs` (new ops, tombstones, schema-checked, idempotent). |
| 8 | this commit | `docs/NOTIFICATIONS.md`, `docs/WIDGETS.md`, this file. |

Phase 6 (repair agent, runner) was removed by the founder (plan section 14); nothing in `runner/`
was touched. Voice: nothing.

## Staging run (2026-10-15 evening, by the builder)

- Worker deployed to `midas-api-staging` (version fc177773), without the `FILES` binding (the
  file routes answer 503 until the lead adds it).
- `reminders` and `care-reminders` deployed to staging (`20261016T011358074Z-fc82222c`,
  `20261016T011434989Z-a49ae2be`); the founder's reminders copy followed the base.
- Migration run on staging after a backup (`~/midas-backups/staging-midas-staging-20261016T011458Z.sql`,
  also in R2 `midas-backups`): founder's account 86 writes, 49 tombstones, items 77 -> 77; test
  account reminders 10 writes, care-reminders 8 writes; no schema problems; 6 insert statements. A
  second dry run changes nothing.
- **Not done: the check on the phone (Midas Test).** Needs a Midas Test build from this branch on
  the phone first: an older shell refuses the new pages' undated items (its reminder check wanted
  `at`) and knows no `update`, files or `$type` stamping.

## Lead

- `backend/wrangler.jsonc`: `{ "binding": "FILES", "bucket_name": "midas-files-staging" }` in the
  staging env `r2_buckets`, `{ "binding": "FILES", "bucket_name": "midas-files" }` at the top level.
  Redeploy staging after. No `package.json` change is needed.
- `docs/PRODUCT.md` (section 5, data model / notifications, and section 2 data format): every record
  carries `$type`; schemas live in each Sidekick's `manifest.json` `types` block; one validator
  `shell/sdk/record-schema.js`; `store.update`, `store.putFile`, `store.fileUrl`; a record holds at
  most 64 KB, a file at most 20 MB in R2 `midas-files`; refused ops are never dropped and are counted
  on the home screen; `task:` and `body` retired, `settings:self`; care early alerts and hourly times
  are fields on the item that the engine expands; Done is one change for every writer. State: all
  phases built and committed on `agent/data-rework`, staging migrated 2026-10-15, phone check and
  live pending.
- `docs/primitives/` is not in git: `daily-planner/records.md` must drop its own `task:` shape and
  `v` field and use `$type` plus a `types` block in the manifest.
- Merge order with the repair work (plan section 14): this branch and repair merge together after the
  founder checks the feature; `runner/agents/reminders.md` still describes `task:`, `body` and "no
  file store" and is for that later pass.

## Founder (live), in order

1. Install a Midas Test build from this branch on the phone; open Reminders and care-reminders
   against staging; check undated items, Done from a notification and a widget, an hourly reminder.
2. Create the R2 bucket `midas-files` (and `midas-files-staging` if the lead's binding needs it).
3. Deploy the Worker live, then `node scripts/deploy-sidekick.mjs reminders --env live` and
   `care-reminders --env live`, then a TestFlight build, then
   `node scripts/migrate-records.mjs --env live --dry-run` and, when the plan looks right,
   `node scripts/migrate-records.mjs --env live` (backs up first).

## Decisions the builder made (confirm or change)

- Validator: a hand-written JSON Schema subset in `shell/sdk/record-schema.js` instead of
  `@cfworker/json-schema` (plan section 3 named it as a proposal). Reason: no `package.json` change
  allowed, and the shell loads the same file into JavaScriptCore without a bundler. Same file in the
  Worker, the shell and tests.
- `at` is optional for the shell's own `reminder:` check (undated items); a record without `at`
  notifies nobody.
- Pages stamp `$type` themselves as well as the shell gate.
- Server: an op without `sidekickVersion` is checked against the user's current version; a version
  without `types` is not content-checked. An old shell pushing records without `$type` against a
  manifest with types is refused and keeps them on the phone (shown as not backed up): ship the
  shell update before deploying new manifests live.
- Snooze on an early alert or hourly time snoozes the item (one `snoozedUntil`); the snoozed
  notification carries the item's title.
- Files are per user, not per Sidekick: any Sidekick of the user can read a file by its reference.
- Done on a repeat from the care page now also writes `lastDoneAt` (it wrote `doneThrough` only),
  so every writer produces the same record.

## Test-guardian requests

All accepted, all logged in `TEST_CHANGES.md`: the change-log merge; the directory-test compile fix;
RecordSyncTests (refused op stays, reply reasons); reminders-logic (`task:` retired);
ReminderRecordTests, MidasStoreScriptTests, RemindersSidekickTests (undated items);
RecordTypeGateTests (bad `at`); CareRemindersSidekickTests, CareRemindersHourlyRepeatTests,
CareRemindersSimpleSheetTests (one record and the expansion, three tests replaced by
CareRemindersFieldsTests); ReminderExpansionTests epochs; ReminderActionTests and
NotificationEngineTests (snooze removed, not null); compile fixes in RecordWriterTests,
RecordSyncFilesTests and record-upgrades.test.ts.

## Open questions for the founder (collected, not asked)

1. Backward compatibility for later schema changes a repair makes to a copy (plan section 14, open).
2. Whether a snooze on an early alert should carry the alert's wording rather than the item's title.
3. Whether files should be readable across a user's Sidekicks (today: yes, by reference).
