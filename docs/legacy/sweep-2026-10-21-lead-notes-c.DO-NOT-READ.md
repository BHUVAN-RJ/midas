# Second old-format sweep, agent C (docs, briefs, prompts, midas-intel): for the lead (2026-10-20)

Branch `agent/legacy-sweep2-c`. Brief: midas-intel `docs/plans/2026-10-21-legacy-sweep-2-brief.md`.
The founder decision is on main (`ede0f55`, `docs/PRODUCT.md` "Old formats retired (founder,
2026-10-20)", `CLAUDE.md`), merged into this branch. Every date agent C wrote is 2026-10-20.

## 1. Lead-only files: changes still open

`docs/PRODUCT.md`:

- line 525 ("Notifications"): drop "; the engine read `body` until then", so it reads
  "Notifications show the record's `notes` under the title (founder, 2026-10-20)."
- line 616: "Not built. Founder, 2026-10-13: in scope now, built in the unified data rework
  (midas-intel `docs/plans/2026-10-13-unified-data-v1.md`)." → "Built 2026-10-15 in the unified
  data rework: `store.putFile` / `store.fileUrl`, files in R2 as `file:<id>`, 20 MB (midas-intel
  `docs/plans/2026-10-15-unified-data-v2.md`)." (v1 is a superseded plan; files are on main since
  `18e777c`.)

The quarantine file's intro (no agent's section) is agent A's, per the lead.

## 2. Matches agents A and B (true on `main` once all three merge)

- `runner/README.md`: the reporter's records are checked as stored (no in-memory upgrade, no
  `record-upgrades.mjs`), the `records do not fit schema` detail names no stored key, and
  `runner error` covers a checkout lacking the validator or the store helper. Matches A's notes.
- `docs/NOTIFICATIONS.md` 4.6 quotes `reminder.at must be an ISO 8601 date`; 4.2 and the example
  name only `notes`. Matches B's notes (`body` is not read at all).
- `docs/briefs/data-rework-product-changes.md`: lines 17, 66-67 and the test log line (A's list)
  no longer name the two scripts or the live migration commands.
- `backend/test/legacy-sweep-docs.test.ts` line 79 goes through test-guardian on this branch.
  Brief item 3 names this file too: if A also changes it, expect a merge clash there and in
  `TEST_CHANGES.md`. It has no allow-list for the converter or the migration: it skips only
  `docs/legacy/` and `docs/PRODUCT.md`.

## 3. Kept as is, not hits

- `docs/NOTIFICATIONS.md:289` "epoch seconds": the suffix of a notification identifier, current.
- `lastDoneAt` in NOTIFICATIONS 4.2/4.5, WIDGETS, the reminders-app and widget-reminders briefs,
  concern 2026-10-11 #3 and both repair prompts: the current field written with `doneThrough`.
- `docs/briefs/repair-data-2026-10-19.md` lines 17, 41, 44 ("shapes from before the rework", "hold
  old shapes"): the dated brief's task statement, no shape described.
- "Add only" rule in both prompts, "older phones still write them": older app versions writing
  today's schema shapes, still true.
- Untouched as in sweep 1: midas-intel `docs/prototypes/`, the two legacy-sweep briefs (they name
  the markers on purpose), `docs/primitives/daily-planner/` (untracked, main checkout only).

## 4. Test-guardian

- `legacy-sweep-docs.test.ts:79`: `toContain("stays as it is; write only the")` →
  `not.toContain("stays as it is")` plus `toContain("Write only the types above.")`. First answer
  NEEDS-EVIDENCE (decision not yet in PRODUCT.md); resent after `ede0f55`.
- New `legacy-sweep-2-docs.test.ts` (written this session): its dates 2026-10-21 → 2026-10-20.

## 5. midas-intel (edited in place, not committed)

- `docs/plans/2026-10-15-unified-data-v2.md` (untracked in midas-intel): status line (built and
  merged, live converted 2026-10-20), section 8 (done; migration and upgrade on read retired),
  section 9 item 7, section 10, the backward-compatibility answer (the "breaking change with its
  migration" exception dropped by the founder 2026-10-19).
- No other hit in `CLAUDE.md`, `docs/designs/`, `docs/process/` or the other plans. Every dated
  research note with old shapes already carries the superseded header.
- Still uncommitted in midas-intel from sweep 1: `docs/designs/jess-personal-assistant-shell.md`,
  `docs/plans/2026-10-13-voice-reminders-v1.md`, `docs/process/sidekick-design-process.md`; the
  plans folder holds untracked plans (`2026-10-13-unified-data-v1.md`, `2026-10-15-*`,
  `2026-10-20-legacy-sweep-brief.md`, `2026-10-21-legacy-sweep-2-brief.md`).
