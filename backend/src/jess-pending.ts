// jess grows the Sidekick (founder 2026-10-21; flagged, monitored): pending requests
// (migration 0008). A spoken request the Sidekick has no option for files a feature request with
// the repair agent and is kept here. Right after the runner publishes that repair to the user's
// own copy, the runner runs it again, once, with its original time (jess-rerun.ts), and its ops go
// into the user's op log; the phone pulls them and shows the line once (GET /voice/jess/pending).
// Every step is appended to the row's steps for backend/scripts/jess-grow-log.mjs.
//
//   waiting --(repair live, claimed by the runner)--> re-running --(ops appended)--> done
//      |                                                  '--(still cannot act, handler refused,
//      |                                                      op refused, runner never finished)--> failed
//      '--(repair failed other than couldnt_fix, or live and never re-run)--> failed
//
// An edit the agent could not make (couldnt_fix) does not fail its request (founder, 2026-11-02,
// build 22 small fixes, pick B): the founder makes it by hand and marks it Built, the report turns
// deployed_live, and the runner, between jobs, re-runs the request on his published copy
// (GET /repairs/jess-reruns, handFixedReruns below). Until then the request waits.
//   done or failed --(phone showed the banner or the Not Done card)--> shown_at set

// The whole path sits behind this flag: on for staging, off on live until the founder turns it on
export function growEnabled(env: { JESS_GROW?: string }): boolean {
  return env.JESS_GROW === "true";
}

export const PENDING_ID_PATTERN = /^[0-9a-f-]{36}$/;
// A pending request the runner did not finish this long after its repair went live (or after it
// claimed the re-run) is failed and shown as Not Done
export const RERUN_ANSWER_MS = 10 * 60 * 1000;

export type PendingRow = {
  id: string;
  user_id: string;
  sidekick_id: string;
  report_id: string;
  log_id: string;
  rerun_log_id: string | null;
  transcript: string;
  feature: string;
  request_now: string;
  time_zone: string;
  locale: string | null;
  status: "waiting" | "re-running" | "done" | "failed";
  fail_reason: string | null;
  result_text: string | null;
  steps: string;
  shown_at: string | null;
  rerun_at: string | null;
  created_at: string;
  updated_at: string;
};

export type NewPending = {
  id: string;
  userId: string;
  sidekickId: string;
  logId: string;
  transcript: string;
  feature: string;
  requestNow: string;
  timeZone: string;
  locale: string | null;
  createdAt: string;
};

// What the repair agent reads (the runner writes only the transcript to the job folder): the
// person's own words first, then what jess found missing.
export function growRepairTranscript(transcript: string, feature: string): string {
  return `${transcript}\n\njess (voice) could not do this yet: ${feature}. Add it to the page with its voice tool, so the same sentence works by voice; once your change is live, Midas runs the sentence again with it.`;
}

export function stepJson(step: string, at: string, details: Record<string, unknown> = {}): string {
  return JSON.stringify({ step, at, ...details });
}

export function insertPendingStatement(db: D1Database, pending: NewPending, reportId: string): D1PreparedStatement {
  const firstStep = stepJson("sent-to-repair", pending.createdAt, { reportId, logId: pending.logId, feature: pending.feature });
  const statement = db.prepare(
    `INSERT INTO jess_pending_requests (id, user_id, sidekick_id, report_id, log_id, transcript, feature, request_now, time_zone, locale, status, steps, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'waiting', json_array(json(?)), ?, ?)`,
  );
  return statement.bind(
    pending.id,
    pending.userId,
    pending.sidekickId,
    reportId,
    pending.logId,
    pending.transcript,
    pending.feature,
    pending.requestNow,
    pending.timeZone,
    pending.locale,
    firstStep,
    pending.createdAt,
    pending.createdAt,
  );
}

