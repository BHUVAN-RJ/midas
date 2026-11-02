import { Hono } from "hono";
import type { Context, Next } from "hono";
import { MAKE_INBOX_SIDEKICK_ID, makeFounderUserId } from "./make-sidekick";
import { pushFetchFromEnv, sendToUserDevices } from "./push";
import type { PushBindings } from "./push";

// Account deletion carried out in code (founder, 2026-11-02; docs/briefs/account-deletion-2026-11-02.md).
// A person asks in Settings (POST /account/delete-request, account.ts); the founder runs
// backend/scripts/delete-account.mjs, which calls these routes with ACCOUNT_DELETION_TOKEN:
//   GET  /account-deletions                    open requests (age, push outcome) and done ones
//   GET  /account-deletions/:userId            what the person still has, per table and R2 folder
//                                              (before: the preview; after: the check, allZero)
//   POST /account-deletions/:userId/carry-out  deletes all of it; pushes the founder the outcome
// The runner (REPAIR_RUNNER_TOKEN) removes its job folders on the Mac mini:
//   GET  /account-deletions/runner/pending     done deletions whose job folders are not removed
//   POST /account-deletions/runner/:userId/cleaned {result}
//
// Only the person's data (founder, 2026-11-02): every row and object is matched on the exact user
// id or on the person's own Edit report ids; the founder's inbox copies are picked by the user id
// segment of the key, the founder's files only when their copiedFrom is the person. No LIKE, no
// prefix without its "/". The founder's own account is never deleted here.

export type DeletionBindings = PushBindings & {
  DB: D1Database;
  BUNDLES: R2Bucket;
  FILES?: R2Bucket;
  MAKE_FOUNDER_USER_ID?: string;
  ACCOUNT_DELETION_TOKEN?: string;
  REPAIR_RUNNER_TOKEN?: string;
};

type DeletionEnv = { Bindings: DeletionBindings };
type DeletionContext = Context<DeletionEnv>;

const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const DELETION_PREFIX = "Deletion ";
const RUNNER_PREFIX = "Runner ";
const INBOX_KINDS = new Set(["person", "req", "message", "card", "answer"]);
// Delete markers this file writes into the founder's inbox; they hold no value.
export const DELETION_TOMBSTONE_PREFIX = "account-deleted:";
const R2_DELETE_BATCH = 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
// The founder is reminded on day 6 of the 7 (founder, 2026-11-02).
export const REMINDER_AFTER_MS = 6 * DAY_MS;
export const DELETION_DAYS = 7;

// Founder-facing push words (docs/WRITING.md: the action, then stop).
export const ACCOUNT_DELETED_PUSH_TITLE = "Account Deleted";
export const ACCOUNT_DELETION_INCOMPLETE_PUSH_TITLE = "Account Deletion Incomplete";
export const ACCOUNT_DELETION_DUE_PUSH_TITLE = "Delete Account Due";

export function accountDeletedPushBody(userName: string): string {
  return `${userName}'s account is deleted.`;
}

export function accountDeletionIncompletePushBody(userName: string, itemsLeft: number): string {
  return `${userName}: ${itemsLeft} items left. Run it again.`;
}

export function accountDeletionDuePushBody(userName: string, dueDate: string): string {
  return `${userName}'s account must be deleted by ${dueDate}.`;
}

// A push outcome that reached at least one phone ("sent 1 of 1", "sent 2 of 3; failed 1 (...)").
export function isDeliveredAlert(result: string | null | undefined): boolean {
  if (typeof result !== "string") {
    return false;
  }
  return /^sent [1-9]/.test(result);
}

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

/* ---------- Tokens ---------- */

async function sha256Bytes(text: string): Promise<Uint8Array> {
  const encoded = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return new Uint8Array(digest);
}

function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

// The header carries "<prefix><token>"; compared by hash so the time does not depend on the token.
async function presentsToken(c: DeletionContext, prefix: string, configuredToken: string | undefined): Promise<boolean> {
  if (configuredToken === undefined || configuredToken.length === 0) {
    return false;
  }
  const authorization = c.req.header("Authorization") ?? "";
  if (!authorization.startsWith(prefix)) {
    return false;
  }
  const presentedToken = authorization.slice(prefix.length);
  const presentedHash = await sha256Bytes(presentedToken);
  const configuredHash = await sha256Bytes(configuredToken);
  return sameBytes(presentedHash, configuredHash);
}

