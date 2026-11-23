import type { Context } from "hono";

// An X on the repair tag cancels the repair (founder, 2026-11-22; docs/PRODUCT.md "An X on the
// repair tag cancels the repair"). The phone calls this for a report it already sent; one still in
// its outbox is simply never sent.
//
// POST /repairs/:clientReportId/cancel (the person's session; the phone's own report id)
//   -> 200 { id, status, cancelled: true }   cancelled now, or already cancelled (idempotent)
//   -> 200 { id, status, cancelled: false }  already finished (deployed_live or failed): nothing
//                                            changes; with publish first a fix already live stays
//   -> 404                                   no such report for this person (not sent, or someone
//                                            else's: told apart from nothing)
//
// Cancelled is stored as status 'failed', fail_reason CANCELLED_REASON and cancelled_at (migration
// 0017; the status CHECK cannot gain 'cancelled'). Nothing is removed (the no-data-loss rule). So:
//   - no runner claims it (claims take only queued, or running with an expired lease);
//   - a sort still running or a question card still waiting is dropped (sort_status 'dropped'),
//     so the sort places nothing, the setting lane writes nothing and an answer gets 410;
//   - a job already running learns it from its next status post or heartbeat (409 cancelled: true)
//     and from GET /repairs/:id (cancelled: true), and the publish routes refuse it.
// No event is written: neither the founder nor the person is told of a repair the person dropped.

export const CANCELLED_REASON = "cancelled by the person";
const CLIENT_REPORT_ID_PATTERN = /^[A-Za-z0-9-]{1,80}$/;
// A repair that already ended is left as it is
const FINISHED_STATUSES = new Set(["deployed_live", "failed"]);

type CancelBindings = { DB: D1Database };

type CancelRow = {
  id: string;
  user_id: string;
  status: string;
  cancelled_at: string | null;
};

async function readCancelRow(db: D1Database, userId: string, clientReportId: string): Promise<CancelRow | null> {
  const prepared = db.prepare("SELECT id, user_id, status, cancelled_at FROM repair_reports WHERE user_id = ? AND client_report_id = ?");
  const statement = prepared.bind(userId, clientReportId);
  return statement.first<CancelRow>();
}

function cancelReply(row: CancelRow) {
  return { id: row.id, status: row.status, cancelled: row.cancelled_at !== null };
}

// One statement marks the report, only while it has not finished, so a runner finishing at the same
// moment either wins (the cancel then changes nothing) or loses (its status post gets 409).
function cancelStatement(db: D1Database, reportId: string, at: string): D1PreparedStatement {
  const prepared = db.prepare(
    `UPDATE repair_reports
       SET status = 'failed', fail_reason = ?, cancelled_at = ?, updated_at = ?,
           sort_status = CASE WHEN sort_status IN ('sorting', 'asking') THEN 'dropped' ELSE sort_status END
     WHERE id = ? AND cancelled_at IS NULL AND status NOT IN ('deployed_live', 'failed')`,
  );
  return prepared.bind(CANCELLED_REASON, at, at, reportId);
}

export async function handleCancelRepair(c: Context) {
  const env = c.env as CancelBindings;
  const userId = c.get("userId") as string;
  const clientReportId = c.req.param("clientReportId") ?? "";
  if (!CLIENT_REPORT_ID_PATTERN.test(clientReportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  const row = await readCancelRow(env.DB, userId, clientReportId);
  if (row === null) {
    return c.json({ error: "no such report" }, 404);
  }
  if (row.cancelled_at !== null || FINISHED_STATUSES.has(row.status)) {
    return c.json(cancelReply(row));
  }
  const cancelledAt = new Date().toISOString();
  await cancelStatement(env.DB, row.id, cancelledAt).run();
  const after = await readCancelRow(env.DB, userId, clientReportId);
  const shown = after ?? row;
  console.log(JSON.stringify({ event: "repair-cancelled", reportId: row.id, userId, previousStatus: row.status, cancelled: shown.cancelled_at !== null }));
  return c.json(cancelReply(shown));
}
