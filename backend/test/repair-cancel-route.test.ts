import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { CANCELLED_REASON } from "../src/repair-cancel";
import { RepairCancelled, createBackendClient } from "../../runner/lib/backend.mjs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// An X on the repair tag cancels the repair (founder, 2026-11-22; docs/PRODUCT.md "An X on the
// repair tag cancels the repair", commit f2e047f). POST /repairs/:clientReportId/cancel, the
// person's own reports only, idempotent: a report on the server is marked cancelled (status failed,
// fail_reason "cancelled by the person", cancelled_at), never claimed by the runner, never
// published, and a running job learns it from its next status post (409 cancelled: true) and from
// GET /repairs/:id. A repair that already finished is left as it is.

const RUNNER_TOKEN = "runner-secret-for-cancel-tests";

function makeEnv() {
  return { DB: makeMigratedD1(), BUNDLES: makeFakeR2(), REPAIR_RUNNER_TOKEN: RUNNER_TOKEN };
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'hydration', 'now')", userId);
  return token;
}

type Seed = { status: string; sortStatus?: string | null; lane?: string | null; resultKind?: string | null; createdAt?: string };

let seedCount = 0;

// A report as the upload and the sort leave it; returns the server id
function seedReport(env: TestEnv, userId: string, clientReportId: string, seed: Seed): string {
  seedCount += 1;
  const reportId = `00000000-0000-4000-8000-${String(seedCount).padStart(12, "0")}`;
  const createdAt = seed.createdAt ?? `2026-11-22T10:00:${String(seedCount % 60).padStart(2, "0")}.000Z`;
  env.DB.execute(
    `INSERT INTO repair_reports (id, user_id, sidekick_id, kind, transcript, client_report_id, status, sort_status, lane, result_kind, attempts, created_at, updated_at)
     VALUES (?, ?, 'hydration', 'change', 'make it blue', ?, ?, ?, ?, ?, 0, ?, ?)`,
    reportId,
    userId,
    clientReportId,
    seed.status,
    seed.sortStatus ?? null,
    seed.lane ?? null,
    seed.resultKind ?? null,
    createdAt,
    createdAt,
  );
  return reportId;
}

function row(env: TestEnv, reportId: string): Record<string, unknown> {
  return env.DB.query("SELECT * FROM repair_reports WHERE id = ?", reportId)[0];
}

async function cancel(env: TestEnv, token: string, clientReportId: string) {
  const response = await app.request(`/repairs/${clientReportId}/cancel`, { method: "POST", headers: { Authorization: `Bearer ${token}` } }, env);
  const body = (await response.json()) as Record<string, unknown>;
  return { response, body };
}

function runnerHeaders(): Record<string, string> {
  return { Authorization: `Runner ${RUNNER_TOKEN}`, "Content-Type": "application/json" };
}

async function claim(env: TestEnv) {
  const response = await app.request("/repairs/jobs/claim", { method: "POST", headers: runnerHeaders(), body: "{}" }, env);
  if (response.status === 204) {
    return null;
  }
  return (await response.json()) as Record<string, unknown>;
}

async function postStatus(env: TestEnv, reportId: string, body: Record<string, unknown>) {
  const response = await app.request(`/repairs/${reportId}/status`, { method: "POST", headers: runnerHeaders(), body: JSON.stringify(body) }, env);
  return { response, body: (await response.json()) as Record<string, unknown> };
}

function eventCount(env: TestEnv, reportId: string): number {
  return env.DB.query("SELECT id FROM repair_events WHERE report_id = ?", reportId).length;
}

