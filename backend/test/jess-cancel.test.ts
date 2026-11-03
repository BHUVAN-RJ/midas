// A jess task deleted on the Workdesk before it finished does not finish later (founder,
// 2026-11-02, build 22 feedback; src/jess-cancel.ts). POST /voice/jess/cancel marks the request id,
// the grow request and the Edit it filed so none of them runs; only the person's own rows change.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { cancelJessWork } from "../src/jess-cancel";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const NOW = "2026-11-02T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");
const REMINDERS_MANIFEST = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8");
const REQUEST_ID = "5a1d3c0e-7f2b-4c11-9e8d-1b2c3d4e5f60";
const OTHER_REPORT = "11111111-2222-4333-8444-555555555555";

type Db = ReturnType<typeof makeMigratedD1>;
type Row = Record<string, unknown>;

function makeBucket() {
  const objectsByKey: Record<string, string> = {
    "sidekicks/reminders/current.json": JSON.stringify({ version: "b5", scriptHashes: [], contentHash: "hash-b5", baseVersion: null, tools: "tools.js" }),
    "sidekicks/reminders/b5/manifest.json": REMINDERS_MANIFEST,
  };
  async function getObject(key: string) {
    if (!(key in objectsByKey)) {
      return null;
    }
    const objectText = objectsByKey[key];
    return { body: new Response(objectText).body, json: async () => JSON.parse(objectText) };
  }
  return { get: getObject };
}

function makeEnv(grow = false) {
  const env: Record<string, unknown> = { DB: makeMigratedD1(), BUNDLES: makeBucket(), OPENROUTER_API_KEY: "sk-or-test" };
  if (grow) {
    env.JESS_GROW = "true";
  }
  return env as { DB: Db };
}

