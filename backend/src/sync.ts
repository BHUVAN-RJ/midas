import { Hono } from "hono";
import type { Context } from "hono";
import { requireSession } from "./auth";
import { isValidSidekickVersion, makeRecordChecker } from "./record-types";
import { SIDEKICK_ID_PATTERN } from "./sidekicks";

// Records backed up to the server (D4, 2026-10-10). The shell pushes every local write and
// delete as an op and pulls the ops it has not seen. The server only appends: an op is never
// changed or removed, and the same op_id sent twice is stored once.

type SyncBindings = {
  DB: D1Database;
  BUNDLES: R2Bucket;
  RP_ID?: string;
};

type SyncVariables = {
  userId: string;
};

type SyncEnv = { Bindings: SyncBindings; Variables: SyncVariables };
type SyncContext = Context<SyncEnv>;

// Sized so one push is one SQL statement well inside D1's limits.
export const MAX_OPS_PER_PUSH = 100;
export const MAX_VALUE_BYTES = 64 * 1024;
export const MAX_PUSH_VALUE_BYTES = 1024 * 1024;
export const MAX_KEY_LENGTH = 200;
export const PULL_PAGE_SIZE = 1000;

const OP_ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
const MAX_CLIENT_TIME_LENGTH = 40;

// One op as stored: value already JSON text, deleted as 0 or 1. sidekickVersion is the bundle
// version of the Sidekick that wrote it (null from a shell that does not say); it picks the
// schema the value is checked against and is not stored.
export type CleanOp = {
  opId: string;
  sidekickId: string;
  key: string;
  value: string | null;
  deleted: 0 | 1;
  clientTime: string | null;
  sidekickVersion: string | null;
};

export type RejectedOp = { opId: unknown; error: string };

type OpRow = {
  seq: number;
  op_id: string;
  sidekick_id: string;
  key: string;
  value: string | null;
  deleted: number;
  client_time: string | null;
};

const textEncoder = new TextEncoder();

function byteLength(text: string): number {
  return textEncoder.encode(text).length;
}

// Returns the op ready to store, or the reason it cannot be stored.
export function cleanOp(rawOp: unknown): CleanOp | RejectedOp {
  if (typeof rawOp !== "object" || rawOp === null) {
    return { opId: null, error: "op must be an object" };
  }
  const op = rawOp as Record<string, unknown>;
  if (typeof op.opId !== "string" || !OP_ID_PATTERN.test(op.opId)) {
    return { opId: op.opId ?? null, error: "opId must be 8 to 64 letters, digits, - or _" };
  }
  if (typeof op.sidekickId !== "string" || !SIDEKICK_ID_PATTERN.test(op.sidekickId)) {
    return { opId: op.opId, error: "bad sidekickId" };
  }
  if (typeof op.key !== "string" || op.key.length === 0 || op.key.length > MAX_KEY_LENGTH) {
    return { opId: op.opId, error: `key must be 1 to ${MAX_KEY_LENGTH} characters` };
  }
  if (op.deleted !== true && op.deleted !== false) {
    return { opId: op.opId, error: "deleted must be true or false" };
  }
  let clientTime: string | null = null;
  if (op.clientTime !== undefined && op.clientTime !== null) {
    if (typeof op.clientTime !== "string" || op.clientTime.length > MAX_CLIENT_TIME_LENGTH) {
      return { opId: op.opId, error: "bad clientTime" };
    }
    clientTime = op.clientTime;
  }
  let sidekickVersion: string | null = null;
  if (op.sidekickVersion !== undefined && op.sidekickVersion !== null) {
    if (!isValidSidekickVersion(op.sidekickVersion)) {
      return { opId: op.opId, error: "bad sidekickVersion" };
    }
    sidekickVersion = op.sidekickVersion;
  }

  if (op.deleted) {
    return { opId: op.opId, sidekickId: op.sidekickId, key: op.key, value: null, deleted: 1, clientTime, sidekickVersion };
  }
  if (!("value" in op) || op.value === undefined) {
    return { opId: op.opId, error: "a write needs a value" };
  }
  const valueText = JSON.stringify(op.value);
  if (byteLength(valueText) > MAX_VALUE_BYTES) {
    return { opId: op.opId, error: `value is over ${MAX_VALUE_BYTES} bytes` };
  }
  return { opId: op.opId, sidekickId: op.sidekickId, key: op.key, value: valueText, deleted: 0, clientTime, sidekickVersion };
}

function isRejected(result: CleanOp | RejectedOp): result is RejectedOp {
  return "error" in result;
}

async function readJsonBody(c: SyncContext): Promise<unknown> {
  try {
    return await c.req.json();
  } catch {
    return null;
  }
}