async function requireDeletionToken(c: DeletionContext, next: Next) {
  if (!(await presentsToken(c, DELETION_PREFIX, c.env.ACCOUNT_DELETION_TOKEN))) {
    return c.json({ error: "deletion token required" }, 401);
  }
  await next();
}

async function requireRunnerToken(c: DeletionContext, next: Next) {
  if (!(await presentsToken(c, RUNNER_PREFIX, c.env.REPAIR_RUNNER_TOKEN))) {
    return c.json({ error: "runner token required" }, 401);
  }
  await next();
}

/* ---------- Finding the person's data ---------- */

type InboxRow = { seq: number; op_id: string; key: string; deleted: number };

// The founder's inbox key is "<kind>:<userId>:..." (make.ts parseInboxKey). Exact segment match:
// "ab_c" never picks "ab_cd" or "abXc".
export function isInboxKeyAbout(key: string, userId: string): boolean {
  const parts = key.split(":");
  if (parts.length < 2) {
    return false;
  }
  return INBOX_KINDS.has(parts[0]) && parts[1] === userId;
}

async function inboxRowsAbout(db: D1Database, founderId: string | null, userId: string): Promise<InboxRow[]> {
  if (founderId === null || founderId === userId) {
    return [];
  }
  const statement = boundStatement(db, "SELECT seq, op_id, key, deleted FROM ops WHERE user_id = ? AND sidekick_id = ? ORDER BY seq", founderId, MAKE_INBOX_SIDEKICK_ID);
  const result = await statement.all<InboxRow>();
  const rowsAbout: InboxRow[] = [];
  for (const row of result.results) {
    if (isInboxKeyAbout(row.key, userId)) {
      rowsAbout.push(row);
    }
  }
  return rowsAbout;
}

function isDeletionTombstone(row: InboxRow): boolean {
  return row.op_id.startsWith(DELETION_TOMBSTONE_PREFIX);
}

// The seq of the latest op per key, for the keys whose latest op is still a live record.
function latestLiveSeqs(rows: InboxRow[]): number[] {
  const latestByKey = new Map<string, InboxRow>();
  for (const row of rows) {
    latestByKey.set(row.key, row);
  }
  const liveSeqs: number[] = [];
  for (const latest of latestByKey.values()) {
    if (latest.deleted === 0) {
      liveSeqs.push(latest.seq);
    }
  }
  return liveSeqs;
}

async function personReportIds(db: D1Database, userId: string): Promise<string[]> {
  const statement = boundStatement(db, "SELECT id FROM repair_reports WHERE user_id = ? ORDER BY id", userId);
  const result = await statement.all<{ id: string }>();
  const reportIds: string[] = [];
  for (const row of result.results) {
    reportIds.push(row.id);
  }
  return reportIds;
}

type ListedObject = { key: string; customMetadata?: Record<string, string> };

// Every object under a prefix, across pages.
async function listAll(bucket: R2Bucket, prefix: string, withMetadata: boolean): Promise<ListedObject[]> {
  const listed: ListedObject[] = [];
  let cursor: string | undefined = undefined;
  for (;;) {
    const options: R2ListOptions = { prefix, cursor };
    if (withMetadata) {
      options.include = ["customMetadata"];
    }
    const page = await bucket.list(options);
    for (const object of page.objects) {
      listed.push({ key: object.key, customMetadata: object.customMetadata });
    }
    if (!page.truncated) {
      return listed;
    }
    cursor = page.cursor;
  }
}

// The Sidekick ids that have a folder in the bundles bucket ("sidekicks/<id>/").
async function sidekickFolders(bundles: R2Bucket): Promise<string[]> {
  const folders: string[] = [];
  let cursor: string | undefined = undefined;
  for (;;) {
    const page = await bundles.list({ prefix: "sidekicks/", delimiter: "/", cursor });
    for (const folderPrefix of page.delimitedPrefixes) {
      folders.push(folderPrefix);
    }
    if (!page.truncated) {
      return folders;
    }
    cursor = page.cursor;
  }
}

export type PersonObjects = {
  files: string[];
  founderCopies: string[];
  sidekickCopies: string[];
  editFiles: string[];
};

function keyStartsWithSegments(key: string, segments: string[]): boolean {
  const keySegments = key.split("/");
  for (let index = 0; index < segments.length; index += 1) {
    if (keySegments[index] !== segments[index]) {
      return false;
    }
  }
  return keySegments.length > segments.length;
}

