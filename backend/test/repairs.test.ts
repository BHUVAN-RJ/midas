import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { LEASE_MS, MAX_ATTEMPTS, MAX_IMAGE_BYTES, USER_DONE_TEXT } from "../src/repairs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Repair intake (founder, 2026-10-13; docs/briefs/repair-intake.md). Done when: a report lands
// as one D1 row plus its R2 objects with the same id; another user cannot read it; claim gives
// each job to one runner; an expired lease comes back; a user cannot reach runner endpoints;
// an empty transcript is refused; the user's "done" notice is shown once.

const RUNNER_TOKEN = "runner-secret-for-tests";

function makeEnv(withRunnerToken = true) {
  const env: { DB: ReturnType<typeof makeMigratedD1>; BUNDLES: ReturnType<typeof makeFakeR2>; REPAIR_RUNNER_TOKEN?: string } = {
    DB: makeMigratedD1(),
    BUNDLES: makeFakeR2(),
  };
  if (withRunnerToken) {
    env.REPAIR_RUNNER_TOKEN = RUNNER_TOKEN;
  }
  return env;
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string, assignedSidekicks: string[]): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  for (const sidekickId of assignedSidekicks) {
    env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, 'now')", userId, sidekickId);
  }
  return token;
}

const PNG_HEADER = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const STROKES = JSON.stringify([[[10, 20, 0], [30, 40, 50]], [[100, 100, 900]]]);

type ReportFields = Partial<{
  sidekickId: string;
  kind: string;
  transcript: string | null;
  strokes: string | null;
  screenshot: Blob | null;
  drawing: Blob | null;
  bundleVersion: string;
}>;

function makeForm(fields: ReportFields = {}): FormData {
  const form = new FormData();
  form.set("sidekickId", fields.sidekickId ?? "reminders");
  form.set("kind", fields.kind ?? "bug");
  if (fields.transcript !== null) {
    form.set("transcript", fields.transcript ?? "reminders fire when I have not set them");
  }
  if (fields.strokes !== null) {
    form.set("strokes", fields.strokes ?? STROKES);
  }
  if (fields.screenshot !== null) {
    form.set("screenshot", fields.screenshot ?? new Blob([PNG_HEADER], { type: "image/png" }), "screenshot.png");
  }
  if (fields.drawing !== null) {
    form.set("drawing", fields.drawing ?? new Blob([PNG_HEADER], { type: "image/png" }), "drawing.png");
  }
  form.set("bundleVersion", fields.bundleVersion ?? "v7");
  form.set("device", "iPhone 16 Pro");
  form.set("appVersion", "0.1.0 (2)");
  return form;
}

function sessionHeaders(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}

function runnerHeaders(token = RUNNER_TOKEN): Record<string, string> {
  return { Authorization: `Runner ${token}`, "Content-Type": "application/json" };
}

async function postReport(env: TestEnv, token: string | null, form: FormData) {
  const headers = token === null ? {} : sessionHeaders(token);
  return app.request("/repairs", { method: "POST", headers, body: form }, env);
}

async function createReport(env: TestEnv, token: string, fields: ReportFields = {}): Promise<string> {
  const response = await postReport(env, token, makeForm(fields));
  expect(response.status).toBe(201);
  const reply = (await response.json()) as { id: string; status: string };
  expect(reply.status).toBe("queued");
  return reply.id;
}

async function claim(env: TestEnv, headers: Record<string, string> = runnerHeaders(), runnerId = "mac-mini") {
  return app.request("/repairs/jobs/claim", { method: "POST", headers, body: JSON.stringify({ runnerId }) }, env);
}

async function setStatus(env: TestEnv, reportId: string, status: string, reason?: string) {
  const body = JSON.stringify({ status, reason });
  return app.request(`/repairs/${reportId}/status`, { method: "POST", headers: runnerHeaders(), body }, env);
}

function reportRow(env: TestEnv, reportId: string): Record<string, unknown> {
  const rows = env.DB.query("SELECT * FROM repair_reports WHERE id = ?", reportId);
  expect(rows.length).toBe(1);
  return rows[0];
}

function eventKinds(env: TestEnv, audience: string): string[] {
  const rows = env.DB.query("SELECT kind FROM repair_events WHERE audience = ? ORDER BY created_at", audience);
  const kinds: string[] = [];
  for (const row of rows) {
    kinds.push(String(row.kind));
  }
  return kinds;
}

