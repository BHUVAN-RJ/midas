import { Hono } from "hono";
import type { Context, Next } from "hono";
import { requireSession } from "./auth";
import { SIDEKICK_ID_PATTERN } from "./sidekicks";

// Repair (founder, 2026-10-13; docs/briefs/repair-contract.md). A user scribbles in a Sidekick,
// draws on the frozen screen and speaks; the shell posts the report here. Text and metadata go
// to D1 (repair_reports), screenshot / drawing / strokes to R2 under repairs/<id>/ in the
// BUNDLES bucket. The founder's Mac mini pulls jobs with a runner token (a Worker secret, never a
// user session), fixes the reporter's own copy and stops at fix_ready; the founder deploys live.
// Nothing here writes the ops table; the runner-only records route reads the reporter's own.

type RepairBindings = {
  DB: D1Database;
  BUNDLES: R2Bucket;
  // Shared secret for the Mac mini runner: `wrangler secret put REPAIR_RUNNER_TOKEN`.
  REPAIR_RUNNER_TOKEN?: string;
  RP_ID?: string;
};

type RepairVariables = {
  userId: string;
  caller: "user" | "runner";
};

type RepairEnv = { Bindings: RepairBindings; Variables: RepairVariables };
type RepairContext = Context<RepairEnv>;

export const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
export const MAX_STROKES_BYTES = 1024 * 1024;
export const MAX_TRANSCRIPT_BYTES = 32 * 1024;
export const MAX_TIMINGS_BYTES = 256 * 1024;
// Everything in one report, with multipart overhead. Checked against Content-Length first.
export const MAX_REPORT_BYTES = 10 * 1024 * 1024;
export const LEASE_MS = 15 * 60 * 1000;
export const MAX_ATTEMPTS = 3;
// The only words the user ever gets (founder, 2026-10-13).
export const USER_DONE_TEXT = "The update you requested is done.";

// bug: said out loud; change: shown by drawing; feature: a new capability asked by voice, maybe
// with no drawing at all (founder, 2026-10-13). A hint only; the agent decides from the transcript.
const REPORT_KINDS = new Set(["bug", "change", "feature", "unknown"]);
const BUNDLE_SCOPES = new Set(["user", "base"]);
const REPORT_ID_PATTERN = /^[0-9a-f-]{36}$/;
const MAX_SHORT_FIELD_LENGTH = 80;
const RUNNER_PREFIX = "Runner ";
const ASSET_COLUMNS: Record<string, "screenshot_key" | "drawing_key" | "strokes_key"> = {
  screenshot: "screenshot_key",
  drawing: "drawing_key",
  strokes: "strokes_key",
};
// Served live from the Sidekick bucket, not stored with the report: the reporter's current copy.
const BUNDLE_ASSETS: Record<string, { fileName: string; contentType: string }> = {
  "bundle.html": { fileName: "index.html", contentType: "text/html; charset=utf-8" },
  "bundle.manifest.json": { fileName: "manifest.json", contentType: "application/json" },
  // jess router (2026-10-21): 404 when the copy has no tools.js; the runner then works without one
  "bundle.tools.js": { fileName: "tools.js", contentType: "text/javascript; charset=utf-8" },
};

type ReportRow = {
  id: string;
  user_id: string;
  sidekick_id: string;
  bundle_version: string | null;
  bundle_scope: string | null;
  kind: string;
  transcript: string;
  transcript_words: string | null;
  typed_text: string | null;
  client_report_id: string | null;
  device: string | null;
  ios_version: string | null;
  app_version: string | null;
  app_build: string | null;
  status: string;
  fail_reason: string | null;
  runner_id: string | null;
  lease_until: number | null;
  attempts: number;
  screenshot_key: string | null;
  drawing_key: string | null;
  strokes_key: string | null;
  created_at: string;
  updated_at: string;
};

type EventRow = {
  id: string;
  report_id: string;
  kind: string;
  created_at: string;
  sidekick_id: string;
  user_id: string;
  status: string;
  transcript: string;
  fail_reason: string | null;
};

const textEncoder = new TextEncoder();

function byteLength(text: string): number {
  return textEncoder.encode(text).length;
}

function nowIso(): string {
  return new Date().toISOString();
}

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

// ---- runner token --------------------------------------------------------------------------

async function sha256Bytes(text: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest("SHA-256", textEncoder.encode(text));
  return new Uint8Array(digest);
}

// Compares digests of equal length without stopping at the first difference.
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