// The one re-run, for the runner: the waiting request linked to this report becomes re-running
// in the same statement that checks the report is live on its user's copy, so two calls never
// both get it. Null when there is none, it is not live yet, or it already ran.
export async function claimPendingForReport(db: D1Database, reportId: string, at: string): Promise<PendingRow | null> {
  const statement = db.prepare(
    `UPDATE jess_pending_requests
     SET status = 're-running', rerun_at = ?, updated_at = ?, steps = json_insert(steps, '$[#]', json(?))
     WHERE report_id = ? AND status = 'waiting'
       AND EXISTS (SELECT 1 FROM repair_reports r WHERE r.id = jess_pending_requests.report_id AND r.user_id = jess_pending_requests.user_id AND r.status = 'deployed_live')
     RETURNING *`,
  );
  const bound = statement.bind(at, at, stepJson("claimed", at), reportId);
  const result = await bound.all<PendingRow>();
  return result.results.length === 0 ? null : result.results[0];
}

// The re-running request linked to this report, for the runner's ops; null otherwise
export async function rerunningPendingForReport(db: D1Database, reportId: string, pendingId: string): Promise<PendingRow | null> {
  const statement = db.prepare("SELECT * FROM jess_pending_requests WHERE id = ? AND report_id = ? AND status = 're-running' AND rerun_log_id IS NOT NULL");
  return await statement.bind(pendingId, reportId).first<PendingRow>();
}

// What the re-run's model call came to. A "done" waits for the runner's ops; anything else fails
// the request at once.
export async function recordRerun(db: D1Database, pendingId: string, logId: string, at: string, done: { tool: string } | { reason: string }): Promise<void> {
  if ("tool" in done) {
    const statement = db.prepare(
      "UPDATE jess_pending_requests SET rerun_log_id = ?, updated_at = ?, steps = json_insert(steps, '$[#]', json(?)) WHERE id = ? AND status = 're-running'",
    );
    await statement.bind(logId, at, stepJson("re-run", at, { logId, tool: done.tool }), pendingId).run();
    return;
  }
  await failPending(db, pendingId, "still cannot act: " + done.reason, at, { logId, notDone: done.reason }, logId);
}

// A re-running request failed with the reason (and the re-run's log row when there is one)
export async function failPending(db: D1Database, pendingId: string, failReason: string, at: string, details: Record<string, unknown> = {}, logId: string | null = null): Promise<void> {
  await failPendingStatement(db, pendingId, failReason, at, details, logId).run();
}

export function failPendingStatement(db: D1Database, pendingId: string, failReason: string, at: string, details: Record<string, unknown> = {}, logId: string | null = null): D1PreparedStatement {
  const statement = db.prepare(
    "UPDATE jess_pending_requests SET status = 'failed', fail_reason = ?, rerun_log_id = COALESCE(?, rerun_log_id), updated_at = ?, steps = json_insert(steps, '$[#]', json(?)) WHERE id = ? AND status = 're-running'",
  );
  return statement.bind(failReason, logId, at, stepJson("failed", at, { reason: failReason, ...details }), pendingId);
}

// The re-run's ops are in the op log: done, with the handler's line for the banner. Only from
// re-running, so it happens once.
export function donePendingStatement(db: D1Database, pendingId: string, resultText: string, at: string, opCount: number): D1PreparedStatement {
  const statement = db.prepare(
    "UPDATE jess_pending_requests SET status = 'done', result_text = ?, updated_at = ?, steps = json_insert(steps, '$[#]', json(?)) WHERE id = ? AND status = 're-running'",
  );
  return statement.bind(resultText, at, stepJson("applied", at, { ops: opCount }), pendingId);
}

// Before listing: a waiting request whose repair failed (not couldnt_fix: the founder is making
// that one by hand), one whose repair went live but was never re-run, and a re-run the runner never
// finished, are failed with the reason.
async function failFinished(db: D1Database, userId: string, now: number): Promise<void> {
  const at = new Date(now).toISOString();
  const cutoff = new Date(now - RERUN_ANSWER_MS).toISOString();
  const repairFailed = db.prepare(
    `UPDATE jess_pending_requests
     SET status = 'failed', updated_at = ?, steps = json_insert(steps, '$[#]', json(?)),
         fail_reason = 'repair failed: ' || COALESCE((SELECT r.fail_reason FROM repair_reports r WHERE r.id = jess_pending_requests.report_id), '')
     WHERE user_id = ? AND status = 'waiting'
       AND EXISTS (SELECT 1 FROM repair_reports r WHERE r.id = jess_pending_requests.report_id AND r.status = 'failed'
                   AND COALESCE(r.result_kind, '') <> 'couldnt_fix')`,
  );
  const neverRerun = db.prepare(
    `UPDATE jess_pending_requests
     SET status = 'failed', fail_reason = 'live but not run again', updated_at = ?, steps = json_insert(steps, '$[#]', json(?))
     WHERE user_id = ? AND status = 'waiting'
       AND EXISTS (SELECT 1 FROM repair_reports r WHERE r.id = jess_pending_requests.report_id AND r.status = 'deployed_live' AND r.updated_at < ?)`,
  );
  const unfinished = db.prepare(
    `UPDATE jess_pending_requests
     SET status = 'failed', fail_reason = 'runner did not finish the re-run', updated_at = ?, steps = json_insert(steps, '$[#]', json(?))
     WHERE user_id = ? AND status = 're-running' AND rerun_at < ?`,
  );
  await db.batch([
    repairFailed.bind(at, stepJson("repair-failed", at), userId),
    neverRerun.bind(at, stepJson("not-run-again", at), userId, cutoff),
    unfinished.bind(at, stepJson("runner-unfinished", at), userId, cutoff),
  ]);
}

