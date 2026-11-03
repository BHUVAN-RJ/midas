// A jess task deleted on the Workdesk before it finished does not finish later (founder,
// 2026-11-02, build 22 feedback: "Deleting a request that is still processing also cancels that
// request on the server so it does not finish later").
//
// POST /voice/jess/cancel { requestId?, reportId?, pendingId? } -> 200 { ok: true }, 400 when none
// is given or one is malformed. Only the signed-in person's own rows change; nothing is removed
// (the no-data-loss rule): each row is marked so it never runs.
//
//   requestId  the phone's request id (jess-requests.ts): kept as answered "not-done / deleted", so a
//              send of it later never runs, and a run still on its way files no Edit or grow and
//              does not overwrite that answer (handleJess, keepAnswer).
//   pendingId  the grow request (jess-pending.ts): waiting or re-running becomes failed "deleted",
//              already marked shown, so the runner's re-run ops are refused and nothing is shown.
//   reportId   the Edit jess filed: received or queued becomes failed "deleted by the person", so
//              the runner never claims it. An Edit the runner already started is left to finish.

import { normalizedRequestId } from "./jess-requests";
import { PENDING_ID_PATTERN, stepJson } from "./jess-pending";

export const DELETED_REASON = "deleted";
export const DELETED_REPORT_REASON = "deleted by the person";
const REPORT_ID_PATTERN = /^[0-9a-f-]{36}$/;

// The answer kept for a deleted request: what a later send of the same id gets
export function deletedReply(): Record<string, unknown> {
  return { status: "not-done", reason: DELETED_REASON, transcript: "" };
}

export type CancelBody = { requestId: string | null; reportId: string | null; pendingId: string | null };

// The ids in the body; null when none is given or one given is malformed
export function parseCancelBody(body: unknown): CancelBody | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return null;
  }
  const fields = body as Record<string, unknown>;
  const parsed: CancelBody = { requestId: null, reportId: null, pendingId: null };
  if (fields.requestId !== undefined && fields.requestId !== null) {
    parsed.requestId = normalizedRequestId(fields.requestId);
    if (parsed.requestId === null) {
      return null;
    }
  }
  if (fields.reportId !== undefined && fields.reportId !== null) {
    if (typeof fields.reportId !== "string" || !REPORT_ID_PATTERN.test(fields.reportId)) {
      return null;
    }
    parsed.reportId = fields.reportId;
  }
  if (fields.pendingId !== undefined && fields.pendingId !== null) {
    if (typeof fields.pendingId !== "string" || !PENDING_ID_PATTERN.test(fields.pendingId)) {
      return null;
    }
    parsed.pendingId = fields.pendingId;
  }
  const hasAny = parsed.requestId !== null || parsed.reportId !== null || parsed.pendingId !== null;
  return hasAny ? parsed : null;
}

// The request id never runs: a new row is kept as answered "deleted"; an open or running one
// becomes it. One already answered keeps its answer (it ran; the phone drops it).
function cancelRequestStatement(db: D1Database, userId: string, requestId: string, nowIso: string): D1PreparedStatement {
  const statement = db.prepare(
    "INSERT INTO jess_requests (user_id, request_id, state, reply, log_id, sends, claimed_at, created_at, updated_at) " +
      "VALUES (?, ?, 'answered', ?, NULL, 0, ?, ?, ?) " +
      "ON CONFLICT (user_id, request_id) DO UPDATE SET state = 'answered', reply = excluded.reply, updated_at = excluded.updated_at " +
      "WHERE jess_requests.state IN ('open', 'running')",
  );
  return statement.bind(userId, requestId, JSON.stringify(deletedReply()), nowIso, nowIso, nowIso);
}

function cancelPendingStatement(db: D1Database, userId: string, pendingId: string, nowIso: string): D1PreparedStatement {
  const statement = db.prepare(
    "UPDATE jess_pending_requests SET status = 'failed', fail_reason = ?, shown_at = ?, updated_at = ?, steps = json_insert(steps, '$[#]', json(?)) " +
      "WHERE id = ? AND user_id = ? AND status IN ('waiting', 're-running')",
  );
  return statement.bind(DELETED_REASON, nowIso, nowIso, stepJson("deleted", nowIso), pendingId, userId);
}

function cancelReportStatement(db: D1Database, userId: string, reportId: string, nowIso: string): D1PreparedStatement {
  const statement = db.prepare(
    "UPDATE repair_reports SET status = 'failed', fail_reason = ?, updated_at = ? " +
      "WHERE id = ? AND user_id = ? AND status IN ('received', 'queued')",
  );
  return statement.bind(DELETED_REPORT_REASON, nowIso, reportId, userId);
}

// Every cancel in the body, in one batch
export async function cancelJessWork(db: D1Database, userId: string, cancel: CancelBody, nowMs: number): Promise<void> {
  const nowIso = new Date(nowMs).toISOString();
  const statements: D1PreparedStatement[] = [];
  if (cancel.requestId !== null) {
    statements.push(cancelRequestStatement(db, userId, cancel.requestId, nowIso));
  }
  if (cancel.pendingId !== null) {
    statements.push(cancelPendingStatement(db, userId, cancel.pendingId, nowIso));
  }
  if (cancel.reportId !== null) {
    statements.push(cancelReportStatement(db, userId, cancel.reportId, nowIso));
  }
  await db.batch(statements);
}

// A run still on its way checks this before filing an Edit or a grow
export async function isRequestDeleted(db: D1Database, userId: string, requestId: string): Promise<boolean> {
  const lookup = db.prepare("SELECT state, reply FROM jess_requests WHERE user_id = ? AND request_id = ?");
  const row = await lookup.bind(userId, requestId).first<{ state: string; reply: string | null }>();
  if (row === null || row.state !== "answered" || row.reply === null) {
    return false;
  }
  const reply = JSON.parse(row.reply) as Record<string, unknown>;
  return reply.status === "not-done" && reply.reason === DELETED_REASON;
}