async function isRunnerToken(c: RepairContext): Promise<boolean> {
  const configuredToken = c.env.REPAIR_RUNNER_TOKEN;
  if (configuredToken === undefined || configuredToken.length === 0) {
    return false;
  }
  const authorization = c.req.header("Authorization") ?? "";
  if (!authorization.startsWith(RUNNER_PREFIX)) {
    return false;
  }
  const presentedToken = authorization.slice(RUNNER_PREFIX.length);
  const [presentedHash, configuredHash] = await Promise.all([sha256Bytes(presentedToken), sha256Bytes(configuredToken)]);
  return sameBytes(presentedHash, configuredHash);
}

// Runner-only routes. A user session is refused like any other wrong token.
async function requireRunner(c: RepairContext, next: Next) {
  if (!(await isRunnerToken(c))) {
    return c.json({ error: "runner token required" }, 401);
  }
  c.set("caller", "runner");
  await next();
}

// Routes the runner and the reporter may both use. The runner sees any report; a user only
// their own (checked per route with ownsReport).
async function requireRunnerOrSession(c: RepairContext, next: Next) {
  if (await isRunnerToken(c)) {
    c.set("caller", "runner");
    await next();
    return;
  }
  c.set("caller", "user");
  return requireSession(c as unknown as Parameters<typeof requireSession>[0], next);
}

// ---- rows ----------------------------------------------------------------------------------

function assetKey(reportId: string, fileName: string): string {
  return `repairs/${reportId}/${fileName}`;
}

