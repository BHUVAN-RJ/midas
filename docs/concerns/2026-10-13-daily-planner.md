# Daily planner primitive (session of 2026-10-12 to 2026-10-13)

Handoff from the lead session that ran the daily planner research and wrote the primitive docs.
Recording only; nothing here is decided or approved to build.

## 1. Decided by the founder in chat

- 2026-10-12: the friend's Structured-style app is a **daily planner**, not a reminders app; treated
  as a new category. Research: planners and calendars wide; UI/UX first plus the full brief;
  category placement as facts only, no verdict.
- 2026-10-12: primitive docs cover both page blocks plus recipe and shell briefs; they live in
  midas `docs/primitives/daily-planner/`; all 69 patterns specified, core ones tagged.
- To move: the lead adds a line on the daily planner category to `docs/PRODUCT.md` section 2 and
  the midas-intel design doc. Not done here because PRODUCT.md holds another session's
  uncommitted edits (2026-10-13).

## 2. Uncommitted work (not committed by this handoff)

- midas `main`: `docs/primitives/daily-planner/` (19 files, about 5,200 lines: README, recipe,
  records, checklist, 10 `blocks/`, 5 `shell/` briefs) and `tests/guard/test_daily_planner_primitive.py`
  (8 tests; shown to fail when a pattern ID is changed). Last full run `scripts/test-all.sh`: all
  suites passed (guard 36, backend 156, shell, midas-intel 31). Commit when the founder says.
- midas-intel `main`: `docs/research/daily-planner/` (BRIEF, structured-ui-teardown, group-a to
  group-d, category-and-completeness, ANALYSIS). `structured-ui-teardown.md` was moved there from
  `docs/research/reminders/`.
- Screenshots used by the research live only in the session scratchpad
  (`/private/tmp/claude-501/-Users-bhuvanrj-Desktop-Midas/3246bf72-b422-4ae5-8f17-82ce11ee64f2/scratchpad/shots/`)
  and are lost on reboot. Offered to copy them into midas-intel; no answer.

## 3. Waiting on the founder

- The 11 open choices in `docs/primitives/daily-planner/recipe.md` section 6 (core tags, defaults,
  agent-chosen numbers, wording, energy ring, SF Symbols in a page, Watch without a brief,
  `records.md` choices, engine facts, two doc/code contradictions).
- The first request (2026-10-12), deferred: a clickable Structured-style HTML prototype from the
  recipe's Structured preset, published as an Artifact. Offered; waiting for "go".
- Shell briefs in `shell/` (calendar access, local-time alerts, repeat exceptions, planner widget,
  Live Activity): drafts, none approved.

## 4. Found, out of brief

- `docs/NOTIFICATIONS.md` section 7 says records are not synced; `RecordSync.swift` syncs them per
  account. The owner of NOTIFICATIONS.md settles it.
- `docs/PRODUCT.md` says `store.query` supports single-field equality; `shell/sdk/midas-store.js`
  sends a key prefix only. The lead settles it.
- Engine: Done on one occurrence of a repeat cannot stop that day's other alerts (concern 3); Done
  on one alert does not stop a task's other alerts until the page opens; an alert written with a
  past time fires at once as "missed"; a repeating alert cannot be pinned to a time zone; no
  ActivityKit in the shell and the minimum iOS is 17.

## 5. Care-reminders staging request (from a peer session, during this session)

- A peer session (worktree branch `agent/care-reminders`, HEAD `0ce06e9`) asked the founder to
  run `node scripts/deploy-sidekick.mjs care-reminders --env staging`, assign it to staging "R J",
  and run on the Simulator. Not done from this session. `0ce06e9` is now on `main` and commit
  `048b15c` records care-reminders as merged and live, so the request is probably superseded; the
  founder confirms.