// All ops of one push go in as one statement, in the order sent, so their seq follows that
// order. An op_id already stored is skipped (ON CONFLICT DO NOTHING), never overwritten.
export function insertOpsStatement(db: D1Database, userId: string, ops: CleanOp[], receivedAt: string): D1PreparedStatement {
  const opsJson = JSON.stringify(ops);
  const prepared = db.prepare(
    `INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, client_time, received_at)
     SELECT json_extract(item.value, '$.opId'), ?, json_extract(item.value, '$.sidekickId'),
            json_extract(item.value, '$.key'), json_extract(item.value, '$.value'),
            json_extract(item.value, '$.deleted'), json_extract(item.value, '$.clientTime'), ?
     FROM json_each(?) AS item
     WHERE true
     ON CONFLICT(op_id) DO NOTHING`,
  );
  return prepared.bind(userId, receivedAt, opsJson);
}

// POST /sync/push {"ops":[{opId, sidekickId, key, value, deleted, clientTime, sidekickVersion?}]}
// Replies {"accepted":[opId...], "rejected":[{opId, error}]}. Accepted means stored, now or
// by an earlier push of the same op; the shell can drop it from its outbox. A rejected op is
// kept on the phone and shown as not backed up (plan section 5); it is never dropped.
async function handlePush(c: SyncContext) {
  const body = await readJsonBody(c);
  const rawOps = (body as { ops?: unknown } | null)?.ops;
  if (!Array.isArray(rawOps)) {
    return c.json({ error: "ops must be a list" }, 400);
  }
  if (rawOps.length > MAX_OPS_PER_PUSH) {
    return c.json({ error: `at most ${MAX_OPS_PER_PUSH} ops per push` }, 413);
  }

  const cleanOps: CleanOp[] = [];
  const rejected: RejectedOp[] = [];
  const recordChecker = makeRecordChecker(c.env.BUNDLES, c.get("userId"));
  let totalValueBytes = 0;
  for (const rawOp of rawOps) {
    const result = cleanOp(rawOp);
    if (isRejected(result)) {
      rejected.push(result);
      continue;
    }
    // A write must fit the schema of the version that wrote it (a delete has no content).
    if (result.value !== null) {
      const problem = await recordChecker.recordProblem(result.sidekickId, result.sidekickVersion, result.key, (rawOp as { value: unknown }).value);
      if (problem !== null) {
        rejected.push({ opId: result.opId, error: problem });
        continue;
      }
    }
    totalValueBytes += result.value === null ? 0 : byteLength(result.value);
    cleanOps.push(result);
  }
  if (totalValueBytes > MAX_PUSH_VALUE_BYTES) {
    return c.json({ error: `at most ${MAX_PUSH_VALUE_BYTES} bytes of values per push` }, 413);
  }

  if (cleanOps.length > 0) {
    const receivedAt = new Date().toISOString();
    const insert = insertOpsStatement(c.env.DB, c.get("userId"), cleanOps, receivedAt);
    await insert.run();
  }
  const accepted: string[] = [];
  for (const op of cleanOps) {
    accepted.push(op.opId);
  }
  return c.json({ accepted, rejected });
}

function parseAfter(rawAfter: string | undefined): number | null {
  if (rawAfter === undefined || rawAfter === "") {
    return 0;
  }
  if (!/^\d{1,15}$/.test(rawAfter)) {
    return null;
  }
  return Number(rawAfter);
}

function opFromRow(row: OpRow) {
  const value = row.value === null ? null : JSON.parse(row.value);
  return {
    seq: row.seq,
    opId: row.op_id,
    sidekickId: row.sidekick_id,
    key: row.key,
    value,
    deleted: row.deleted === 1,
    clientTime: row.client_time,
  };
}

// GET /sync/pull?after=<seq> -> {"ops":[...], "lastSeq": n, "more": bool}, the user's own ops
// after that seq in seq order. The shell applies them in order and asks again while more.
async function handlePull(c: SyncContext) {
  const after = parseAfter(c.req.query("after"));
  if (after === null) {
    return c.json({ error: "after must be a whole number" }, 400);
  }
  const prepared = c.env.DB.prepare(
    "SELECT seq, op_id, sidekick_id, key, value, deleted, client_time FROM ops WHERE user_id = ? AND seq > ? ORDER BY seq LIMIT ?",
  );
  const pullStatement = prepared.bind(c.get("userId"), after, PULL_PAGE_SIZE + 1);
  const queryResult = await pullStatement.all<OpRow>();
  const rows = queryResult.results;
  const more = rows.length > PULL_PAGE_SIZE;
  const pageRows = more ? rows.slice(0, PULL_PAGE_SIZE) : rows;

  const ops = [];
  for (const row of pageRows) {
    ops.push(opFromRow(row));
  }
  const lastSeq = ops.length > 0 ? ops[ops.length - 1].seq : after;
  return c.json({ ops, lastSeq, more });
}

export const syncRoutes = new Hono<SyncEnv>();
syncRoutes.use("*", requireSession);
syncRoutes.post("/push", handlePush);
syncRoutes.get("/pull", handlePull);
