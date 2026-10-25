-- Repair asked for on a Sidekick built into the shell (founder, 2026-10-24;
-- docs/briefs/make-contract.md section 6): the three-finger swipe on Make, Inbox or jess shows
-- "Repair not available" and logs one row here (POST /repairs/blocked). client_id is the shell's,
-- so a retried post is stored once.
-- Additive only. Apply with: node scripts/migrate.mjs --env staging|live (staging first).

CREATE TABLE repair_blocked (id TEXT PRIMARY KEY, user_id TEXT NOT NULL
REFERENCES users(id), sidekick_id TEXT NOT NULL, client_id TEXT NOT NULL, app_version TEXT, app_build
TEXT, created_at TEXT NOT NULL);
CREATE UNIQUE INDEX repair_blocked_client ON repair_blocked(user_id, client_id);
