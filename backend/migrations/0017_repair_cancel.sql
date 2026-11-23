-- An X on the repair tag cancels the repair (founder, 2026-11-22; docs/PRODUCT.md). The status
-- CHECK cannot gain 'cancelled' without rebuilding the table, which the no-data-loss rails forbid,
-- so a cancelled report is stored as status 'failed' with fail_reason 'cancelled by the person'
-- and this column set. No runner claims a failed report, the publish routes refuse it, and the
-- status route answers 409 { cancelled: true } so a running job stops before it publishes.
--
-- cancelled_at: when the person tapped X (POST /repairs/:clientReportId/cancel); set once. NULL
--   for every report that was not cancelled.
-- Additive only. Apply with: node scripts/migrate.mjs --env staging|live (staging first).

ALTER TABLE repair_reports ADD COLUMN cancelled_at TEXT;
