// Build 22 small fixes (founder 2026-11-02, docs/PRODUCT.md section 6 "Open, 2026-10-31: build 22",
// "Small fixes"; pick B): a jess request that needed an edit the agent could not make stayed Not
// Done after the founder fixed the edit by hand. Cause: the backend failed the request as soon as
// the edit failed (jess-pending.ts failFinished), and nothing re-ran it after the founder published
// his fix and marked it Built (only the runner's own publish re-ran requests). Now the request keeps
// waiting while the founder works, the runner asks between jobs which live reports a request still
// waits on (GET /repairs/jess-reruns), and re-runs it on the founder's copy, so the person's request
// is carried out and the card turns Done.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { closingStatements } from "../src/edit-failed";
import { createBackendClient } from "../../runner/lib/backend.mjs";
import { rerunHandFixed } from "../../runner/lib/hand-fixed-rerun.mjs";
import { runLoop } from "../../runner/lib/loop.mjs";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const ORIGINAL_NOW = "2026-10-20T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");
const RUNNER_TOKEN = "runner-secret-for-hand-fix";
const BASE_URL = "https://midas.test";
const REMINDERS_MANIFEST = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8");
const REMINDERS_TOOLS = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "tools.js"), "utf8");
const SAID = "add call the bank tomorrow at 9am and flag it";

type Db = ReturnType<typeof makeMigratedD1>;
type Row = Record<string, unknown>;

/* ---------- Fakes ---------- */

function makeBucket() {
  const objectsByKey: Record<string, string> = {
    "sidekicks/reminders/current.json": JSON.stringify({ version: "b5", scriptHashes: [], contentHash: "hash-b5", baseVersion: null, tools: "tools.js" }),
    "sidekicks/reminders/b5/manifest.json": REMINDERS_MANIFEST,
    "sidekicks/reminders/b5/tools.js": REMINDERS_TOOLS,
  };
  async function getObject(key: string) {
    if (!(key in objectsByKey)) {
      return null;
    }
    const objectText = objectsByKey[key];
    return { body: new Response(objectText).body, json: async () => JSON.parse(objectText) };
  }
  return { get: getObject, objectsByKey };
}

type Bucket = ReturnType<typeof makeBucket>;

// What the founder's hand deploy does to R2: the person's own pointer moves to his fixed version
function publishHandFix(bucket: Bucket, userId: string, version: string, withTools = true) {
  bucket.objectsByKey[`sidekicks/reminders/users/${userId}/current.json`] = JSON.stringify({ version, scriptHashes: [], contentHash: "hash-" + version, baseVersion: "b5", tools: "tools.js" });
  bucket.objectsByKey[`sidekicks/reminders/users/${userId}/${version}/manifest.json`] = REMINDERS_MANIFEST;
  if (withTools) {
    bucket.objectsByKey[`sidekicks/reminders/users/${userId}/${version}/tools.js`] = REMINDERS_TOOLS;
  }
}

type Env = { DB: Db; BUNDLES: Bucket; JESS_GROW?: string };

function makeEnv(): Env {
  const env: Record<string, unknown> = { DB: makeMigratedD1(), BUNDLES: makeBucket(), OPENROUTER_API_KEY: "sk-or-test", REPAIR_RUNNER_TOKEN: RUNNER_TOKEN, JESS_GROW: "true" };
  return env as Env;
}

