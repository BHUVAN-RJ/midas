// jess runs each request once (founder 2026-10-22, docs/PRODUCT.md "jess queue, instant
// acknowledgement and the Workdesk"): the phone keeps a spoken request queued and sends it again
// with the same requestId when the answer never reached it. The server keeps the answer it gave,
// so a request sent again is answered from jess_requests: no second model call, no second repair,
// no second grow. While the first send still runs, a second one gets 409 busy. A model that could
// not be reached leaves the id open, so the next send runs again.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { STALE_CLAIM_MS, normalizedRequestId } from "../src/jess-requests";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const NOW = "2026-10-22T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");
const REMINDERS_MANIFEST = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8");
const REQUEST_ID = "0f6c9a52-6b1e-4f43-9a0c-2d7b8e51c3aa";

type Db = ReturnType<typeof makeMigratedD1>;
type Row = Record<string, unknown>;

/* ---------- Fakes ---------- */

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

async function ask(env: object, token: string, requestId: string | undefined, transcript = "remind me to call the bank tomorrow at 9am") {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  const executionContext = { waitUntil, passThroughOnException, props: {} };
  const body: Record<string, unknown> = { transcript, now: NOW, timeZone: ZONE, locale: "en-US", sidekicks: [{ id: "reminders", context: { lists: [], items: [] } }] };
  if (requestId !== undefined) {
    body.requestId = requestId;
  }
  const init: RequestInit = { method: "POST", headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(body) };
  const response = await app.request("/voice/jess", init, env, executionContext as unknown as ExecutionContext);
  await Promise.all(pending);
  return response;
}

function toolCallAnswer(name: string, args: Record<string, unknown>) {
  const message = { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name, arguments: JSON.stringify(args) } }] };
  return new Response(JSON.stringify({ choices: [{ message }] }), { status: 200, headers: { "content-type": "application/json" } });
}

const ADD_ARGS = {
  title: "Call the bank",
  notes: null,
  list: null,
  when: { whenKind: "absolute", minutesFromNow: null, daysFromNow: null, date: "2026-10-23", yearMissing: false, weekday: null, weekdayNext: false, time: "09:00", ampmStated: true, partOfDay: null, repeat: null, whenText: "tomorrow at 9am" },
};

function answerAdd() {
  return toolCallAnswer("reminders__add", ADD_ARGS);
}

function answerRepair() {
  return toolCallAnswer("midas__repair_request", { sidekick: "reminders", kind: "change", request: "make the circles bigger" });
}

function answerGrow() {
  return toolCallAnswer("midas__grow_sidekick", { sidekick: "reminders", feature: "flag a reminder" });
}

function answerServerDown() {
  return new Response("upstream down", { status: 503 });
}

function rows(db: Db, sql: string, ...params: Array<string | number | null>): Row[] {
  return db.query(sql, ...params);
}

let fetchMock: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  fetchMock = vi.spyOn(globalThis, "fetch");
});

afterEach(() => {
  fetchMock.mockRestore();
});

/* ---------- Sent again: the same answer, nothing done twice ---------- */

describe("a request sent again with the same requestId", () => {
  it("gets the first answer again, without a second model call", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerAdd);
    const firstResponse = await ask(env, token, REQUEST_ID);
    const first = await firstResponse.json();
    const secondResponse = await ask(env, token, REQUEST_ID);
    const second = await secondResponse.json();
    expect(firstResponse.status).toBe(200);
    expect(secondResponse.status).toBe(200);
    expect(first.status).toBe("done");
    expect(second).toEqual(first);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("is logged once, with the request id, and counted as sent twice", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerAdd);
    const first = await (await ask(env, token, REQUEST_ID)).json();
    await ask(env, token, REQUEST_ID);
    const logs = rows(env.DB, "SELECT id, request_id FROM voice_logs");
    expect(logs).toEqual([{ id: first.logId, request_id: REQUEST_ID }]);
    const kept = rows(env.DB, "SELECT state, sends, log_id FROM jess_requests WHERE user_id = 'u1' AND request_id = ?", REQUEST_ID);
    expect(kept).toEqual([{ state: "answered", sends: 2, log_id: first.logId }]);
  });

  it("files one repair, not two", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerRepair);
    const first = await (await ask(env, token, REQUEST_ID, "make the circles bigger")).json();
    const second = await (await ask(env, token, REQUEST_ID, "make the circles bigger")).json();
    expect(first.status).toBe("repair");
    expect(second.reportId).toBe(first.reportId);
    expect(rows(env.DB, "SELECT id FROM repair_reports")).toHaveLength(1);
  });

  it("files one grow and keeps one pending request, not two", async () => {
    const env = makeEnv(true);
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerGrow);
    const first = await (await ask(env, token, REQUEST_ID, "add call the bank tomorrow and flag it")).json();
    const second = await (await ask(env, token, REQUEST_ID, "add call the bank tomorrow and flag it")).json();
    expect(first.status).toBe("grow");
    expect(second.pendingId).toBe(first.pendingId);
    expect(rows(env.DB, "SELECT id FROM repair_reports")).toHaveLength(1);
    expect(rows(env.DB, "SELECT id FROM jess_pending_requests")).toHaveLength(1);
  });

  it("is the same request in upper or lower case", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerAdd);
    const first = await (await ask(env, token, REQUEST_ID.toUpperCase())).json();
    const second = await (await ask(env, token, REQUEST_ID)).json();
    expect(second).toEqual(first);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("belongs to one user: another user's same id runs on its own", async () => {
    const env = makeEnv();
    const firstToken = signIn(env.DB, "u1");
    const secondToken = signIn(env.DB, "u2");
    fetchMock.mockImplementation(answerAdd);
    const first = await (await ask(env, firstToken, REQUEST_ID)).json();
    const second = await (await ask(env, secondToken, REQUEST_ID)).json();
    expect(second.logId).not.toBe(first.logId);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});