function parseJsonOrNull(text: string | null): unknown {
  if (text === null) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function assetNames(row: ReportRow): Record<string, string | null> {
  function fileNameOf(key: string | null): string | null {
    if (key === null) {
      return null;
    }
    return key.slice(key.lastIndexOf("/") + 1);
  }
  return {
    screenshot: fileNameOf(row.screenshot_key),
    drawing: fileNameOf(row.drawing_key),
    strokes: fileNameOf(row.strokes_key),
  };
}

function reportFromRow(row: ReportRow) {
  return {
    id: row.id,
    userId: row.user_id,
    sidekickId: row.sidekick_id,
    bundleVersion: row.bundle_version,
    bundleScope: row.bundle_scope,
    kind: row.kind,
    transcript: row.transcript,
    transcriptWords: parseJsonOrNull(row.transcript_words),
    typedText: row.typed_text,
    clientReportId: row.client_report_id,
    device: row.device,
    iosVersion: row.ios_version,
    appVersion: row.app_version,
    appBuild: row.app_build,
    status: row.status,
    failReason: row.fail_reason,
    runnerId: row.runner_id,
    leaseUntil: row.lease_until,
    attempts: row.attempts,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    assets: assetNames(row),
  };
}

async function readReport(db: D1Database, reportId: string): Promise<ReportRow | null> {
  const statement = boundStatement(db, "SELECT * FROM repair_reports WHERE id = ?", reportId);
  return statement.first<ReportRow>();
}

// A report another user cannot see answers exactly like one that does not exist.
function ownsReport(c: RepairContext, row: ReportRow): boolean {
  if (c.get("caller") === "runner") {
    return true;
  }
  return row.user_id === c.get("userId");
}

async function isAssigned(db: D1Database, userId: string, sidekickId: string): Promise<boolean> {
  const statement = boundStatement(db, "SELECT 1 AS assigned FROM assignments WHERE user_id = ? AND sidekick_id = ?", userId, sidekickId);
  const assignment = await statement.first();
  return assignment !== null;
}

function insertEventStatement(db: D1Database, reportId: string, audience: "founder" | "user", kind: string, createdAt: string): D1PreparedStatement {
  return boundStatement(
    db,
    "INSERT INTO repair_events (id, report_id, audience, kind, created_at) VALUES (?, ?, ?, ?, ?)",
    crypto.randomUUID(),
    reportId,
    audience,
    kind,
    createdAt,
  );
}

// ---- POST /repairs -------------------------------------------------------------------------

type UploadedFile = { bytes: ArrayBuffer; contentType: string };

type CleanReport = {
  sidekickId: string;
  kind: string;
  transcript: string;
  transcriptWords: string | null;
  typedText: string | null;
  clientReportId: string | null;
  bundleVersion: string | null;
  bundleScope: string | null;
  device: string | null;
  iosVersion: string | null;
  appVersion: string | null;
  appBuild: string | null;
  strokes: string | null;
  screenshot: UploadedFile | null;
  drawing: UploadedFile | null;
};

type Rejection = { error: string; status: 400 | 413 };

function isRejection(result: CleanReport | Rejection): result is Rejection {
  return "error" in result;
}

function isFilePart(value: unknown): value is Blob {
  return typeof value === "object" && value !== null && typeof (value as Blob).arrayBuffer === "function";
}

function shortField(form: FormData, name: string): string | null | Rejection {
  const value = form.get(name);
  if (value === null) {
    return null;
  }
  if (typeof value !== "string" || value.length > MAX_SHORT_FIELD_LENGTH) {
    return { error: `${name} must be text up to ${MAX_SHORT_FIELD_LENGTH} characters`, status: 400 };
  }
  return value;
}

// Images are optional: a feature request may be voice only. A part that is present but is not a
// file is still an error.
async function imagePart(form: FormData, name: string): Promise<UploadedFile | null | Rejection> {
  const value = form.get(name);
  if (value === null) {
    return null;
  }
  if (!isFilePart(value)) {
    return { error: `${name} must be a file`, status: 400 };
  }
  if (value.size > MAX_IMAGE_BYTES) {
    return { error: `${name} is over ${MAX_IMAGE_BYTES} bytes`, status: 413 };
  }
  const contentType = value.type === "image/jpeg" ? "image/jpeg" : "image/png";
  return { bytes: await value.arrayBuffer(), contentType };
}

// JSON text that must be an array: strokes and word timings.
async function jsonArrayPart(form: FormData, name: string, maxBytes: number, required: boolean): Promise<string | null | Rejection> {
  const value = form.get(name);
  if (value === null) {
    return required ? { error: `${name} is missing`, status: 400 } : null;
  }
  const text = isFilePart(value) ? await value.text() : String(value);
  if (byteLength(text) > maxBytes) {
    return { error: `${name} is over ${maxBytes} bytes`, status: 413 };
  }
  const parsed = parseJsonOrNull(text);
  if (!Array.isArray(parsed)) {
    return { error: `${name} must be a JSON array`, status: 400 };
  }
  return text;
}

// Everything the phone sends, checked. Transcript is required (founder, 2026-10-13): a drawing
// alone does not say what to change.
async function cleanReport(form: FormData): Promise<CleanReport | Rejection> {
  const sidekickId = form.get("sidekickId");
  if (typeof sidekickId !== "string" || !SIDEKICK_ID_PATTERN.test(sidekickId)) {
    return { error: "bad sidekickId", status: 400 };
  }
  const rawKind = form.get("kind");
  const kind = typeof rawKind === "string" && REPORT_KINDS.has(rawKind) ? rawKind : "unknown";

  const rawTranscript = form.get("transcript");
  const transcript = typeof rawTranscript === "string" ? rawTranscript.trim() : "";
  if (transcript.length === 0) {
    return { error: "transcript is required: say what to change", status: 400 };
  }
  if (byteLength(transcript) > MAX_TRANSCRIPT_BYTES) {
    return { error: `transcript is over ${MAX_TRANSCRIPT_BYTES} bytes`, status: 413 };
  }

  const rawTypedText = form.get("typedText");
  const typedText = typeof rawTypedText === "string" && rawTypedText.trim().length > 0 ? rawTypedText.trim() : null;
  if (typedText !== null && byteLength(typedText) > MAX_TRANSCRIPT_BYTES) {
    return { error: `typedText is over ${MAX_TRANSCRIPT_BYTES} bytes`, status: 413 };
  }

  const shortFields: Record<string, string | null> = {};
  for (const name of ["bundleVersion", "bundleScope", "clientReportId", "device", "iosVersion", "appVersion", "appBuild"]) {
    const value = shortField(form, name);
    if (value !== null && typeof value === "object") {
      return value;
    }
    shortFields[name] = value;
  }
  if (shortFields.bundleScope !== null && !BUNDLE_SCOPES.has(shortFields.bundleScope)) {
    return { error: "bundleScope must be user or base", status: 400 };
  }

  // The shell sends transcriptWords; transcriptTimings is the older name from the contract.
  const wordsPartName = form.has("transcriptWords") ? "transcriptWords" : "transcriptTimings";
  const transcriptWords = await jsonArrayPart(form, wordsPartName, MAX_TIMINGS_BYTES, false);
  if (transcriptWords !== null && typeof transcriptWords === "object") {
    return transcriptWords;
  }
  const strokes = await jsonArrayPart(form, "strokes", MAX_STROKES_BYTES, false);
  if (strokes !== null && typeof strokes === "object") {
    return strokes;
  }
  const screenshot = await imagePart(form, "screenshot");
  if (screenshot !== null && "error" in screenshot) {
    return screenshot;
  }
  const drawing = await imagePart(form, "drawing");
  if (drawing !== null && "error" in drawing) {
    return drawing;
  }

  return {
    sidekickId,
    kind,
    transcript,
    transcriptWords,
    typedText,
    clientReportId: shortFields.clientReportId,
    bundleVersion: shortFields.bundleVersion,
    bundleScope: shortFields.bundleScope,
    device: shortFields.device,
    iosVersion: shortFields.iosVersion,
    appVersion: shortFields.appVersion,
    appBuild: shortFields.appBuild,
    strokes,
    screenshot,
    drawing,
  };
}

// A retry of a report the phone already sent (same clientReportId, same user) gets the stored row.
async function existingReportForClientId(db: D1Database, userId: string, clientReportId: string | null): Promise<ReportRow | null> {
  if (clientReportId === null) {
    return null;
  }
  const statement = boundStatement(db, "SELECT * FROM repair_reports WHERE user_id = ? AND client_report_id = ?", userId, clientReportId);
  return statement.first<ReportRow>();
}

type AssetPut = { key: string; put: Promise<unknown> };

// Only the parts the phone sent are stored; a voice-only report has none.
function putAssets(bucket: R2Bucket, reportId: string, report: CleanReport): { screenshotKey: string | null; drawingKey: string | null; strokesKey: string | null; puts: Promise<unknown>[] } {
  const puts: Promise<unknown>[] = [];
  function putImage(baseName: string, file: UploadedFile | null): string | null {
    if (file === null) {
      return null;
    }
    const key = assetKey(reportId, imageFileName(baseName, file));
    puts.push(bucket.put(key, file.bytes, { httpMetadata: { contentType: file.contentType } }));
    return key;
  }
  const screenshotKey = putImage("screenshot", report.screenshot);
  const drawingKey = putImage("drawing", report.drawing);
  let strokesKey: string | null = null;
  if (report.strokes !== null) {
    strokesKey = assetKey(reportId, "strokes.json");
    puts.push(bucket.put(strokesKey, report.strokes, { httpMetadata: { contentType: "application/json" } }));
  }
  return { screenshotKey, drawingKey, strokesKey, puts };
}

function imageFileName(baseName: string, file: UploadedFile): string {
  return file.contentType === "image/jpeg" ? `${baseName}.jpg` : `${baseName}.png`;
}

// The row is written as `received` first, then the three objects, then the row becomes
// `queued` with its keys. A crash between leaves a visible `received` row that no runner claims.
async function handleCreateReport(c: RepairContext) {
  const declaredLength = Number(c.req.header("Content-Length") ?? "0");
  if (declaredLength > MAX_REPORT_BYTES) {
    return c.json({ error: `report is over ${MAX_REPORT_BYTES} bytes` }, 413);
  }
  let form: FormData;
  try {
    form = await c.req.formData();
  } catch {
    return c.json({ error: "multipart form expected" }, 400);
  }
  const report = await cleanReport(form);
  if (isRejection(report)) {
    return c.json({ error: report.error }, report.status);
  }
  const userId = c.get("userId");
  if (!(await isAssigned(c.env.DB, userId, report.sidekickId))) {
    return c.json({ error: "no such sidekick" }, 404);
  }
  const alreadyStored = await existingReportForClientId(c.env.DB, userId, report.clientReportId);
  if (alreadyStored !== null) {
    return c.json({ id: alreadyStored.id, status: alreadyStored.status }, 200);
  }

  const reportId = crypto.randomUUID();
  const createdAt = nowIso();
  const insertRow = boundStatement(
    c.env.DB,
    `INSERT INTO repair_reports (id, user_id, sidekick_id, bundle_version, bundle_scope, kind, transcript, transcript_words,
       typed_text, client_report_id, device, ios_version, app_version, app_build, status, attempts, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'received', 0, ?, ?)`,
    reportId,
    userId,
    report.sidekickId,
    report.bundleVersion,
    report.bundleScope,
    report.kind,
    report.transcript,
    report.transcriptWords,
    report.typedText,
    report.clientReportId,
    report.device,
    report.iosVersion,
    report.appVersion,
    report.appBuild,
    createdAt,
    createdAt,
  );
  try {
    await insertRow.run();
  } catch {
    // Two retries of the same clientReportId raced; the first one's row wins.
    const raced = await existingReportForClientId(c.env.DB, userId, report.clientReportId);
    if (raced !== null) {
      return c.json({ id: raced.id, status: raced.status }, 200);
    }
    return c.json({ error: "could not store the report, try again" }, 500);
  }

  const { screenshotKey, drawingKey, strokesKey, puts } = putAssets(c.env.BUNDLES, reportId, report);
  try {
    await Promise.all(puts);
  } catch {
    return c.json({ error: "could not store the report, try again" }, 500);
  }

  const queuedAt = nowIso();
  const markQueued = boundStatement(
    c.env.DB,
    "UPDATE repair_reports SET status = 'queued', screenshot_key = ?, drawing_key = ?, strokes_key = ?, updated_at = ? WHERE id = ?",
    screenshotKey,
    drawingKey,
    strokesKey,
    queuedAt,
    reportId,
  );
  const founderEvent = insertEventStatement(c.env.DB, reportId, "founder", "request_received", queuedAt);
  await c.env.DB.batch([markQueued, founderEvent]);

  return c.json({ id: reportId, status: "queued" }, 201);
}

// A repair asked for through jess (jess router, founder 2026-10-21: "make the Reminders list
// colours bigger" goes straight to the repair agent, no confirmation). The same row a voice-only
// report from the repair layer makes: no screenshot, drawing or strokes, the person's own words
// as the transcript, queued at once with the founder's request_received event. Returns the report
// id, or null when the Sidekick is not assigned to the user.
export type VoiceRepairRequest = {
  userId: string;
  sidekickId: string;
  kind: "bug" | "change" | "feature";
  transcript: string;
  bundleVersion: string | null;
  device: string | null;
  iosVersion: string | null;
  appVersion: string | null;
  appBuild: string | null;
};

export async function queueVoiceRepair(db: D1Database, request: VoiceRepairRequest): Promise<string | null> {
  if (!(await isAssigned(db, request.userId, request.sidekickId))) {
    return null;
  }
  const reportId = crypto.randomUUID();
  const createdAt = nowIso();
  const transcript = request.transcript.slice(0, MAX_TRANSCRIPT_BYTES);
  const insertRow = boundStatement(
    db,
    `INSERT INTO repair_reports (id, user_id, sidekick_id, bundle_version, bundle_scope, kind, transcript, transcript_words,
       typed_text, client_report_id, device, ios_version, app_version, app_build, status, attempts, created_at, updated_at)
     VALUES (?, ?, ?, ?, NULL, ?, ?, NULL, NULL, NULL, ?, ?, ?, ?, 'queued', 0, ?, ?)`,
    reportId,
    request.userId,
    request.sidekickId,
    request.bundleVersion,
    request.kind,
    transcript,
    request.device,
    request.iosVersion,
    request.appVersion,
    request.appBuild,
    createdAt,
    createdAt,
  );
  const founderEvent = insertEventStatement(db, reportId, "founder", "request_received", createdAt);
  await db.batch([insertRow, founderEvent]);
  return reportId;
}

// ---- GET /repairs/:id, /repairs/:id/assets/:name --------------------------------------------

async function handleGetReport(c: RepairContext) {
  const reportId = c.req.param("id") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  const row = await readReport(c.env.DB, reportId);
  if (row === null || !ownsReport(c, row)) {
    return c.json({ error: "no such report" }, 404);
  }
  return c.json(reportFromRow(row));
}

type BundlePointer = { version: string; scriptHashes: string[] };

// The reporter's current copy of the Sidekick (repair-copies layout): their own pointer under
// sidekicks/<id>/users/<uid>/ if they have one, else the shared page. This is what the agent edits.
async function currentBundleFile(bucket: R2Bucket, sidekickId: string, userId: string, fileName: string) {
  const userPrefix = `sidekicks/${sidekickId}/users/${userId}`;
  const basePrefix = `sidekicks/${sidekickId}`;
  const candidates: Array<{ prefix: string; scope: "user" | "base" }> = [
    { prefix: userPrefix, scope: "user" },
    { prefix: basePrefix, scope: "base" },
  ];
  for (const candidate of candidates) {
    const pointerObject = await bucket.get(`${candidate.prefix}/current.json`);
    if (pointerObject === null) {
      continue;
    }
    const pointer = (await pointerObject.json()) as BundlePointer;
    const fileObject = await bucket.get(`${candidate.prefix}/${pointer.version}/${fileName}`);
    if (fileObject === null) {
      return null;
    }
    return { object: fileObject, version: pointer.version, scope: candidate.scope };
  }
  return null;
}

async function serveBundleAsset(c: RepairContext, row: ReportRow, assetName: string) {
  const bundleAsset = BUNDLE_ASSETS[assetName];
  const found = await currentBundleFile(c.env.BUNDLES, row.sidekick_id, row.user_id, bundleAsset.fileName);
  if (found === null) {
    return c.json({ error: "no deployed sidekick for this report" }, 404);
  }
  return new Response(found.object.body, {
    headers: {
      "Content-Type": bundleAsset.contentType,
      "Cache-Control": "no-store",
      "X-Midas-Bundle-Version": found.version,
      "X-Midas-Bundle-Scope": found.scope,
    },
  });
}

// `name` is screenshot, drawing or strokes (with or without its file extension), or bundle.html /
// bundle.manifest.json / bundle.tools.js for the reporter's current Sidekick copy.
async function handleGetAsset(c: RepairContext) {
  const reportId = c.req.param("id") ?? "";
  const rawName = c.req.param("name") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "no such asset" }, 404);
  }
  const baseName = rawName.replace(/\.[a-z]+$/, "");
  const column = ASSET_COLUMNS[baseName];
  const isBundleAsset = rawName in BUNDLE_ASSETS;
  if (column === undefined && !isBundleAsset) {
    return c.json({ error: "no such asset" }, 404);
  }
  const row = await readReport(c.env.DB, reportId);
  if (row === null || !ownsReport(c, row)) {
    return c.json({ error: "no such report" }, 404);
  }
  if (isBundleAsset || column === undefined) {
    return serveBundleAsset(c, row, rawName);
  }
  const key = row[column];
  if (key === null) {
    return c.json({ error: "no such asset" }, 404);
  }
  const object = await c.env.BUNDLES.get(key);
  if (object === null) {
    return c.json({ error: "asset missing" }, 500);
  }
  const contentType = object.httpMetadata?.contentType ?? "application/octet-stream";
  return new Response(object.body, { headers: { "Content-Type": contentType, "Cache-Control": "no-store" } });
}

