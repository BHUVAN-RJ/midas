# Legacy sweep, agent C: for the lead (2026-10-20)

Branch `agent/legacy-sweep-c`. Things agent C may not change or that sit outside its worktree.

## 1. `docs/PRODUCT.md` (lead only)

Two places still show `body` as a field of a `reminder:` record:

- D8 (line 124, inside the build1-deliverables block): drop `body` from the record's field list,
  leaving `at` and `title` (or `at`, `title`, `notes`, now that notifications show `notes`).
- "Notifications" (line 522): the same in the `store.set("reminder:<id>", ...)` example.

The D8 text must stay identical to midas-intel `docs/designs/jess-personal-assistant-shell.md`
D8 (line 1594; `intel/tests/test_build1_deliverables.py` compares them against the main checkout).
Agent C left the design doc's D8 as it is so that test stays green; change both in the same
session. The design doc's other mention (line 854) already lists only `at` and `title`.

## 2. `docs/primitives/daily-planner/` (untracked, main checkout only)

Not in git and not in any worktree, so not swept. About 155 old-shape hits over 17 files (the
retired undated-item key, a `v` field, `lastDoneAt`, epoch ms), main ones in `records.md`,
`checklist.md`, `blocks/capture.md`, `blocks/item.md`. It needs moving to `$type` plus a manifest
`types` block before it is used or committed. The untracked
`tests/guard/test_daily_planner_primitive.py` next to it may assert on that text.

## 3. Notifications show `notes` (settled)

Settled 2026-10-20 (lead): notifications show the item's `notes` (founder decision, built on
`agent/legacy-sweep-b`). `docs/NOTIFICATIONS.md` carries agent B's edits: `notes` row, example,
`reminder.notes must be a string`, "the record's `title` and `notes`". These describe B's
branch; they are true on `main` once both branches merge. Epoch ms stay readable in the shell
until the live conversion (B's notes, item 2); the doc quotes the `at` message as
`reminder.at must be an ISO 8601 date ...`.

## 4. midas-intel (edited in place, not committed)

Edited: `docs/plans/2026-10-15-unified-data-v2.md`, `docs/plans/2026-10-13-voice-reminders-v1.md`
(section 6), `docs/designs/jess-personal-assistant-shell.md` (line 854),
`docs/process/sidekick-design-process.md` (line 179). Header added ("Superseded by the unified
data format (2026-10-15); old shapes are not current"): `docs/plans/2026-10-13-unified-data-v1.md`,
`docs/research/agent-ready/{reminders-voice-engine,single-file-protocol,data-format-domain-standards,data-inventory-2026-10-13,data-plan-recheck-2026-10-15}.md`,
`docs/research/reminders-list-rules/PROPOSAL.md`. The design doc and the voice-reminders plan
already had someone else's uncommitted edits; those were kept.

Not touched (outside the brief's midas-intel list): `docs/prototypes/reminders-bhuvan/*.html` and
`docs/prototypes/reminders/repeat-after-completion.html` (dated prototypes that simulate
`lastDoneAt` as epoch ms and the retired undated-item key). `docs/plans/2026-10-20-legacy-sweep-brief.md`
names the markers on purpose and was left as it is.

## 5. Repair prompt test (done)

`runner-repair-data.test.ts:229` now requires the Reminders repair prompt to hold no old
undated-item key and to state that every item is a `reminder:` record. test-guardian accepted it
on 2026-10-20 (founder 2026-10-20, old-format sweep), proved it fails with the old prompt text,
and logged it.
