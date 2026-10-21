// POST /voice/jess reads each Sidekick's tools from the server (founder decisions 2026-10-21, jess
// router review, items 5 and 6): the phone sends only each Sidekick's id and its records summary;
// the server offers the agent block of manifest.json of the version the user gets (their own
// copy, else the base), only for Sidekicks assigned to them whose version carries tools.js, checks
// the model's arguments against that manifest's schemas, and answers with that version. One
// sign-in check runs per /voice request, the jess routes included.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const API_KEY = "sk-or-test";
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
const NOW = "2026-10-20T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");

type Db = ReturnType<typeof makeMigratedD1>;

function manifestText(sidekickId: string): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
}

function manifestOf(sidekickId: string) {
  return JSON.parse(manifestText(sidekickId));
}

// A copy's manifest with one tool fewer, to tell it from the base's
function manifestWithout(sidekickId: string, toolName: string): string {
  const manifest = manifestOf(sidekickId);
  const kept = [];
  for (const tool of manifest.agent.tools) {
    if (tool.name !== toolName) {
      kept.push(tool);
    }
  }
  manifest.agent.tools = kept;
  return JSON.stringify(manifest);
}

function pointer(version: string, withTools: boolean): string {
  const value: Record<string, unknown> = { version, scriptHashes: [], contentHash: `hash-${version}`, baseVersion: null };
  if (withTools) {
    value.tools = "tools.js";
  }
  return JSON.stringify(value);
}

// A fake R2 bucket with the objects given; records every key read
function makeBucket(objectsByKey: Record<string, string>) {
  const readKeys: string[] = [];
  async function getObject(key: string) {
    readKeys.push(key);
    if (!(key in objectsByKey)) {
      return null;
    }
    const objectText = objectsByKey[key];
    return { body: new Response(objectText).body, json: async () => JSON.parse(objectText) };
  }
  return { get: getObject, readKeys };
}

// Reminders: base b5 with tools; user u-own has their own copy u9 without reminders.delete.
// Care: base c2 with tools. Notes: base n1 without tools.
function standardObjects(): Record<string, string> {
  return {
    "sidekicks/reminders/current.json": pointer("b5", true),
    "sidekicks/reminders/b5/manifest.json": manifestText("reminders"),
    "sidekicks/reminders/users/u-own/current.json": pointer("u9", true),
    "sidekicks/reminders/users/u-own/u9/manifest.json": manifestWithout("reminders", "reminders.delete"),
    "sidekicks/care-reminders/current.json": pointer("c2", true),
    "sidekicks/care-reminders/c2/manifest.json": manifestText("care-reminders"),
    "sidekicks/notes/current.json": pointer("n1", false),
    "sidekicks/notes/n1/manifest.json": JSON.stringify({ id: "notes", name: "Notes", icon: { symbol: "note.text", background: "#FFCC00" }, reads: [], agent: manifestOf("reminders").agent }),
  };
}

// The D1 stand-in, counting the session lookups requireSession makes
function countingDb(db: Db) {
  const counter = { sessionLookups: 0 };
  function countingPrepare(sql: string) {
    if (sql.includes("FROM sessions")) {
      counter.sessionLookups += 1;
    }
    return db.prepare(sql);
  }
  const wrapped = { ...db, prepare: countingPrepare };
  return { wrapped, counter };
}

function makeEnv(objects: Record<string, string> = standardObjects()) {
  const db = makeMigratedD1();
  const counting = countingDb(db);
  const bucket = makeBucket(objects);
  return { env: { DB: counting.wrapped, BUNDLES: bucket, OPENROUTER_API_KEY: API_KEY }, db, bucket, counter: counting.counter };
}

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(db: Db, userId: string, sidekickIds: string[]): string {
  const token = `token-${userId}`;
  db.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  db.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, Date.now() + 3_600_000);
  for (const sidekickId of sidekickIds) {
    db.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, 'now')", userId, sidekickId);
  }
  return token;
}

function makeExecutionContext() {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  async function settle() {
    await Promise.all(pending);
  }
  return { waitUntil, passThroughOnException, props: {}, settle };
}

