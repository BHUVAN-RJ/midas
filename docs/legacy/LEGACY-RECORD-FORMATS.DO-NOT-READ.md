# DO NOT READ: old record formats (retired 2026-10-15)

**Agents: do not open, read, search or load this file into context** unless the developer
explicitly asks for it by name. Nothing here is current. Reading it makes agents write code for
formats that no longer exist. The current format is the unified data format: JSON records with
`$type`, one JSON Schema per record type inside each Sidekick's `manifest.json` (midas
`docs/PRODUCT.md`, "Data format"; `docs/NOTIFICATIONS.md`).

This file holds every description of the record formats used before the unified data rework
(main `18e777c`), kept only for history. Live and staging are converted and no code reads or
writes these shapes (founder, 2026-10-20; `docs/PRODUCT.md`, "Old formats retired"). The retired
converter and one-time migration are kept, not run and not tested, in
`docs/legacy/code/record-upgrades.mjs` and `docs/legacy/code/migrate-records.mjs`.

Founder, 2026-10-20.

## Backend and scripts

**Retired 2026-10-20** (founder: live converted, migration retired; dry run 0 writes). No code
in the backend, runner or scripts reads or writes these shapes any more. The converter and the
migration were moved from `backend/scripts/` to `docs/legacy/code/record-upgrades.mjs` and
`docs/legacy/code/migrate-records.mjs`: kept for history, not imported, not run, not tested (their
imports still name the old place). Their tests (`record-upgrades.test.ts`,
`record-upgrades-snoozes.test.ts`, `runner-clash-moved-key.test.ts`) were removed through
test-guardian. The runner checks a reporter's records exactly as stored; the copies planner flags
any literal write a copy's types do not declare instead of a list of retired keys.

Until 2026-10-20 the converter was also used in memory by `runner/lib/user-records.mjs` (and so by
the user-copy planner), and `RETIRED_WRITE_PATTERNS` in it listed literal `store.set` /
`store.update` writes of `task:` keys ("writes task: records") and of `settings:sidebar`
("writes settings:sidebar") for the planner to flag.

Old shapes the converter turned into the unified format:

| Old shape | Sidekick | Becomes |
|---|---|---|
| `task:<id>` key (undated item) | reminders | `reminder:<id>`, plus a tombstone on `task:<id>` (skipped if `reminder:<id>` exists) |
| `settings:sidebar` | reminders | `settings:self`, plus a tombstone |
| `body` on an item | reminders | `notes` (only when `notes` is missing and `body` is not empty); `body` removed |
| Epoch milliseconds in `at`, `snoozedUntil`, `lastDoneAt`, `doneThrough`, `completedAt`, `createdAt`, `finishedAt`, `exportedAt`, `occurrenceAt`, `repeat.until` | all | ISO 8601 text |
| `null` fields (e.g. `list: null`) | all | field removed |
| Record without `$type` | all | `$type` stamped from the manifest's `types` |
| `reminder:<item>~<ruleId>` alert record | care-reminders | folded into the item: `done: true` with `completedAt` from its `lastDoneAt` (one-time), `doneThrough` from its `occurrenceAt` (repeat); its `snoozedUntil` becomes `snoozes["~<ruleId>"]`; record tombstoned |
| `reminder:<item>@HHMM` time record | care-reminders | folded into the item: its `lastDoneAt` becomes `slotsDone["HH:MM"]`, its `snoozedUntil` becomes `snoozes["@HHMM"]`; record tombstoned |
| Care item fields `kind`, `body`, `icon`, `alertRules`, `seriesId` | care-reminders | removed; the list's `alerts` rules copied onto the item as `alerts` (none for an hourly item with `everyHours` 2, 3 or 4 and a daily repeat; `everyHours` removed otherwise) |
| Care list rules | care-reminders | cleaned to their kind's fields: `daysBefore` {days 1-14, time default 18:00}, `morningOf` {time default 08:00}, `before` {minutes, default 60}; `text` kept only when not empty |

Text moved here from code comments (2026-10-20 sweep):

- `runner/lib/user-records.mjs` header: records "still in an older shape (no `$type`, `task:`,
  `body`, epoch ms, care `~rule` / `@HHMM` parts)" are upgraded in memory before the check.
  Its comments used `task:9 -> reminder:9` as the example of a record the upgrade moves to a new
  key, and the failure detail reads `reminder:9 (stored as task:9)` for such a record.
- `runner/lib/schema-change.mjs`: literal reads are not counted as writes because the reminders
  page queries `task:` once on read to move those records forward.

Text and behaviour removed from code (2026-10-20 sweep):

- `runner/lib/user-records.mjs`: records "stored before the unified data format are first
  upgraded in memory the way the page upgrades them on read"; the check returned an `upgraded`
  count and, for a record the upgrade moved to a new key, `storedAs` (failure detail
  `<key> (stored as <old key>)`); the clash check also looked at each record's upgraded form and,
  for a failed upgrade that moved key, at the stored value under the new key.
