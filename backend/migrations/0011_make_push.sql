-- Make pushes (founder, 2026-10-24; docs/briefs/make-contract.md section 4).
-- push_devices: one row per APNs device token the shell registered (POST /push/register). A token
-- APNs refuses (410, or BadDeviceToken on both hosts) is disabled, never deleted.
-- make_events: one row per push Make sends: a new question card or a Built request (to the
-- person), a person's message or answer (to the founder). The id is the dedupe key, so one event
-- is pushed once; sent_at stays NULL until a send has a final outcome, so a fallback sender can
-- find the rows left over. result is the last outcome in words.
-- Additive only. Apply with: node scripts/migrate.mjs --env staging|live (staging first).

CREATE TABLE push_devices (
  token TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
  env TEXT NOT NULL CHECK (env IN ('sandbox','production')),
  bundle_id TEXT NOT NULL CHECK (bundle_id IN ('com.bhuvanrj.midas','com.bhuvanrj.midas.test')),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, disabled_at TEXT, disabled_reason TEXT);
CREATE INDEX push_devices_by_user ON push_devices(user_id, disabled_at);
CREATE TABLE make_events (
  id TEXT PRIMARY KEY,
  audience TEXT NOT NULL CHECK (audience IN ('person','founder')),
  user_id TEXT NOT NULL, about_user_id TEXT NOT NULL, request_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('card','built','message','answer')),
  title TEXT NOT NULL, body TEXT NOT NULL,
  created_at TEXT NOT NULL, sent_at TEXT, result TEXT);
CREATE INDEX make_events_unsent ON make_events(sent_at, created_at);
