import { Hono } from "hono";
import type { Context } from "hono";
import { requireRunner, sweepBeforeClaim } from "./repairs";
import type { RepairEnv } from "./repairs";

// Publish first (founder, 2026-11-13; docs/briefs/repair-lanes.md W7). The runner publishes a
// repaired copy through the Worker instead of one `wrangler r2` process per file (about 1.5-3 s
// each, 25 s median per repair): the upload runs while the fast checks run, the pointer flips the
// moment they pass, and a slow check that fails after publishing puts the pointer back at once.
// Every route takes the runner token and acts only on the report's own user and Sidekick: the
// runner can never write the base or another person's copy through them.
//
// POST /repairs/:id/publish/files { version, files: [{ name, body }] }
//   Stores the files of a new version under sidekicks/<sid>/users/<uid>/<version>/. Names:
//   index.html, manifest.json, tools.js, tests/<file>. Nothing points at them yet, so the person
//   still gets their current version. A version that was ever pointed at is immutable (409).
// POST /repairs/:id/publish/pointer { version, pointer: { scriptHashes, contentHash, tools? } }
//   Checks the version's page, manifest and tools.js are stored and hash to contentHash, writes
//   its version.json (with the pointer it replaces, for the roll back) and then the person's
//   current.json. -> { version, previousVersion }
// POST /repairs/:id/publish/rollback { version, reason }
//   When the person's pointer still names `version`: puts back the pointer it replaced (or removes
//   it when there was none, so the person gets the base again). -> { rolledBack, version }
//   409 when the copy has moved on to another version since: a later repair is never undone.
// GET /repairs/jobs/wait?seconds=<1..25>
//   Long poll for the runner (instead of a 30 s poll): answers { ready: true } as soon as a job
//   can be claimed, or { ready: false } after `seconds`. The runner then claims as before.

type PublishContext = Context<RepairEnv>;

type StoredPointer = {
  version: string;
  scriptHashes: string[];
  contentHash: string;
  baseVersion: string | null;
  tools?: string;
};

const REPORT_ID_PATTERN = /^[0-9a-f-]{36}$/;
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const SIDEKICK_ID_PATTERN = /^[a-z0-9-]{1,40}$/;
// bundle-tools.mjs bundleVersion: <yyyymmddThhmmssmmmZ>-<8 hex>
export const VERSION_PATTERN = /^\d{8}T\d{9}Z-[0-9a-f]{8}$/;
// bundle-tools.mjs TEST_FILE_NAME_PATTERN, under tests/
const TEST_FILE_PATTERN = /^tests\/[A-Za-z0-9][A-Za-z0-9_.-]{0,120}$/;
const SCRIPT_HASH_PATTERN = /^'sha256-[A-Za-z0-9+/=]{44}'$/;
const CONTENT_HASH_PATTERN = /^[0-9a-f]{64}$/;
export const TOOLS_FILE = "tools.js";
export const MAX_PUBLISH_BYTES = 8 * 1024 * 1024;
const MAX_FILES = 60;
// The report must still belong to the runner's job: claimed and not finished
const PUBLISHABLE_STATUSES = new Set(["running", "fix_ready"]);
// A roll back also follows a publish the runner already marked live
const ROLLBACK_STATUSES = new Set(["running", "fix_ready", "deployed_live"]);
export const MAX_WAIT_SECONDS = 25;
export const WAIT_STEP_MS = 1000;

const CONTENT_TYPES: Record<string, string> = {
  "index.html": "text/html; charset=utf-8",
  "manifest.json": "application/json",
  [TOOLS_FILE]: "text/javascript; charset=utf-8",
};
const TESTS_INDEX = "tests/index.json";

type ReportTarget = { id: string; userId: string; sidekickId: string; status: string };

function userPrefix(target: ReportTarget): string {
  return `sidekicks/${target.sidekickId}/users/${target.userId}`;
}

function basePrefix(target: ReportTarget): string {
  return `sidekicks/${target.sidekickId}`;
}

