import type { Context } from "hono";
import MidasRecordSchema from "../../shell/sdk/record-schema.js";
import MidasSettings from "../../shell/sdk/midas-settings.js";
import type { SettingValue, SettingsCatalogue } from "../../shell/sdk/midas-settings.js";
import { mapSetting } from "./repair-setting-model";
import type { FetchLike, SettingChange } from "./repair-setting-model";
import { makeRecordChecker } from "./record-types";
import { cleanOp, insertOpsStatement } from "./sync";

// The setting lane (repair lanes W5, founder 2026-11-13): a request the sort put in lane `setting`
// is done in the Worker, without a runner job and without a publish. Haiku maps the words to
// { key, value } changes from the Sidekick's own catalogue (repair-setting-model.ts); the changes
// are written to the person's settings:self record as one op, the way a phone's write is stored,
// and the phone hears the result at once. The page redraws by itself (shell/sdk/midas-settings.js
// watches settings:self). Undo puts the old values back.
//
// The catalogue and the record types come from the version the person runs now (their own copy,
// else the base): a copy without a catalogue, or one whose types refuse the record, goes up to code.
//
//   POST /repairs (lane setting)  ->  { id, status, lane: "setting", message: "Changed", setting: { changes } }
//   POST /repairs/:id/undo        ->  { lane: "setting", message: "Undone", setting: { changes } }
//     409 when there is nothing to undo (not a setting, or already undone), 404 not the reporter's

export const CHANGED_TEXT = "Changed";
export const UNDONE_TEXT = "Undone";
const SETTINGS_KEY = MidasSettings.RECORD_KEY;
const USER_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const REPORT_ID_PATTERN = /^[0-9a-f-]{36}$/;

type SettingBindings = { DB: D1Database; BUNDLES: R2Bucket; OPENROUTER_API_KEY?: string };

export type SettingReplyChange = { key: string; label: string; value: SettingValue | null };
export type SettingReply = { changes: SettingReplyChange[] };

export type SettingOutcome =
  | { applied: true; changes: SettingChange[]; version: string; latencyMs: number; costUsd: number }
  | { applied: false; reason: string; latencyMs: number; costUsd: number };

type CopyManifest = { version: string; manifest: Record<string, unknown> };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function boundStatement(db: D1Database, sql: string, ...params: unknown[]): D1PreparedStatement {
  const prepared = db.prepare(sql);
  return prepared.bind(...params);
}

function workerFetch(url: string, init: RequestInit): Promise<Response> {
  return fetch(url, init);
}

/* ---------- What the person runs now ---------- */

// The manifest of the version the person gets: their own pointer, else the base. Null when neither.
export async function currentCopyManifest(bucket: R2Bucket, sidekickId: string, userId: string): Promise<CopyManifest | null> {
  if (!USER_ID_PATTERN.test(userId)) {
    return null;
  }
  const prefixes = [`sidekicks/${sidekickId}/users/${userId}`, `sidekicks/${sidekickId}`];
  for (const prefix of prefixes) {
    const pointerObject = await bucket.get(`${prefix}/current.json`);
    if (pointerObject === null) {
      continue;
    }
    const pointer = (await pointerObject.json()) as { version?: unknown };
    if (typeof pointer.version !== "string") {
      return null;
    }
    const manifestObject = await bucket.get(`${prefix}/${pointer.version}/manifest.json`);
    if (manifestObject === null) {
      return null;
    }
    const manifest = (await manifestObject.json()) as unknown;
    return isPlainObject(manifest) ? { version: pointer.version, manifest } : null;
  }
  return null;
}

// The person's settings:self as stored now (the newest op), or null
export async function currentSettingsRecord(db: D1Database, userId: string, sidekickId: string): Promise<Record<string, unknown> | null> {
  const statement = boundStatement(
    db,
    "SELECT value, deleted FROM ops WHERE user_id = ? AND sidekick_id = ? AND key = ? ORDER BY seq DESC LIMIT 1",
    userId,
    sidekickId,
    SETTINGS_KEY,
  );
  const row = await statement.first<{ value: string | null; deleted: number }>();
  if (row === null || row.deleted === 1 || row.value === null) {
    return null;
  }
  const value = JSON.parse(row.value) as unknown;
  return isPlainObject(value) ? value : null;
}

/* ---------- Writing ---------- */

type PreparedWrite = { statement: D1PreparedStatement } | { problem: string };

// settings:self with the changes, stamped and checked against the version's types as /sync/push
// checks a phone's write. opId is fixed per report and step, so a retry never writes twice.
async function preparedSettingsWrite(
  env: SettingBindings,
  userId: string,
  sidekickId: string,
  copy: CopyManifest,
  record: Record<string, unknown> | null,
  changes: Record<string, SettingValue | null>,
  opId: string,
  at: string,
): Promise<PreparedWrite> {
  const catalogue = copy.manifest.settings;
  const nextValue = MidasSettings.recordWith(catalogue, record, changes);
  const stamped = MidasRecordSchema.stampType(copy.manifest.types, SETTINGS_KEY, nextValue);
  const recordChecker = makeRecordChecker(env.BUNDLES, userId);
  const problem = await recordChecker.recordProblem(sidekickId, copy.version, SETTINGS_KEY, stamped);
  if (problem !== null) {
    return { problem: `record refused: ${problem}` };
  }
  const cleaned = cleanOp({ opId, sidekickId, key: SETTINGS_KEY, value: stamped, deleted: false, clientTime: at, sidekickVersion: copy.version });
  if ("error" in cleaned) {
    return { problem: `op refused: ${cleaned.error}` };
  }
  return { statement: insertOpsStatement(env.DB, userId, [cleaned], at) };
}

