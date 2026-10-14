import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Per-user Sidekick copies (repair, founder 2026-10-13). Every user has their own copy under
// sidekicks/<id>/users/<user_id>/; a repair moves one user's pointer only. The base at
// sidekicks/<id>/ is the founder's and is never written by a user's load or deploy.

const BASE_HTML = "<!doctype html><title>Reminders</title><script>document.title='base'</script>";
const AMOGH_HTML = "<!doctype html><title>Reminders</title><script>document.title='fixed for Amogh'</script>";
const BASE_MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] };
const AMOGH_MANIFEST = { ...BASE_MANIFEST, name: "Reminders (Amogh)" };

// A fake R2 bucket that records writes, so a test can see exactly which keys a load touched.
function makeRecordingBucket(objectsByKey: Record<string, string>) {
  const store: Record<string, string> = { ...objectsByKey };
  const writtenKeys: string[] = [];
  async function getObject(key: string) {
    if (!(key in store)) {
      return null;
    }
    const objectText = store[key];
    return {
      body: new Response(objectText).body,
      json: async () => JSON.parse(objectText),
    };
  }
  async function putObject(key: string, body: ReadableStream | string) {
    const text = typeof body === "string" ? body : await new Response(body).text();
    store[key] = text;
    writtenKeys.push(key);
  }
  async function listObjects() {
    return { objects: [] };
  }
  return { get: getObject, put: putObject, list: listObjects, store, writtenKeys };
}

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function makeEnv() {
  const bucket = makeRecordingBucket({
    "sidekicks/reminders/current.json": JSON.stringify({ version: "b2", scriptHashes: ["'sha256-BASE='"], contentHash: "hash-b2", baseVersion: null }),
    "sidekicks/reminders/b1/index.html": "<p>old base</p>",
    "sidekicks/reminders/b1/manifest.json": JSON.stringify({ ...BASE_MANIFEST, name: "Old Reminders" }),
    "sidekicks/reminders/b2/index.html": BASE_HTML,
    "sidekicks/reminders/b2/manifest.json": JSON.stringify(BASE_MANIFEST),
    // Amogh's copy: repaired on top of base b2.
    "sidekicks/reminders/users/u-amogh/current.json": JSON.stringify({ version: "a9", scriptHashes: ["'sha256-AMOGH='"], contentHash: "hash-a9", baseVersion: "b2" }),
    "sidekicks/reminders/users/u-amogh/b2/index.html": BASE_HTML,
    "sidekicks/reminders/users/u-amogh/b2/manifest.json": JSON.stringify(BASE_MANIFEST),
    "sidekicks/reminders/users/u-amogh/a9/index.html": AMOGH_HTML,
    "sidekicks/reminders/users/u-amogh/a9/manifest.json": JSON.stringify(AMOGH_MANIFEST),
    // A copy whose pointer names a version that was never stored.
    "sidekicks/reminders/users/u-broken/current.json": JSON.stringify({ version: "gone", scriptHashes: [] }),
  });
  const db = makeMigratedD1();
  return { DB: db, BUNDLES: bucket };
}

type TestEnv = ReturnType<typeof makeEnv>;

function addSignedInUser(env: TestEnv, userId: string, name: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, name);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

function assign(env: TestEnv, userId: string, sidekickId: string) {
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, ?)", userId, sidekickId, "2026-10-13T09:00:00.000Z");
}

function authorized(token: string) {
  return { headers: { Authorization: `Bearer ${token}` } };
}

type CatalogReply = { sidekicks: Array<Record<string, unknown>> };

