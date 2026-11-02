import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { EXPECTED_ORIGIN, RELYING_PARTY_ID } from "../src/auth";
import { STARTER_SIDEKICK_IDS } from "../src/starter-sidekicks";
import { currentAgentListing } from "../src/sidekicks";
import { assignToEveryoneSql, assignmentCountsSql } from "../scripts/db-tools.mjs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";
import { makeSoftAuthenticator } from "./helpers/soft-authenticator";

// Starter Sidekicks (founder, 2026-11-01: "every account gets a to do, reminders, hydration"):
// Reminders, Water (id "hydration") and To-Do (id "todo") for every account besides jess and
// Make. New accounts at sign-up, in the same batch; existing accounts by
// scripts/assign-starter-sidekicks-to-everyone.mjs, which never gives back one a person deleted.
// A starter whose page is not deployed yet is assigned anyway and stays out of sight until it is.

const TIME = "2026-11-01T12:00:00.000Z";
const PRIYA = "u-priya";
const SAM = "u-sam";
const LENA = "u-lena";
const REMINDERS_MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [], types: {} };
const TODO_MANIFEST = { id: "todo", name: "To-Do", icon: { symbol: "checklist.checked", background: "#C9F24D" }, reads: [], types: {} };

// Only Reminders is deployed; Water and To-Do have no base yet.
function makeEnv() {
  const bundles = makeFakeR2({
    "sidekicks/reminders/current.json": JSON.stringify({ version: "r1", scriptHashes: [] }),
    "sidekicks/reminders/r1/index.html": "<p>reminders</p>",
    "sidekicks/reminders/r1/manifest.json": JSON.stringify(REMINDERS_MANIFEST),
  });
  return { DB: makeMigratedD1(), BUNDLES: bundles, FILES: makeFakeR2() };
}

type TestEnv = ReturnType<typeof makeEnv>;
type OptionsReply = { challengeId: string; options: { challenge: string; user: { id: string; name: string } } };
type SessionReply = { token: string; user: { id: string; name: string } };
type CatalogReply = { sidekicks: Array<Record<string, unknown>> };

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

async function deployTodoBase(env: TestEnv) {
  await env.BUNDLES.put("sidekicks/todo/t1/index.html", "<p>todo</p>");
  await env.BUNDLES.put("sidekicks/todo/t1/manifest.json", JSON.stringify(TODO_MANIFEST));
  await env.BUNDLES.put("sidekicks/todo/current.json", JSON.stringify({ version: "t1", scriptHashes: [] }));
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

// An account from before starters existed: a session, jess and Make, nothing else.
function addExistingUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', ?)", sha256Hex(token), userId, farFuture);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'jess', 'then')", userId);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'make', 'then')", userId);
  return token;
}