function signIn(db: Db, userId: string): string {
  const token = `token-${userId}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  db.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  db.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", tokenHash, userId, Date.now() + 3_600_000);
  db.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'reminders', 'now')", userId);
  return token;
}

function executionContext() {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  const context = { waitUntil, passThroughOnException, props: {} };
  return { context: context as unknown as ExecutionContext, pending };
}

async function ask(env: object, token: string, transcript: string) {
  const { context, pending } = executionContext();
  const body = { transcript, now: NOW, timeZone: ZONE, locale: "en-US", requestId: REQUEST_ID, sidekicks: [{ id: "reminders", context: { lists: [], items: [] } }] };
  const init: RequestInit = { method: "POST", headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(body) };
  const response = await app.request("/voice/jess", init, env, context);
  await Promise.all(pending);
  return response;
}

async function cancel(env: object, token: string, body: unknown) {
  const { context, pending } = executionContext();
  const init: RequestInit = { method: "POST", headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(body) };
  const response = await app.request("/voice/jess/cancel", init, env, context);
  await Promise.all(pending);
  return response;
}

function toolCallAnswer(name: string, args: Record<string, unknown>) {
  const message = { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name, arguments: JSON.stringify(args) } }] };
  return new Response(JSON.stringify({ choices: [{ message }] }), { status: 200, headers: { "content-type": "application/json" } });
}

function answerRepair() {
  return toolCallAnswer("midas__repair_request", { sidekick: "reminders", kind: "change", request: "make the circles bigger" });
}

function answerGrow() {
  return toolCallAnswer("midas__grow_sidekick", { sidekick: "reminders", feature: "flag a reminder" });
}

function rows(db: Db, sql: string, ...params: Array<string | number | null>): Row[] {
  return db.query(sql, ...params);
}

function seedReport(db: Db, reportId: string, userId: string, status: string) {
  db.execute(
    "INSERT INTO repair_reports (id, user_id, sidekick_id, kind, transcript, status, created_at, updated_at) VALUES (?, ?, 'reminders', 'change', 'bigger circles', ?, 'now', 'now')",
    reportId,
    userId,
    status,
  );
}

let fetchMock: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  fetchMock = vi.spyOn(globalThis, "fetch");
});

afterEach(() => {
  fetchMock.mockRestore();
});

describe("a request deleted before it was sent", () => {
  it("never runs when it is sent later: no model call, answered not done", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerRepair);
    const cancelResponse = await cancel(env, token, { requestId: REQUEST_ID });
    expect(cancelResponse.status).toBe(200);
    const answer = await (await ask(env, token, "make the circles bigger")).json();
    expect(answer).toEqual({ status: "not-done", reason: "deleted", transcript: "" });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(rows(env.DB, "SELECT id FROM repair_reports")).toHaveLength(0);
  });
});

describe("a request deleted while the model answers", () => {
  it("files no Edit and keeps the deleted answer", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    async function deleteThenAnswer() {
      await cancelJessWork(env.DB as unknown as D1Database, "u1", { requestId: REQUEST_ID, reportId: null, pendingId: null }, Date.now());
      return answerRepair();
    }
    fetchMock.mockImplementation(deleteThenAnswer);
    const answer = await (await ask(env, token, "make the circles bigger")).json();
    expect(answer.status).toBe("not-done");
    expect(answer.reason).toBe("deleted");
    expect(rows(env.DB, "SELECT id FROM repair_reports")).toHaveLength(0);
    const kept = rows(env.DB, "SELECT state, reply FROM jess_requests WHERE request_id = ?", REQUEST_ID);
    expect(kept).toHaveLength(1);
    expect(JSON.parse(String(kept[0].reply)).reason).toBe("deleted");
  });
});

describe("a grow request deleted while it waits for its Edit", () => {
  it("fails the pending request, already shown, and drops the queued Edit", async () => {
    const env = makeEnv(true);
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerGrow);
    const grown = await (await ask(env, token, "add call the bank and flag it")).json();
    expect(grown.status).toBe("grow");
    const reportBefore = rows(env.DB, "SELECT status FROM repair_reports WHERE id = ?", grown.reportId);
    expect(["received", "queued"]).toContain(reportBefore[0].status);

    const response = await cancel(env, token, { reportId: grown.reportId, pendingId: grown.pendingId });
    expect(response.status).toBe(200);

    const pending = rows(env.DB, "SELECT status, fail_reason, shown_at FROM jess_pending_requests WHERE id = ?", grown.pendingId);
    expect(pending[0].status).toBe("failed");
    expect(pending[0].fail_reason).toBe("deleted");
    expect(pending[0].shown_at).not.toBeNull();
    const report = rows(env.DB, "SELECT status, fail_reason FROM repair_reports WHERE id = ?", grown.reportId);
    expect(report[0]).toEqual({ status: "failed", fail_reason: "deleted by the person" });

    const listResponse = await app.request("/voice/jess/pending", { headers: { Authorization: `Bearer ${token}` } }, env, executionContext().context);
    const listed = await listResponse.json();
    expect(listed.pending).toEqual([]);
  });
});

describe("what a cancel leaves alone", () => {
  it("an Edit the runner already started", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    seedReport(env.DB, OTHER_REPORT, "u1", "running");
    await cancel(env, token, { reportId: OTHER_REPORT });
    expect(rows(env.DB, "SELECT status FROM repair_reports WHERE id = ?", OTHER_REPORT)[0].status).toBe("running");
  });

  it("another person's Edit", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    signIn(env.DB, "u2");
    seedReport(env.DB, OTHER_REPORT, "u2", "queued");
    const response = await cancel(env, token, { reportId: OTHER_REPORT });
    expect(response.status).toBe(200);
    expect(rows(env.DB, "SELECT status FROM repair_reports WHERE id = ?", OTHER_REPORT)[0].status).toBe("queued");
  });

  it("a request that already has its answer", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const keptReply = JSON.stringify({ status: "done", sidekickId: "reminders" });
    env.DB.execute(
      "INSERT INTO jess_requests (user_id, request_id, state, reply, log_id, sends, claimed_at, created_at, updated_at) VALUES ('u1', ?, 'answered', ?, NULL, 1, 'now', 'now', 'now')",
      REQUEST_ID,
      keptReply,
    );
    await cancel(env, token, { requestId: REQUEST_ID });
    expect(rows(env.DB, "SELECT reply FROM jess_requests WHERE request_id = ?", REQUEST_ID)[0].reply).toBe(keptReply);
  });
});

describe("POST /voice/jess/cancel input", () => {
  it("needs at least one id", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    expect((await cancel(env, token, {})).status).toBe(400);
  });

  it("refuses a malformed id", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    expect((await cancel(env, token, { requestId: "not-a-uuid" })).status).toBe(400);
    expect((await cancel(env, token, { reportId: "../x" })).status).toBe(400);
    expect((await cancel(env, token, { pendingId: 42 })).status).toBe(400);
  });

  it("needs a signed-in person", async () => {
    const env = makeEnv();
    const response = await app.request("/voice/jess/cancel", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ requestId: REQUEST_ID }) }, env, executionContext().context);
    expect(response.status).toBe(401);
  });
});
