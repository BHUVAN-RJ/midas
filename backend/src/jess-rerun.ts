import { Hono } from "hono";
import type { Context } from "hono";
import { parseSidekick } from "./jess";
import type { JessContext } from "./jess";
import { claimPendingForReport, donePendingStatement, failPendingStatement, growEnabled, recordRerun, rerunningPendingForReport } from "./jess-pending";
import type { PendingRow } from "./jess-pending";
import { runJess, writeJessLogSafely } from "./jess-route";
import type { JessLogEntry, JessRun, ParsedJessRequest } from "./jess-route";
import { makeRecordChecker } from "./record-types";
import { requireRunner } from "./repairs";
import type { RepairEnv } from "./repairs";
import { currentAgentListing } from "./sidekicks";
import { MAX_OPS_PER_PUSH, cleanOp, insertOpsStatement } from "./sync";
import type { CleanOp } from "./sync";

// jess grows the Sidekick, the re-run (founder 2026-10-21: in the backend, not on the phone).
// Right after the runner publishes a repair to the reporter's own copy and marks it deployed_live,
// it calls these, with the runner token:
//
// POST /repairs/:id/jess-rerun { context }
//   Claims the waiting pending request linked to report :id (once: waiting -> re-running only
//   while the report is live), and routes its stored transcript with its stored clock, time zone
//   and locale, offering only its Sidekick, read from the manifest of the version the user now
//   gets, with `context` (the new tools.js context() of the user's records, from the runner).
//   No grow and no repair: a re-run acts or fails. Logged in voice_logs with pending_id.
//   -> 204 when there is nothing to re-run (none linked, not live, already ran, or the flag off)
//   -> { pendingId, status: "done", sidekickId, version, tool, input, logId }
//   -> { pendingId, status: "not-done", reason, logId }   the pending request is failed
//
// POST /repairs/:id/jess-rerun/ops { pendingId, version, text, ops: [{ op: "set"|"delete", key, value? }] }
//   or { pendingId, version, refused, text } (the handler refused)
//   or { pendingId, version, failed, text } (the runner could not run the handler)
//   The runner ran that version's handler in node:vm. Each op is checked as /sync/push checks a
//   phone's (the key and size rules, and the schema of `version`, which must still be the version
//   the user gets), then all are appended to the user's op log in one statement, with op ids made
//   from the pending id so a retry never adds them twice, and the request is done with `text` for
//   the phone's banner. One op that does not fit, a refusal, or a changed version fails the
//   request and appends nothing.
//   -> { status: "done", ops } or { status: "failed", reason }; 409 when it is not re-running.

type RerunBindings = RepairEnv["Bindings"] & { OPENROUTER_API_KEY?: string; JESS_GROW?: string };
type RerunEnv = { Bindings: RerunBindings; Variables: RepairEnv["Variables"] };
type RerunContext = Context<RerunEnv>;

const REPORT_ID_PATTERN = /^[0-9a-f-]{36}$/;
const MAX_TEXT_LENGTH = 200;
const MAX_REASON_LENGTH = 200;
// The runner is the one asking: no phone, no app build
const RUNNER_APP = { version: null, build: null, ios: null, device: "runner" };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function readJsonBody(c: RerunContext): Promise<Record<string, unknown>> {
  try {
    const body = await c.req.json();
    return isPlainObject(body) ? body : {};
  } catch {
    return {};
  }
}

// The pending request's own words and time, with its one Sidekick as the user gets it now
async function rerunContext(c: RerunContext, pending: PendingRow, sentContext: unknown): Promise<JessContext> {
  const listing = await currentAgentListing(c.env.BUNDLES, pending.sidekick_id, pending.user_id);
  const sidekicks = [];
  if (listing !== null) {
    const sidekick = parseSidekick({ id: pending.sidekick_id, name: listing.name, version: listing.version, agent: listing.agent, context: sentContext ?? null });
    if (sidekick !== null) {
      sidekicks.push(sidekick);
    }
  }
  return { transcript: pending.transcript, now: pending.request_now, timeZone: pending.time_zone, locale: pending.locale ?? undefined, sidekicks, grow: false };
}

async function handleRerun(c: RerunContext) {
  const reportId = c.req.param("id") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  if (!growEnabled(c.env)) {
    return c.body(null, 204);
  }
  const body = await readJsonBody(c);
  const startedAt = Date.now();
  const createdAt = new Date(startedAt).toISOString();
  const pending = await claimPendingForReport(c.env.DB, reportId, createdAt);
  if (pending === null) {
    return c.body(null, 204);
  }
  const context = await rerunContext(c, pending, body.context);
  let run: JessRun;
  if (context.sidekicks.length === 0) {
    run = { outcome: { status: "not-done", reason: "no-tools", transcript: context.transcript }, rawReply: null, steps: [], retries: 0 };
  } else {
    run = await runJess(context, c.env.OPENROUTER_API_KEY);
  }
  // A re-run only acts or fails: it never files another repair
  if (run.outcome.status === "repair" || run.outcome.status === "grow") {
    run.outcome = { status: "not-done", reason: "still-cannot-act", transcript: context.transcript };
  }
  const logId = crypto.randomUUID();
  const outcome = run.outcome;
  if (outcome.status === "done") {
    await recordRerun(c.env.DB, pending.id, logId, createdAt, { tool: outcome.tool });
  } else if (outcome.status === "not-done") {
    await recordRerun(c.env.DB, pending.id, logId, createdAt, { reason: outcome.reason });
  }
  const parsed: ParsedJessRequest = { context, app: RUNNER_APP, listenMs: null };
  const entry: JessLogEntry = { logId, userId: pending.user_id, createdAt, parsed, run, reportId: null, pendingId: pending.id, totalMs: Date.now() - startedAt };
  await writeJessLogSafely(c.env.DB, entry);
  if (outcome.status === "done") {
    const version = context.sidekicks[0].version;
    return c.json({ pendingId: pending.id, status: "done", sidekickId: outcome.sidekickId, version, tool: outcome.tool, input: outcome.input, logId });
  }
  const reason = outcome.status === "not-done" ? outcome.reason : "still-cannot-act";
  return c.json({ pendingId: pending.id, status: "not-done", reason, logId });
}