/* ---------- The lane ---------- */

export type SettingLaneInput = {
  reportId: string;
  userId: string;
  sidekickId: string;
  sidekickName: string;
  words: string;
  drawing: string;
};

// Maps and writes the request; { applied: false, reason } sends it up to code. The op is written
// here, before the report row says so, so a phone that hears "Changed" always finds the change.
export async function runSettingLane(env: SettingBindings, input: SettingLaneInput, fetchImpl: FetchLike = workerFetch): Promise<SettingOutcome> {
  const copy = await currentCopyManifest(env.BUNDLES, input.sidekickId, input.userId);
  if (copy === null) {
    return { applied: false, reason: "no deployed version", latencyMs: 0, costUsd: 0 };
  }
  const catalogue = copy.manifest.settings;
  if (MidasSettings.catalogueProblems(catalogue).length > 0) {
    return { applied: false, reason: "no settings catalogue in this copy", latencyMs: 0, costUsd: 0 };
  }
  const record = await currentSettingsRecord(env.DB, input.userId, input.sidekickId);
  const request = { words: input.words, sidekickName: input.sidekickName, drawing: input.drawing, catalogue: catalogue as SettingsCatalogue, record };
  const mapping = await mapSetting(request, env.OPENROUTER_API_KEY, fetchImpl);
  if (!mapping.ok) {
    return { applied: false, reason: mapping.reason, latencyMs: mapping.latencyMs, costUsd: mapping.costUsd };
  }
  const changes: Record<string, SettingValue> = {};
  for (const change of mapping.changes) {
    changes[change.key] = change.value;
  }
  const at = new Date().toISOString();
  const write = await preparedSettingsWrite(env, input.userId, input.sidekickId, copy, record, changes, `setting-${input.reportId}`, at);
  if ("problem" in write) {
    return { applied: false, reason: write.problem, latencyMs: mapping.latencyMs, costUsd: mapping.costUsd };
  }
  await write.statement.run();
  return { applied: true, changes: mapping.changes, version: copy.version, latencyMs: mapping.latencyMs, costUsd: mapping.costUsd };
}

// What the phone hears: each change by its label and new value
export function settingReply(changes: SettingChange[], useOld: boolean): SettingReply {
  const replyChanges: SettingReplyChange[] = [];
  for (const change of changes) {
    replyChanges.push({ key: change.key, label: change.label, value: useOld ? change.previous : change.value });
  }
  return { changes: replyChanges };
}

// The stored changes of a report (setting_changes), or null
export function storedChanges(changesJson: string | null): SettingChange[] | null {
  if (changesJson === null) {
    return null;
  }
  const parsed = JSON.parse(changesJson) as unknown;
  return Array.isArray(parsed) ? (parsed as SettingChange[]) : null;
}

/* ---------- POST /repairs/:id/undo ---------- */

type UndoRow = {
  id: string;
  user_id: string;
  sidekick_id: string;
  lane: string | null;
  setting_changes: string | null;
  setting_undone_at: string | null;
};

// Puts back the values the setting lane replaced (a key the person never set is removed). Only the
// reporter may undo, once; the record is read fresh, so settings changed since are kept.
export async function handleUndoSetting(c: Context) {
  const env = c.env as SettingBindings;
  const reportId = c.req.param("id") ?? "";
  if (!REPORT_ID_PATTERN.test(reportId)) {
    return c.json({ error: "bad report id" }, 400);
  }
  const rowStatement = boundStatement(env.DB, "SELECT id, user_id, sidekick_id, lane, setting_changes, setting_undone_at FROM repair_reports WHERE id = ?", reportId);
  const row = await rowStatement.first<UndoRow>();
  if (row === null || row.user_id !== c.get("userId")) {
    return c.json({ error: "no such report" }, 404);
  }
  const changes = storedChanges(row.setting_changes);
  if (row.lane !== "setting" || changes === null || row.setting_undone_at !== null) {
    return c.json({ error: "nothing to undo" }, 409);
  }
  const copy = await currentCopyManifest(env.BUNDLES, row.sidekick_id, row.user_id);
  if (copy === null) {
    return c.json({ error: "nothing to undo" }, 409);
  }
  const at = new Date().toISOString();
  // One statement takes the undo, so two taps never write twice
  const takeUndo = boundStatement(env.DB, "UPDATE repair_reports SET setting_undone_at = ?, updated_at = ? WHERE id = ? AND setting_undone_at IS NULL RETURNING id", at, at, reportId);
  const taken = await takeUndo.all();
  if (taken.results.length === 0) {
    return c.json({ error: "nothing to undo" }, 409);
  }
  const record = await currentSettingsRecord(env.DB, row.user_id, row.sidekick_id);
  const oldValues: Record<string, SettingValue | null> = {};
  for (const change of changes) {
    oldValues[change.key] = change.previous;
  }
  const write = await preparedSettingsWrite(env, row.user_id, row.sidekick_id, copy, record, oldValues, `setting-undo-${reportId}`, at);
  if ("problem" in write) {
    const giveBack = boundStatement(env.DB, "UPDATE repair_reports SET setting_undone_at = NULL WHERE id = ?", reportId);
    await giveBack.run();
    console.error(`setting undo for ${reportId} refused: ${write.problem}`);
    return c.json({ error: "could not undo" }, 409);
  }
  await write.statement.run();
  console.log(JSON.stringify({ event: "repair-setting-undone", reportId, userId: row.user_id, sidekickId: row.sidekick_id }));
  return c.json({ lane: "setting", message: UNDONE_TEXT, setting: settingReply(changes, true) });
}