describe("POST /repairs", () => {
  it("stores one row and three R2 objects under the same id, queued, with a founder event", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const reportId = await createReport(env, token);

    const row = reportRow(env, reportId);
    expect(row.user_id).toBe("amogh");
    expect(row.sidekick_id).toBe("reminders");
    expect(row.status).toBe("queued");
    expect(row.kind).toBe("bug");
    expect(row.transcript).toBe("reminders fire when I have not set them");
    expect(row.bundle_version).toBe("v7");
    expect(env.BUNDLES.keys()).toEqual([
      `repairs/${reportId}/drawing.png`,
      `repairs/${reportId}/screenshot.png`,
      `repairs/${reportId}/strokes.json`,
    ]);
    expect(row.screenshot_key).toBe(`repairs/${reportId}/screenshot.png`);
    const strokesObject = await env.BUNDLES.get(`repairs/${reportId}/strokes.json`);
    expect(await strokesObject?.text()).toBe(STROKES);
    expect(eventKinds(env, "founder")).toEqual(["request_received"]);
    expect(env.DB.query("SELECT count(*) AS n FROM ops")[0].n).toBe(0);
  });

  it("refuses an empty transcript and stores nothing", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const emptyResponse = await postReport(env, token, makeForm({ transcript: "   " }));
    const missingResponse = await postReport(env, token, makeForm({ transcript: null }));

    expect(emptyResponse.status).toBe(400);
    expect(missingResponse.status).toBe(400);
    expect(env.DB.query("SELECT count(*) AS n FROM repair_reports")[0].n).toBe(0);
    expect(env.BUNDLES.keys()).toEqual([]);
  });

  it("refuses a Sidekick not assigned to the user like one that does not exist", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const response = await postReport(env, token, makeForm({ sidekickId: "split" }));

    expect(response.status).toBe(404);
    expect(env.DB.query("SELECT count(*) AS n FROM repair_reports")[0].n).toBe(0);
    expect(env.BUNDLES.keys()).toEqual([]);
  });

  it("refuses a screenshot over the size limit", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const tooBig = new Blob([new Uint8Array(MAX_IMAGE_BYTES + 1)], { type: "image/png" });

    const response = await postReport(env, token, makeForm({ screenshot: tooBig }));

    expect(response.status).toBe(413);
    expect(env.BUNDLES.keys()).toEqual([]);
  });

  it("refuses strokes that are not a JSON array", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);

    const response = await postReport(env, token, makeForm({ strokes: "{\"not\": \"an array\"}" }));

    expect(response.status).toBe(400);
  });

  it("needs a user session: no token and the runner token are both refused", async () => {
    const env = makeEnv();
    addSignedInUser(env, "amogh", ["reminders"]);

    const noToken = await postReport(env, null, makeForm());
    const runnerToken = await app.request("/repairs", { method: "POST", headers: { Authorization: `Runner ${RUNNER_TOKEN}` }, body: makeForm() }, env);

    expect(noToken.status).toBe(401);
    expect(runnerToken.status).toBe(401);
    expect(env.DB.query("SELECT count(*) AS n FROM repair_reports")[0].n).toBe(0);
  });
});

describe("reading a report", () => {
  it("is open to the reporter and the runner, closed to another user", async () => {
    const env = makeEnv();
    const amoghToken = addSignedInUser(env, "amogh", ["reminders"]);
    const otherToken = addSignedInUser(env, "other", ["reminders"]);
    const reportId = await createReport(env, amoghToken);

    const ownReport = await app.request(`/repairs/${reportId}`, { headers: sessionHeaders(amoghToken) }, env);
    const otherReport = await app.request(`/repairs/${reportId}`, { headers: sessionHeaders(otherToken) }, env);
    const otherAsset = await app.request(`/repairs/${reportId}/assets/screenshot.png`, { headers: sessionHeaders(otherToken) }, env);
    const runnerAsset = await app.request(`/repairs/${reportId}/assets/strokes.json`, { headers: runnerHeaders() }, env);
    const anonymous = await app.request(`/repairs/${reportId}`, {}, env);

    expect(ownReport.status).toBe(200);
    expect(((await ownReport.json()) as { id: string }).id).toBe(reportId);
    expect(otherReport.status).toBe(404);
    expect(otherAsset.status).toBe(404);
    expect(runnerAsset.status).toBe(200);
    expect(await runnerAsset.text()).toBe(STROKES);
    expect(anonymous.status).toBe(401);
  });
});