describe("GET /sidekicks/:id/bundle with per-user copies", () => {
  it("serves the user's own copy when they have one", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-amogh", "Amogh");
    assign(env, "u-amogh", "reminders");
    const response = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("X-Midas-Bundle-Version")).toBe("a9");
    expect(response.headers.get("X-Midas-Script-Hashes")).toBe("'sha256-AMOGH='");
    expect(response.headers.get("X-Midas-Bundle-Scope")).toBe("user");
    expect(await response.text()).toBe(AMOGH_HTML);
    // Serving an existing copy writes nothing.
    expect(env.BUNDLES.writtenKeys).toEqual([]);
  });

  it("serves the base to a user without a copy and does not give them another user's repair", async () => {
    const env = makeEnv();
    const priyaToken = addSignedInUser(env, "u-priya", "Priya");
    addSignedInUser(env, "u-amogh", "Amogh");
    assign(env, "u-priya", "reminders");
    assign(env, "u-amogh", "reminders");
    const response = await app.request("/sidekicks/reminders/bundle", authorized(priyaToken), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("X-Midas-Bundle-Version")).toBe("b2");
    expect(response.headers.get("X-Midas-Script-Hashes")).toBe("'sha256-BASE='");
    expect(response.headers.get("X-Midas-Bundle-Scope")).toBe("base");
    expect(await response.text()).toBe(BASE_HTML);
  });

  it("copies the base into the user's own store on their first load, and never writes the base", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "reminders");
    await app.request("/sidekicks/reminders/bundle", authorized(token), env);

    expect(env.BUNDLES.writtenKeys).toEqual([
      "sidekicks/reminders/users/u-priya/b2/index.html",
      "sidekicks/reminders/users/u-priya/b2/manifest.json",
      "sidekicks/reminders/users/u-priya/b2/version.json",
      "sidekicks/reminders/users/u-priya/current.json",
    ]);
    expect(env.BUNDLES.store["sidekicks/reminders/users/u-priya/b2/index.html"]).toBe(BASE_HTML);
    const pointer = JSON.parse(env.BUNDLES.store["sidekicks/reminders/users/u-priya/current.json"]);
    expect(pointer).toEqual({ version: "b2", scriptHashes: ["'sha256-BASE='"], contentHash: "hash-b2", baseVersion: "b2" });
    const versionRecord = JSON.parse(env.BUNDLES.store["sidekicks/reminders/users/u-priya/b2/version.json"]);
    expect(versionRecord.forUser).toBe("u-priya");
    expect(versionRecord.baseVersion).toBe("b2");

    // The second load is served from the copy and writes nothing more.
    const secondResponse = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(secondResponse.headers.get("X-Midas-Bundle-Scope")).toBe("user");
    expect(env.BUNDLES.writtenKeys).toHaveLength(4);
  });

  it("keeps a user on their copy when the base moves on", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-amogh", "Amogh");
    assign(env, "u-amogh", "reminders");
    // The founder deploys a new base.
    env.BUNDLES.store["sidekicks/reminders/current.json"] = JSON.stringify({ version: "b3", scriptHashes: [], contentHash: "hash-b3" });
    env.BUNDLES.store["sidekicks/reminders/b3/index.html"] = "<p>new base</p>";
    const response = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(response.headers.get("X-Midas-Bundle-Version")).toBe("a9");
    expect(await response.text()).toBe(AMOGH_HTML);
  });

  it("answers 404 when the Sidekick is not assigned, even if a copy exists", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-amogh", "Amogh");
    const response = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(response.status).toBe(404);
    expect(env.BUNDLES.writtenKeys).toEqual([]);
  });

  it("returns 500 when the user's pointer names a version that is not stored, instead of falling back to the base", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-broken", "Broken");
    assign(env, "u-broken", "reminders");
    const response = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(response.status).toBe(500);
  });

  it("still serves the base page when the copy cannot be written", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "reminders");
    async function failingPut() {
      throw new Error("R2 is down");
    }
    env.BUNDLES.put = failingPut;
    const response = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe(BASE_HTML);
  });
});

describe("GET /sidekicks with per-user copies", () => {
  it("lists each user's own version and manifest", async () => {
    const env = makeEnv();
    const amoghToken = addSignedInUser(env, "u-amogh", "Amogh");
    const priyaToken = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-amogh", "reminders");
    assign(env, "u-priya", "reminders");

    const amoghList = (await (await app.request("/sidekicks", authorized(amoghToken), env)).json()) as CatalogReply;
    const priyaList = (await (await app.request("/sidekicks", authorized(priyaToken), env)).json()) as CatalogReply;
    expect(amoghList.sidekicks).toEqual([{ ...AMOGH_MANIFEST, version: "a9" }]);
    expect(priyaList.sidekicks).toEqual([{ ...BASE_MANIFEST, version: "b2" }]);
    // Listing does not create a copy; the first bundle load does.
    expect(env.BUNDLES.writtenKeys).toEqual([]);
  });
});
