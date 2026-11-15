-- Repair lanes, the setting lane (founder, 2026-11-13; docs/briefs/repair-lanes.md W5). A request the
-- sort put in lane `setting` is mapped to { key, value } changes by Haiku from the Sidekick's
-- catalogue and written to the person's settings:self record in the Worker: no runner job, no
-- publish. The report keeps status 'received' (never claimed), sort_status 'sorted', lane 'setting'.
--
-- setting_changes: the changes written, as JSON [{ key, label, value, previous }] (previous null when
--   the person had never set that key; Undo then removes it). NULL when the lane was not used.
-- setting_version: the Sidekick version whose catalogue and types the write was checked against.
-- setting_problem: why a `setting` request went up to code instead (no catalogue, no setting does
--   it, a timeout, a record the types refuse).
-- setting_latency_ms / setting_cost_usd: the Haiku mapping call.
-- setting_undone_at: when the person tapped Undo (POST /repairs/:id/undo); set once.
-- Additive only. Apply with: node scripts/migrate.mjs --env staging|live (staging first).

ALTER TABLE repair_reports ADD COLUMN setting_changes TEXT;
ALTER TABLE repair_reports ADD COLUMN setting_version TEXT;
ALTER TABLE repair_reports ADD COLUMN setting_problem TEXT;
ALTER TABLE repair_reports ADD COLUMN setting_latency_ms INTEGER;
ALTER TABLE repair_reports ADD COLUMN setting_cost_usd REAL;
ALTER TABLE repair_reports ADD COLUMN setting_undone_at TEXT;