function signIn(db: Db, userId: string): string {
  const token = `token-${userId}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  db.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  db.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", tokenHash, userId, Date.now() + 3_600_000);
  db.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'reminders', 'now')", userId);
  return token;
}

async function request(env: object, path: string, init: RequestInit) {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  const executionContext = { waitUntil, passThroughOnException, props: {} };
  const response = await app.request(path, init, env, executionContext as unknown as ExecutionContext);
  await Promise.all(pending);
  return response;
}

function call(env: object, path: string, method: string, authorization: string, body?: unknown) {
  const headers: Record<string, string> = { Authorization: authorization };
  const init: RequestInit = { method, headers };
  if (body !== undefined) {
    headers["content-type"] = "application/json";
    init.body = JSON.stringify(body);
  }
  return request(env, path, init);
}

// The runner's real backend client, talking to the real routes
function runnerClient(env: object, environment = "staging") {
  async function fetchThroughApp(url: string, init: RequestInit = {}) {
    const path = url.slice(BASE_URL.length);
    return request(env, path, init);
  }
  return createBackendClient({ baseUrl: BASE_URL, token: RUNNER_TOKEN, environment, fetchImplementation: fetchThroughApp });
}

function modelCalls(...calls: Array<{ name: string; args: Record<string, unknown> }>) {
  const queue = [...calls];
  async function answer() {
    const next = queue.shift();
    if (next === undefined) {
      return new Response("no more answers", { status: 500 });
    }
    const message = { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name: next.name, arguments: JSON.stringify(next.args) } }] };
    return new Response(JSON.stringify({ choices: [{ message }] }), { status: 200, headers: { "content-type": "application/json" } });
  }
  return answer;
}

const GROW_CALL = { name: "midas__grow_sidekick", args: { sidekick: "reminders", feature: "flag a reminder" } };
const ADD_CALL = {
  name: "reminders__add",
  args: { title: "Call the bank", notes: null, list: null, reminderType: null, when: { whenKind: "absolute", minutesFromNow: null, daysFromNow: null, date: "2026-10-21", yearMissing: false, weekday: null, weekdayNext: false, time: "09:00", ampmStated: true, partOfDay: null, repeat: null, whenText: "tomorrow at 9am" } },
};

function rows(db: Db, sql: string, ...params: Array<string | number | null>): Row[] {
  return db.query(sql, ...params);
}

function pendingRow(db: Db): Row {
  return rows(db, "SELECT * FROM jess_pending_requests")[0];
}

let fetchMock: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  fetchMock = vi.spyOn(globalThis, "fetch");
});

afterEach(() => {
  fetchMock.mockRestore();
});

// One person asked for something Reminders cannot do: jess filed the edit and keeps the request
async function grown(env: Env) {
  const token = signIn(env.DB, "u1");
  fetchMock.mockImplementation(modelCalls(GROW_CALL));
  const body = { transcript: SAID, now: ORIGINAL_NOW, timeZone: ZONE, locale: "en-US", sidekicks: [{ id: "reminders", context: { lists: [], items: [] } }] };
  const reply = await (await call(env, "/voice/jess", "POST", `Bearer ${token}`, body)).json();
  expect(reply).toMatchObject({ status: "grow" });
  return { token, reportId: reply.reportId as string, pendingId: reply.pendingId as string };
}

// The edit agent could not make it: the report is failed / couldnt_fix, as the runner's failed status
// and the lease running out both store it
function editCouldNotBeMade(db: Db, reportId: string, at = new Date().toISOString()) {
  db.execute("UPDATE repair_reports SET status = 'failed', fail_reason = 'agent: unsupported', result_kind = 'couldnt_fix', updated_at = ? WHERE id = ?", at, reportId);
}

// The founder published his fix and marked the inbox thread Built
async function founderMarksBuilt(db: Db, reportId: string) {
  await db.batch(closingStatements(db as unknown as D1Database, reportId, "u1", "Reminders can be flagged.", new Date().toISOString()));
}

function listPending(env: Env, token: string) {
  return call(env, "/voice/jess/pending", "GET", `Bearer ${token}`);
}

/* ---------- The request waits while the founder works ---------- */

describe("an edit the agent could not make", () => {
  it("leaves the jess request waiting, not failed, so the person's card is not Not Done", async () => {
    const env = makeEnv();
    const { token, reportId } = await grown(env);
    editCouldNotBeMade(env.DB, reportId, new Date(Date.now() - 60 * 60 * 1000).toISOString());

    const listed = await (await listPending(env, token)).json();

    expect(listed).toEqual({ pending: [] });
    expect(pendingRow(env.DB)).toMatchObject({ status: "waiting", fail_reason: null });
  });

  it("still fails the request when the edit failed any other way", async () => {
    const env = makeEnv();
    const { token, reportId } = await grown(env);
    env.DB.execute("UPDATE repair_reports SET status = 'failed', fail_reason = 'nothing to change', result_kind = 'already_there' WHERE id = ?", reportId);

    const listed = await (await listPending(env, token)).json();

    expect(listed.pending).toEqual([expect.objectContaining({ state: "failed", transcript: SAID })]);
    expect(pendingRow(env.DB)).toMatchObject({ status: "failed", fail_reason: "repair failed: nothing to change" });
  });
});

/* ---------- GET /repairs/jess-reruns ---------- */

describe("GET /repairs/jess-reruns", () => {
  it("lists a live report a request still waits on, only for the runner, and nothing with the flag off", async () => {
    const env = makeEnv();
    const { token, reportId } = await grown(env);
    const runnerAuth = `Runner ${RUNNER_TOKEN}`;

    expect(await (await call(env, "/repairs/jess-reruns", "GET", runnerAuth)).json()).toEqual({ reports: [] });
    editCouldNotBeMade(env.DB, reportId);
    expect(await (await call(env, "/repairs/jess-reruns", "GET", runnerAuth)).json()).toEqual({ reports: [] });

    publishHandFix(env.BUNDLES, "u1", "h1");
    await founderMarksBuilt(env.DB, reportId);
    const listed = await (await call(env, "/repairs/jess-reruns", "GET", runnerAuth)).json();
    expect(listed).toEqual({ reports: [{ id: reportId, userId: "u1", sidekickId: "reminders", kind: "feature" }] });

    expect((await call(env, "/repairs/jess-reruns", "GET", `Bearer ${token}`)).status).toBe(401);
    delete env.JESS_GROW;
    expect(await (await call(env, "/repairs/jess-reruns", "GET", runnerAuth)).json()).toEqual({ reports: [] });
  });
});

/* ---------- The whole path ---------- */

describe("the founder's hand fix", () => {
  it("is followed by the runner's re-run on his copy: the request is carried out and the phone shows it done", async () => {
    const env = makeEnv();
    const { token, reportId, pendingId } = await grown(env);
    editCouldNotBeMade(env.DB, reportId);
    publishHandFix(env.BUNDLES, "u1", "h1");
    await founderMarksBuilt(env.DB, reportId);
    fetchMock.mockImplementation(modelCalls(ADD_CALL));
    const logged: string[] = [];
    function logLine(line: string) {
      logged.push(line);
    }

    const outcomes = await rerunHandFixed({ backends: [runnerClient(env)], log: logLine });

    expect(outcomes).toEqual([{ environment: "staging", reportId, result: { status: "done", ops: 1 } }]);
    expect(logged).toEqual([`runner: jess re-run of ${reportId} on staging (hand fix): done`]);
    const ops = rows(env.DB, "SELECT * FROM ops WHERE user_id = 'u1'");
    expect(ops).toHaveLength(1);
    expect(ops[0]).toMatchObject({ op_id: `jess-${pendingId}-0`, sidekick_id: "reminders" });
    expect(JSON.parse(String(ops[0].value))).toMatchObject({ $type: "reminders.item", title: "Call the bank" });

    const listed = await (await listPending(env, token)).json();
    expect(listed).toEqual({ pending: [{ id: pendingId, sidekickId: "reminders", state: "done", text: "Added Call the bank", transcript: SAID }] });

    // Once: the next idle turn finds nothing
    expect(await rerunHandFixed({ backends: [runnerClient(env)] })).toEqual([]);
    expect(rows(env.DB, "SELECT * FROM ops")).toHaveLength(1);
  });

  it("a copy without tools.js runs nothing; one environment failing does not stop the other", async () => {
    const env = makeEnv();
    const { reportId } = await grown(env);
    editCouldNotBeMade(env.DB, reportId);
    publishHandFix(env.BUNDLES, "u1", "h1", false);
    await founderMarksBuilt(env.DB, reportId);
    async function failingList(): Promise<never> {
      throw new Error("offline");
    }
    const broken = { environment: "live", listJessReruns: failingList };
    const errors: string[] = [];
    function recordError(error: Error) {
      errors.push(error.message);
    }

    const outcomes = await rerunHandFixed({ backends: [broken, runnerClient(env)], onError: recordError });

    expect(errors).toEqual(["live: offline"]);
    expect(outcomes).toEqual([{ environment: "staging", reportId, result: { status: "none" } }]);
    expect(pendingRow(env.DB)).toMatchObject({ status: "waiting" });
  });
});

/* ---------- The runner loop ---------- */

describe("the runner loop between jobs", () => {
  it("runs whenIdle only when no job was claimed, and an error there does not stop the loop", async () => {
    const claims: Array<object | null> = [null, { id: "job" }, null];
    const happened: string[] = [];
    let turns = 0;
    async function claimJob() {
      turns += 1;
      return claims.shift() ?? null;
    }
    async function runJob() {
      happened.push("job");
    }
    async function whenIdle() {
      happened.push("idle");
      if (happened.length === 1) {
        throw new Error("idle broke");
      }
    }
    async function sleep() {
      happened.push("sleep");
    }
    function shouldStop() {
      return turns >= 3;
    }
    const errors: string[] = [];
    function onError(error: Error) {
      errors.push(error.message);
    }

    await runLoop({ claimJob, runJob, pollIntervalMs: 1, sleep, shouldStop, onError, whenIdle });

    expect(happened).toEqual(["idle", "sleep", "job", "idle", "sleep"]);
    expect(errors).toEqual(["idle broke"]);
  });
});
