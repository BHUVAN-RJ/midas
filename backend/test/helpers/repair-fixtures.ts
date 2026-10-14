import { createHash } from "node:crypto";
import { expect } from "vitest";
import app from "../../src/index";
import { makeFakeR2 } from "./fake-r2";
import { makeMigratedD1 } from "./migrated-d1";

// Shared set-up for the repair tests: a migrated D1, an in-memory R2, signed-in users with
// assignments, multipart report forms and the runner's headers.

export const RUNNER_TOKEN = "runner-secret-for-tests";
export const PNG_HEADER = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
export const STROKES = JSON.stringify([[[10, 20, 0], [30, 40, 50]], [[100, 100, 900]]]);

export type RepairTestEnv = {
  DB: ReturnType<typeof makeMigratedD1>;
  BUNDLES: ReturnType<typeof makeFakeR2>;
  REPAIR_RUNNER_TOKEN?: string;
};

export function makeRepairEnv(seedObjects: Record<string, string> = {}): RepairTestEnv {
  return { DB: makeMigratedD1(), BUNDLES: makeFakeR2(seedObjects), REPAIR_RUNNER_TOKEN: RUNNER_TOKEN };
}

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

export function addSignedInUser(env: RepairTestEnv, userId: string, assignedSidekicks: string[]): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  for (const sidekickId of assignedSidekicks) {
    env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, 'now')", userId, sidekickId);
  }
  return token;
}

// Every part the shell may send. A field set to null is left out of the form.
export type ReportParts = Partial<Record<string, string | Blob | null>>;

export function makeReportForm(parts: ReportParts = {}): FormData {
  const defaults: Record<string, string | Blob> = {
    sidekickId: "reminders",
    kind: "bug",
    transcript: "reminders fire when I have not set them",
    strokes: STROKES,
    screenshot: new Blob([PNG_HEADER], { type: "image/png" }),
    drawing: new Blob([PNG_HEADER], { type: "image/png" }),
    bundleVersion: "v7",
    device: "iPhone 16 Pro",
    appVersion: "0.1.0",
  };
  const merged: Record<string, string | Blob | null> = { ...defaults, ...parts };
  const form = new FormData();
  for (const [name, value] of Object.entries(merged)) {
    if (value === null) {
      continue;
    }
    if (typeof value === "string") {
      form.set(name, value);
    } else {
      form.set(name, value, `${name}.png`);
    }
  }
  return form;
}

export function sessionHeaders(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}

export function runnerHeaders(token = RUNNER_TOKEN): Record<string, string> {
  return { Authorization: `Runner ${token}`, "Content-Type": "application/json" };
}

export async function postReport(env: RepairTestEnv, token: string, form: FormData) {
  return app.request("/repairs", { method: "POST", headers: sessionHeaders(token), body: form }, env);
}

export async function createReport(env: RepairTestEnv, token: string, parts: ReportParts = {}): Promise<string> {
  const response = await postReport(env, token, makeReportForm(parts));
  expect(response.status).toBe(201);
  const reply = (await response.json()) as { id: string; status: string };
  expect(reply.status).toBe("queued");
  return reply.id;
}

export async function claimJob(env: RepairTestEnv, runnerId = "mac-mini") {
  return app.request("/repairs/jobs/claim", { method: "POST", headers: runnerHeaders(), body: JSON.stringify({ runnerId }) }, env);
}

export async function setStatus(env: RepairTestEnv, reportId: string, status: string, reason?: string) {
  const body = JSON.stringify({ status, reason });
  return app.request(`/repairs/${reportId}/status`, { method: "POST", headers: runnerHeaders(), body }, env);
}

export async function getReport(env: RepairTestEnv, reportId: string, headers: Record<string, string>) {
  return app.request(`/repairs/${reportId}`, { headers }, env);
}

export async function getAsset(env: RepairTestEnv, reportId: string, name: string, headers: Record<string, string>) {
  return app.request(`/repairs/${reportId}/assets/${name}`, { headers }, env);
}

export function reportRow(env: RepairTestEnv, reportId: string): Record<string, unknown> {
  const rows = env.DB.query("SELECT * FROM repair_reports WHERE id = ?", reportId);
  expect(rows.length).toBe(1);
  return rows[0];
}

export function eventKinds(env: RepairTestEnv, audience: string): string[] {
  const rows = env.DB.query("SELECT kind FROM repair_events WHERE audience = ? ORDER BY created_at", audience);
  const kinds: string[] = [];
  for (const row of rows) {
    kinds.push(String(row.kind));
  }
  return kinds;
}

export function reportCount(env: RepairTestEnv): number {
  return Number(env.DB.query("SELECT count(*) AS n FROM repair_reports")[0].n);
}