// Every R2 object that is the person's. Each key is re-checked segment by segment after listing.
export async function findPersonObjects(env: DeletionBindings, userId: string, founderId: string | null, reportIds: string[]): Promise<PersonObjects> {
  const found: PersonObjects = { files: [], founderCopies: [], sidekickCopies: [], editFiles: [] };
  const files = env.FILES;
  if (files !== undefined) {
    const ownFiles = await listAll(files, `${userId}/`, false);
    for (const object of ownFiles) {
      if (keyStartsWithSegments(object.key, [userId])) {
        found.files.push(object.key);
      }
    }
    // Files the person sent through Make, copied into the founder's folder. The founder's own
    // files (no copiedFrom, or copied from someone else) stay.
    if (founderId !== null && founderId !== userId) {
      const founderFiles = await listAll(files, `${founderId}/`, true);
      for (const object of founderFiles) {
        const copiedFrom = object.customMetadata?.copiedFrom;
        if (copiedFrom === userId && keyStartsWithSegments(object.key, [founderId])) {
          found.founderCopies.push(object.key);
        }
      }
    }
  }
  // The person's own copies of Sidekicks; the shared pages (sidekicks/<id>/<version>/) stay.
  const folders = await sidekickFolders(env.BUNDLES);
  for (const folderPrefix of folders) {
    const sidekickId = folderPrefix.split("/")[1];
    const copyObjects = await listAll(env.BUNDLES, `${folderPrefix}users/${userId}/`, false);
    for (const object of copyObjects) {
      if (keyStartsWithSegments(object.key, ["sidekicks", sidekickId, "users", userId])) {
        found.sidekickCopies.push(object.key);
      }
    }
  }
  // Screenshots, drawings and strokes of the person's Edit requests (repairs.ts assetKey).
  for (const reportId of reportIds) {
    if (reportId.length === 0 || reportId.includes("/")) {
      continue;
    }
    const editObjects = await listAll(env.BUNDLES, `repairs/${reportId}/`, false);
    for (const object of editObjects) {
      if (keyStartsWithSegments(object.key, ["repairs", reportId])) {
        found.editFiles.push(object.key);
      }
    }
  }
  return found;
}

/* ---------- Counting: the preview and the check ---------- */

type CountQuery = { name: string; sql: string; params: (userId: string) => unknown[] };

// Every table that holds the person's rows, matched exactly. repair_events and jess_pending
// requests are reached through the person's own Edit reports.
const COUNT_QUERIES: CountQuery[] = [
  { name: "users", sql: "SELECT COUNT(*) AS count FROM users WHERE id = ?", params: (userId) => [userId] },
  { name: "passkeys", sql: "SELECT COUNT(*) AS count FROM passkeys WHERE user_id = ?", params: (userId) => [userId] },
  { name: "sessions", sql: "SELECT COUNT(*) AS count FROM sessions WHERE user_id = ?", params: (userId) => [userId] },
  { name: "auth_challenges", sql: "SELECT COUNT(*) AS count FROM auth_challenges WHERE user_id = ?", params: (userId) => [userId] },
  { name: "assignments", sql: "SELECT COUNT(*) AS count FROM assignments WHERE user_id = ?", params: (userId) => [userId] },
  { name: "sidekick_removals", sql: "SELECT COUNT(*) AS count FROM sidekick_removals WHERE user_id = ?", params: (userId) => [userId] },
  { name: "ops", sql: "SELECT COUNT(*) AS count FROM ops WHERE user_id = ?", params: (userId) => [userId] },
  { name: "voice_logs", sql: "SELECT COUNT(*) AS count FROM voice_logs WHERE user_id = ?", params: (userId) => [userId] },
  { name: "jess_requests", sql: "SELECT COUNT(*) AS count FROM jess_requests WHERE user_id = ?", params: (userId) => [userId] },
  {
    name: "jess_pending_requests",
    sql: "SELECT COUNT(*) AS count FROM jess_pending_requests WHERE user_id = ? OR report_id IN (SELECT id FROM repair_reports WHERE user_id = ?)",
    params: (userId) => [userId, userId],
  },
  { name: "repair_reports", sql: "SELECT COUNT(*) AS count FROM repair_reports WHERE user_id = ?", params: (userId) => [userId] },
  {
    name: "repair_events",
    sql: "SELECT COUNT(*) AS count FROM repair_events WHERE report_id IN (SELECT id FROM repair_reports WHERE user_id = ?)",
    params: (userId) => [userId],
  },
  { name: "repair_blocked", sql: "SELECT COUNT(*) AS count FROM repair_blocked WHERE user_id = ?", params: (userId) => [userId] },
  { name: "push_devices", sql: "SELECT COUNT(*) AS count FROM push_devices WHERE user_id = ?", params: (userId) => [userId] },
  { name: "make_events", sql: "SELECT COUNT(*) AS count FROM make_events WHERE user_id = ? OR about_user_id = ?", params: (userId) => [userId, userId] },
  { name: "account_deletion_requests", sql: "SELECT COUNT(*) AS count FROM account_deletion_requests WHERE user_id = ?", params: (userId) => [userId] },
];