describe("POST /repairs/jobs/claim", () => {
  it("gives one job to one runner; the second runner gets nothing", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);

    const [first, second] = await Promise.all([claim(env, runnerHeaders(), "mac-a"), claim(env, runnerHeaders(), "mac-b")]);

    const statuses = [first.status, second.status].sort();
    expect(statuses).toEqual([200, 204]);
    const winner = first.status === 200 ? first : second;
    const job = (await winner.json()) as { id: string; status: string; transcript: string; assets: Record<string, string> };
    expect(job.id).toBe(reportId);
    expect(job.status).toBe("running");
    expect(job.transcript).toBe("reminders fire when I have not set them");
    expect(job.assets.screenshot).toBe("screenshot.png");
    const row = reportRow(env, reportId);
    expect(row.attempts).toBe(1);
    expect(Number(row.lease_until)).toBeGreaterThan(Date.now() + LEASE_MS - 5000);
  });

  it("claims the oldest queued job first and never a received one", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const firstId = await createReport(env, token, { transcript: "first" });
    const secondId = await createReport(env, token, { transcript: "second" });
    env.DB.execute("UPDATE repair_reports SET created_at = '2026-01-01T00:00:00.000Z' WHERE id = ?", firstId);
    env.DB.execute("UPDATE repair_reports SET created_at = '2026-01-02T00:00:00.000Z' WHERE id = ?", secondId);
    env.DB.execute("INSERT INTO repair_reports (id, user_id, sidekick_id, kind, transcript, status, attempts, created_at, updated_at) VALUES ('00000000-0000-0000-0000-000000000000', 'amogh', 'reminders', 'bug', 'half uploaded', 'received', 0, '2025-01-01T00:00:00.000Z', '2025-01-01T00:00:00.000Z')");

    const first = await claim(env);
    const second = await claim(env);
    const third = await claim(env);

    expect(((await first.json()) as { id: string }).id).toBe(firstId);
    expect(((await second.json()) as { id: string }).id).toBe(secondId);
    expect(third.status).toBe(204);
  });

  it("hands an expired lease to the next claim, and fails the job after the last attempt", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      const liveLease = await claim(env);
      expect(liveLease.status).toBe(200);
      expect(reportRow(env, reportId).attempts).toBe(attempt);
      const whileLeased = await claim(env);
      expect(whileLeased.status).toBe(204);
      env.DB.execute("UPDATE repair_reports SET lease_until = ? WHERE id = ?", Date.now() - 1000, reportId);
    }

    const afterLastExpiry = await claim(env);

    expect(afterLastExpiry.status).toBe(204);
    const row = reportRow(env, reportId);
    expect(row.status).toBe("failed");
    expect(row.fail_reason).toBe(`lease expired ${MAX_ATTEMPTS} times`);
    expect(eventKinds(env, "founder")).toEqual(["request_received", "failed"]);
  });

  it("refuses a user session, a wrong token, and any token when none is configured", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    await createReport(env, token);
    const noSecretEnv = makeEnv(false);

    const userSession = await claim(env, { ...sessionHeaders(token), "Content-Type": "application/json" });
    const wrongToken = await claim(env, runnerHeaders("not-the-secret"));
    const noSecret = await claim(noSecretEnv);

    expect(userSession.status).toBe(401);
    expect(wrongToken.status).toBe(401);
    expect(noSecret.status).toBe(401);
    expect(env.DB.query("SELECT status FROM repair_reports")[0].status).toBe("queued");
  });
});