// ---- runner: the reporter's records --------------------------------------------------------

// The most record text a records reply carries, in bytes of the stored JSON. A Worker holds the
// rows, the parsed values and the reply at once, so a copy with more than this is refused (413)
// rather than read or checked in part.
export const MAX_REPORT_RECORD_BYTES = 4 * 1024 * 1024;

// The latest op per key for one user and Sidekick: one GROUP BY over that user's ops (the
// ops_by_user_seq index finds them; no per-key subquery, so no index on key is needed). SQLite
// takes the bare columns key, value and deleted from the row holding MAX(seq), so a key whose
// latest op is a delete has deleted = 1 here and is left out by the outer WHERE.
const LATEST_OPS_SQL = [
  "SELECT key, value, deleted, MAX(seq) AS seq FROM ops",
  "WHERE user_id = ? AND sidekick_id = ? GROUP BY key",
].join(" ");

// How many live records and how many bytes of record text, so the size is known before any is read.
export const REPORT_RECORDS_SIZE_SQL = `SELECT COUNT(*) AS count, COALESCE(SUM(LENGTH(CAST(value AS BLOB))), 0) AS bytes FROM (${LATEST_OPS_SQL}) WHERE deleted = 0`;
export const REPORT_RECORDS_SQL = `SELECT key, value FROM (${LATEST_OPS_SQL}) WHERE deleted = 0 ORDER BY key`;

