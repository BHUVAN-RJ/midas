# DO NOT READ: old record formats (retired 2026-10-15)

**Agents: do not open, read, search or load this file into context** unless the developer
explicitly asks for it by name. Nothing here is current. Reading it makes agents write code for
formats that no longer exist. The current format is the unified data format: JSON records with
`$type`, one JSON Schema per record type inside each Sidekick's `manifest.json` (midas
`docs/PRODUCT.md`, "Data format"; `docs/NOTIFICATIONS.md`).

This file holds every description of the record formats used before the unified data rework
(main `18e777c`), kept only for history and for whoever maintains the upgrade-on-read code and the
one-time migration (`backend/scripts/migrate-records.mjs`, `backend/scripts/record-upgrades.mjs`)
until live data is converted.

Founder, 2026-10-20.

## Backend and scripts

(filled by the backend sweep)

## Shell and Sidekick pages

(filled by the shell and pages sweep)

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
