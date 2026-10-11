import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// GET /sidekicks and GET /sidekicks/:id/bundle: a session is required, and a user sees and
// loads only the Sidekicks assigned to them (2026-10-10, D5).

const REMINDERS_HTML = "<!doctype html><title>Reminders</title><script>document.title='ok'</script>";
const REMINDERS_MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] };
const CALENDAR_MANIFEST = { id: "calendar", name: "Calendar", icon: { symbol: "calendar", background: "#FF3B30" }, reads: ["reminder"] };

function makeFakeBucket(objectsByKey: Record<string, string>) {
  async function getObject(key: string) {
    if (!(key in objectsByKey)) {
      return null;
    }
    const objectText = objectsByKey[key];
    return {
      body: new Response(objectText).body,
      json: async () => JSON.parse(objectText),
    };
  }
  async function listObjects() {
    return { objects: [] };
  }
  return { get: getObject, list: listObjects };
}

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function makeEnv() {
  const bucket = makeFakeBucket({
    "sidekicks/reminders/current.json": JSON.stringify({ version: "v2", scriptHashes: ["'sha256-AAA='", "'sha256-BBB='"] }),
    "sidekicks/reminders/v1/index.html": "<p>old</p>",
    "sidekicks/reminders/v1/manifest.json": JSON.stringify({ ...REMINDERS_MANIFEST, name: "Old Reminders" }),
    "sidekicks/reminders/v2/index.html": REMINDERS_HTML,
    "sidekicks/reminders/v2/manifest.json": JSON.stringify(REMINDERS_MANIFEST),
    "sidekicks/calendar/current.json": JSON.stringify({ version: "c1", scriptHashes: [] }),
    "sidekicks/calendar/c1/index.html": "<p>calendar</p>",
    "sidekicks/calendar/c1/manifest.json": JSON.stringify(CALENDAR_MANIFEST),
    "sidekicks/broken/current.json": JSON.stringify({ version: "v9", scriptHashes: [] }),
  });
  const db = makeMigratedD1();
  return { DB: db, BUNDLES: bucket };
}

type TestEnv = ReturnType<typeof makeEnv>;

// Seeds a user with a live session directly, as /auth/register/verify would leave them.
function addSignedInUser(env: TestEnv, userId: string, name: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, name);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

function assign(env: TestEnv, userId: string, sidekickId: string, assignedAt: string) {
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, ?)", userId, sidekickId, assignedAt);
}

function authorized(token: string) {
  return { headers: { Authorization: `Bearer ${token}` } };
}

type CatalogReply = { sidekicks: Array<Record<string, unknown>> };

describe("GET /sidekicks", () => {
  it("requires a session", async () => {
    const env = makeEnv();
    const noSession = await app.request("/sidekicks", {}, env);
    const madeUpSession = await app.request("/sidekicks", authorized("nope"), env);
    expect(noSession.status).toBe(401);
    expect(madeUpSession.status).toBe(401);
  });

  it("returns only the user's assigned Sidekicks, in assignment order, with the current manifest", async () => {
    const env = makeEnv();
    const priyaToken = addSignedInUser(env, "u-priya", "Priya");
    addSignedInUser(env, "u-sam", "Sam");
    assign(env, "u-priya", "calendar", "2026-10-11T10:00:00.000Z");
    assign(env, "u-priya", "reminders", "2026-10-11T09:00:00.000Z");
    assign(env, "u-sam", "broken", "2026-10-11T09:00:00.000Z");

    const response = await app.request("/sidekicks", authorized(priyaToken), env);
    expect(response.status).toBe(200);
    const body = (await response.json()) as CatalogReply;
    expect(body.sidekicks).toEqual([
      { ...REMINDERS_MANIFEST, version: "v2" },
      { ...CALENDAR_MANIFEST, version: "c1" },
    ]);
  });

  it("is empty for a user with no assignments", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-new", "New Friend");
    const response = await app.request("/sidekicks", authorized(token), env);
    expect(await response.json()).toEqual({ sidekicks: [] });
  });

  it("leaves out an assigned Sidekick that has no manifest or was never deployed", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "broken", "2026-10-11T08:00:00.000Z");
    assign(env, "u-priya", "never-deployed", "2026-10-11T08:30:00.000Z");
    assign(env, "u-priya", "reminders", "2026-10-11T09:00:00.000Z");
    const response = await app.request("/sidekicks", authorized(token), env);
    const body = (await response.json()) as CatalogReply;
    const ids = body.sidekicks.map(sidekickIdOf);
    expect(ids).toEqual(["reminders"]);
  });
});

function sidekickIdOf(listing: Record<string, unknown>): unknown {
  return listing.id;
}

describe("GET /sidekicks/:id/bundle", () => {
  it("requires a session", async () => {
    const env = makeEnv();
    const response = await app.request("/sidekicks/reminders/bundle", {}, env);
    expect(response.status).toBe(401);
  });

  it("serves the current version's html and script hashes to an assigned user", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "reminders", "2026-10-11T09:00:00.000Z");
    const response = await app.request("/sidekicks/reminders/bundle", authorized(token), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
    expect(response.headers.get("X-Midas-Bundle-Version")).toBe("v2");
    expect(response.headers.get("X-Midas-Script-Hashes")).toBe("'sha256-AAA=' 'sha256-BBB='");
    expect(await response.text()).toBe(REMINDERS_HTML);
  });

  it("answers 404 for a deployed Sidekick that is not assigned to the user", async () => {
    const env = makeEnv();
    const samToken = addSignedInUser(env, "u-sam", "Sam");
    addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "reminders", "2026-10-11T09:00:00.000Z");
    const response = await app.request("/sidekicks/reminders/bundle", authorized(samToken), env);
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "no such sidekick" });
  });

  it("answers 404 for an assigned Sidekick that was never deployed", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "nope", "2026-10-11T09:00:00.000Z");
    const response = await app.request("/sidekicks/nope/bundle", authorized(token), env);
    expect(response.status).toBe(404);
  });

  it("rejects ids that could escape the sidekick prefix", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    const response = await app.request("/sidekicks/..%2Fsecrets/bundle", authorized(token), env);
    expect(response.status).toBe(400);
  });

  it("returns 500 when the pointer names a version that is not stored", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "broken", "2026-10-11T09:00:00.000Z");
    const response = await app.request("/sidekicks/broken/bundle", authorized(token), env);
    expect(response.status).toBe(500);
  });
});
