// jess runs each request once (founder, 2026-10-22; migration 0009). The phone sends a request id
// with every POST /voice/jess and sends the same id again when the answer never reached it. The
// first send claims the id and runs; the answer is kept before it is sent, so a later send of the
// same id gets that answer again without a second model call, repair or grow. A send that arrives
// while the first is still running is told to try again later (409 busy). Only a model that could
// not be reached leaves the id open, so the next send runs again.

export const REQUEST_ID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

// A claim older than this belongs to a run that never finished (the Worker was stopped); the next
// send takes it over. Far longer than one run: two model attempts of 8 s plus R2 and D1.
export const STALE_CLAIM_MS = 120_000;

export type RequestClaim =
  | { kind: "run" }
  | { kind: "answered"; reply: Record<string, unknown> }
  | { kind: "busy" };

type RequestRow = { state: string; reply: string | null };

// The phone's id, lower case so the same UUID in either case is one request; null when absent or
// not a UUID (older phones send none)
export function normalizedRequestId(value: unknown): string | null {
  if (typeof value !== "string" || !REQUEST_ID_PATTERN.test(value)) {
    return null;
  }
  return value.toLowerCase();
}

async function insertClaim(db: D1Database, userId: string, requestId: string, nowIso: string): Promise<boolean> {
  const statement = db.prepare(
    "INSERT INTO jess_requests (user_id, request_id, state, reply, log_id, sends, claimed_at, created_at, updated_at) " +
      "VALUES (?, ?, 'running', NULL, NULL, 1, ?, ?, ?) ON CONFLICT (user_id, request_id) DO NOTHING",
  );
  const result = await statement.bind(userId, requestId, nowIso, nowIso, nowIso).run();
  return (result.meta?.changes ?? 0) === 1;
}

// Takes the id again when it was left open or its run never finished; one statement, so two sends
// arriving together cannot both take it
async function reclaim(db: D1Database, userId: string, requestId: string, nowIso: string, staleBeforeIso: string): Promise<boolean> {
  const statement = db.prepare(
    "UPDATE jess_requests SET state = 'running', claimed_at = ?, sends = sends + 1, updated_at = ? " +
      "WHERE user_id = ? AND request_id = ? AND (state = 'open' OR (state = 'running' AND claimed_at < ?))",
  );
  const result = await statement.bind(nowIso, nowIso, userId, requestId, staleBeforeIso).run();
  return (result.meta?.changes ?? 0) === 1;
}

async function countSend(db: D1Database, userId: string, requestId: string, nowIso: string): Promise<void> {
  const statement = db.prepare("UPDATE jess_requests SET sends = sends + 1, updated_at = ? WHERE user_id = ? AND request_id = ?");
  await statement.bind(nowIso, userId, requestId).run();
}

export async function claimRequest(db: D1Database, userId: string, requestId: string, nowMs: number): Promise<RequestClaim> {
  const nowIso = new Date(nowMs).toISOString();
  if (await insertClaim(db, userId, requestId, nowIso)) {
    return { kind: "run" };
  }
  const staleBeforeIso = new Date(nowMs - STALE_CLAIM_MS).toISOString();
  if (await reclaim(db, userId, requestId, nowIso, staleBeforeIso)) {
    return { kind: "run" };
  }
  await countSend(db, userId, requestId, nowIso);
  const lookup = db.prepare("SELECT state, reply FROM jess_requests WHERE user_id = ? AND request_id = ?");
  const row = await lookup.bind(userId, requestId).first<RequestRow>();
  if (row !== null && row.state === "answered" && row.reply !== null) {
    return { kind: "answered", reply: JSON.parse(row.reply) as Record<string, unknown> };
  }
  return { kind: "busy" };
}

// Keeps the answer before it is sent; never throws (a lost row only means a later send runs again)
export async function keepAnswer(db: D1Database, userId: string, requestId: string, reply: Record<string, unknown>, logId: string, nowMs: number): Promise<void> {
  const nowIso = new Date(nowMs).toISOString();
  const statement = db.prepare("UPDATE jess_requests SET state = 'answered', reply = ?, log_id = ?, updated_at = ? WHERE user_id = ? AND request_id = ?");
  try {
    await statement.bind(JSON.stringify(reply), logId, nowIso, userId, requestId).run();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("jess request answer not kept: " + message);
  }
}

// The model could not be reached: the next send of this id runs again. Never throws.
export async function reopenRequest(db: D1Database, userId: string, requestId: string, nowMs: number): Promise<void> {
  const nowIso = new Date(nowMs).toISOString();
  const statement = db.prepare("UPDATE jess_requests SET state = 'open', updated_at = ? WHERE user_id = ? AND request_id = ?");
  try {
    await statement.bind(nowIso, userId, requestId).run();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("jess request not reopened: " + message);
  }
}
