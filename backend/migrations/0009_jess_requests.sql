-- jess runs each request once (founder, 2026-10-22, docs/PRODUCT.md "jess queue, instant
-- acknowledgement and the Workdesk"): the phone keeps a spoken request queued until it gets an
-- answer and sends it again with the same request id when it was cut off. The server keeps the
-- answer it gave for each (user, request id), so a request sent again is answered from here: the
-- model is not called again and no second repair or grow is filed.
-- Apply with: node scripts/migrate.mjs --env staging|live
--
-- state: running (claimed; claimed_at says since when, a claim older than a few minutes is taken
-- again because that run never finished), open (the model could not be reached; the next send of
-- the same id runs again), answered (reply holds the JSON answer, given again as it is).
-- Rows are never removed (the no-data-loss suite).

CREATE TABLE jess_requests (
  user_id TEXT NOT NULL REFERENCES users(id),
  request_id TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('running', 'open', 'answered')),
  reply TEXT,
  -- The voice_logs row of the attempt whose answer is kept
  log_id TEXT,
  -- How many times the request was sent (the first send counts)
  sends INTEGER NOT NULL,
  claimed_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, request_id)
);

-- The phone's request id of each jess attempt (null for older phones and for re-runs)
ALTER TABLE voice_logs ADD COLUMN request_id TEXT;