describe("POST /repairs/:clientReportId/cancel", () => {
  it("marks a queued report cancelled, and the runner never claims it", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    const reportId = seedReport(env, "user-a", "phone-1", { status: "queued", sortStatus: "sorted", lane: "code" });
    const { response, body } = await cancel(env, token, "phone-1");
    expect(response.status).toBe(200);
    expect(body).toEqual({ id: reportId, status: "failed", cancelled: true });
    const stored = row(env, reportId);
    expect(stored.status).toBe("failed");
    expect(stored.fail_reason).toBe(CANCELLED_REASON);
    expect(typeof stored.cancelled_at).toBe("string");
    expect(stored.result_kind).toBeNull();
    expect(await claim(env)).toBeNull();
    expect(eventCount(env, reportId)).toBe(0);
  });

  it("is idempotent: a second cancel answers the same and changes nothing", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    const reportId = seedReport(env, "user-a", "phone-1", { status: "queued", sortStatus: "sorted", lane: "code" });
    await cancel(env, token, "phone-1");
    const firstCancelledAt = row(env, reportId).cancelled_at;
    const again = await cancel(env, token, "phone-1");
    expect(again.response.status).toBe(200);
    expect(again.body).toEqual({ id: reportId, status: "failed", cancelled: true });
    expect(row(env, reportId).cancelled_at).toBe(firstCancelledAt);
  });

  it("only the owner may cancel: someone else's report answers like none", async () => {
    const env = makeEnv();
    addSignedInUser(env, "user-a");
    const otherToken = addSignedInUser(env, "user-b");
    const reportId = seedReport(env, "user-a", "phone-1", { status: "queued", sortStatus: "sorted", lane: "code" });
    const { response } = await cancel(env, otherToken, "phone-1");
    expect(response.status).toBe(404);
    expect(row(env, reportId).status).toBe("queued");
    expect(row(env, reportId).cancelled_at).toBeNull();
    const unsigned = await app.request("/repairs/phone-1/cancel", { method: "POST" }, env);
    expect(unsigned.status).toBe(401);
  });

  it("answers 404 for a report the server never got and 400 for a bad id", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    expect((await cancel(env, token, "never-sent")).response.status).toBe(404);
    const bad = await app.request("/repairs/bad%20id!/cancel", { method: "POST", headers: { Authorization: `Bearer ${token}` } }, env);
    expect(bad.status).toBe(400);
  });

  it("leaves a finished repair as it is: a fix already live stays", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    const liveId = seedReport(env, "user-a", "phone-live", { status: "deployed_live", sortStatus: "sorted", lane: "code", resultKind: "fixed" });
    const failedId = seedReport(env, "user-a", "phone-failed", { status: "failed", sortStatus: "sorted", lane: "code", resultKind: "couldnt_fix" });
    const live = await cancel(env, token, "phone-live");
    expect(live.response.status).toBe(200);
    expect(live.body).toEqual({ id: liveId, status: "deployed_live", cancelled: false });
    expect(row(env, liveId).cancelled_at).toBeNull();
    const failed = await cancel(env, token, "phone-failed");
    expect(failed.body).toEqual({ id: failedId, status: "failed", cancelled: false });
    expect(row(env, failedId).result_kind).toBe("couldnt_fix");
  });

  it("drops a question card still waiting, so a late answer is refused", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    const reportId = seedReport(env, "user-a", "phone-q", { status: "received", sortStatus: "asking", lane: "ask_back" });
    env.DB.execute("UPDATE repair_reports SET sort_question = ?, sort_asked_at = ? WHERE id = ?", JSON.stringify({ text: "What should it be?", options: [{ id: "bigger", label: "Bigger" }] }), new Date().toISOString(), reportId);
    const { body } = await cancel(env, token, "phone-q");
    expect(body.cancelled).toBe(true);
    expect(row(env, reportId).sort_status).toBe("dropped");
    const answer = await app.request(`/repairs/${reportId}/answer`, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ optionId: "bigger" }) }, env);
    expect(answer.status).toBe(410);
    expect(row(env, reportId).status).toBe("failed");
  });

  it("stops a sort still running from placing the report", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    const reportId = seedReport(env, "user-a", "phone-s", { status: "received", sortStatus: "sorting" });
    await cancel(env, token, "phone-s");
    expect(row(env, reportId).sort_status).toBe("dropped");
    // The lane route's stuck-sort rescue would put a sorting report in code; a dropped one stays
    const lane = await app.request("/repairs/lanes/phone-s", { headers: { Authorization: `Bearer ${token}` } }, env);
    expect(lane.status).toBe(200);
    expect(row(env, reportId).status).toBe("failed");
    expect(await claim(env)).toBeNull();
  });
});