export type PersonCounts = Record<string, number>;

// Report ids remembered by a done deletion (the reports themselves are gone by then).
async function doneReportIds(db: D1Database, userId: string): Promise<string[]> {
  const statement = boundStatement(db, "SELECT report_ids FROM account_deletions_done WHERE user_id = ?", userId);
  const row = await statement.first<{ report_ids: string }>();
  if (row === null) {
    return [];
  }
  return parseStringList(row.report_ids);
}

function parseStringList(text: string): string[] {
  try {
    const parsed: unknown = JSON.parse(text);
    if (!Array.isArray(parsed)) {
      return [];
    }
    const strings: string[] = [];
    for (const item of parsed) {
      if (typeof item === "string") {
        strings.push(item);
      }
    }
    return strings;
  } catch {
    return [];
  }
}

function mergedIds(first: string[], second: string[]): string[] {
  const merged = new Set<string>(first);
  for (const id of second) {
    merged.add(id);
  }
  return Array.from(merged).sort();
}

// What the person still has, per table and per R2 folder. Delete markers this file wrote into
// the founder's inbox carry no value and are not counted.
export async function countPersonData(env: DeletionBindings, userId: string, reportIds: string[]): Promise<PersonCounts> {
  const db = env.DB;
  const founderId = makeFounderUserId(env);
  const counts: PersonCounts = {};
  for (const countQuery of COUNT_QUERIES) {
    const statement = boundStatement(db, countQuery.sql, ...countQuery.params(userId));
    const row = await statement.first<{ count: number }>();
    counts[countQuery.name] = Number(row?.count ?? 0);
  }
  const inboxRows = await inboxRowsAbout(db, founderId, userId);
  let inboxCount = 0;
  for (const row of inboxRows) {
    if (!isDeletionTombstone(row)) {
      inboxCount += 1;
    }
  }
  counts["make-inbox ops"] = inboxCount;
  const objects = await findPersonObjects(env, userId, founderId, reportIds);
  counts["R2 files"] = objects.files.length;
  counts["R2 founder copies"] = objects.founderCopies.length;
  counts["R2 sidekick copies"] = objects.sidekickCopies.length;
  counts["R2 edit files"] = objects.editFiles.length;
  return counts;
}

export function totalOf(counts: PersonCounts): number {
  let total = 0;
  for (const value of Object.values(counts)) {
    total += value;
  }
  return total;
}

export function nonZeroNames(counts: PersonCounts): string[] {
  const names: string[] = [];
  for (const [name, value] of Object.entries(counts)) {
    if (value > 0) {
      names.push(name);
    }
  }
  return names;
}

/* ---------- Carrying it out ---------- */

type RequestRow = { user_id: string; user_name: string; requested_at: string };

async function removeObjects(bucket: R2Bucket, keys: string[]): Promise<void> {
  for (let start = 0; start < keys.length; start += R2_DELETE_BATCH) {
    const chunk = keys.slice(start, start + R2_DELETE_BATCH);
    await bucket.delete(chunk);
  }
}

// R2 first: if it stops part way the request stays open and a second run finds the rest.
async function removePersonObjects(env: DeletionBindings, objects: PersonObjects): Promise<void> {
  const files = env.FILES;
  if (files !== undefined) {
    await removeObjects(files, objects.files);
    await removeObjects(files, objects.founderCopies);
  }
  await removeObjects(env.BUNDLES, objects.sidekickCopies);
  await removeObjects(env.BUNDLES, objects.editFiles);
}

type LabelledStatement = { name: string; statement: D1PreparedStatement };

