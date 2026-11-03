// jess's camera (founder, 2026-11-02, docs/mockups/jess-camera-2026-11-02.html): POST /voice/jess may
// carry a photo (JPEG, base64). A photo request goes to a model that reads images
// (JESS_PHOTO_MODEL) with the photo as an image part; words are optional with a photo; the photo
// is never logged; the privacy page says so.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { JESS_MODEL, JESS_PHOTO_MODEL, MAX_PHOTO_BASE64_LENGTH } from "../src/jess";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const NOW = "2026-11-02T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");
const REMINDERS_MANIFEST = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8");
// A few bytes standing in for a JPEG; only the shape matters to the server
const PHOTO_DATA = Buffer.from("not really a jpeg but base64 all the same").toString("base64");

type Db = ReturnType<typeof makeMigratedD1>;

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

function makeEnv() {
  const env: Record<string, unknown> = { DB: makeMigratedD1(), BUNDLES: makeBucket(), OPENROUTER_API_KEY: "sk-or-test" };
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

async function ask(env: object, token: string, extra: Record<string, unknown>) {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  const executionContext = { waitUntil, passThroughOnException, props: {} };
  const body = { now: NOW, timeZone: ZONE, locale: "en-US", sidekicks: [{ id: "reminders", context: { lists: [], items: [] } }], ...extra };
  const init: RequestInit = { method: "POST", headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(body) };
  const response = await app.request("/voice/jess", init, env, executionContext as unknown as ExecutionContext);
  await Promise.all(pending);
  return response;
}

function answerNotSure() {
  const message = { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name: "midas__repair_request", arguments: JSON.stringify({ sidekick: "reminders", kind: "change", request: "x" }) } }] };
  return new Response(JSON.stringify({ choices: [{ message }] }), { status: 200, headers: { "content-type": "application/json" } });
}

let fetchMock: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  fetchMock = vi.spyOn(globalThis, "fetch");
  fetchMock.mockImplementation(answerNotSure);
});

afterEach(() => {
  fetchMock.mockRestore();
});

function sentModelBody(): Record<string, unknown> {
  const call = fetchMock.mock.calls[0];
  const init = call[1] as RequestInit;
  return JSON.parse(String(init.body)) as Record<string, unknown>;
}

describe("a request with a photo", () => {
  it("goes to the model that reads images, with the photo as an image part", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const response = await ask(env, token, { transcript: "add this", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    expect(response.status).toBe(200);
    const sent = sentModelBody();
    expect(sent.model).toBe(JESS_PHOTO_MODEL);
    const messages = sent.messages as Array<{ role: string; content: unknown }>;
    const userMessage = messages[1];
    expect(Array.isArray(userMessage.content)).toBe(true);
    const parts = userMessage.content as Array<Record<string, unknown>>;
    expect(parts[0]).toEqual({ type: "text", text: JSON.stringify({ sentence: "add this", photo: true }) });
    expect(parts[1]).toEqual({ type: "image_url", image_url: { url: "data:image/jpeg;base64," + PHOTO_DATA } });
    expect(String(messages[0].content)).toContain("The person also sent a photo");
  });

  it("needs no words", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const response = await ask(env, token, { transcript: "", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    expect(response.status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("is logged with the photo model and without the photo", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    await ask(env, token, { transcript: "add this", photo: { mediaType: "image/jpeg", data: PHOTO_DATA } });
    const logged = env.DB.query("SELECT * FROM voice_logs");
    expect(logged).toHaveLength(1);
    expect(logged[0].model).toBe(JESS_PHOTO_MODEL);
    expect(JSON.stringify(logged[0])).not.toContain(PHOTO_DATA);
  });
});

describe("a request without a photo", () => {
  it("stays on jess's text model with a plain sentence", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    await ask(env, token, { transcript: "remind me to call mom" });
    const sent = sentModelBody();
    expect(sent.model).toBe(JESS_MODEL);
    const messages = sent.messages as Array<{ role: string; content: unknown }>;
    expect(messages[1].content).toBe(JSON.stringify({ sentence: "remind me to call mom" }));
    expect(String(messages[0].content)).not.toContain("photo");
  });

  it("still needs words", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const response = await ask(env, token, { transcript: "" });
    expect(response.status).toBe(400);
  });
});

describe("a photo the server refuses", () => {
  it("is not a JPEG, is too big, or is not base64", async () => {
    const env = makeEnv();
    const token = signIn(env.DB, "u1");
    const png = await ask(env, token, { transcript: "x", photo: { mediaType: "image/png", data: PHOTO_DATA } });
    const tooBig = await ask(env, token, { transcript: "x", photo: { mediaType: "image/jpeg", data: "A".repeat(MAX_PHOTO_BASE64_LENGTH + 4) } });
    const notBase64 = await ask(env, token, { transcript: "x", photo: { mediaType: "image/jpeg", data: "<script>" } });
    expect(png.status).toBe(400);
    expect(tooBig.status).toBe(400);
    expect(notBase64.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("the privacy page", () => {
  it("says a photo goes to a model provider and is not kept", async () => {
    const response = await app.request("/privacy", {}, makeEnv());
    const page = await response.text();
    expect(page).toContain("Camera");
    expect(page).toContain("Midas does not keep the photo.");
  });
});
