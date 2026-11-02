import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { EXPECTED_ORIGIN, RELYING_PARTY_ID } from "../src/auth";
import { STARTER_SIDEKICK_IDS, starterAssignedAt } from "../src/starter-sidekicks";
import { assignToEveryoneSql } from "../scripts/db-tools.mjs";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";
import { makeSoftAuthenticator } from "./helpers/soft-authenticator";

// Starter order (lead for the founder, 2026-11-01; docs/PRODUCT.md "New accounts"): after jess
// and Make the home shows Reminders, To-Do, Water. The catalog sorts by assigned_at, so sign-up and
// scripts/assign-starter-sidekicks-to-everyone.mjs assign each starter one millisecond after the
// one before it.

const RUN_START_MS = Date.parse("2026-11-01T12:00:00.000Z");

function manifestFor(sidekickId: string, name: string) {
  return { id: sidekickId, name, icon: { symbol: "circle", background: "#FFFFFF" }, reads: [], types: {} };
}

// All three starters deployed.
function makeEnv() {
  const bundles = makeFakeR2({
    "sidekicks/reminders/current.json": JSON.stringify({ version: "r1", scriptHashes: [] }),
    "sidekicks/reminders/r1/index.html": "<p>reminders</p>",
    "sidekicks/reminders/r1/manifest.json": JSON.stringify(manifestFor("reminders", "Reminders")),
    "sidekicks/todo/current.json": JSON.stringify({ version: "t1", scriptHashes: [] }),
    "sidekicks/todo/t1/index.html": "<p>todo</p>",
    "sidekicks/todo/t1/manifest.json": JSON.stringify(manifestFor("todo", "To-Do")),
    "sidekicks/hydration/current.json": JSON.stringify({ version: "h1", scriptHashes: [] }),
    "sidekicks/hydration/h1/index.html": "<p>water</p>",
    "sidekicks/hydration/h1/manifest.json": JSON.stringify(manifestFor("hydration", "Water")),
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

async function listedIds(env: TestEnv, token: string): Promise<unknown[]> {
  const response = await app.request("/sidekicks", { headers: { Authorization: `Bearer ${token}` } }, env);
  expect(response.status).toBe(200);
  const body = (await response.json()) as CatalogReply;
  const ids: unknown[] = [];
  for (const listing of body.sidekicks) {
    ids.push(listing.id);
  }
  return ids;
}

// An account from before starters existed, with jess and Make assigned at the same time.
function addExistingUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', ?)", sha256Hex(token), userId, farFuture);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'jess', '2026-10-01T00:00:00.000Z')", userId);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'make', '2026-10-01T00:00:00.000Z')", userId);
  return token;
}

// What the script runs: each starter one millisecond after the one before.
function runScriptSqlInListOrder(env: TestEnv) {
  for (const [listIndex, sidekickId] of STARTER_SIDEKICK_IDS.entries()) {
    const assignedAt = new Date(RUN_START_MS + listIndex);
    env.DB.execute(assignToEveryoneSql(sidekickId, assignedAt));
  }
}

describe("starter order", () => {
  it("the starter list is Reminders, To-Do, Water", () => {
    expect([...STARTER_SIDEKICK_IDS]).toEqual(["reminders", "todo", "hydration"]);
  });

  it("each starter is assigned one millisecond after the one before", () => {
    const signUpIso = "2026-11-01T12:00:00.998Z";
    expect(starterAssignedAt(signUpIso, 0)).toBe("2026-11-01T12:00:00.998Z");
    expect(starterAssignedAt(signUpIso, 1)).toBe("2026-11-01T12:00:00.999Z");
    expect(starterAssignedAt(signUpIso, 2)).toBe("2026-11-01T12:00:01.000Z");
  });

  it("a new account's home is jess, Make, Reminders, To-Do, Water", async () => {
    const env = makeEnv();
    const session = await signUp(env, "Priya");
    expect(await listedIds(env, session.token)).toEqual(["jess", "make", "reminders", "todo", "hydration"]);
  });

  it("an existing account gets the same order from the script", async () => {
    const env = makeEnv();
    const token = addExistingUser(env, "u-sam");
    runScriptSqlInListOrder(env);
    expect(await listedIds(env, token)).toEqual(["jess", "make", "reminders", "todo", "hydration"]);
  });

  it("the script staggers its times in list order", () => {
    const script = readFileSync(new URL("../scripts/assign-starter-sidekicks-to-everyone.mjs", import.meta.url), "utf8");
    expect(script).toContain("STARTER_SIDEKICK_IDS.entries()");
    expect(script).toContain("new Date(runStartMs + listIndex)");
    expect(script).toContain("assignToEveryoneSql(sidekickId, assignedAt)");
  });
});