describe("POST /repairs/:id/status", () => {
  it("follows the chain running -> fix_ready -> deployed_live with the right events", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);

    const beforeRunning = await setStatus(env, reportId, "deployed_live");
    await claim(env);
    const renewed = await setStatus(env, reportId, "running");
    const fixReady = await setStatus(env, reportId, "fix_ready");
    const backToRunning = await setStatus(env, reportId, "running");
    const deployed = await setStatus(env, reportId, "deployed_live");
    const again = await setStatus(env, reportId, "deployed_live");

    expect(beforeRunning.status).toBe(409);
    expect(renewed.status).toBe(200);
    expect(fixReady.status).toBe(200);
    expect(backToRunning.status).toBe(409);
    expect(deployed.status).toBe(200);
    expect(again.status).toBe(409);
    expect(reportRow(env, reportId).status).toBe("deployed_live");
    expect(eventKinds(env, "founder")).toEqual(["request_received", "fix_ready"]);
    expect(eventKinds(env, "user")).toEqual(["deployed_live"]);
  });

  it("needs a reason to fail, keeps it, and tells the founder", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);
    await claim(env);

    const noReason = await setStatus(env, reportId, "failed");
    const failed = await setStatus(env, reportId, "failed", "Sidekick tests failed");
    const unknown = await setStatus(env, "11111111-1111-1111-1111-111111111111", "failed", "x");

    expect(noReason.status).toBe(400);
    expect(failed.status).toBe(200);
    expect(unknown.status).toBe(404);
    expect(reportRow(env, reportId).fail_reason).toBe("Sidekick tests failed");
    expect(eventKinds(env, "founder")).toEqual(["request_received", "failed"]);
  });

  it("refuses a user session", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);
    await claim(env);

    const headers = { ...sessionHeaders(token), "Content-Type": "application/json" };
    const response = await app.request(`/repairs/${reportId}/status`, { method: "POST", headers, body: JSON.stringify({ status: "fix_ready" }) }, env);

    expect(response.status).toBe(401);
    expect(reportRow(env, reportId).status).toBe("running");
  });
});

describe("founder events and user notices", () => {
  it("lists founder events for the runner until delivered", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh", ["reminders"]);
    const reportId = await createReport(env, token);

    const listed = await app.request("/repairs/events", { headers: runnerHeaders() }, env);
    const reply = (await listed.json()) as { events: Array<{ id: string; kind: string; reportId: string; transcript: string }> };
    expect(reply.events.length).toBe(1);
    expect(reply.events[0].kind).toBe("request_received");
    expect(reply.events[0].reportId).toBe(reportId);
    expect(reply.events[0].transcript).toBe("reminders fire when I have not set them");

    const delivered = await app.request(`/repairs/events/${reply.events[0].id}/delivered`, { method: "POST", headers: runnerHeaders() }, env);
    const twice = await app.request(`/repairs/events/${reply.events[0].id}/delivered`, { method: "POST", headers: runnerHeaders() }, env);
    const afterwards = await app.request("/repairs/events", { headers: runnerHeaders() }, env);
    const asUser = await app.request("/repairs/events", { headers: sessionHeaders(token) }, env);

    expect(delivered.status).toBe(204);
    expect(twice.status).toBe(404);
    expect(((await afterwards.json()) as { events: unknown[] }).events).toEqual([]);
    expect(asUser.status).toBe(401);
  });

  it("shows the reporter one done notice, once, and nothing to anyone else", async () => {
    const env = makeEnv();
    const amoghToken = addSignedInUser(env, "amogh", ["reminders"]);
    const otherToken = addSignedInUser(env, "other", ["reminders"]);
    const reportId = await createReport(env, amoghToken);
    await claim(env);
    await setStatus(env, reportId, "fix_ready");

    const beforeLive = await app.request("/repairs/notices", { headers: sessionHeaders(amoghToken) }, env);
    expect(((await beforeLive.json()) as { notices: unknown[] }).notices).toEqual([]);

    await setStatus(env, reportId, "deployed_live");
    const amoghNotices = await app.request("/repairs/notices", { headers: sessionHeaders(amoghToken) }, env);
    const otherNotices = await app.request("/repairs/notices", { headers: sessionHeaders(otherToken) }, env);
    const amoghReply = (await amoghNotices.json()) as { notices: Array<{ id: string; reportId: string; sidekickId: string; text: string }> };

    expect(amoghReply.notices.length).toBe(1);
    expect(amoghReply.notices[0].reportId).toBe(reportId);
    expect(amoghReply.notices[0].sidekickId).toBe("reminders");
    expect(amoghReply.notices[0].text).toBe(USER_DONE_TEXT);
    expect(((await otherNotices.json()) as { notices: unknown[] }).notices).toEqual([]);

    const noticeId = amoghReply.notices[0].id;
    const otherSeen = await app.request(`/repairs/notices/${noticeId}/seen`, { method: "POST", headers: sessionHeaders(otherToken) }, env);
    const seen = await app.request(`/repairs/notices/${noticeId}/seen`, { method: "POST", headers: sessionHeaders(amoghToken) }, env);
    const afterSeen = await app.request("/repairs/notices", { headers: sessionHeaders(amoghToken) }, env);

    expect(otherSeen.status).toBe(404);
    expect(seen.status).toBe(204);
    expect(((await afterSeen.json()) as { notices: unknown[] }).notices).toEqual([]);
  });
});
