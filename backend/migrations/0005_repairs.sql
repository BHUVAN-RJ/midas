-- Repair reports (founder, 2026-10-13): a user scribbles in a Sidekick, draws and speaks; the
-- report lands here. Text and metadata in this table; screenshot, drawing and strokes in R2 under
-- repairs/<id>/ in the BUNDLES bucket, linked by id. Every repair is kept: this table is the
-- repair log. Status chain: received -> queued -> running -> fix_ready -> deployed_live | failed.
-- Apply with: node scripts/migrate.mjs --env staging|live

CREATE TABLE repair_reports (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  sidekick_id TEXT NOT NULL,
  bundle_version TEXT,
  -- user: the reporter was on their own copy; base: on the shared page (repair-copies).
  bundle_scope TEXT CHECK (bundle_scope IN ('user', 'base')),
  -- A hint from the phone; the agent decides from the transcript. feature (2026-10-13): a new
  -- capability asked by voice, possibly with no drawing at all.
  kind TEXT NOT NULL CHECK (kind IN ('bug', 'change', 'feature', 'unknown')),
  transcript TEXT NOT NULL,
  -- JSON word timings from the phone's transcriber, when it gives them.
  transcript_words TEXT,
  -- Text the user typed instead of or besides speaking.
  typed_text TEXT,
  -- The phone's own id for the report, so a retry after a lost reply stores one row, not two.
  client_report_id TEXT,
  device TEXT,
  ios_version TEXT,
  app_version TEXT,
  app_build TEXT,
  status TEXT NOT NULL CHECK (status IN ('received', 'queued', 'running', 'fix_ready', 'deployed_live', 'failed')),
  fail_reason TEXT,
  -- Lease: set by a claim; a running job whose lease_until has passed is claimed again.
  runner_id TEXT,
  lease_until INTEGER,
  attempts INTEGER NOT NULL DEFAULT 0,
  screenshot_key TEXT,
  drawing_key TEXT,
  strokes_key TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX repair_reports_by_user ON repair_reports(user_id, created_at);
CREATE INDEX repair_reports_by_status ON repair_reports(status, created_at);
CREATE UNIQUE INDEX repair_reports_client_id ON repair_reports(user_id, client_report_id);

-- The log is never shortened: the no-data-loss suite forbids any statement that removes rows
-- here, in Worker code, scripts and migrations alike (a trigger would need the forbidden word).

-- One row per thing someone must hear about. audience founder: request_received, fix_ready,
-- failed (the runner shows them on the Mac until a founder channel exists). audience user:
-- deployed_live ("The update you requested is done."), shown once by the shell.
CREATE TABLE repair_events (
  id TEXT PRIMARY KEY,
  report_id TEXT NOT NULL REFERENCES repair_reports(id),
  audience TEXT NOT NULL CHECK (audience IN ('founder', 'user')),
  kind TEXT NOT NULL CHECK (kind IN ('request_received', 'fix_ready', 'failed', 'deployed_live')),
  created_at TEXT NOT NULL,
  delivered_at TEXT
);
CREATE INDEX repair_events_undelivered ON repair_events(audience, delivered_at, created_at);
