-- Settings and delete (founder, 2026-10-31; docs/briefs/build-22-2026-10-31.md).
-- A person removes a Sidekick from their home grid: the assignment row stays and gets removed_at,
-- so nothing is ever lost from D1; every query of assignments reads only rows with removed_at
-- NULL. Its records go by delete ops appended to ops (history kept). sidekick_removals logs each
-- removal and how many records went.
-- A person asks for their account to be deleted: one row per user in account_deletion_requests,
-- the founder is pushed, and the founder carries out the deletion by hand (only the founder
-- deletes data). alert_result is the push's outcome in words.
-- Additive only. Apply with: node scripts/migrate.mjs --env staging|live (staging first).

ALTER TABLE assignments ADD COLUMN removed_at TEXT;

CREATE TABLE sidekick_removals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  sidekick_id TEXT NOT NULL,
  records_removed INTEGER NOT NULL,
  removed_at TEXT NOT NULL
);
CREATE INDEX sidekick_removals_by_user ON sidekick_removals(user_id, removed_at);

CREATE TABLE account_deletion_requests (
  user_id TEXT PRIMARY KEY REFERENCES users(id),
  user_name TEXT NOT NULL,
  requested_at TEXT NOT NULL,
  alert_result TEXT,
  carried_out_at TEXT
);
