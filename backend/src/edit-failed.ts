import { MAKE_INBOX_PUSH_TITLE, MAKE_INBOX_SIDEKICK_ID, makeFounderUserId } from "./make-sidekick";
import { copyOpStatement, makeEventStatement, personRecordOpId, pushBodyText, userName } from "./make";

// An edit that could not be made (build 22, founder 2026-10-31; docs/briefs/edit-failed-contract.md).
// The person sees "Check back in some time." (repairs.ts USER_RESULT_TEXT.couldnt_fix). The founder
// is alerted twice, in one batch with the failed status:
//   - a thread in his Make inbox: req:<userId>:edit-<report hex> (title: the Sidekick and what was
//     asked) and one message with what was asked, why it failed and where the job's log is
//   - a push to his phones ("Inbox" / "<name> · <sidekick>: <asked>"), kind message, so a tap opens
//     that thread
// He fixes the copy by hand and publishes it, then marks the thread Built in the inbox: the report
// turns fixed and the person's notice says the update is done (closingStatements below, run from the
// Make copy step). Edit threads never reach the person's own Make store.

export const EDIT_REQUEST_PREFIX = "edit-";
// Where the Mac mini runner keeps each job's log (runner/lib/config.mjs logsRoot): the job link.
export const RUNNER_LOG_FOLDER = "~/Library/Application Support/midas-runner/log";
const MAX_TITLE_LENGTH = 200;
const MAX_MESSAGE_LENGTH = 4000;
const MAX_ASKED_IN_MESSAGE = 3000;
const MAX_DETAIL_LENGTH = 400;
const REPORT_HEX_PATTERN = /^[0-9a-f]{32}$/;
const REPORT_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// The parts of a repair report the founder's alert needs.
export type FailedReport = {
  id: string;
  user_id: string;
  sidekick_id: string;
  transcript: string;
  typed_text: string | null;
};

export type FailureCause = {
  reason: string;
  detail: string | null;
};

export type EditFailedPlan = {
  statements: D1PreparedStatement[];
  // Index inside statements of the make_events insert, so the caller pushes only when it was stored now
  eventIndex: number;
  eventId: string;
};

type FounderBindings = { MAKE_FOUNDER_USER_ID?: string };

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

/* ---------- Ids ---------- */

// edit-<the report id without dashes>: 37 characters, inside the Make id pattern. A phone's own
// request ids are hex, so they never start with "edit-".
export function editRequestId(reportId: string): string {
  const hex = reportId.replaceAll("-", "");
  return `${EDIT_REQUEST_PREFIX}${hex}`;
}

export function isEditRequestId(requestId: string | null): boolean {
  return reportIdFromEditRequest(requestId) !== null;
}