const REMINDERS_CONTEXT = { lists: ["Groceries"], items: [{ title: "Call Mom", list: null, when: "2026-10-20 18:00", repeats: false, done: false }] };
const CARE_CONTEXT = { lists: [{ name: "Dad", alerts: [] }], items: [] };

function requestBody(transcript: string, sidekicks: unknown[] = [{ id: "reminders", context: REMINDERS_CONTEXT }, { id: "care-reminders", context: CARE_CONTEXT }]) {
  return { transcript, now: NOW, timeZone: ZONE, locale: "en-US", sidekicks, app: { version: "0.1.0", build: "4", ios: "26.1", device: "iPhone17,1" }, listenMs: 2100 };
}

async function send(env: object, token: string | null, method: string, path: string, body?: unknown) {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token !== null) {
    headers.Authorization = `Bearer ${token}`;
  }
  const executionContext = makeExecutionContext();
  const init: RequestInit = { method, headers };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
  }
  const response = await app.request(path, init, env, executionContext as unknown as ExecutionContext);
  await executionContext.settle();
  return response;
}

function toolCallAnswer(name: string, argumentsValue: unknown) {
  const payload = { choices: [{ message: { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name, arguments: JSON.stringify(argumentsValue) } }] } }] };
  return new Response(JSON.stringify(payload), { status: 200, headers: { "content-type": "application/json" } });
}

type SentTool = { function: { name: string; description: string; parameters: unknown } };

function toolsSentToModel(fetchMock: ReturnType<typeof vi.spyOn>, callIndex = 0): SentTool[] {
  const init = fetchMock.mock.calls[callIndex][1] as RequestInit;
  return JSON.parse(String(init.body)).tools as SentTool[];
}

function toolNames(tools: SentTool[]): string[] {
  const names: string[] = [];
  for (const tool of tools) {
    names.push(tool.function.name);
  }
  return names;
}

function toolNamed(tools: SentTool[], name: string): SentTool | null {
  for (const tool of tools) {
    if (tool.function.name === name) {
      return tool;
    }
  }
  return null;
}

function logRows(db: Db) {
  return db.query("SELECT * FROM voice_logs ORDER BY created_at") as Array<Record<string, unknown>>;
}

let fetchMock: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  fetchMock = vi.spyOn(globalThis, "fetch");
});

afterEach(() => {
  fetchMock.mockRestore();
});