// How many re-runs one runner call gets at most
export const MAX_HAND_FIXED_RERUNS = 20;

export type HandFixedRerun = { id: string; userId: string; sidekickId: string; kind: string };

// GET /repairs/jess-reruns, for the runner between jobs: the reports whose repair is live on their
// user's copy while a request still waits on them. That is an edit the founder made by hand and
// marked Built (edit-failed.ts closingStatements), or a runner publish whose re-run call was lost.
// Oldest first. The runner then calls POST /repairs/:id/jess-rerun for each, as after its own
// publish; the claim there makes a second call a no-op.
export async function handFixedReruns(db: D1Database): Promise<HandFixedRerun[]> {
  const statement = db.prepare(
    `SELECT r.id AS id, r.user_id AS user_id, r.sidekick_id AS sidekick_id, r.kind AS kind
     FROM jess_pending_requests p
     JOIN repair_reports r ON r.id = p.report_id AND r.user_id = p.user_id
     WHERE p.status = 'waiting' AND r.status = 'deployed_live'
     ORDER BY r.updated_at
     LIMIT ?`,
  );
  const result = await statement.bind(MAX_HAND_FIXED_RERUNS).all<{ id: string; user_id: string; sidekick_id: string; kind: string | null }>();
  const reruns: HandFixedRerun[] = [];
  for (const row of result.results) {
    reruns.push({ id: row.id, userId: row.user_id, sidekickId: row.sidekick_id, kind: row.kind ?? "feature" });
  }
  return reruns;
}

export type PendingItem = { id: string; sidekickId: string; state: "done" | "failed"; text: string | null; transcript: string };

// GET /voice/jess/pending: what the phone shows once, oldest first. done: the re-run's line for
// the banner ("Added Ibuprofen"); failed: the transcript for the Not Done card.
export async function listPending(db: D1Database, userId: string, now: number): Promise<PendingItem[]> {
  await failFinished(db, userId, now);
  const statement = db.prepare(
    `SELECT id, sidekick_id, transcript, status, result_text FROM jess_pending_requests
     WHERE user_id = ? AND status IN ('done', 'failed') AND shown_at IS NULL
     ORDER BY created_at`,
  );
  const result = await statement.bind(userId).all<{ id: string; sidekick_id: string; transcript: string; status: string; result_text: string | null }>();
  const items: PendingItem[] = [];
  for (const row of result.results) {
    const state = row.status === "done" ? "done" : "failed";
    items.push({ id: row.id, sidekickId: row.sidekick_id, state, text: row.result_text, transcript: row.transcript });
  }
  return items;
}

// POST /voice/jess/pending/:id/seen: the banner or the Not Done card was shown. True when it was
// the user's done or failed request and not marked before.
export async function markPendingShown(db: D1Database, pendingId: string, userId: string, at: string): Promise<boolean> {
  const statement = db.prepare(
    "UPDATE jess_pending_requests SET shown_at = ?, updated_at = ?, steps = json_insert(steps, '$[#]', json(?)) WHERE id = ? AND user_id = ? AND status IN ('done', 'failed') AND shown_at IS NULL",
  );
  const result = await statement.bind(at, at, stepJson("shown", at), pendingId, userId).run();
  return (result.meta?.changes ?? 0) === 1;
}