type RecordRow = { key: string; value: string };
type RecordsSizeRow = { count: number; bytes: number };

// GET /repairs/:id/records (runner only; founder, 2026-10-19): the reporter's latest non-deleted
// record per key for that report's Sidekick, so the runner can check them against a repaired
// copy's new schema before publishing (unified data plan, section 6). Only that user, only that
// Sidekick; nothing is written. {"records":[{key,value}]} sorted by key; 413 when the records are
// larger than MAX_REPORT_RECORD_BYTES (the runner then does not publish).
async function handleListReportRecords(c: RepairContext) {
  const reportId = c.req.param("id") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  const row = await readReport(c.env.DB, reportId);
  if (row === null) {
    return c.json({ error: "no such report" }, 404);
  }
  const sizeStatement = boundStatement(c.env.DB, REPORT_RECORDS_SIZE_SQL, row.user_id, row.sidekick_id);
  const size = await sizeStatement.first<RecordsSizeRow>();
  const totalBytes = Number(size?.bytes ?? 0);
  if (totalBytes > MAX_REPORT_RECORD_BYTES) {
    return c.json({ error: "records too large", count: Number(size?.count ?? 0), bytes: totalBytes, limit: MAX_REPORT_RECORD_BYTES }, 413);
  }
  const recordsStatement = boundStatement(c.env.DB, REPORT_RECORDS_SQL, row.user_id, row.sidekick_id);
  const queryResult = await recordsStatement.all<RecordRow>();
  const records = [];
  for (const recordRow of queryResult.results) {
    records.push({ key: recordRow.key, value: JSON.parse(recordRow.value) });
  }
  return c.json({ userId: row.user_id, sidekickId: row.sidekick_id, records });
}

