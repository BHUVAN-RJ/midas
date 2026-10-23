-- What a repair came to, in the user's terms (founder, 2026-10-23, docs/briefs/repair-ux-upgrade.md):
-- the shell's Repair tag shows Fixed ("Repair done. Click to update"), Already There or Couldn't
-- Fix, and a tap shows the runner's one-line summary. Before this the only user notice was the
-- fixed "done" text, and a runner "no change" was stored and shown as failed.
--
-- result_kind: fixed (deployed_live), already_there (the runner found nothing to change; the
-- status stays 'failed' with fail_reason 'no change', because the status CHECK cannot change
-- without rebuilding the table, which the no-data-loss rails forbid), couldnt_fix (any other
-- failure). NULL while the repair is still open, and on rows from before this migration.
-- result_summary: the runner's summary for fixed and already_there; never a failure reason.
-- Additive only. Apply with: node scripts/migrate.mjs --env staging|live (staging first).

ALTER TABLE repair_reports ADD COLUMN result_kind TEXT CHECK (result_kind IN ('fixed', 'already_there', 'couldnt_fix'));
ALTER TABLE repair_reports ADD COLUMN result_summary TEXT;
