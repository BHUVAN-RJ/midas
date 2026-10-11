-- Sidekicks are assigned per person (2026-10-10). A user sees and can load only the Sidekicks
-- assigned to them. Rows are only inserted; unassigning is the founder's to run by hand.
-- Apply with: node scripts/migrate.mjs --env staging|live

CREATE TABLE assignments (
  user_id TEXT NOT NULL REFERENCES users(id),
  sidekick_id TEXT NOT NULL,
  assigned_at TEXT NOT NULL,
  PRIMARY KEY (user_id, sidekick_id)
);