// ---- runner: claim and status --------------------------------------------------------------

async function readJsonBody(c: RepairContext): Promise<Record<string, unknown>> {
  try {
    const body = await c.req.json();
    return typeof body === "object" && body !== null ? (body as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

// A running job whose lease ran out MAX_ATTEMPTS times is failed, and the founder hears of it.
async function failExhaustedJobs(db: D1Database, now: number) {
  const failedAt = nowIso();
  const failExhausted = boundStatement(
    db,
    `UPDATE repair_reports SET status = 'failed', fail_reason = ?, updated_at = ?
     WHERE status = 'running' AND lease_until < ? AND attempts >= ?
     RETURNING id`,
    `lease expired ${MAX_ATTEMPTS} times`,
    failedAt,
    now,
    MAX_ATTEMPTS,
  );
  const failed = await failExhausted.all<{ id: string }>();
  const events: D1PreparedStatement[] = [];
  for (const row of failed.results) {
    events.push(insertEventStatement(db, row.id, "founder", "failed", failedAt));
  }
  if (events.length > 0) {
    await db.batch(events);
  }
}

// POST /repairs/jobs/claim {"runnerId"?: string} -> 200 report, or 204 when nothing waits.
// One statement picks and leases the oldest claimable job, so two runners never get the same one.
async function handleClaim(c: RepairContext) {
  const body = await readJsonBody(c);
  const runnerId = typeof body.runnerId === "string" && body.runnerId.length <= MAX_SHORT_FIELD_LENGTH ? body.runnerId : "runner";
  const now = Date.now();
  await failExhaustedJobs(c.env.DB, now);

  const claim = boundStatement(
    c.env.DB,
    `UPDATE repair_reports
     SET status = 'running', runner_id = ?, lease_until = ?, attempts = attempts + 1, updated_at = ?
     WHERE id = (
       SELECT id FROM repair_reports
       WHERE status = 'queued' OR (status = 'running' AND lease_until < ?)
       ORDER BY created_at LIMIT 1
     )
     RETURNING *`,
    runnerId,
    now + LEASE_MS,
    nowIso(),
    now,
  );
  const claimed = await claim.all<ReportRow>();
  if (claimed.results.length === 0) {
    return c.body(null, 204);
  }
  return c.json(reportFromRow(claimed.results[0]));
}

// Which status may follow which. `running -> running` renews the lease.
const ALLOWED_TRANSITIONS: Record<string, Set<string>> = {
  running: new Set(["running", "fix_ready", "failed"]),
  fix_ready: new Set(["deployed_live", "failed"]),
};

// POST /repairs/:id/status {"status": ..., "reason"?: string}
async function handleSetStatus(c: RepairContext) {
  const reportId = c.req.param("id") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  const body = await readJsonBody(c);
  const nextStatus = typeof body.status === "string" ? body.status : "";
  const reason = typeof body.reason === "string" ? body.reason.slice(0, 1000) : null;
  const row = await readReport(c.env.DB, reportId);
  if (row === null) {
    return c.json({ error: "no such report" }, 404);
  }
  const allowed = ALLOWED_TRANSITIONS[row.status];
  if (allowed === undefined || !allowed.has(nextStatus)) {
    return c.json({ error: `cannot go from ${row.status} to ${nextStatus || "nothing"}` }, 409);
  }
  if (nextStatus === "failed" && (reason === null || reason.length === 0)) {
    return c.json({ error: "failed needs a reason" }, 400);
  }

  const changedAt = nowIso();
  const leaseUntil = nextStatus === "running" ? Date.now() + LEASE_MS : row.lease_until;
  const statements: D1PreparedStatement[] = [
    boundStatement(
      c.env.DB,
      "UPDATE repair_reports SET status = ?, fail_reason = ?, lease_until = ?, updated_at = ? WHERE id = ?",
      nextStatus,
      nextStatus === "failed" ? reason : row.fail_reason,
      leaseUntil,
      changedAt,
      reportId,
    ),
  ];
  if (nextStatus === "fix_ready" || nextStatus === "failed") {
    statements.push(insertEventStatement(c.env.DB, reportId, "founder", nextStatus, changedAt));
  }
  if (nextStatus === "deployed_live") {
    statements.push(insertEventStatement(c.env.DB, reportId, "user", "deployed_live", changedAt));
  }
  await c.env.DB.batch(statements);
  return c.json({ id: reportId, status: nextStatus });
}

// ---- events (founder, via the runner) and notices (user, via the shell) --------------------

const EVENT_SELECT = `SELECT e.id, e.report_id, e.kind, e.created_at, r.sidekick_id, r.user_id, r.status, r.transcript, r.fail_reason
  FROM repair_events e JOIN repair_reports r ON r.id = e.report_id
  WHERE e.audience = ? AND e.delivered_at IS NULL`;

// GET /repairs/events -> founder events not yet shown on the Mac, oldest first.
async function handleListEvents(c: RepairContext) {
  const statement = boundStatement(c.env.DB, `${EVENT_SELECT} ORDER BY e.created_at`, "founder");
  const result = await statement.all<EventRow>();
  const events = [];
  for (const row of result.results) {
    events.push({
      id: row.id,
      reportId: row.report_id,
      kind: row.kind,
      sidekickId: row.sidekick_id,
      userId: row.user_id,
      status: row.status,
      transcript: row.transcript,
      failReason: row.fail_reason,
      createdAt: row.created_at,
    });
  }
  return c.json({ events });
}

async function markDelivered(db: D1Database, eventId: string, audience: "founder" | "user", userId: string | null): Promise<boolean> {
  const ownerClause = userId === null ? "" : " AND report_id IN (SELECT id FROM repair_reports WHERE user_id = ?)";
  const params: unknown[] = [nowIso(), eventId, audience];
  if (userId !== null) {
    params.push(userId);
  }
  const statement = boundStatement(
    db,
    `UPDATE repair_events SET delivered_at = ? WHERE id = ? AND audience = ? AND delivered_at IS NULL${ownerClause}`,
    ...params,
  );
  const result = await statement.run();
  return result.meta.changes === 1;
}

// POST /repairs/events/:id/delivered
async function handleEventDelivered(c: RepairContext) {
  const eventId = c.req.param("id") ?? "";
  const delivered = await markDelivered(c.env.DB, eventId, "founder", null);
  if (!delivered) {
    return c.json({ error: "no such event" }, 404);
  }
  return c.body(null, 204);
}

// GET /repairs/notices -> the signed-in user's unseen "done" notices. The shell shows each once
// and posts /seen.
async function handleListNotices(c: RepairContext) {
  const statement = boundStatement(c.env.DB, `${EVENT_SELECT} AND r.user_id = ? ORDER BY e.created_at`, "user", c.get("userId"));
  const result = await statement.all<EventRow>();
  const notices = [];
  for (const row of result.results) {
    notices.push({ id: row.id, reportId: row.report_id, sidekickId: row.sidekick_id, text: USER_DONE_TEXT, createdAt: row.created_at });
  }
  return c.json({ notices });
}

// POST /repairs/notices/:id/seen
async function handleNoticeSeen(c: RepairContext) {
  const eventId = c.req.param("id") ?? "";
  const seen = await markDelivered(c.env.DB, eventId, "user", c.get("userId"));
  if (!seen) {
    return c.json({ error: "no such notice" }, 404);
  }
  return c.body(null, 204);
}

export const repairRoutes = new Hono<RepairEnv>();
// Fixed paths before /:id so "jobs", "events" and "notices" are never read as report ids.
repairRoutes.post("/jobs/claim", requireRunner, handleClaim);
repairRoutes.get("/events", requireRunner, handleListEvents);
repairRoutes.post("/events/:id/delivered", requireRunner, handleEventDelivered);
repairRoutes.get("/notices", requireSession, handleListNotices);
repairRoutes.post("/notices/:id/seen", requireSession, handleNoticeSeen);
repairRoutes.post("/", requireSession, handleCreateReport);
repairRoutes.get("/:id", requireRunnerOrSession, handleGetReport);
repairRoutes.get("/:id/assets/:name", requireRunnerOrSession, handleGetAsset);
repairRoutes.get("/:id/records", requireRunner, handleListReportRecords);
repairRoutes.post("/:id/status", requireRunner, handleSetStatus);