describe("a running job learns of the cancel", () => {
  it("every status post, the heartbeat included, is refused with cancelled: true", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    const reportId = seedReport(env, "user-a", "phone-r", { status: "queued", sortStatus: "sorted", lane: "code" });
    const job = await claim(env);
    expect(job?.id).toBe(reportId);
    expect(job?.cancelled).toBe(false);
    const { body } = await cancel(env, token, "phone-r");
    expect(body).toEqual({ id: reportId, status: "failed", cancelled: true });
    for (const status of ["running", "fix_ready", "deployed_live", "no_change"]) {
      const posted = await postStatus(env, reportId, { status, summary: "done" });
      expect(posted.response.status, status).toBe(409);
      expect(posted.body.cancelled, status).toBe(true);
    }
    const failed = await postStatus(env, reportId, { status: "failed", reason: "agent exited" });
    expect(failed.response.status).toBe(409);
    expect(row(env, reportId).result_kind).toBeNull();
    expect(eventCount(env, reportId)).toBe(0);
    const seen = await app.request(`/repairs/${reportId}`, { headers: runnerHeaders() }, env);
    const report = (await seen.json()) as Record<string, unknown>;
    expect(report.cancelled).toBe(true);
    expect(typeof report.cancelledAt).toBe("string");
  });

  it("the publish routes refuse a cancelled report, the roll back still goes through", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    const reportId = seedReport(env, "user-a", "phone-p", { status: "queued", sortStatus: "sorted", lane: "code" });
    await claim(env);
    await cancel(env, token, "phone-p");
    for (const step of ["files", "pointer"]) {
      const response = await app.request(`/repairs/${reportId}/publish/${step}`, { method: "POST", headers: runnerHeaders(), body: JSON.stringify({ version: "20261122T100000000Z-0a1b2c3d", files: [], pointer: {} }) }, env);
      expect(response.status, step).toBe(409);
      const body = (await response.json()) as Record<string, unknown>;
      expect(body.cancelled, step).toBe(true);
    }
    const rollBack = await app.request(`/repairs/${reportId}/publish/rollback`, { method: "POST", headers: runnerHeaders(), body: JSON.stringify({ version: "20261122T100000000Z-0a1b2c3d", reason: "cancelled" }) }, env);
    const rollBackBody = (await rollBack.json()) as Record<string, unknown>;
    expect(rollBackBody.cancelled).toBeUndefined();
  });

  it("the runner's own client turns the refusal into RepairCancelled and sees it on the report", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "user-a");
    const reportId = seedReport(env, "user-a", "phone-c", { status: "queued", sortStatus: "sorted", lane: "code" });
    function workerFetch(input: string, init?: RequestInit) {
      return app.request(input, init, env);
    }
    const client = createBackendClient({ baseUrl: "http://worker.test", token: RUNNER_TOKEN, fetchImplementation: workerFetch });
    const job = await client.claimJob();
    expect(job?.id).toBe(reportId);
    expect(await client.isCancelled(reportId)).toBe(false);
    await client.postStatus(reportId, "running");
    await cancel(env, token, "phone-c");
    expect(await client.isCancelled(reportId)).toBe(true);
    await expect(client.postStatus(reportId, "running")).rejects.toBeInstanceOf(RepairCancelled);
    await expect(client.flipPointer(reportId, { version: "20261122T100000000Z-0a1b2c3d", pointer: {} })).rejects.toBeInstanceOf(RepairCancelled);
    // Any other refusal stays a plain error
    await expect(client.postStatus("00000000-0000-4000-8000-999999999999", "running")).rejects.not.toBeInstanceOf(RepairCancelled);
  });
});