// The re-run's log row gets what became of the call, as a phone's outcome would
function logOutcomeStatement(c: RerunContext, logId: string | null, outcome: string): D1PreparedStatement {
  const statement = c.env.DB.prepare("UPDATE voice_logs SET phone_outcome = ? WHERE id = ? AND phone_outcome IS NULL");
  return statement.bind(outcome.slice(0, MAX_REASON_LENGTH + 20), logId);
}

async function failRerun(c: RerunContext, pending: PendingRow, reason: string, logOutcome: string, at: string) {
  await c.env.DB.batch([failPendingStatement(c.env.DB, pending.id, reason, at), logOutcomeStatement(c, pending.rerun_log_id, logOutcome)]);
  return c.json({ status: "failed", reason });
}

type CheckedOps = { ops: CleanOp[] } | { problem: string };

// Every op as /sync/push would store it, stamped with the version the handler came from; the
// first that does not fit is the problem
async function checkedOps(c: RerunContext, pending: PendingRow, version: string, rawOps: unknown[], at: string): Promise<CheckedOps> {
  const recordChecker = makeRecordChecker(c.env.BUNDLES, pending.user_id);
  const ops: CleanOp[] = [];
  for (let index = 0; index < rawOps.length; index += 1) {
    const rawOp = rawOps[index];
    if (!isPlainObject(rawOp) || (rawOp.op !== "set" && rawOp.op !== "delete")) {
      return { problem: `op ${index} is neither set nor delete` };
    }
    // Made from the pending id: the same re-run sent twice stores its ops once (ON CONFLICT)
    const syncOp = {
      opId: `jess-${pending.id}-${index}`,
      sidekickId: pending.sidekick_id,
      key: rawOp.key,
      value: rawOp.value,
      deleted: rawOp.op === "delete",
      clientTime: at,
      sidekickVersion: version,
    };
    const cleaned = cleanOp(syncOp);
    if ("error" in cleaned) {
      return { problem: `${String(rawOp.key)}: ${cleaned.error}` };
    }
    if (cleaned.value !== null) {
      const recordProblem = await recordChecker.recordProblem(cleaned.sidekickId, version, cleaned.key, rawOp.value);
      if (recordProblem !== null) {
        return { problem: `${cleaned.key}: ${recordProblem}` };
      }
    }
    ops.push(cleaned);
  }
  return { ops };
}

async function handleRerunOps(c: RerunContext) {
  const reportId = c.req.param("id") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  const body = await readJsonBody(c);
  if (typeof body.pendingId !== "string" || typeof body.version !== "string" || typeof body.text !== "string") {
    return c.json({ error: "pendingId, version and text are required" }, 400);
  }
  const pending = await rerunningPendingForReport(c.env.DB, reportId, body.pendingId);
  if (pending === null) {
    return c.json({ error: "no re-run waits for ops" }, 409);
  }
  const at = new Date().toISOString();
  if (typeof body.refused === "string") {
    const refusal = body.refused.slice(0, MAX_REASON_LENGTH);
    return failRerun(c, pending, "handler refused: " + refusal, "refused:" + refusal, at);
  }
  if (typeof body.failed === "string") {
    const failure = body.failed.slice(0, MAX_REASON_LENGTH);
    return failRerun(c, pending, "runner: " + failure, "failed:" + failure, at);
  }
  if (!Array.isArray(body.ops) || body.ops.length === 0 || body.ops.length > MAX_OPS_PER_PUSH) {
    return failRerun(c, pending, `ops must be 1 to ${MAX_OPS_PER_PUSH}`, "failed:bad ops", at);
  }
  // The ops are checked against, and stamped with, the version the user gets now; one that
  // changed since the re-run was routed could have other schemas
  const listing = await currentAgentListing(c.env.BUNDLES, pending.sidekick_id, pending.user_id);
  if (listing === null || listing.version !== body.version) {
    return failRerun(c, pending, "version changed", "failed:version-changed", at);
  }
  const checked = await checkedOps(c, pending, body.version, body.ops, at);
  if ("problem" in checked) {
    return failRerun(c, pending, "op refused: " + checked.problem, "failed:" + checked.problem, at);
  }
  const text = body.text.slice(0, MAX_TEXT_LENGTH);
  await c.env.DB.batch([
    insertOpsStatement(c.env.DB, pending.user_id, checked.ops, at),
    donePendingStatement(c.env.DB, pending.id, text, at, checked.ops.length),
    logOutcomeStatement(c, pending.rerun_log_id, "applied"),
  ]);
  return c.json({ status: "done", ops: checked.ops.length });
}

export const jessRerunRoutes = new Hono<RerunEnv>();
jessRerunRoutes.post("/:id/jess-rerun", requireRunner as never, handleRerun);
jessRerunRoutes.post("/:id/jess-rerun/ops", requireRunner as never, handleRerunOps);
