// A tool may keep the jess request's photo (founder, 2026-11-08: Money keeps a receipt with its
// expense). jess stays general: the router offers every assigned Sidekick's tools, and a receipt
// photo lands on money.add_expense because of Money's agent block and tool descriptions. The
// tool's _meta["midas/photo"] names a field the model never sees; when that tool is chosen for a
// request with a photo, the server stores the photo as the user's file and puts "file:<id>" in
// that field. Every other request keeps "the photo is never stored".
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const NOW = "2026-11-08T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");
const PHOTO_BYTES = Buffer.from("\xFF\xD8\xFF a receipt, standing in for JPEG bytes", "latin1");
const PHOTO_DATA = PHOTO_BYTES.toString("base64");
const SIDEKICK_IDS = ["money", "todo", "reminders"];

type Db = ReturnType<typeof makeMigratedD1>;
type Env = { DB: Db; BUNDLES: ReturnType<typeof makeFakeR2>; FILES?: ReturnType<typeof makeFakeR2>; OPENROUTER_API_KEY: string };

function manifestText(sidekickId: string): string {
  return readFileSync(join(REPO_ROOT, "sidekicks", sidekickId, "manifest.json"), "utf8");
}

function makeBundles() {
  const seed: Record<string, string> = {};
  for (const sidekickId of SIDEKICK_IDS) {
    seed[`sidekicks/${sidekickId}/current.json`] = JSON.stringify({ version: "v1", scriptHashes: [], contentHash: "h-" + sidekickId, baseVersion: null, tools: "tools.js" });
    seed[`sidekicks/${sidekickId}/v1/manifest.json`] = manifestText(sidekickId);
  }
  return makeFakeR2(seed);
}

function makeEnv(withFiles = true): Env {
  const env: Env = { DB: makeMigratedD1(), BUNDLES: makeBundles(), OPENROUTER_API_KEY: "sk-or-test" };
  if (withFiles) {
    env.FILES = makeFakeR2();
  }
  return env;
}

