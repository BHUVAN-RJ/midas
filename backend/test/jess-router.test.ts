import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { CANNOT_ACT_TOOL, JESS_MODEL, REPAIR_TOOL, buildJessPrompt, buildJessRequest, outcomeFromToolCall, parseSidekick, toolCallFromMessage, wireToolName } from "../src/jess";
import type { JessContext, JessSidekick } from "../src/jess";
import { OPENROUTER_URL } from "../src/voice-route";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// POST /voice/jess (jess router, founder 2026-10-21, phase 3): the model calls one tool of the
// user's Sidekicks, or midas.repair_request, or midas.cannot_act. The server checks the call's
// arguments against the tool's inputSchema and works out any date with the voice resolver; a
// repair is queued for the repair agent; anything else is "not done" with the transcript. Every
// attempt is logged in voice_logs with the tool chosen and its arguments (migration 0007).

const API_KEY = "sk-or-test";
// Tuesday Oct 20, 2026, 10:00 in Los Angeles
const NOW = "2026-10-20T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");

function agentOf(sidekickId: string) {
  return JSON.parse(readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8")).agent;
}

function sidekicksSent() {
  return [
    { id: "reminders", name: "Reminders", version: "v5", agent: agentOf("reminders"), context: { lists: ["Groceries", "Work"], items: [{ title: "Call Mom", list: null, when: "2026-10-20 18:00", repeats: false, done: false }] } },
    { id: "care-reminders", name: "Care", version: "c2", agent: agentOf("care-reminders"), context: { lists: [{ name: "Dad", alerts: [] }], items: [] } },
  ];
}

function jessContext(transcript: string): JessContext {
  const sidekicks: JessSidekick[] = [];
  for (const sent of sidekicksSent()) {
    const parsed = parseSidekick(sent);
    if (parsed === null) {
      throw new Error(`${sent.id} did not parse`);
    }
    sidekicks.push(parsed);
  }
  return { transcript, now: NOW, timeZone: ZONE, locale: "en-US", sidekicks };
}

function noWhen() {
  return { whenKind: "none", minutesFromNow: null, daysFromNow: null, date: null, yearMissing: false, weekday: null, weekdayNext: false, time: null, ampmStated: false, partOfDay: null, repeat: null, whenText: "" };
}

function whenWith(fields: Record<string, unknown>) {
  return { ...noWhen(), whenKind: "absolute", ...fields };
}

function call(name: string, argumentsValue: unknown) {
  return { name, argumentsText: JSON.stringify(argumentsValue) };
}

describe("the request to the model", () => {
  it("offers every tool of every Sidekick under its wire name, plus repair and cannot-act", () => {
    const request = buildJessRequest(jessContext("add milk"), { reasoning: "off" });
    const names: string[] = [];
    for (const tool of request.tools as Array<{ function: { name: string; strict: boolean } }>) {
      names.push(tool.function.name);
      expect(tool.function.strict).toBe(true);
      expect(tool.function.name).toMatch(/^[a-zA-Z0-9_-]{1,64}$/);
    }
    expect(names).toContain("reminders__add");
    expect(names).toContain("care-reminders__add_list_alert");
    expect(names).toContain("midas__repair_request");
    expect(names).toContain("midas__cannot_act");
    expect(names.length).toBe(agentOf("reminders").tools.length + agentOf("care-reminders").tools.length + 2);
    expect(request.model).toBe(JESS_MODEL);
    expect(request.model).toBe("deepseek/deepseek-v4-flash");
    expect(request.tool_choice).toBe("required");
    expect(request).not.toHaveProperty("parallel_tool_calls");
    expect(request.temperature).toBe(0);
    expect(request.provider).toEqual({ require_parameters: true, data_collection: "deny" });
  });

  it("puts each Sidekick's description, not-for lines and records summary in the prompt, and the sentence apart as data", () => {
    const prompt = buildJessPrompt(jessContext("add milk"));
    expect(prompt.system).toContain(agentOf("reminders").description);
    expect(prompt.system).toContain(agentOf("reminders").notFor[0]);
    expect(prompt.system).toContain("Call Mom");
    expect(prompt.system).toContain("Today is Tuesday 2026-10-20");
    expect(prompt.system).not.toContain("add milk");
    expect(JSON.parse(prompt.user)).toEqual({ sentence: "add milk" });
  });

  it("leaves out a Sidekick whose tools are outside its own name", () => {
    const bad = { ...sidekicksSent()[0], agent: { ...agentOf("reminders"), tools: [{ name: "care-reminders.add", description: "x", inputSchema: { type: "object" } }] } };
    expect(parseSidekick(bad)).toBeNull();
    expect(parseSidekick({ ...sidekicksSent()[0], agent: { ...agentOf("reminders"), tools: [] } })).toBeNull();
  });
});

describe("checking the model's call", () => {
  it("passes an add through with its when worked out by the voice resolver", () => {
    const context = jessContext("remind me to call Dad tomorrow at 6pm");
    const outcome = outcomeFromToolCall(call("reminders__add", { title: "Call Dad", notes: null, list: null, when: whenWith({ date: "2026-10-21", time: "18:00", ampmStated: true, whenText: "tomorrow at 6pm" }) }), context);
    expect(outcome).toEqual({
      status: "done",
      sidekickId: "reminders",
      tool: "reminders.add",
      input: { title: "Call Dad", notes: null, list: null, when: { date: "2026-10-21", time: "18:00", allDay: false, at: "2026-10-22T01:00:00.000Z", repeat: null, timeZone: ZONE } },
    });
  });

  it("works out a weekday and a repeat in code, not in the model", () => {
    const context = jessContext("remind me every Friday at 5pm to water the plants");
    const outcome = outcomeFromToolCall(call("reminders__add", { title: "Water the plants", notes: null, list: null, when: whenWith({ weekday: 5, time: "17:00", ampmStated: true, repeat: { every: "week", interval: 1, weekdays: [5] }, whenText: "every Friday at 5pm" }) }), context);
    expect(outcome.status).toBe("done");
    const when = (outcome as { input: { when: Record<string, unknown> } }).input.when;
    expect(when.date).toBe("2026-10-23");
    expect(when.at).toBe("2026-10-24T00:00:00.000Z");
    expect(when.repeat).toEqual({ every: "week", weekdays: [5] });
  });

  it("hands over null for a when with nothing said, and leaves tools without a when alone", () => {
    const context = jessContext("add bananas to groceries");
    const added = outcomeFromToolCall(call("reminders__add", { title: "Bananas", notes: null, list: "Groceries", when: noWhen() }), context);
    expect(added).toMatchObject({ status: "done", input: { when: null, list: "Groceries" } });
    const completed = outcomeFromToolCall(call("reminders__complete", { item: "Call Mom" }), jessContext("mark call mom done"));
    expect(completed).toEqual({ status: "done", sidekickId: "reminders", tool: "reminders.complete", input: { item: "Call Mom" } });
  });

  it("is not done when the when is in the past", () => {
    const context = jessContext("remind me to stretch today at 8am");
    const outcome = outcomeFromToolCall(call("reminders__add", { title: "Stretch", notes: null, list: null, when: whenWith({ date: "2026-10-20", time: "08:00", ampmStated: true, whenText: "today at 8am" }) }), context);
    expect(outcome).toEqual({ status: "not-done", reason: "past", transcript: "remind me to stretch today at 8am" });
  });

  it("refuses arguments outside the tool's inputSchema, an unknown tool and a reply with no call", () => {
    const context = jessContext("delete the dentist");
    expect(outcomeFromToolCall(call("reminders__delete", { item: "Dentist", force: true }), context)).toMatchObject({ status: "not-done", reason: "bad-arguments" });
    expect(outcomeFromToolCall(call("reminders__delete", {}), context)).toMatchObject({ status: "not-done", reason: "bad-arguments" });
    expect(outcomeFromToolCall(call("reminders__delete", { item: 7 }), context)).toMatchObject({ status: "not-done", reason: "bad-arguments" });
    expect(outcomeFromToolCall(call("reminders__wipe_everything", {}), context)).toMatchObject({ status: "not-done", reason: "unknown-tool" });
    expect(outcomeFromToolCall({ name: "reminders__delete", argumentsText: "not json" }, context)).toMatchObject({ status: "not-done", reason: "bad-reply" });
    expect(outcomeFromToolCall(null, context)).toEqual({ status: "not-done", reason: "bad-reply", transcript: "delete the dentist" });
  });

  it("turns cannot-act into not-done with the model's reason", () => {
    const context = jessContext("what's the weather");
    expect(outcomeFromToolCall(call(wireToolName(CANNOT_ACT_TOOL), { reason: "question" }), context)).toEqual({ status: "not-done", reason: "question", transcript: "what's the weather" });
    expect(outcomeFromToolCall(call(wireToolName(CANNOT_ACT_TOOL), { reason: "whatever" }), context)).toMatchObject({ reason: "no-tool-fits" });
  });

  it("sends a repair with the person's own words, only for a Sidekick they have", () => {
    const context = jessContext("make the reminders list colours bigger");
    const repair = outcomeFromToolCall(call(wireToolName(REPAIR_TOOL), { sidekick: "reminders", kind: "change", request: "Bigger colours" }), context);
    expect(repair).toEqual({ status: "repair", sidekickId: "reminders", kind: "change", request: "make the reminders list colours bigger" });
    expect(outcomeFromToolCall(call(wireToolName(REPAIR_TOOL), { sidekick: "notes", kind: "change", request: "x" }), context)).toMatchObject({ status: "not-done", reason: "unknown-sidekick" });
    expect(outcomeFromToolCall(call(wireToolName(REPAIR_TOOL), { sidekick: "reminders", kind: "redesign", request: "x" }), context)).toMatchObject({ status: "not-done", reason: "bad-arguments" });
  });

  it("reads the first tool call of a chat message, arguments as text or object", () => {
    expect(toolCallFromMessage({ tool_calls: [{ function: { name: "reminders__add", arguments: "{\"title\":\"x\"}" } }] })).toEqual({ name: "reminders__add", argumentsText: "{\"title\":\"x\"}" });
    expect(toolCallFromMessage({ tool_calls: [{ function: { name: "a__b", arguments: { item: "x" } } }] })).toEqual({ name: "a__b", argumentsText: "{\"item\":\"x\"}" });
    expect(toolCallFromMessage({ content: "Sure!" })).toBeNull();
  });
});

/* ---------- The route ---------- */

type Db = ReturnType<typeof makeMigratedD1>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

// The server reads each Sidekick's manifest from R2 (jess router review, founder 2026-10-21, item 5):
// Reminders v5 and Care c2, both with tools.js
function makeBucket() {
  const objectsByKey: Record<string, string> = {
    "sidekicks/reminders/current.json": JSON.stringify({ version: "v5", scriptHashes: [], contentHash: "hash-v5", baseVersion: null, tools: "tools.js" }),
    "sidekicks/reminders/v5/manifest.json": readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8"),
    "sidekicks/care-reminders/current.json": JSON.stringify({ version: "c2", scriptHashes: [], contentHash: "hash-c2", baseVersion: null, tools: "tools.js" }),
    "sidekicks/care-reminders/c2/manifest.json": readFileSync(join(REPO_ROOT, "sidekicks", "care-reminders", "manifest.json"), "utf8"),
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

// What the phone sends for each Sidekick: its id and its records summary
function sidekicksSentByPhone() {
  const sidekicks = [];
  for (const sent of sidekicksSent()) {
    sidekicks.push({ id: sent.id, context: sent.context });
  }
  return sidekicks;
}

function makeEnv(withKey = true) {
  const env: { DB: Db; BUNDLES: object; OPENROUTER_API_KEY?: string } = { DB: makeMigratedD1(), BUNDLES: makeBucket() };
  if (withKey) {
    env.OPENROUTER_API_KEY = API_KEY;
  }
  return env;
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
  return { waitUntil, passThroughOnException, props: {}, pending, settle };
}

function requestBody(transcript: string) {
  return { transcript, now: NOW, timeZone: ZONE, locale: "en-US", sidekicks: sidekicksSentByPhone(), app: { version: "0.1.0", build: "4", ios: "26.1", device: "iPhone17,1" }, listenMs: 2100 };
}

async function post(env: object, token: string | null, path: string, body: unknown) {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token !== null) {
    headers.Authorization = `Bearer ${token}`;
  }
  const executionContext = makeExecutionContext();
  const response = await app.request(path, { method: "POST", headers, body: JSON.stringify(body) }, env, executionContext as unknown as ExecutionContext);
  await executionContext.settle();
  return response;
}

function toolCallAnswer(name: string, argumentsValue: unknown) {
  const payload = { choices: [{ message: { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name, arguments: JSON.stringify(argumentsValue) } }] } }] };
  return new Response(JSON.stringify(payload), { status: 200, headers: { "content-type": "application/json" } });
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