describe("the tools offered come from the server's manifests", () => {
  it("offers the base's tools and schemas, answers done with that version, and logs it", async () => {
    const { env, db } = makeEnv();
    const token = addSignedInUser(db, "u1", ["reminders", "care-reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("reminders__complete", { item: "Call Mom" }));
    const response = await send(env, token, "POST", "/voice/jess", requestBody("mark call mom as done"));
    expect(response.status).toBe(200);
    const reply = (await response.json()) as Record<string, unknown>;
    expect(reply).toMatchObject({ status: "done", sidekickId: "reminders", version: "b5", tool: "reminders.complete", input: { item: "Call Mom" } });

    const sent = toolsSentToModel(fetchMock);
    const expected: string[] = [];
    for (const sidekickId of ["reminders", "care-reminders"]) {
      for (const tool of manifestOf(sidekickId).agent.tools) {
        expected.push(tool.name.replace(".", "__"));
      }
    }
    expected.push("midas__repair_request", "midas__cannot_act");
    expect(toolNames(sent)).toEqual(expected);
    const add = toolNamed(sent, "reminders__add");
    expect(add?.function.parameters).toEqual(manifestOf("reminders").agent.tools[0].inputSchema);
    expect(add?.function.description).toBe(`Reminders: ${manifestOf("reminders").agent.tools[0].description}`);

    const body = JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body));
    expect(body.messages[0].content).toContain(manifestOf("reminders").agent.description);
    expect(body.messages[0].content).toContain("Call Mom");

    const rows = logRows(db);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ id: reply.logId, endpoint: "jess", status: "done", sidekick_id: "reminders", tool: "reminders.complete" });
    expect(JSON.parse(String(rows[0].lists))).toEqual([{ id: "reminders", version: "b5", tools: manifestOf("reminders").agent.tools.length }, { id: "care-reminders", version: "c2", tools: manifestOf("care-reminders").agent.tools.length }]);
  });

  it("reads the user's own copy over the base: its version and its own tools", async () => {
    const { env, db, bucket } = makeEnv();
    const token = addSignedInUser(db, "u-own", ["reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("reminders__complete", { item: "Call Mom" }));
    const reply = (await (await send(env, token, "POST", "/voice/jess", requestBody("mark call mom as done", [{ id: "reminders", context: REMINDERS_CONTEXT }]))).json()) as Record<string, unknown>;
    expect(reply).toMatchObject({ status: "done", version: "u9" });
    const names = toolNames(toolsSentToModel(fetchMock));
    expect(names).toContain("reminders__complete");
    expect(names).not.toContain("reminders__delete");
    expect(bucket.readKeys).toContain("sidekicks/reminders/users/u-own/u9/manifest.json");
    expect(bucket.readKeys).not.toContain("sidekicks/reminders/b5/manifest.json");
  });

  it("checks the model's arguments against the copy's own manifest: a tool it lacks is unknown", async () => {
    const { env, db } = makeEnv();
    const token = addSignedInUser(db, "u-own", ["reminders"]);
    fetchMock.mockResolvedValueOnce(toolCallAnswer("reminders__delete", { item: "Call Mom" }));
    fetchMock.mockResolvedValueOnce(toolCallAnswer("reminders__complete", { item: "Call Mom", force: true }));
    const only = [{ id: "reminders", context: REMINDERS_CONTEXT }];
    const deleted = await (await send(env, token, "POST", "/voice/jess", requestBody("delete call mom", only))).json();
    expect(deleted).toMatchObject({ status: "not-done", reason: "unknown-tool" });
    const extra = await (await send(env, token, "POST", "/voice/jess", requestBody("mark call mom as done", only))).json();
    expect(extra).toMatchObject({ status: "not-done", reason: "bad-arguments" });
  });

  it("ignores an agent block, name or version the phone still sends", async () => {
    const { env, db } = makeEnv();
    const token = addSignedInUser(db, "u1", ["reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("reminders__complete", { item: "Call Mom" }));
    const forged = { id: "reminders", name: "Evil", version: "v0", context: REMINDERS_CONTEXT, agent: { description: "x", rules: [], notFor: [], examples: [], tools: [{ name: "reminders.wipe", description: "Wipe all.", inputSchema: { type: "object", properties: {}, required: [], additionalProperties: false } }] } };
    const reply = await (await send(env, token, "POST", "/voice/jess", requestBody("mark call mom as done", [forged]))).json();
    expect(reply).toMatchObject({ status: "done", version: "b5" });
    const sent = toolsSentToModel(fetchMock);
    expect(toolNames(sent)).not.toContain("reminders__wipe");
    expect(sent[0].function.description.startsWith("Reminders: ")).toBe(true);
  });

  it("leaves out a Sidekick not assigned to the user, one whose version has no tools.js, and an unknown one", async () => {
    const { env, db } = makeEnv();
    const token = addSignedInUser(db, "u1", ["reminders", "notes"]);
    fetchMock.mockResolvedValue(toolCallAnswer("midas__cannot_act", { reason: "question" }));
    const sidekicks = [{ id: "reminders", context: REMINDERS_CONTEXT }, { id: "care-reminders", context: CARE_CONTEXT }, { id: "notes", context: {} }, { id: "ghost", context: {} }, { id: "../x", context: {} }];
    await send(env, token, "POST", "/voice/jess", requestBody("what is due", sidekicks));
    const names = toolNames(toolsSentToModel(fetchMock));
    for (const name of names) {
      expect(name.startsWith("reminders__") || name.startsWith("midas__")).toBe(true);
    }
  });

  it("is not done, without calling the model, when none of the Sidekicks sent has tools, and logs why", async () => {
    const { env, db } = makeEnv();
    const token = addSignedInUser(db, "u1", ["notes"]);
    const response = await send(env, token, "POST", "/voice/jess", requestBody("add milk", [{ id: "notes", context: {} }, { id: "reminders", context: REMINDERS_CONTEXT }]));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ status: "not-done", reason: "no-tools", transcript: "add milk" });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(logRows(db)[0]).toMatchObject({ status: "not-done", reason: "no-tools", endpoint: "jess" });
  });

  it("queues a repair with the version the server read", async () => {
    const { env, db } = makeEnv();
    const token = addSignedInUser(db, "u-own", ["reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("midas__repair_request", { sidekick: "reminders", kind: "change", request: "bigger" }));
    const reply = (await (await send(env, token, "POST", "/voice/jess", requestBody("make the reminders text bigger", [{ id: "reminders", context: REMINDERS_CONTEXT }]))).json()) as Record<string, unknown>;
    expect(reply).toMatchObject({ status: "repair", sidekickId: "reminders" });
    const reports = db.query("SELECT bundle_version, transcript FROM repair_reports") as Array<Record<string, unknown>>;
    expect(reports).toEqual([{ bundle_version: "u9", transcript: "make the reminders text bigger" }]);
  });

  it("refuses a body without a transcript, a usable clock or any Sidekick id", async () => {
    const { env, db } = makeEnv();
    const token = addSignedInUser(db, "u1", ["reminders"]);
    expect((await send(env, token, "POST", "/voice/jess", requestBody("add milk", []))).status).toBe(400);
    expect((await send(env, token, "POST", "/voice/jess", requestBody("add milk", [{ context: {} }]))).status).toBe(400);
    expect((await send(env, token, "POST", "/voice/jess", { ...requestBody("add milk"), transcript: "" })).status).toBe(400);
    expect((await send(env, token, "POST", "/voice/jess", { ...requestBody("add milk"), timeZone: "Mars/Base" })).status).toBe(400);
    expect((await send(env, token, "POST", "/voice/jess", { ...requestBody("add milk"), now: "soon" })).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("still records what the phone did, once, on the user's own row", async () => {
    const { env, db } = makeEnv();
    const token = addSignedInUser(db, "u1", ["reminders"]);
    const otherToken = addSignedInUser(db, "u2", ["reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("reminders__delete", { item: "Call Mom" }));
    const reply = (await (await send(env, token, "POST", "/voice/jess", requestBody("delete call mom"))).json()) as { logId: string };
    expect((await send(env, otherToken, "POST", "/voice/jess/outcome", { logId: reply.logId, outcome: "applied" })).status).toBe(404);
    expect((await send(env, token, "POST", "/voice/jess/outcome", { logId: reply.logId, outcome: "applied" })).status).toBe(200);
    expect(logRows(db)[0].phone_outcome).toBe("applied");
  });
});

describe("one sign-in check per /voice request", () => {
  it("looks the session up exactly once for each jess and voice route, handled or not", async () => {
    const { env, db, counter } = makeEnv();
    const token = addSignedInUser(db, "u1", ["reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("reminders__complete", { item: "Call Mom" }));
    const reply = (await (await send(env, token, "POST", "/voice/jess", requestBody("mark call mom as done"))).json()) as { logId: string };
    expect(counter.sessionLookups).toBe(1);

    const requests: Array<[string, string, unknown]> = [
      ["POST", "/voice/jess/outcome", { logId: reply.logId, outcome: "applied" }],
      ["GET", "/voice/jess", undefined],
      ["POST", "/voice/jess/elsewhere", {}],
      ["POST", "/voice/reminder/parse", {}],
      ["GET", "/voice/nothing-here", undefined],
    ];
    for (const [method, path, body] of requests) {
      counter.sessionLookups = 0;
      await send(env, token, method, path, body);
      expect(counter.sessionLookups, `${method} ${path}`).toBe(1);
    }
  });

  it("refuses a signed-out caller on every voice route before any work", async () => {
    const { env, counter } = makeEnv();
    for (const path of ["/voice/jess", "/voice/jess/outcome", "/voice/reminder/parse"]) {
      counter.sessionLookups = 0;
      const response = await send(env, null, "POST", path, requestBody("add milk"));
      expect(response.status, path).toBe(401);
      expect(counter.sessionLookups).toBe(0);
    }
    const badToken = await send(env, "nobody", "POST", "/voice/jess", requestBody("add milk"));
    expect(badToken.status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