/* ---------- Still running, never finished, model unreachable ---------- */

describe("a request whose first send has not finished", () => {
  function seedClaim(db: Db, claimedAt: string) {
    db.execute(
      "INSERT INTO jess_requests (user_id, request_id, state, reply, log_id, sends, claimed_at, created_at, updated_at) VALUES ('u1', ?, 'running', NULL, NULL, 1, ?, ?, ?)",
      REQUEST_ID,
      claimedAt,
      claimedAt,
      claimedAt,
    );
  }

  it("gets 409 busy while the first send still runs, and the model is not called", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    seedClaim(env.DB, new Date().toISOString());
    fetchMock.mockImplementation(answerAdd);
    const response = await ask(env, token, REQUEST_ID);
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "busy" });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("runs again when the first claim is older than a run can take", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const staleAt = new Date(Date.now() - STALE_CLAIM_MS - 1000).toISOString();
    seedClaim(env.DB, staleAt);
    fetchMock.mockImplementation(answerAdd);
    const response = await ask(env, token, REQUEST_ID);
    const reply = await response.json();
    expect(response.status).toBe(200);
    expect(reply.status).toBe("done");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

describe("a request the model could not answer", () => {
  it("is left open, and the next send of the same id runs again", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerServerDown);
    const first = await (await ask(env, token, REQUEST_ID)).json();
    expect(first).toMatchObject({ status: "not-done", reason: "model-error" });
    expect(rows(env.DB, "SELECT state FROM jess_requests")).toEqual([{ state: "open" }]);
    fetchMock.mockImplementation(answerAdd);
    const second = await (await ask(env, token, REQUEST_ID)).json();
    expect(second.status).toBe("done");
    expect(rows(env.DB, "SELECT state FROM jess_requests")).toEqual([{ state: "answered" }]);
  });

  it("keeps a final not-done (the request cannot be acted on) as the answer", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    function answerCannotAct() {
      return toolCallAnswer("midas__cannot_act", { reason: "not-a-request" });
    }
    fetchMock.mockImplementation(answerCannotAct);
    const first = await (await ask(env, token, REQUEST_ID, "hello there")).json();
    const second = await (await ask(env, token, REQUEST_ID, "hello there")).json();
    expect(first.status).toBe("not-done");
    expect(second).toEqual(first);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

/* ---------- Older phones and bad ids ---------- */

describe("a request without a usable requestId", () => {
  it("runs every time, as before (older phones), and keeps nothing", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerAdd);
    await ask(env, token, undefined);
    await ask(env, token, undefined);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(rows(env.DB, "SELECT * FROM jess_requests")).toEqual([]);
    expect(rows(env.DB, "SELECT request_id FROM voice_logs")).toEqual([{ request_id: null }, { request_id: null }]);
  });

  it("ignores an id that is not a UUID", async () => {
    expect(normalizedRequestId("not-a-uuid")).toBeNull();
    expect(normalizedRequestId(42)).toBeNull();
    expect(normalizedRequestId(REQUEST_ID.toUpperCase())).toBe(REQUEST_ID);
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(answerAdd);
    await ask(env, token, "not-a-uuid");
    await ask(env, token, "not-a-uuid");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