describe("POST /voice/jess", () => {
  it("answers done with the checked call, and logs the tool and its arguments", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "u1", ["reminders", "care-reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("reminders__complete", { item: "Call Mom" }));
    const response = await post(env, token, "/voice/jess", requestBody("mark call mom as done"));
    expect(response.status).toBe(200);
    const reply = (await response.json()) as Record<string, unknown>;
    expect(reply).toMatchObject({ status: "done", sidekickId: "reminders", tool: "reminders.complete", input: { item: "Call Mom" } });
    expect(typeof reply.logId).toBe("string");

    const [calledUrl, calledInit] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(calledUrl).toBe(OPENROUTER_URL);
    expect(JSON.parse(String(calledInit.body)).tool_choice).toBe("required");

    const rows = logRows(env.DB);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ id: reply.logId, user_id: "u1", endpoint: "jess", status: "done", sidekick_id: "reminders", tool: "reminders.complete", transcript: "mark call mom as done", model: "deepseek/deepseek-v4-flash", phone_outcome: null });
    expect(JSON.parse(String(rows[0].tool_input))).toEqual({ item: "Call Mom" });
    expect(String(rows[0].lists)).not.toContain("Call Mom");
  });

  it("queues a repair for the repair agent at once, with the person's words", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "u1", ["reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("midas__repair_request", { sidekick: "reminders", kind: "change", request: "bigger colours" }));
    const response = await post(env, token, "/voice/jess", { ...requestBody("make the reminders list colours bigger"), sidekicks: [sidekicksSentByPhone()[0]] });
    const reply = (await response.json()) as Record<string, unknown>;
    expect(reply).toMatchObject({ status: "repair", sidekickId: "reminders" });
    const reports = env.DB.query("SELECT * FROM repair_reports") as Array<Record<string, unknown>>;
    expect(reports).toHaveLength(1);
    expect(reports[0]).toMatchObject({ id: reply.reportId, user_id: "u1", sidekick_id: "reminders", kind: "change", transcript: "make the reminders list colours bigger", status: "queued", bundle_version: "v5", screenshot_key: null });
    const events = env.DB.query("SELECT audience, kind FROM repair_events WHERE report_id = ?", reply.reportId) as Array<Record<string, unknown>>;
    expect(events).toEqual([{ audience: "founder", kind: "request_received" }]);
    expect(logRows(env.DB)[0]).toMatchObject({ status: "done", tool: "midas.repair_request", sidekick_id: "reminders" });
  });

  it("does not queue a repair for a Sidekick the user is not assigned", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "u1", ["care-reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("midas__repair_request", { sidekick: "reminders", kind: "bug", request: "x" }));
    const response = await post(env, token, "/voice/jess", requestBody("the done button is broken"));
    expect(await response.json()).toMatchObject({ status: "not-done", reason: "unknown-sidekick" });
    expect(env.DB.query("SELECT * FROM repair_reports")).toHaveLength(0);
  });

  it("is not done, with the transcript, when the model cannot act, and logs why", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "u1", ["reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("midas__cannot_act", { reason: "question" }));
    const response = await post(env, token, "/voice/jess", requestBody("what's the weather tomorrow"));
    expect(await response.json()).toMatchObject({ status: "not-done", reason: "question", transcript: "what's the weather tomorrow" });
    expect(logRows(env.DB)[0]).toMatchObject({ status: "not-done", reason: "question", tool: null });
  });

  it("is not done when there is no key or the model fails twice", async () => {
    const noKey = makeEnv(false);
    const token = addSignedInUser(noKey.DB, "u1", ["reminders"]);
    const keyless = await post(noKey, token, "/voice/jess", requestBody("add milk"));
    expect(await keyless.json()).toMatchObject({ status: "not-done", reason: "model-error" });
    expect(fetchMock).not.toHaveBeenCalled();

    const env = makeEnv();
    const otherToken = addSignedInUser(env.DB, "u2", ["reminders"]);
    fetchMock.mockResolvedValue(new Response("busy", { status: 503 }));
    const failed = await post(env, otherToken, "/voice/jess", requestBody("add milk"));
    expect(await failed.json()).toMatchObject({ status: "not-done", reason: "model-error" });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(logRows(env.DB)[0]).toMatchObject({ retries: 1, status: "not-done" });
  });

  it("refuses a bad body and a signed-out caller", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "u1", ["reminders"]);
    expect((await post(env, token, "/voice/jess", { ...requestBody("add milk"), sidekicks: [] })).status).toBe(400);
    expect((await post(env, token, "/voice/jess", { ...requestBody(""), transcript: "" })).status).toBe(400);
    expect((await post(env, null, "/voice/jess", requestBody("add milk"))).status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("records what the phone did, once, only on the user's own row", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "u1", ["reminders"]);
    const otherToken = addSignedInUser(env.DB, "u2", ["reminders"]);
    fetchMock.mockResolvedValue(toolCallAnswer("reminders__delete", { item: "Dentist" }));
    const reply = (await (await post(env, token, "/voice/jess", requestBody("delete the dentist"))).json()) as { logId: string };

    expect((await post(env, otherToken, "/voice/jess/outcome", { logId: reply.logId, outcome: "applied" })).status).toBe(404);
    expect((await post(env, token, "/voice/jess/outcome", { logId: reply.logId, outcome: "maybe" })).status).toBe(400);
    expect((await post(env, token, "/voice/jess/outcome", { logId: reply.logId, outcome: "refused", reason: "ambiguous" })).status).toBe(200);
    expect(logRows(env.DB)[0].phone_outcome).toBe("refused:ambiguous");
    expect((await post(env, token, "/voice/jess/outcome", { logId: reply.logId, outcome: "applied" })).status).toBe(404);
    expect(logRows(env.DB)[0].phone_outcome).toBe("refused:ambiguous");
  });
});