async function readJsonBody(c: PublishContext): Promise<Record<string, unknown>> {
  try {
    const body = await c.req.json();
    return typeof body === "object" && body !== null ? (body as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

async function readJsonObject(bucket: R2Bucket, key: string): Promise<Record<string, unknown> | null> {
  const stored = await bucket.get(key);
  if (stored === null) {
    return null;
  }
  try {
    return (await stored.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function readText(bucket: R2Bucket, key: string): Promise<string | null> {
  const stored = await bucket.get(key);
  if (stored === null) {
    return null;
  }
  return stored.text();
}

// The report, as the route may act on it, or the reply that refuses it
async function reportTarget(c: PublishContext, allowedStatuses: Set<string>): Promise<ReportTarget | Response> {
  const reportId = c.req.param("id") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  const statement = c.env.DB.prepare("SELECT id, user_id, sidekick_id, status FROM repair_reports WHERE id = ?");
  const boundStatement = statement.bind(reportId);
  const row = await boundStatement.first<{ id: string; user_id: string; sidekick_id: string; status: string }>();
  if (row === null) {
    return c.json({ error: "no such report" }, 404);
  }
  // Ids from the table are checked again: nothing here may leave sidekicks/<sid>/users/<uid>/
  if (!USER_ID_PATTERN.test(row.user_id) || !SIDEKICK_ID_PATTERN.test(row.sidekick_id)) {
    return c.json({ error: "report names no valid user copy" }, 409);
  }
  if (!allowedStatuses.has(row.status)) {
    return c.json({ error: `report is ${row.status}` }, 409);
  }
  return { id: row.id, userId: row.user_id, sidekickId: row.sidekick_id, status: row.status };
}

function isResponse(value: unknown): value is Response {
  return value instanceof Response;
}

// The content type a file is stored with, decided here from its name, never by the caller
export function contentTypeFor(name: string): string | null {
  if (Object.hasOwn(CONTENT_TYPES, name)) {
    return CONTENT_TYPES[name];
  }
  if (name === TESTS_INDEX) {
    return "application/json";
  }
  if (TEST_FILE_PATTERN.test(name)) {
    return "text/plain; charset=utf-8";
  }
  return null;
}

type CleanFile = { name: string; body: string; contentType: string };

// The files of an upload, or why they are refused
export function cleanFiles(rawFiles: unknown): CleanFile[] | string {
  if (!Array.isArray(rawFiles) || rawFiles.length === 0) {
    return "files must be a non-empty list";
  }
  if (rawFiles.length > MAX_FILES) {
    return `at most ${MAX_FILES} files`;
  }
  const files: CleanFile[] = [];
  const seenNames = new Set<string>();
  let totalBytes = 0;
  for (const rawFile of rawFiles) {
    const name = typeof rawFile?.name === "string" ? rawFile.name : "";
    const body = typeof rawFile?.body === "string" ? rawFile.body : null;
    const contentType = contentTypeFor(name);
    if (contentType === null) {
      return `file name not allowed: ${name.slice(0, 80)}`;
    }
    if (body === null) {
      return `${name} has no body`;
    }
    if (seenNames.has(name)) {
      return `${name} is listed twice`;
    }
    seenNames.add(name);
    totalBytes += new TextEncoder().encode(body).length;
    files.push({ name, body, contentType });
  }
  if (totalBytes > MAX_PUBLISH_BYTES) {
    return `the files are over ${MAX_PUBLISH_BYTES} bytes`;
  }
  return files;
}

async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hexParts: string[] = [];
  for (const byte of new Uint8Array(digest)) {
    hexParts.push(byte.toString(16).padStart(2, "0"));
  }
  return hexParts.join("");
}

// bundle-tools.mjs bundleContentHash, the same bytes in the same order: each part's length (in
// UTF-16 units, JavaScript's string length) before the part, tools.js only when there is one
export async function bundleContentHash(html: string, manifestText: string, toolsText: string | null): Promise<string> {
  const parts = [`${html.length}:`, html, `${manifestText.length}:`, manifestText];
  if (toolsText !== null) {
    parts.push(`tools.js ${toolsText.length}:`, toolsText);
  }
  return sha256Hex(parts.join(""));
}

function versionFromBody(body: Record<string, unknown>): string | null {
  const version = body.version;
  if (typeof version !== "string" || !VERSION_PATTERN.test(version)) {
    return null;
  }
  return version;
}

async function handlePublishFiles(c: PublishContext) {
  const target = await reportTarget(c, PUBLISHABLE_STATUSES);
  if (isResponse(target)) {
    return target;
  }
  const body = await readJsonBody(c);
  const version = versionFromBody(body);
  if (version === null) {
    return c.json({ error: "bad version" }, 400);
  }
  const files = cleanFiles(body.files);
  if (typeof files === "string") {
    return c.json({ error: files }, 400);
  }
  const prefix = `${userPrefix(target)}/${version}`;
  // A version that was ever pointed at has a version.json: its files never change again
  const alreadyPublished = await c.env.BUNDLES.head(`${prefix}/version.json`);
  if (alreadyPublished !== null) {
    return c.json({ error: `version ${version} is already published; versions are immutable` }, 409);
  }
  const puts: Promise<unknown>[] = [];
  for (const file of files) {
    const put = c.env.BUNDLES.put(`${prefix}/${file.name}`, file.body, { httpMetadata: { contentType: file.contentType } });
    puts.push(put);
  }
  await Promise.all(puts);
  const storedNames = files.map(function fileName(file) {
    return file.name;
  });
  return c.json({ version, stored: storedNames });
}

type CleanPointer = { scriptHashes: string[]; contentHash: string; tools: boolean };

function cleanPointer(rawPointer: unknown): CleanPointer | string {
  if (typeof rawPointer !== "object" || rawPointer === null) {
    return "pointer must be an object";
  }
  const pointer = rawPointer as Record<string, unknown>;
  const scriptHashes = pointer.scriptHashes;
  if (!Array.isArray(scriptHashes) || scriptHashes.length > 64) {
    return "pointer.scriptHashes must be a list";
  }
  for (const scriptHash of scriptHashes) {
    if (typeof scriptHash !== "string" || !SCRIPT_HASH_PATTERN.test(scriptHash)) {
      return "pointer.scriptHashes holds a bad hash";
    }
  }
  if (typeof pointer.contentHash !== "string" || !CONTENT_HASH_PATTERN.test(pointer.contentHash)) {
    return "pointer.contentHash must be a sha256 hex";
  }
  const tools = pointer.tools === undefined || pointer.tools === null ? false : pointer.tools === TOOLS_FILE;
  if (pointer.tools !== undefined && pointer.tools !== null && !tools) {
    return `pointer.tools must be ${TOOLS_FILE}`;
  }
  return { scriptHashes: scriptHashes as string[], contentHash: pointer.contentHash, tools };
}

async function currentOpSeq(db: D1Database): Promise<number | null> {
  try {
    const statement = db.prepare("SELECT COALESCE(MAX(seq), 0) AS seq FROM ops");
    const row = await statement.first<{ seq: number }>();
    return row?.seq ?? null;
  } catch {
    return null;
  }
}

async function storedTestNames(bucket: R2Bucket, prefix: string): Promise<string[] | null> {
  const index = await readJsonObject(bucket, `${prefix}/${TESTS_INDEX}`);
  if (index === null || !Array.isArray(index.files)) {
    return null;
  }
  return index.files.filter(function isName(name) {
    return typeof name === "string";
  }) as string[];
}

async function handleFlipPointer(c: PublishContext) {
  const target = await reportTarget(c, PUBLISHABLE_STATUSES);
  if (isResponse(target)) {
    return target;
  }
  const body = await readJsonBody(c);
  const version = versionFromBody(body);
  if (version === null) {
    return c.json({ error: "bad version" }, 400);
  }
  const pointerInput = cleanPointer(body.pointer);
  if (typeof pointerInput === "string") {
    return c.json({ error: pointerInput }, 400);
  }
  const bucket = c.env.BUNDLES;
  const ownPrefix = userPrefix(target);
  const versionPrefix = `${ownPrefix}/${version}`;
  const [html, manifestText, toolsText] = await Promise.all([
    readText(bucket, `${versionPrefix}/index.html`),
    readText(bucket, `${versionPrefix}/manifest.json`),
    pointerInput.tools ? readText(bucket, `${versionPrefix}/${TOOLS_FILE}`) : Promise.resolve(null),
  ]);
  if (html === null || manifestText === null || (pointerInput.tools && toolsText === null)) {
    return c.json({ error: `version ${version} is not fully uploaded` }, 409);
  }
  // The read-back, done before the flip instead of after it: the person is only ever pointed at
  // exactly the files the runner checked
  const storedHash = await bundleContentHash(html, manifestText, toolsText);
  if (storedHash !== pointerInput.contentHash) {
    return c.json({ error: `stored files hash to ${storedHash}, expected ${pointerInput.contentHash}` }, 409);
  }
  const [previousPointer, basePointer, deployedAtSeq, testFiles] = await Promise.all([
    readJsonObject(bucket, `${ownPrefix}/current.json`),
    readJsonObject(bucket, `${basePrefix(target)}/current.json`),
    currentOpSeq(c.env.DB),
    storedTestNames(bucket, versionPrefix),
  ]);
  if (previousPointer !== null && previousPointer.version === version) {
    return c.json({ version, previousVersion: version, unchanged: true });
  }
  // The copy records the base it builds on: the previous copy's base, else the current base
  const previousBase = typeof previousPointer?.baseVersion === "string" ? previousPointer.baseVersion : null;
  const currentBase = typeof basePointer?.version === "string" ? basePointer.version : null;
  const baseVersion = previousBase ?? currentBase;
  const pointer: StoredPointer = { version, scriptHashes: pointerInput.scriptHashes, contentHash: pointerInput.contentHash, baseVersion };
  if (pointerInput.tools) {
    pointer.tools = TOOLS_FILE;
  }
  const versionRecord = {
    ...pointer,
    forUser: target.userId,
    deployedAt: new Date().toISOString(),
    deployedAtSeq,
    testFiles,
    reportId: target.id,
    previousPointer,
  };
  await bucket.put(`${versionPrefix}/version.json`, JSON.stringify(versionRecord), { httpMetadata: { contentType: "application/json" } });
  await bucket.put(`${ownPrefix}/current.json`, JSON.stringify(pointer), { httpMetadata: { contentType: "application/json" } });
  const previousVersion = typeof previousPointer?.version === "string" ? previousPointer.version : null;
  return c.json({ version, previousVersion });
}

async function handleRollBack(c: PublishContext) {
  const target = await reportTarget(c, ROLLBACK_STATUSES);
  if (isResponse(target)) {
    return target;
  }
  const body = await readJsonBody(c);
  const version = versionFromBody(body);
  if (version === null) {
    return c.json({ error: "bad version" }, 400);
  }
  const reason = typeof body.reason === "string" ? body.reason.slice(0, 1000) : "";
  const bucket = c.env.BUNDLES;
  const ownPrefix = userPrefix(target);
  const pointerKey = `${ownPrefix}/current.json`;
  const versionRecordKey = `${ownPrefix}/${version}/version.json`;
  const [currentPointer, versionRecord] = await Promise.all([readJsonObject(bucket, pointerKey), readJsonObject(bucket, versionRecordKey)]);
  if (versionRecord === null || versionRecord.reportId !== target.id) {
    return c.json({ error: `version ${version} was not published by this report` }, 409);
  }
  if (currentPointer === null || currentPointer.version !== version) {
    const currentVersion = typeof currentPointer?.version === "string" ? currentPointer.version : null;
    return c.json({ error: "the copy has moved on to another version", currentVersion }, 409);
  }
  const previousPointer = versionRecord.previousPointer as Record<string, unknown> | null | undefined;
  if (previousPointer === null || previousPointer === undefined) {
    // No copy before this one: without its own pointer the person gets the base again
    await bucket.delete(pointerKey);
  } else {
    await bucket.put(pointerKey, JSON.stringify(previousPointer), { httpMetadata: { contentType: "application/json" } });
  }
  const restoredVersion = typeof previousPointer?.version === "string" ? previousPointer.version : null;
  const marker = { reportId: target.id, rolledBackAt: new Date().toISOString(), restoredVersion, reason };
  await bucket.put(`${ownPrefix}/${version}/rolled-back.json`, JSON.stringify(marker), { httpMetadata: { contentType: "application/json" } });
  return c.json({ rolledBack: true, version: restoredVersion });
}

function pauseMs(milliseconds: number): Promise<void> {
  return new Promise(function waitAWhile(resolve) {
    setTimeout(resolve, milliseconds);
  });
}

async function claimableJobExists(db: D1Database, nowMs: number): Promise<boolean> {
  const statement = db.prepare("SELECT 1 AS waiting FROM repair_reports WHERE status = 'queued' OR (status = 'running' AND lease_until < ?) LIMIT 1");
  const boundStatement = statement.bind(nowMs);
  const row = await boundStatement.first();
  return row !== null;
}

export function waitSecondsFrom(rawValue: string | undefined): number {
  const parsed = Number.parseInt(rawValue ?? "", 10);
  if (Number.isNaN(parsed) || parsed < 0) {
    return MAX_WAIT_SECONDS;
  }
  return Math.min(parsed, MAX_WAIT_SECONDS);
}

async function handleWaitForJob(c: PublishContext) {
  const waitSeconds = waitSecondsFrom(c.req.query("seconds"));
  // The claim's own sweeps (expired leases, unanswered cards) ran on every 30 s poll; now here
  await sweepBeforeClaim(c, Date.now());
  const deadline = Date.now() + waitSeconds * 1000;
  while (true) {
    if (await claimableJobExists(c.env.DB, Date.now())) {
      return c.json({ ready: true });
    }
    const remainingMs = deadline - Date.now();
    if (remainingMs <= 0) {
      return c.json({ ready: false });
    }
    await pauseMs(Math.min(WAIT_STEP_MS, remainingMs));
  }
}

export const repairPublishRoutes = new Hono<RepairEnv>();

repairPublishRoutes.get("/jobs/wait", requireRunner, handleWaitForJob);
repairPublishRoutes.post("/:id/publish/files", requireRunner, handlePublishFiles);
repairPublishRoutes.post("/:id/publish/pointer", requireRunner, handleFlipPointer);
repairPublishRoutes.post("/:id/publish/rollback", requireRunner, handleRollBack);