// One batch, one transaction: children before parents (D1 enforces the foreign keys), users last.
function personRowStatements(db: D1Database, userId: string): LabelledStatement[] {
  return [
    { name: "repair_events", statement: boundStatement(db, "DELETE FROM repair_events WHERE report_id IN (SELECT id FROM repair_reports WHERE user_id = ?)", userId) },
    {
      name: "jess_pending_requests",
      statement: boundStatement(db, "DELETE FROM jess_pending_requests WHERE user_id = ? OR report_id IN (SELECT id FROM repair_reports WHERE user_id = ?)", userId, userId),
    },
    { name: "repair_reports", statement: boundStatement(db, "DELETE FROM repair_reports WHERE user_id = ?", userId) },
    { name: "voice_logs", statement: boundStatement(db, "DELETE FROM voice_logs WHERE user_id = ?", userId) },
    { name: "jess_requests", statement: boundStatement(db, "DELETE FROM jess_requests WHERE user_id = ?", userId) },
    { name: "ops", statement: boundStatement(db, "DELETE FROM ops WHERE user_id = ?", userId) },
    { name: "assignments", statement: boundStatement(db, "DELETE FROM assignments WHERE user_id = ?", userId) },
    { name: "sidekick_removals", statement: boundStatement(db, "DELETE FROM sidekick_removals WHERE user_id = ?", userId) },
    { name: "push_devices", statement: boundStatement(db, "DELETE FROM push_devices WHERE user_id = ?", userId) },
    { name: "repair_blocked", statement: boundStatement(db, "DELETE FROM repair_blocked WHERE user_id = ?", userId) },
    { name: "sessions", statement: boundStatement(db, "DELETE FROM sessions WHERE user_id = ?", userId) },
    { name: "passkeys", statement: boundStatement(db, "DELETE FROM passkeys WHERE user_id = ?", userId) },
    { name: "auth_challenges", statement: boundStatement(db, "DELETE FROM auth_challenges WHERE user_id = ?", userId) },
    { name: "make_events", statement: boundStatement(db, "DELETE FROM make_events WHERE user_id = ? OR about_user_id = ?", userId, userId) },
    { name: "account_deletion_requests", statement: boundStatement(db, "DELETE FROM account_deletion_requests WHERE user_id = ?", userId) },
    { name: "users", statement: boundStatement(db, "DELETE FROM users WHERE id = ?", userId) },
  ];
}

// The founder's inbox copies: a delete marker for each live key first, so the founder's phone
// drops them on its next pull, then the old rows themselves.
function inboxStatements(db: D1Database, founderId: string | null, userId: string, inboxRows: InboxRow[], nowIso: string): LabelledStatement[] {
  if (founderId === null || inboxRows.length === 0) {
    return [];
  }
  const oldSeqs: number[] = [];
  for (const row of inboxRows) {
    if (!isDeletionTombstone(row)) {
      oldSeqs.push(row.seq);
    }
  }
  const liveSeqs = latestLiveSeqs(inboxRows);
  const markerStatement = boundStatement(
    db,
    `INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, client_time, received_at)
     SELECT ? || ops.seq, ops.user_id, ops.sidekick_id, ops.key, NULL, 1, NULL, ?
     FROM ops WHERE ops.user_id = ? AND ops.sidekick_id = ? AND ops.seq IN (SELECT value FROM json_each(?)) ORDER BY ops.seq`,
    `${DELETION_TOMBSTONE_PREFIX}${userId}:`,
    nowIso,
    founderId,
    MAKE_INBOX_SIDEKICK_ID,
    JSON.stringify(liveSeqs),
  );
  const removeStatement = boundStatement(
    db,
    "DELETE FROM ops WHERE user_id = ? AND sidekick_id = ? AND seq IN (SELECT value FROM json_each(?))",
    founderId,
    MAKE_INBOX_SIDEKICK_ID,
    JSON.stringify(oldSeqs),
  );
  return [
    { name: "make-inbox markers", statement: markerStatement },
    { name: "make-inbox ops", statement: removeStatement },
  ];
}

export type CarryOutResult =
  | { status: "deleted"; counts: PersonCounts; check: PersonCounts; alertResult: string }
  | { status: "incomplete"; error: string; remaining: PersonCounts; alertResult: string };

async function pushFounder(env: DeletionBindings, payload: Record<string, unknown>): Promise<string> {
  const founderId = makeFounderUserId(env);
  if (founderId === null) {
    return "no founder set";
  }
  try {
    return await sendToUserDevices(env.DB, env, founderId, payload, pushFetchFromEnv(env), Date.now());
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`account deletion push failed: ${message}`);
    return message;
  }
}

