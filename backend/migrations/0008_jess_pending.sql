-- jess grows the Sidekick (founder, 2026-10-21; flagged, monitored): a spoken request the
-- Sidekick has no option for is kept here as a pending request, linked to the feature request it
-- filed with the repair agent (repair_reports). Right after the runner publishes that repair to
-- the user's own copy (repair_reports.status deployed_live), the runner runs the request again,
-- once, with its original time (POST /repairs/:id/jess-rerun), runs the new tools.js handler and
-- sends its ops (POST /repairs/:id/jess-rerun/ops), which are checked against the new version's
-- schemas and appended to the user's op log. The phone gets them through its normal pull.
-- Staging only from this branch; the founder applies it to live.
-- Apply with: node scripts/migrate.mjs --env staging|live
--
-- status: waiting (filed, repair not live yet), re-running (the one re-run was claimed; set by the
-- same statement that checks the repair is live, so it happens once), done (its ops are in the op
-- log; result_text is the handler's line for the banner), failed (fail_reason: the repair failed,
-- the re-run still could not act, the handler refused, an op did not fit the schema, or the runner
-- never finished). A done or failed request is shown once on the phone (the banner or the Not
-- Done card): shown_at.
-- steps: JSON array, one entry per step, {"step": "...", "at": "<ISO time>", ...}, for the
-- founder's script backend/scripts/jess-grow-log.mjs.
-- Rows are never removed (the no-data-loss suite), like the repair log.

CREATE TABLE jess_pending_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  sidekick_id TEXT NOT NULL,
  report_id TEXT NOT NULL REFERENCES repair_reports(id),
  -- The voice_logs row of the attempt that filed it, and of the re-run.
  log_id TEXT NOT NULL,
  rerun_log_id TEXT,
  transcript TEXT NOT NULL,
  -- The model's one line of what the Sidekick lacks.
  feature TEXT NOT NULL,
  -- The original request's clock, time zone and locale, used again for the re-run.
  request_now TEXT NOT NULL,
  time_zone TEXT NOT NULL,
  locale TEXT,
  status TEXT NOT NULL CHECK (status IN ('waiting', 're-running', 'done', 'failed')),
  fail_reason TEXT,
  result_text TEXT,
  steps TEXT NOT NULL,
  shown_at TEXT,
  rerun_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX jess_pending_by_user ON jess_pending_requests(user_id, status, created_at);
CREATE INDEX jess_pending_by_report ON jess_pending_requests(report_id);

-- The pending request a voice_logs row filed or re-ran (null for every other attempt).
ALTER TABLE voice_logs ADD COLUMN pending_id TEXT;
