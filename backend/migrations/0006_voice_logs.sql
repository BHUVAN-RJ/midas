-- Voice log (founder, 2026-10-19): every voice reminder attempt, to see what worked and what did
-- not. Kept apart from people's data: separate from the ops table, never read by the app and never
-- synced to phones. Written by POST /voice/reminder/parse after the reply is sent (waitUntil);
-- read only by the founder's script backend/scripts/voice-log.mjs. Later (not now) it is rebuilt to
-- obscure people's words and keep only errors.
-- Apply with: node scripts/migrate.mjs --env staging|live

CREATE TABLE voice_logs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL,
  transcript TEXT NOT NULL,
  -- The request context the phone sent: its clock, time zone, locale and the user's list names
  -- (JSON array of {id, name}).
  request_now TEXT,
  time_zone TEXT,
  locale TEXT,
  lists TEXT,
  model TEXT NOT NULL,
  -- The model's message text, as received, from the last call that answered (null when none did).
  raw_reply TEXT,
  status TEXT NOT NULL CHECK (status IN ('done', 'not-done')),
  -- done: the resolved reminder as JSON. not-done: the reason (voice.ts NotDoneReason).
  result TEXT,
  reason TEXT,
  -- Calls made after the first (0 or 1).
  retries INTEGER NOT NULL DEFAULT 0,
  -- JSON array, one entry per step: {"step": "model", "attempt": 1, "ms": 812, "error": null},
  -- {"step": "resolve", "ms": 1}.
  steps TEXT,
  total_ms INTEGER,
  -- How long the phone listened, as the phone measured it.
  listen_ms INTEGER,
  app_version TEXT,
  app_build TEXT,
  ios_version TEXT,
  device TEXT
);
CREATE INDEX voice_logs_by_time ON voice_logs(created_at);
CREATE INDEX voice_logs_by_status ON voice_logs(status, created_at);