function founderPayload(title: string, body: string, founderAlert: Record<string, unknown>): Record<string, unknown> {
  return { aps: { alert: { title, body }, sound: "default" }, founderAlert };
}

function addCounts(target: PersonCounts, name: string, value: number): void {
  target[name] = (target[name] ?? 0) + value;
}

async function recordIncomplete(env: DeletionBindings, request: RequestRow, reportIds: string[], error: unknown): Promise<CarryOutResult> {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`account deletion of ${request.user_id} stopped: ${message}`);
  const storeError = boundStatement(env.DB, "UPDATE account_deletion_requests SET last_error = ? WHERE user_id = ?", message, request.user_id);
  await storeError.run();
  const remaining = await countPersonData(env, request.user_id, reportIds);
  const itemsLeft = totalOf(remaining);
  const payload = founderPayload(ACCOUNT_DELETION_INCOMPLETE_PUSH_TITLE, accountDeletionIncompletePushBody(request.user_name, itemsLeft), {
    kind: "account-deletion-incomplete",
    userId: request.user_id,
    itemsLeft,
  });
  const alertResult = await pushFounder(env, payload);
  return { status: "incomplete", error: message, remaining, alertResult };
}

export async function carryOutDeletion(env: DeletionBindings, request: RequestRow, nowMs: number): Promise<CarryOutResult> {
  const db = env.DB;
  const userId = request.user_id;
  const founderId = makeFounderUserId(env);
  const nowIso = new Date(nowMs).toISOString();
  const reportIds = await personReportIds(db, userId);
  const counts: PersonCounts = {};
  try {
    const objects = await findPersonObjects(env, userId, founderId, reportIds);
    await removePersonObjects(env, objects);
    addCounts(counts, "R2 files", objects.files.length);
    addCounts(counts, "R2 founder copies", objects.founderCopies.length);
    addCounts(counts, "R2 sidekick copies", objects.sidekickCopies.length);
    addCounts(counts, "R2 edit files", objects.editFiles.length);

    const inboxRows = await inboxRowsAbout(db, founderId, userId);
    const doneStatement = boundStatement(
      db,
      "INSERT INTO account_deletions_done (user_id, requested_at, carried_out_at, counts, report_ids) VALUES (?, ?, ?, '{}', ?)",
      userId,
      request.requested_at,
      nowIso,
      JSON.stringify(reportIds),
    );
    const labelled = [...inboxStatements(db, founderId, userId, inboxRows, nowIso), ...personRowStatements(db, userId)];
    const statements = [doneStatement];
    for (const entry of labelled) {
      statements.push(entry.statement);
    }
    const results = await db.batch(statements);
    for (let index = 0; index < labelled.length; index += 1) {
      const changes = results[index + 1]?.meta?.changes ?? 0;
      if (labelled[index].name !== "make-inbox markers") {
        addCounts(counts, labelled[index].name, changes);
      }
    }
  } catch (error) {
    return recordIncomplete(env, request, reportIds, error);
  }
  const check = await countPersonData(env, userId, reportIds);
  const payload = founderPayload(ACCOUNT_DELETED_PUSH_TITLE, accountDeletedPushBody(request.user_name), {
    kind: "account-deleted",
    userId,
    counts,
    allZero: totalOf(check) === 0,
  });
  const alertResult = await pushFounder(env, payload);
  const storeOutcome = boundStatement(db, "UPDATE account_deletions_done SET counts = ?, alert_result = ? WHERE user_id = ?", JSON.stringify(counts), alertResult, userId);
  await storeOutcome.run();
  return { status: "deleted", counts, check, alertResult };
}

/* ---------- Routes ---------- */

type OpenRequestRow = RequestRow & { alert_result: string | null; last_error: string | null; reminded_at: string | null };

type DoneRow = {
  user_id: string;
  requested_at: string;
  carried_out_at: string;
  counts: string;
  report_ids: string;
  alert_result: string | null;
  runner_cleaned_at: string | null;
  runner_result: string | null;
};

function parseCounts(text: string): PersonCounts {
  try {
    const parsed: unknown = JSON.parse(text);
    if (typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)) {
      return parsed as PersonCounts;
    }
    return {};
  } catch {
    return {};
  }
}

// "Mon 9 Nov": the last day of the 7, in UTC.
export function dueDateText(requestedAtIso: string): string {
  const requestedMs = Date.parse(requestedAtIso);
  const due = new Date(requestedMs + DELETION_DAYS * DAY_MS);
  const weekday = due.toLocaleDateString("en-GB", { weekday: "short", timeZone: "UTC" });
  const dayAndMonth = due.toLocaleDateString("en-GB", { day: "numeric", month: "short", timeZone: "UTC" });
  return `${weekday} ${dayAndMonth}`;
}

