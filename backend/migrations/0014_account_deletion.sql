-- Account deletion carried out in code (founder, 2026-11-02): when a person deletes their
-- account, all their data goes within 7 days; only their data. Additive only.
--
-- account_deletions_done: one row per carried-out deletion. No name and no foreign key, so it
-- outlives the users row. counts is the JSON the deletion removed per table and R2 folder;
-- report_ids are the person's Edit job ids, kept so the runner can remove its job folders on the
-- Mac mini (runner_cleaned_at once it has). alert_result is the founder's "Account Deleted" push.
CREATE TABLE account_deletions_done (
  user_id TEXT PRIMARY KEY,
  requested_at TEXT NOT NULL,
  carried_out_at TEXT NOT NULL,
  counts TEXT NOT NULL,
  report_ids TEXT NOT NULL,
  alert_result TEXT,
  runner_cleaned_at TEXT,
  runner_result TEXT
);

-- On the open request: the last error of a deletion that did not finish, and when the founder
-- was reminded that the 7 days are nearly over.
ALTER TABLE account_deletion_requests ADD COLUMN last_error TEXT;
ALTER TABLE account_deletion_requests ADD COLUMN reminded_at TEXT;