// The repair report an edit thread is about, or null when the request is not an edit thread.
export function reportIdFromEditRequest(requestId: string | null): string | null {
  if (requestId === null || !requestId.startsWith(EDIT_REQUEST_PREFIX)) {
    return null;
  }
  const hex = requestId.slice(EDIT_REQUEST_PREFIX.length);
  if (!REPORT_HEX_PATTERN.test(hex)) {
    return null;
  }
  // Back into the 8-4-4-4-12 shape of crypto.randomUUID()
  const reportId = [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join("-");
  return REPORT_ID_PATTERN.test(reportId) ? reportId : null;
}

/* ---------- Words ---------- */

// What the person asked: their spoken words, plus what they typed when they typed something.
export function askedText(report: FailedReport): string {
  const spoken = report.transcript.trim();
  const typed = report.typed_text === null ? "" : report.typed_text.trim();
  if (typed.length === 0 || typed === spoken) {
    return spoken;
  }
  return `${spoken}\n${typed}`;
}

function cut(text: string, limit: number): string {
  const characters = Array.from(text);
  if (characters.length <= limit) {
    return text;
  }
  return `${characters.slice(0, limit - 1).join("")}…`;
}

export function editThreadTitle(report: FailedReport): string {
  const firstLine = askedText(report).split("\n")[0];
  return cut(`${report.sidekick_id}: ${firstLine}`, MAX_TITLE_LENGTH);
}

export function jobLink(reportId: string): string {
  return `${RUNNER_LOG_FOLDER}/${reportId}`;
}

// The one message of the thread: what was asked, why it failed, the job.
export function editThreadMessage(report: FailedReport, cause: FailureCause): string {
  const detail = cause.detail === null || cause.detail.trim().length === 0 ? "" : `: ${cut(cause.detail.trim(), MAX_DETAIL_LENGTH)}`;
  const lines = [
    `Could not edit ${report.sidekick_id}.`,
    `Asked: ${cut(askedText(report), MAX_ASKED_IN_MESSAGE)}`,
    `Why: ${cause.reason}${detail}`,
    `Job: ${jobLink(report.id)}`,
    `Report: ${report.id}`,
  ];
  return cut(lines.join("\n"), MAX_MESSAGE_LENGTH);
}

/* ---------- The founder's alert ---------- */

async function userExists(db: D1Database, userId: string): Promise<boolean> {
  const statement = boundStatement(db, "SELECT 1 AS found FROM users WHERE id = ?", userId);
  const row = await statement.first();
  return row !== null;
}

// The statements that open the edit thread in the founder's inbox and queue his push, or null when
// no founder is set on this server (or the id names no user): the failure is then stored alone.
// Op and event ids are fixed by the report, so building them twice stores them once.
export async function editFailedStatements(db: D1Database, env: FounderBindings, report: FailedReport, cause: FailureCause, failedAt: string): Promise<EditFailedPlan | null> {
  const founderId = makeFounderUserId(env);
  if (founderId === null || !(await userExists(db, founderId))) {
    return null;
  }
  const requestId = editRequestId(report.id);
  const reportHex = requestId.slice(EDIT_REQUEST_PREFIX.length);
  const personUserId = report.user_id;
  const name = await userName(db, personUserId);
  const statements: D1PreparedStatement[] = [];

  const personValue = { $type: "make.person", userId: personUserId, name: name.slice(0, 64), firstAt: failedAt };
  statements.push(copyOpStatement(db, personRecordOpId(personUserId), founderId, MAKE_INBOX_SIDEKICK_ID, `person:${personUserId}`, personValue, null, failedAt));

  const requestValue = {
    $type: "make.request",
    userId: personUserId,
    title: editThreadTitle(report),
    status: "sent",
    createdAt: failedAt,
    updatedAt: failedAt,
    editReportId: report.id,
    editSidekickId: report.sidekick_id,
  };
  const requestKey = `req:${personUserId}:${requestId}`;
  statements.push(copyOpStatement(db, `mkedit-${reportHex}-r`, founderId, MAKE_INBOX_SIDEKICK_ID, requestKey, requestValue, null, failedAt));

  const messageValue = { $type: "make.message", userId: personUserId, from: "person", text: editThreadMessage(report, cause), sentAt: failedAt };
  const messageKey = `message:${personUserId}:${requestId}:fail${reportHex.slice(0, 16)}`;
  statements.push(copyOpStatement(db, `mkedit-${reportHex}-m`, founderId, MAKE_INBOX_SIDEKICK_ID, messageKey, messageValue, null, failedAt));

  // kind "message": the shell's tap opens the inbox thread of (userId, requestId)
  const eventId = `editfail:${report.id}`;
  const firstLine = askedText(report).split("\n")[0];
  const body = pushBodyText(`${name} · ${report.sidekick_id}: ${firstLine}`);
  const event = { id: eventId, audience: "founder" as const, userId: founderId, aboutUserId: personUserId, requestId, kind: "message" as const, title: MAKE_INBOX_PUSH_TITLE, body };
  const eventIndex = statements.length;
  statements.push(makeEventStatement(db, event, failedAt));
  return { statements, eventIndex, eventId };
}

// The event id to push when the batch stored the event now; null when it was stored before.
export function insertedEditEventId(plan: EditFailedPlan | null, batchResults: D1Result[], offset: number): string | null {
  if (plan === null) {
    return null;
  }
  const result = batchResults[offset + plan.eventIndex];
  const changes = result?.meta?.changes ?? 0;
  return changes > 0 ? plan.eventId : null;
}

/* ---------- Closing: the founder fixed it by hand ---------- */

// The founder marked an edit thread Built: the report (still couldnt_fix) becomes fixed, with his
// plan line as the summary the person sees on tap, and the person gets a "fixed" notice once.
// Safe to run again: the update only matches a couldnt_fix report, the notice only when none exists.
export function closingStatements(db: D1Database, reportId: string, personUserId: string, summary: string | null, closedAt: string): D1PreparedStatement[] {
  const markFixed = boundStatement(
    db,
    `UPDATE repair_reports SET status = 'deployed_live', result_kind = 'fixed', result_summary = ?, updated_at = ?
     WHERE id = ? AND user_id = ? AND status = 'failed' AND result_kind = 'couldnt_fix'`,
    summary,
    closedAt,
    reportId,
    personUserId,
  );
  const notifyPerson = boundStatement(
    db,
    `INSERT INTO repair_events (id, report_id, audience, kind, created_at)
     SELECT ?, ?, 'user', 'deployed_live', ?
     WHERE EXISTS (SELECT 1 FROM repair_reports WHERE id = ? AND status = 'deployed_live')
       AND NOT EXISTS (SELECT 1 FROM repair_events WHERE report_id = ? AND audience = 'user' AND kind = 'deployed_live')`,
    crypto.randomUUID(),
    reportId,
    closedAt,
    reportId,
    reportId,
  );
  return [markFixed, notifyPerson];
}