function openRequestView(row: OpenRequestRow, nowMs: number) {
  const ageMs = nowMs - Date.parse(row.requested_at);
  return {
    userId: row.user_id,
    userName: row.user_name,
    requestedAt: row.requested_at,
    ageDays: Math.floor(ageMs / DAY_MS),
    dueDate: dueDateText(row.requested_at),
    alertResult: row.alert_result,
    alertDelivered: isDeliveredAlert(row.alert_result),
    lastError: row.last_error,
    remindedAt: row.reminded_at,
  };
}

function doneView(row: DoneRow) {
  return {
    userId: row.user_id,
    requestedAt: row.requested_at,
    carriedOutAt: row.carried_out_at,
    counts: parseCounts(row.counts),
    reportIds: parseStringList(row.report_ids),
    alertResult: row.alert_result,
    runnerCleanedAt: row.runner_cleaned_at,
    runnerResult: row.runner_result,
  };
}

async function founderDeviceCount(env: DeletionBindings): Promise<number> {
  const founderId = makeFounderUserId(env);
  if (founderId === null) {
    return 0;
  }
  const statement = boundStatement(env.DB, "SELECT COUNT(*) AS count FROM push_devices WHERE user_id = ? AND disabled_at IS NULL", founderId);
  const row = await statement.first<{ count: number }>();
  return Number(row?.count ?? 0);
}

async function handleList(c: DeletionContext) {
  const nowMs = Date.now();
  const openStatement = c.env.DB.prepare(
    "SELECT user_id, user_name, requested_at, alert_result, last_error, reminded_at FROM account_deletion_requests ORDER BY requested_at",
  );
  const openResult = await openStatement.all<OpenRequestRow>();
  const doneStatement = c.env.DB.prepare(
    "SELECT user_id, requested_at, carried_out_at, counts, report_ids, alert_result, runner_cleaned_at, runner_result FROM account_deletions_done ORDER BY carried_out_at",
  );
  const doneResult = await doneStatement.all<DoneRow>();
  const open = [];
  for (const row of openResult.results) {
    open.push(openRequestView(row, nowMs));
  }
  const done = [];
  for (const row of doneResult.results) {
    done.push(doneView(row));
  }
  const founderDevices = await founderDeviceCount(c.env);
  return c.json({ founderSet: makeFounderUserId(c.env) !== null, founderDevices, open, done });
}

async function readOpenRequest(db: D1Database, userId: string): Promise<OpenRequestRow | null> {
  const statement = boundStatement(db, "SELECT user_id, user_name, requested_at, alert_result, last_error, reminded_at FROM account_deletion_requests WHERE user_id = ?", userId);
  return statement.first<OpenRequestRow>();
}

async function readDone(db: D1Database, userId: string): Promise<DoneRow | null> {
  const statement = boundStatement(
    db,
    "SELECT user_id, requested_at, carried_out_at, counts, report_ids, alert_result, runner_cleaned_at, runner_result FROM account_deletions_done WHERE user_id = ?",
    userId,
  );
  return statement.first<DoneRow>();
}

// The preview (before) and the check (after): what the person still has.
async function handleCount(c: DeletionContext) {
  const userId = c.req.param("userId") ?? "";
  if (!USER_ID_PATTERN.test(userId)) {
    return c.json({ error: "bad user id" }, 400);
  }
  const reportIds = mergedIds(await personReportIds(c.env.DB, userId), await doneReportIds(c.env.DB, userId));
  const counts = await countPersonData(c.env, userId, reportIds);
  const openRequest = await readOpenRequest(c.env.DB, userId);
  const done = await readDone(c.env.DB, userId);
  let state = "none";
  if (openRequest !== null) {
    state = "open";
  } else if (done !== null) {
    state = "done";
  }
  const runner = done === null ? null : { cleanedAt: done.runner_cleaned_at, result: done.runner_result };
  return c.json({ userId, state, counts, total: totalOf(counts), allZero: totalOf(counts) === 0, nonZero: nonZeroNames(counts), runner });
}

