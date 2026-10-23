// POST /voice/jess with the tools read from the server's manifests (founder decisions 2026-10-21,
// jess router review, item 5): when the model cannot act, or there is no key, or the model fails
// twice, nothing is done, the transcript comes back for the home page card, and the attempt is
// logged with why.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const NOW = "2026-10-20T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");

type Db = ReturnType<typeof makeMigratedD1>;

function makeBucket() {
  const objectsByKey: Record<string, string> = {
    "sidekicks/reminders/current.json": JSON.stringify({ version: "b5", scriptHashes: [], contentHash: "hash-b5", baseVersion: null, tools: "tools.js" }),
    "sidekicks/reminders/b5/manifest.json": readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8"),
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

function makeEnv(withKey: boolean) {
  const env: { DB: Db; BUNDLES: ReturnType<typeof makeBucket>; OPENROUTER_API_KEY?: string } = { DB: makeMigratedD1(), BUNDLES: makeBucket() };
  if (withKey) {
    env.OPENROUTER_API_KEY = "sk-or-test";
  }
  return env;
}

function signIn(db: Db, userId: string): string {
  const token = `token-${userId}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  db.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  db.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", tokenHash, userId, Date.now() + 3_600_000);
  db.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'reminders', 'now')", userId);
  return token;
}

async function ask(env: object, token: string, transcript: string) {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  const executionContext = { waitUntil, passThroughOnException, props: {} };
  const body = { transcript, now: NOW, timeZone: ZONE, locale: "en-US", sidekicks: [{ id: "reminders", context: { lists: [], items: [] } }] };
  const init = { method: "POST", headers: { "content-type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify(body) };
  const response = await app.request("/voice/jess", init, env, executionContext as unknown as ExecutionContext);
  await Promise.all(pending);
  return response;
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

describe("POST /voice/jess when nothing can be done", () => {
  it("is not done, with the transcript, when the model cannot act, and logs why", async () => {
    const env = makeEnv(true);
    const token = signIn(env.DB, "u1");
    const payload = { choices: [{ message: { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name: "midas__cannot_act", arguments: JSON.stringify({ reason: "question" }) } }] } }] };
    fetchMock.mockResolvedValue(new Response(JSON.stringify(payload), { status: 200, headers: { "content-type": "application/json" } }));
    const response = await ask(env, token, "what's the weather tomorrow");
    expect(await response.json()).toMatchObject({ status: "not-done", reason: "question", transcript: "what's the weather tomorrow" });
    expect(logRows(env.DB)[0]).toMatchObject({ status: "not-done", reason: "question", tool: null, endpoint: "jess" });
  });

  it("is not done without a key (no call made), and after the model fails twice (one retry, logged)", async () => {
    const keyless = makeEnv(false);
    const keylessToken = signIn(keyless.DB, "u1");
    expect(await (await ask(keyless, keylessToken, "add milk")).json()).toMatchObject({ status: "not-done", reason: "model-error", transcript: "add milk" });
    expect(fetchMock).not.toHaveBeenCalled();

    const env = makeEnv(true);
    const token = signIn(env.DB, "u2");
    fetchMock.mockResolvedValue(new Response("busy", { status: 503 }));
    expect(await (await ask(env, token, "add milk")).json()).toMatchObject({ status: "not-done", reason: "model-error" });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(logRows(env.DB)[0]).toMatchObject({ retries: 1, status: "not-done", reason: "model-error" });
  });
});
