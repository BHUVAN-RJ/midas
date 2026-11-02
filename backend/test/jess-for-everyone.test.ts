import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { EXPECTED_ORIGIN, RELYING_PARTY_ID } from "../src/auth";
import { JESS_LISTING, JESS_SIDEKICK_ID } from "../src/jess-sidekick";
import { assignToEveryoneSql } from "../scripts/db-tools.mjs";
import { makeMigratedD1 } from "./helpers/migrated-d1";
import { makeSoftAuthenticator } from "./helpers/soft-authenticator";

// jess for everyone (founder, 2026-10-22; docs/PRODUCT.md "jess in the background, one result
// card, jess for everyone"): a "jess" Sidekick on every user's home, assigned at sign-up and to
// every existing user by scripts/assign-jess-to-everyone.mjs. Built into the shell, not a web
// bundle: listed from a constant, first, with no bundle, no tools and nothing to repair.

const REMINDERS_MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] };

function makeFakeBucket(objectsByKey: Record<string, string>) {
  async function getObject(key: string) {
    if (!(key in objectsByKey)) {
      return null;
    }
    const objectText = objectsByKey[key];
    return {
      body: new Response(objectText).body,
      json: async () => JSON.parse(objectText),
      text: async () => objectText,
    };
  }
  async function listObjects() {
    return { objects: [] };
  }
  async function putObject() {
    return null;
  }
  return { get: getObject, list: listObjects, put: putObject };
}

function makeEnv() {
  const bucket = makeFakeBucket({
    "sidekicks/reminders/current.json": JSON.stringify({ version: "v2", scriptHashes: [] }),
    "sidekicks/reminders/v2/index.html": "<p>reminders</p>",
    "sidekicks/reminders/v2/manifest.json": JSON.stringify(REMINDERS_MANIFEST),
  });
  return { DB: makeMigratedD1(), BUNDLES: bucket };
}

type TestEnv = ReturnType<typeof makeEnv>;
type CatalogReply = { sidekicks: Array<Record<string, unknown>> };
type OptionsReply = { challengeId: string; options: { challenge: string; user: { id: string; name: string } } };
type SessionReply = { token: string; user: { id: string; name: string } };

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

// A user who signed up before jess existed: a session and no jess row.
function addExistingUser(env: TestEnv, userId: string, name: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, name);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

function assign(env: TestEnv, userId: string, sidekickId: string, assignedAt: string) {
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, ?)", userId, sidekickId, assignedAt);
}

function jessRows(env: TestEnv, userId: string) {
  return env.DB.query("SELECT sidekick_id FROM assignments WHERE user_id = ? AND sidekick_id = ?", userId, JESS_SIDEKICK_ID);
}

async function postJson(env: TestEnv, path: string, body: unknown) {
  const requestInit = { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) };
  return app.request(path, requestInit, env);
}

async function signUp(env: TestEnv, name: string): Promise<SessionReply> {
  const authenticator = await makeSoftAuthenticator({ rpId: RELYING_PARTY_ID, origin: EXPECTED_ORIGIN });
  const optionsResponse = await postJson(env, "/auth/register/options", { name });
  const optionsReply = (await optionsResponse.json()) as OptionsReply;
  const credential = await authenticator.register(optionsReply.options);
  const verifyResponse = await postJson(env, "/auth/register/verify", { challengeId: optionsReply.challengeId, credential });
  expect(verifyResponse.status).toBe(200);
  return (await verifyResponse.json()) as SessionReply;
}

function authorized(token: string) {
  return { headers: { Authorization: `Bearer ${token}` } };
}

async function listedIds(env: TestEnv, token: string): Promise<unknown[]> {
  const response = await app.request("/sidekicks", authorized(token), env);
  expect(response.status).toBe(200);
  const body = (await response.json()) as CatalogReply;
  const ids: unknown[] = [];
  for (const listing of body.sidekicks) {
    ids.push(listing.id);
  }
  return ids;
}

describe("jess at sign-up", () => {
  it("assigns jess to a new user in the same step that creates them", async () => {
    const env = makeEnv();
    const session = await signUp(env, "Priya");
    expect(jessRows(env, session.user.id)).toHaveLength(1);
    // Reminders is a starter (founder, 2026-11-01) and the only one with a page in this fake bucket.
    expect(await listedIds(env, session.token)).toEqual(["jess", "make", "reminders"]);
  });

  it("lists jess from the built-in listing, with no bundle behind it", async () => {
    const env = makeEnv();
    const session = await signUp(env, "Sam");
    const response = await app.request("/sidekicks", authorized(session.token), env);
    const body = (await response.json()) as CatalogReply;
    expect(body.sidekicks[0]).toEqual(JESS_LISTING);
    expect(body.sidekicks[0]).toMatchObject({ id: "jess", name: "jess", version: "built-in", builtIn: true });
  });
});

describe("jess for every existing user", () => {
  it("the script's statement gives every user jess, once, and keeps their other Sidekicks", () => {
    const env = makeEnv();
    addExistingUser(env, "u-priya", "Priya");
    addExistingUser(env, "u-sam", "Sam");
    assign(env, "u-priya", "reminders", "2026-10-11T09:00:00.000Z");
    expect(jessRows(env, "u-priya")).toHaveLength(0);

    const sql = assignToEveryoneSql(JESS_SIDEKICK_ID, new Date("2026-10-22T18:00:00.000Z"));
    env.DB.execute(sql);
    env.DB.execute(sql);

    expect(jessRows(env, "u-priya")).toHaveLength(1);
    expect(jessRows(env, "u-sam")).toHaveLength(1);
    const priyaRows = env.DB.query("SELECT sidekick_id FROM assignments WHERE user_id = ? ORDER BY sidekick_id", "u-priya");
    expect(priyaRows).toEqual([{ sidekick_id: "jess" }, { sidekick_id: "reminders" }]);
  });

  it("lists jess first, whatever the assignment order, then the others in their order", async () => {
    const env = makeEnv();
    const token = addExistingUser(env, "u-priya", "Priya");
    assign(env, "u-priya", "reminders", "2026-10-11T09:00:00.000Z");
    expect(await listedIds(env, token)).toEqual(["reminders"]);
    assign(env, "u-priya", "jess", "2026-10-22T18:00:00.000Z");
    expect(await listedIds(env, token)).toEqual(["jess", "reminders"]);
  });

  it("the script runs on the environment named and only inserts", () => {
    const script = readFileSync(new URL("../scripts/assign-jess-to-everyone.mjs", import.meta.url), "utf8");
    expect(script).toContain("environmentFromArgs");
    expect(script).toContain("assignToEveryoneSql");
    expect(script).not.toMatch(/DELETE|UPDATE|DROP/);
    expect(assignToEveryoneSql("jess", new Date("2026-10-22T18:00:00.000Z"))).toBe(
      "INSERT OR IGNORE INTO assignments (user_id, sidekick_id, assigned_at) SELECT id, 'jess', '2026-10-22T18:00:00.000Z' FROM users",
    );
  });
});

describe("jess is built in", () => {
  it("has no bundle and no tools to load", async () => {
    const env = makeEnv();
    const session = await signUp(env, "Priya");
    const bundle = await app.request("/sidekicks/jess/bundle", authorized(session.token), env);
    const tools = await app.request("/sidekicks/jess/tools", authorized(session.token), env);
    expect(bundle.status).toBe(404);
    expect(tools.status).toBe(404);
  });
});