function signIn(db: Db, userId: string): string {
  const token = `token-${userId}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  db.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  db.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", tokenHash, userId, Date.now() + 3_600_000);
  for (const sidekickId of SIDEKICK_IDS) {
    db.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, 'now')", userId, sidekickId);
  }
  return token;
}

async function ask(env: object, token: string, extra: Record<string, unknown>) {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  const executionContext = { waitUntil, passThroughOnException, props: {} };
  const sidekicks = [
    { id: "money", context: { currency: "USD", thisMonth: "$0.00", byCategory: [], recent: [], merchantCategories: {}, categories: [] } },
    { id: "todo", context: { lists: [], today: [] } },
    { id: "reminders", context: { lists: [], items: [] } },
  ];
  const body = { now: NOW, timeZone: ZONE, locale: "en-US", sidekicks, ...extra };
  const init: RequestInit = { method: "POST", headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(body) };
  const response = await app.request("/voice/jess", init, env, executionContext as unknown as ExecutionContext);
  await Promise.all(pending);
  return response;
}

function modelAnswer(toolName: string, argumentsValue: Record<string, unknown>) {
  function reply() {
    const message = { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name: toolName, arguments: JSON.stringify(argumentsValue) } }] };
    return new Response(JSON.stringify({ choices: [{ message }] }), { status: 200, headers: { "content-type": "application/json" } });
  }
  return reply;
}

const RECEIPT_CALL = { amount: 38.5, merchant: "Noodle Bar", date: "2026-11-05", daysAgo: null, category: "Dining", items: [{ name: "Spicy Ramen", amount: 16, quantity: 1 }], tax: 3.2, tip: 6.8 };

let fetchMock: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  fetchMock = vi.spyOn(globalThis, "fetch");
  fetchMock.mockImplementation(modelAnswer("money__add_expense", RECEIPT_CALL));
});

afterEach(() => {
  fetchMock.mockRestore();
});

function sentModelBody(): Record<string, unknown> {
  const init = fetchMock.mock.calls[0][1] as RequestInit;
  return JSON.parse(String(init.body)) as Record<string, unknown>;
}

type WireTool = { function: { name: string; description: string; parameters: { properties: Record<string, unknown> } } };

describe("routing a receipt photo with Money, To-Do and Reminders assigned", () => {
  it("offers money.add_expense beside the other Sidekicks' tools, without the photo field", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    await ask(env, token, { transcript: "", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    const sent = sentModelBody();
    const tools = sent.tools as WireTool[];
    const names = tools.map(function nameOf(tool) { return tool.function.name; });
    expect(names).toContain("money__add_expense");
    expect(names.some(function isTodo(name) { return name.startsWith("todo__"); })).toBe(true);
    expect(names.some(function isReminders(name) { return name.startsWith("reminders__"); })).toBe(true);
    const addTool = tools.find(function isAdd(tool) { return tool.function.name === "money__add_expense"; })!;
    expect(Object.keys(addTool.function.parameters.properties)).not.toContain("receipt");
    expect(addTool.function.description).toContain("receipt");
  });

  it("carries Money's receipt rules in the prompt: the total paid, no invented date, US month first", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    await ask(env, token, { transcript: "", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    const messages = sentModelBody().messages as Array<{ content: unknown }>;
    const system = String(messages[0].content);
    expect(system).toContain("## Sidekick money");
    expect(system).toContain("never a suggested-tip line");
    expect(system).toContain("Never invent a date");
    expect(system).toContain("US receipts print the month first");
  });

  it("stores the photo as the user's file and hands file:<id> to money.add_expense", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const response = await ask(env, token, { transcript: "", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    const reply = (await response.json()) as { status: string; tool: string; input: Record<string, unknown> };
    expect(reply.status).toBe("done");
    expect(reply.tool).toBe("money.add_expense");
    expect(reply.input.amount).toBe(38.5);
    const receipt = String(reply.input.receipt);
    expect(receipt).toMatch(/^file:[A-Za-z0-9_-]{8,64}$/);
    const stored = await env.FILES!.get("u1/" + receipt.slice("file:".length));
    expect(stored).not.toBeNull();
    expect(new Uint8Array(await stored!.arrayBuffer())).toEqual(new Uint8Array(PHOTO_BYTES));
    expect(stored!.httpMetadata.contentType).toBe("image/jpeg");
  });

  it("the stored photo is served to its owner only, through GET /files", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const otherToken = signIn(env.DB, "u2");
    const response = await ask(env, token, { transcript: "", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    const reply = (await response.json()) as { input: Record<string, unknown> };
    const fileId = String(reply.input.receipt).slice("file:".length);
    const own = await app.request(`/files/${fileId}`, { headers: { Authorization: `Bearer ${token}` } }, env);
    const other = await app.request(`/files/${fileId}`, { headers: { Authorization: `Bearer ${otherToken}` } }, env);
    expect(own.status).toBe(200);
    expect(other.status).toBe(404);
  });

  it("logs the file reference, never the photo", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    await ask(env, token, { transcript: "", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    const logged = env.DB.query("SELECT * FROM voice_logs");
    expect(logged).toHaveLength(1);
    expect(String(logged[0].tool_input)).toMatch(/"receipt":"file:/);
    expect(JSON.stringify(logged[0])).not.toContain(PHOTO_DATA);
  });

  it("answers a second send of the same request with the same file, storing it once", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const requestId = "6f0b7e1c-3a52-4b8e-9d2f-0c1a2b3c4d5e";
    const first = (await (await ask(env, token, { transcript: "", requestId, photo: { mediaType: "image/jpeg", data: PHOTO_DATA } })).json()) as { input: Record<string, unknown> };
    const second = (await (await ask(env, token, { transcript: "", requestId, photo: { mediaType: "image/jpeg", data: PHOTO_DATA } })).json()) as { input: Record<string, unknown> };
    expect(second.input.receipt).toBe(first.input.receipt);
    const listed = await env.FILES!.list({ prefix: "u1/" });
    expect(listed.objects).toHaveLength(1);
  });
});

describe("the photo stays unstored everywhere else", () => {
  it("is not stored when the chosen tool keeps no photo", async () => {
    fetchMock.mockImplementation(modelAnswer("midas__cannot_act", { reason: "not-confident" }));
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    await ask(env, token, { transcript: "", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    expect((await env.FILES!.list({ prefix: "" })).objects).toHaveLength(0);
  });

  it("is not stored for a request without a photo, and add_expense gets no receipt", async () => {
    fetchMock.mockImplementation(modelAnswer("money__add_expense", { ...RECEIPT_CALL, items: null, tax: null, tip: null, date: null }));
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const response = await ask(env, token, { transcript: "I spent 38.50 at Noodle Bar" });
    const reply = (await response.json()) as { status: string; input: Record<string, unknown> };
    expect(reply.status).toBe("done");
    expect(reply.input.receipt).toBeUndefined();
    expect((await env.FILES!.list({ prefix: "" })).objects).toHaveLength(0);
  });

  it("never takes a receipt value from the model", async () => {
    fetchMock.mockImplementation(modelAnswer("money__add_expense", { ...RECEIPT_CALL, receipt: "file:someoneelses01" }));
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const response = await ask(env, token, { transcript: "add this" });
    const reply = (await response.json()) as { status: string; reason?: string; input?: Record<string, unknown> };
    expect(reply.status).toBe("not-done");
    expect(reply.reason).toBe("bad-arguments");
  });

  it("is not stored when files are not set up; the expense is still added, without a receipt", async () => {
    const env = makeEnv(false);
    const token = signIn(env.DB, "u1");
    const response = await ask(env, token, { transcript: "", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    const reply = (await response.json()) as { status: string; input: Record<string, unknown> };
    expect(reply.status).toBe("done");
    expect(reply.input.receipt).toBeUndefined();
  });
});