async function handleCarryOut(c: DeletionContext) {
  const userId = c.req.param("userId") ?? "";
  if (!USER_ID_PATTERN.test(userId)) {
    return c.json({ error: "bad user id" }, 400);
  }
  if (userId === makeFounderUserId(c.env)) {
    return c.json({ error: "the founder's account is not deleted here" }, 409);
  }
  // Only a person who asked: a deletion always starts from their own request.
  const request = await readOpenRequest(c.env.DB, userId);
  if (request === null) {
    const done = await readDone(c.env.DB, userId);
    if (done !== null) {
      return c.json({ error: "already deleted", carriedOutAt: done.carried_out_at }, 409);
    }
    return c.json({ error: "no deletion request for this user" }, 404);
  }
  const result = await carryOutDeletion(c.env, request, Date.now());
  if (result.status === "incomplete") {
    return c.json({ deleted: false, error: result.error, remaining: result.remaining, alertResult: result.alertResult }, 500);
  }
  return c.json({ deleted: true, counts: result.counts, check: result.check, allZero: totalOf(result.check) === 0, alertResult: result.alertResult });
}

async function handleRunnerPending(c: DeletionContext) {
  const statement = c.env.DB.prepare("SELECT user_id, report_ids FROM account_deletions_done WHERE runner_cleaned_at IS NULL ORDER BY carried_out_at");
  const result = await statement.all<{ user_id: string; report_ids: string }>();
  const deletions = [];
  for (const row of result.results) {
    deletions.push({ userId: row.user_id, reportIds: parseStringList(row.report_ids) });
  }
  return c.json({ deletions });
}

async function handleRunnerCleaned(c: DeletionContext) {
  const userId = c.req.param("userId") ?? "";
  let body: Record<string, unknown> = {};
  try {
    body = await c.req.json();
  } catch {
    body = {};
  }
  const resultText = typeof body.result === "string" ? body.result.slice(0, 500) : "cleaned";
  const statement = boundStatement(
    c.env.DB,
    "UPDATE account_deletions_done SET runner_cleaned_at = ?, runner_result = ? WHERE user_id = ? AND runner_cleaned_at IS NULL",
    new Date().toISOString(),
    resultText,
    userId,
  );
  const outcome = await statement.run();
  const changes = outcome.meta?.changes ?? 0;
  if (changes === 0) {
    return c.json({ error: "no such deletion waiting" }, 404);
  }
  return c.json({ cleaned: true });
}

export const accountDeletionRoutes = new Hono<DeletionEnv>();
accountDeletionRoutes.get("/runner/pending", requireRunnerToken, handleRunnerPending);
accountDeletionRoutes.post("/runner/:userId/cleaned", requireRunnerToken, handleRunnerCleaned);
accountDeletionRoutes.get("/", requireDeletionToken, handleList);
accountDeletionRoutes.get("/:userId", requireDeletionToken, handleCount);
accountDeletionRoutes.post("/:userId/carry-out", requireDeletionToken, handleCarryOut);

/* ---------- The daily reminder (cron) ---------- */

type ReminderAlerter = (env: DeletionBindings, userId: string, userName: string) => Promise<void>;

// Run once a day by the cron trigger. For every open request: an alert that never reached the
// founder's phone is sent again; on day 6 the founder is reminded once that the 7 days end.
export async function remindOpenDeletions(env: DeletionBindings, nowMs: number, resendAlert: ReminderAlerter): Promise<void> {
  const statement = env.DB.prepare("SELECT user_id, user_name, requested_at, alert_result, last_error, reminded_at FROM account_deletion_requests ORDER BY requested_at");
  const result = await statement.all<OpenRequestRow>();
  for (const row of result.results) {
    try {
      if (!isDeliveredAlert(row.alert_result)) {
        await resendAlert(env, row.user_id, row.user_name);
      }
      const isDue = nowMs - Date.parse(row.requested_at) >= REMINDER_AFTER_MS;
      if (isDue && row.reminded_at === null) {
        const payload = founderPayload(ACCOUNT_DELETION_DUE_PUSH_TITLE, accountDeletionDuePushBody(row.user_name, dueDateText(row.requested_at)), {
          kind: "account-deletion-due",
          userId: row.user_id,
        });
        const alertResult = await pushFounder(env, payload);
        const remindedAt = isDeliveredAlert(alertResult) ? new Date(nowMs).toISOString() : null;
        const storeReminder = boundStatement(env.DB, "UPDATE account_deletion_requests SET reminded_at = ? WHERE user_id = ?", remindedAt, row.user_id);
        await storeReminder.run();
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`account deletion reminder for ${row.user_id} failed: ${message}`);
    }
  }
}