function authorized(token: string, method = "GET") {
  return { method, headers: { Authorization: `Bearer ${token}` } };
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

function assignmentRows(env: TestEnv, userId: string) {
  return env.DB.query("SELECT sidekick_id, removed_at FROM assignments WHERE user_id = ? ORDER BY sidekick_id", userId);
}

function assignedIds(env: TestEnv, userId: string): unknown[] {
  const ids: unknown[] = [];
  for (const row of assignmentRows(env, userId)) {
    ids.push(row.sidekick_id);
  }
  return ids;
}

function runStarterScriptSql(env: TestEnv) {
  for (const sidekickId of STARTER_SIDEKICK_IDS) {
    env.DB.execute(assignToEveryoneSql(sidekickId, new Date(TIME)));
  }
}

describe("starters at sign-up", () => {
  it("the starters are Reminders, Water and To-Do", () => {
    expect([...STARTER_SIDEKICK_IDS]).toEqual(["reminders", "hydration", "todo"]);
  });

  it("a new account gets jess, Make, Reminders, Water and To-Do", async () => {
    const env = makeEnv();
    const session = await signUp(env, "Priya");
    const ids = assignedIds(env, session.user.id);
    expect(ids).toEqual(["hydration", "jess", "make", "reminders", "todo"]);
  });

  it("a starter with no page deployed stays out of the list and its page answers 404, without breaking the rest", async () => {
    const env = makeEnv();
    const session = await signUp(env, "Sam");
    expect(await listedIds(env, session.token)).toEqual(["jess", "make", "reminders"]);
    const remindersPage = await app.request("/sidekicks/reminders/bundle", authorized(session.token), env);
    const todoPage = await app.request("/sidekicks/todo/bundle", authorized(session.token), env);
    const waterPage = await app.request("/sidekicks/hydration/bundle", authorized(session.token), env);
    expect(remindersPage.status).toBe(200);
    expect(todoPage.status).toBe(404);
    expect(waterPage.status).toBe(404);
    expect(await currentAgentListing(env.BUNDLES, "todo", session.user.id)).toBeNull();
  });

  it("a starter shows up for an account that already has it once its page is deployed, with nothing re-run", async () => {
    const env = makeEnv();
    const session = await signUp(env, "Lena");
    await deployTodoBase(env);
    expect(await listedIds(env, session.token)).toEqual(["jess", "make", "reminders", "todo"]);
    const todoPage = await app.request("/sidekicks/todo/bundle", authorized(session.token), env);
    expect(todoPage.status).toBe(200);
    expect(await todoPage.text()).toBe("<p>todo</p>");
  });

  it("a new account can delete a starter", async () => {
    const env = makeEnv();
    const session = await signUp(env, "Ana");
    const response = await app.request("/sidekicks/reminders", authorized(session.token, "DELETE"), env);
    expect(response.status).toBe(200);
    expect(await listedIds(env, session.token)).toEqual(["jess", "make"]);
  });
});

describe("starters for existing accounts", () => {
  it("gives every existing account the starters, and running it twice adds nothing", () => {
    const env = makeEnv();
    addExistingUser(env, PRIYA);
    addExistingUser(env, SAM);
    env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'reminders', 'earlier')", SAM);
    runStarterScriptSql(env);
    runStarterScriptSql(env);
    for (const userId of [PRIYA, SAM]) {
      const ids = assignedIds(env, userId);
      expect(ids).toEqual(["hydration", "jess", "make", "reminders", "todo"]);
    }
    // Sam's own Reminders row keeps its first assigned_at: insert only
    const samReminders = env.DB.query("SELECT assigned_at FROM assignments WHERE user_id = ? AND sidekick_id = 'reminders'", SAM);
    expect(samReminders).toEqual([{ assigned_at: "earlier" }]);
  });

  it("never gives back a starter a person deleted", async () => {
    const env = makeEnv();
    const token = addExistingUser(env, LENA);
    runStarterScriptSql(env);
    const deleteResponse = await app.request("/sidekicks/reminders", authorized(token, "DELETE"), env);
    expect(deleteResponse.status).toBe(200);
    runStarterScriptSql(env);
    const remindersRows = env.DB.query("SELECT removed_at FROM assignments WHERE user_id = ? AND sidekick_id = 'reminders'", LENA);
    expect(remindersRows).toHaveLength(1);
    expect(remindersRows[0].removed_at).not.toBeNull();
    expect(await listedIds(env, token)).toEqual(["jess", "make"]);
  });

  it("counts users, accounts that have it and accounts that deleted it", async () => {
    const env = makeEnv();
    addExistingUser(env, PRIYA);
    const samToken = addExistingUser(env, SAM);
    addExistingUser(env, LENA);
    runStarterScriptSql(env);
    await app.request("/sidekicks/reminders", authorized(samToken, "DELETE"), env);
    const remindersCounts = env.DB.query(assignmentCountsSql("reminders"));
    const todoCounts = env.DB.query(assignmentCountsSql("todo"));
    expect(remindersCounts).toEqual([{ users: 3, active: 2, removed: 1 }]);
    expect(todoCounts).toEqual([{ users: 3, active: 3, removed: 0 }]);
  });

  it("the script assigns the same starters as sign-up, insert only, on the environment named", () => {
    const script = readFileSync(new URL("../scripts/assign-starter-sidekicks-to-everyone.mjs", import.meta.url), "utf8");
    const listMatch = script.match(/const STARTER_SIDEKICK_IDS = (\[[^\]]*\]);/);
    expect(listMatch).not.toBeNull();
    const scriptIds = JSON.parse(listMatch?.[1] ?? "[]");
    expect(scriptIds).toEqual([...STARTER_SIDEKICK_IDS]);
    expect(script).toContain("environmentFromArgs");
    expect(script).toContain("assignToEveryoneSql(sidekickId");
    expect(script).not.toMatch(/DELETE|UPDATE|DROP/);
  });
});