- `runner/lib/summary.mjs`: the records line ended "(N old-shape changes applied in memory only)".
- `runner/lib/run-job.mjs`: "modules: the checkout's validator and upgrades"; `loadDataModules`
  also required `backend/scripts/record-upgrades.mjs` in the checkout.
- `backend/scripts/user-copy-plan.mjs` header: the copy's types "narrow what the shell accepts
  from that page (keys built from variables, older value shapes)"; "a page that still writes
  retired shapes needs its repair carried onto today's base".
- `backend/scripts/plan-user-copies.mjs`: "repaired with retired shapes"; it ended by printing
  `Records: node scripts/migrate-records.mjs --env <env> --dry-run`.
- `backend/scripts/wrangler.mjs`: the capture buffer comment said "the migration reads every op".
- `runner/lib/schema-change.mjs`: "a page's upgrade-on-read code may still read a retired prefix
  to move it forward".

## Shell and Sidekick pages

Moved here by the shell and pages sweep (2026-10-20) from `shell/` and `sidekicks/` comments.

### Where code read these shapes (upgrade on read, removed 2026-10-20)

Removed by the second sweep (founder, 2026-10-20: live and staging converted; docs/PRODUCT.md "Old formats retired"). Since then the
shell and both pages read only the current format: a number is not a date
(`reminder.at must be an ISO 8601 date`), `body` is not read, and the pages neither read nor
delete `task:`, `settings:sidebar`, `reminder:<id>~<rule>` or `reminder:<id>@HHMM` records nor
drop old fields on write. `backend/test/legacy-quarantine-shell-pages.test.ts` fails if any of it
comes back. The care page keeps one step the fold also did for current records: on sync a
repeat's `doneThrough` catches up with the shell's `lastDoneAt` / `slotsDone`
(`catchUpDoneThrough`).

What each file read until then:

| File | What it read | Marked by |
|---|---|---|
| `shell/Midas/ReminderRecord.swift` `parseDate` | a number as epoch milliseconds | comment "Upgrade on read" |
| `shell/Midas/ReminderRecord.swift` `parseNotes` | `body` as the notification text when `notes` is not a string | comment "Upgrade on read" |
| `sidekicks/reminders/index.html` | `task:<id>` records, `body` as notes, `settings:sidebar`; drops `body` on write | header above `RemindersLogic`, each spot "Upgrade on read" |
| `sidekicks/care-reminders/index.html` | `reminder:<id>~<rule>` and `reminder:<id>@HHMM` records (folded into the item, then deleted); drops `icon`, `alertRules`, `seriesId`, `kind`, `body` on write | header above `CareLogic`, each spot "Upgrade on read" |

### The old reminder record as the shell's comment described it

`reminder:<id>` → `{ at, title, body?, repeat?, timeZone?, done?, snoozedUntil?, lastDoneAt? }`,
`at` an ISO 8601 string **or epoch milliseconds**; `body` the notification text. No `$type`.
Until 2026-10-20 the engine read only `body` (checked as `reminder.body must be a string`), so
after the pages stopped writing `body` (2026-10-15) their notifications had no text line; since
2026-10-20 it reads `notes` (founder).

### Reminders page (before 2026-10-15)

- Undated items lived under `task:<id>`; an item moved between `task:` and `reminder:` when its
  date was set or cleared. The widget tests said "the Sidekick keeps undated ones under task:".
- `body` was written as a copy of `notes`.
- The sidebar settings lived under `settings:sidebar` (now `settings:self`).

### Care-reminders page (before 2026-10-15)

- Each early alert was its own record `reminder:<itemId>~<ruleId>` (`kind: "care-alert"`,
  `at` the alert's moment, own `title` wording, own `done`, own `snoozedUntil`, `occurrenceAt`
  the occurrence it served). Each extra hourly time was its own record
  `reminder:<itemId>@<HHMM>` (`kind: "care-slot"`, `time: "HH:MM"`, a daily repeat, own
  `lastDoneAt`, own `snoozedUntil`). The item itself had `kind: "care-item"` and `body: ""`;
  earlier still, its own `icon`, its own `alertRules`, and a `seriesId` (2026-10-12).
