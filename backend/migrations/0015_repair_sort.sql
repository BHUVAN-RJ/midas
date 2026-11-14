-- Repair lanes, the sort step (founder, 2026-11-13; docs/briefs/repair-lanes.md W2). Every repair
-- report is sorted into a lane before any runner can claim it.
--
-- The status column's CHECK cannot gain 'sorting' without rebuilding the table, which the
-- no-data-loss rails forbid, so the sort has its own columns. While a report is sorted, asked back
-- or not a job, status stays 'received' (no runner claims it); a lane that needs the runner
-- (code, and setting and look until those lanes exist) moves it to 'queued'.
--
-- sort_status: sorting (model running), asking (the card is on the phone, waiting for the answer),
--   sorted (lane final), dropped (no answer within 2 minutes). NULL on rows from before this.
-- lane: the lane the sort chose (repair-sort-model.ts LANES).
-- sort_confidence: Jev's confidence in its lane; sort_model: which model(s) decided;
-- sort_latency_ms / sort_cost_usd: summed over every model call for this report (both sorts).
-- sort_error: why the request went to code without a model's say (timeout, HTTP error).
-- sort_question: the ask-back card as JSON ({text, options}); sort_answer: the person's answer;
-- sort_asked_at: when the card was sent (the 2-minute clock).
-- sort_message: the one line said for not_a_request and shell_cant.
-- sort_alert: what the founder's push for shell_cant came to.
-- Additive only. Apply with: node scripts/migrate.mjs --env staging|live (staging first).

ALTER TABLE repair_reports ADD COLUMN sort_status TEXT CHECK (sort_status IN ('sorting', 'asking', 'sorted', 'dropped'));
ALTER TABLE repair_reports ADD COLUMN lane TEXT CHECK (lane IN ('ask_back', 'not_a_request', 'shell_cant', 'jess_command', 'setting', 'look', 'code'));
ALTER TABLE repair_reports ADD COLUMN sort_confidence REAL;
ALTER TABLE repair_reports ADD COLUMN sort_model TEXT;
ALTER TABLE repair_reports ADD COLUMN sort_latency_ms INTEGER;
ALTER TABLE repair_reports ADD COLUMN sort_cost_usd REAL;
ALTER TABLE repair_reports ADD COLUMN sort_error TEXT;
ALTER TABLE repair_reports ADD COLUMN sort_question TEXT;
ALTER TABLE repair_reports ADD COLUMN sort_answer TEXT;
ALTER TABLE repair_reports ADD COLUMN sort_asked_at TEXT;
ALTER TABLE repair_reports ADD COLUMN sort_message TEXT;
ALTER TABLE repair_reports ADD COLUMN sort_alert TEXT;
CREATE INDEX repair_reports_by_sort_status ON repair_reports(sort_status, sort_asked_at);
