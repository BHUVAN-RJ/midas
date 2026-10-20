# Legacy sweep, agent C: for the lead (2026-10-20)

Branch `agent/legacy-sweep-c`. Things agent C may not change or that sit outside its worktree.

## 1. `docs/PRODUCT.md` (lead only)

Two places still show `body` as the notification field of a `reminder:` record:

- D8 (line 124, inside the build1-deliverables block): `` `{ at, title, body }` `` → `` `{ at, title }` ``.
- "Notifications" (line 522): `` `store.set("reminder:<id>", { at, title, body })` `` →
  `` `store.set("reminder:<id>", { at, title })` ``.

The D8 text must stay identical to midas-intel `docs/designs/jess-personal-assistant-shell.md`
D8 (line 1594; `intel/tests/test_build1_deliverables.py` compares them against the main checkout).
Agent C left the design doc's D8 as it is so that test stays green; change both in the same
session. The design doc's other mention (line 854) is already `{ at, title }`.

## 2. `docs/primitives/daily-planner/` (untracked, main checkout only)

Not in git and not in any worktree, so not swept. About 155 old-shape hits over 17 files
(`task:` keys, a `v` field, `lastDoneAt`, epoch ms), main ones in `records.md`, `checklist.md`,
`blocks/capture.md`, `blocks/item.md`. It needs moving to `$type` plus a manifest `types` block
before it is used or committed. The untracked `tests/guard/test_daily_planner_primitive.py` next
to it may assert on that text.

## 3. Shell behaviour the docs no longer describe (agent B's scope)

`shell/Midas/ReminderRecord.swift` still reads `body` as notification text and accepts epoch
milliseconds for `at`, with the messages `reminder.body must be a string` and
`reminder.at must be an ISO 8601 date or epoch milliseconds`. `docs/NOTIFICATIONS.md` now lists
`notes` (not shown in the notification) and quotes the `at` message as
`reminder.at must be an ISO 8601 date ...`. If that code becomes upgrade-on-read only, nothing
more is needed in the docs.

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
`lastDoneAt` as epoch ms and a `task:` key). `docs/plans/2026-10-20-legacy-sweep-brief.md` names
the markers on purpose and was left as it is.

## 5. One existing test is red until test-guardian can finish

`backend/test/runner-repair-data.test.ts:229` expects the Reminders repair prompt to contain
"Retired, never write them: `task:`", the old-shape line this sweep removed. test-guardian found
the change acceptable (founder 2026-10-20, old-format sweep) but could not prove it: its Bash
test runs were denied by the permission classifier, so it reverted and logged nothing.
Wanted change (stricter than before):

```
-    expect(prompt).toContain("Retired, never write them: `task:`");
+    expect(prompt).not.toContain("task:");
+    expect(prompt).toContain("Every item, dated or not, is a `reminder:` record");
```

Re-send it to test-guardian in a session where it may run the tests. The new
`backend/test/legacy-sweep-docs.test.ts` already requires the prompts to hold no `task:`.