- A reminder moved to a new time lost its alert and time records' snoozes and Dones.
- Widgets selected items with `where: { kind: "care-item" }` (now `$type: "care.item"`).
- The fold (`foldLegacyRecords`) maps them onto the item: an alert record with `done: true`
  completes a one-time item, or moves a repeat's `doneThrough` to that record's `occurrenceAt`;
  an alert record's `snoozedUntil` (not done) becomes `snoozes["~<ruleId>"]`; a time record's
  `lastDoneAt` becomes `slotsDone["HH:MM"]` and its `snoozedUntil` becomes `snoozes["@HHMM"]`;
  then every such record is deleted (its rows stay in the server's history).

## Docs, briefs and prompts

Moved here by the docs sweep (agent C, 2026-10-20). Each entry says where the text was and what
it said about the old formats; the place it came from now describes only the current format.

### Old record shapes these docs described

- **Reminders undated items** were `task:<id>` records (same fields as a `reminder:` item, without
  `at` / `repeat`); the shell ignored them. An item moved between `task:` and `reminder:` when a
  date was added or removed (set then delete). `voice-reminders-v1` section 6 (midas-intel) said:
  key `reminder:<id>` if dated, `task:<id>` if not; value `title`, `list` (list id or `null`),
  `done: false`, `timeZone`, `createdAt`, `notes` and `body` only if there are notes, if dated
  `at`, `allDay`, `repeat`.
- **`body`** was the notification text field of a `reminder:` record (`{ at, title, body }`,
  `{ at, title, body, repeat, timeZone }` in the D8 text, the notification-engine,
  reminders-app and notification-mockups briefs, and the jess design doc). The Reminders page
  wrote the same text to `notes` and `body`. NOTIFICATIONS.md 4.2 listed `body` ("Notification
  text. The Reminders page stores `notes` instead and writes no `body`"), its section 1 example
  wrote `body: 'Bring the insurance card'`, and section 5 said the notification shows "the
  record's `title` and `body`".
- **Epoch milliseconds for `at`**: NOTIFICATIONS.md 4.2 said "Old records may still hold epoch
  milliseconds; new writes may not". The runner prompts said instants are ISO strings, "never
  epoch milliseconds".
- **Shell check messages** listed in NOTIFICATIONS.md 4.6 that name old shapes:
  `reminder.at must be an ISO 8601 date or epoch milliseconds`, `reminder.body must be a string`;
  the schema example `no record type is declared for task:1`.
- **`lastDoneAt` as the sign of Done on a repeat**: the NOTIFICATIONS.md 4.5 example read
  `laundry.lastDoneAt → user tapped Done on a repeat occurrence`; the reminders-app brief listed
  only `done`, `snoozedUntil`, `lastDoneAt` as the fields taps write.
- **care-reminders early alerts and hourly times** were records of their own:
  `reminder:<id>~<ruleId>` (early alert) and `reminder:<id>@HHMM` (hourly time), with fields
  `kind` and `body`. NOTIFICATIONS.md section 7 said per-alert snoozes are "the behaviour from
  before the rework, when each was a record of its own". The unified-data-v2 plan selected care
  items in widgets with `kind:'care-item'`.
- **`history:<id>`** was described in the Reminders repair prompt only as "completed occurrences".
- **"Records are not synced"**: the reminders-app brief said "Records are on the phone only for
  now (not synced to the backend)"; the daily-planner concern quoted NOTIFICATIONS.md section 7
  saying records are not synced.
- **sidekick-design-process (midas-intel)** listed the reminders plan's records as `reminder:` for
  dated, `task:` for undated (the engine required `at`), `list:`, `settings:sidebar`.

### Rewrites the migration does (unified-data-v2 section 8, as it was written)

`task:` → `reminder:` plus a tombstone for the `task:` key; `body` → `notes`; epoch ms → ISO;
`$type` added; care `~ruleId` and `@HHMM` records folded into their item plus tombstones; their
snoozes carried into the item's `snoozes`.

### Repair prompts (runner/agents), as they were

- Reminders: "Retired, never write them: `task:` (undated items are `reminder:` records without
  `at`) and `body` (the page stores `notes`). The page still reads old `task:` records once to
  move them forward; leave that code as it is."
- care-reminders: "Retired, never write them: `reminder:<id>~<ruleId>` (old early-alert records)
  and `reminder:<id>@HHMM` (old hourly-time records), and the fields `kind` and `body`. The page
  folds old records into their item on load; leave that code as it is."
- runner/README.md gave the example failure detail `reminder:9 (stored as task:9)`.

### Briefs and plans that named the retired shapes

data-rework-product-changes (phase 3: "`task:` retired, read and moved on next write, no `body`";
"`~rule`/`@HHMM` retired and folded in on load"; lead note "`task:` and `body` retired";
daily-planner `records.md` "must drop its own `task:` shape and `v` field"; "`runner/agents/reminders.md`
still describes `task:`, `body`"; test note "reminders-logic (`task:` retired)"), repair-data
2026-10-19 ("`task:` and `body` retired"; "no `task:` or `body`"), CONCERNS §8 ("the prompt drops
`task:`/`body`"), concern 2026-10-11 #1 ("a `task:` record" as the undated example),
unified-data-v2 rules 2 and 5 ("`task:` retired", "no epoch ms") and its section 4 table
("`task:` folded in; `notes` only (no `body`)", "`~ruleId` and `@HHMM` records retired").
