import { createHash, generateKeyPairSync } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { resetApnsTokenCache } from "../src/apns";
import { ACCOUNT_DELETION_PUSH_TITLE, accountDeletionPushBody } from "../src/account";
import { makeFakeR2 } from "../test/helpers/fake-r2";
import { makeMigratedD1 } from "../test/helpers/migrated-d1";

// Settings and delete (founder, 2026-10-31; docs/briefs/build-22-2026-10-31.md): deleting a
// Sidekick from the home grid (DELETE /sidekicks/:id: the assignment gets removed_at, its records
// get delete ops, jess, Make and the Inbox refuse), Make's Built giving a deleted Sidekick back,
// Sign Out (POST /account/sign-out) and the Delete Account request (POST /account/delete-request:
// recorded, every session ended, the founder pushed; nothing deleted).

const FOUNDER = "u-founder";
const PERSON = "u-priya";
const OTHER = "u-sam";
const TIME = "2026-10-31T18:00:00.000Z";
const KEY_P8 = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const NAMES: Record<string, string> = { [FOUNDER]: "Bhuvan", [PERSON]: "Priya", [OTHER]: "Sam" };
const WATER_MANIFEST = { id: "water", name: "Water", icon: { symbol: "drop", background: "#30D5C8" }, reads: [], types: {} };
const REMINDERS_MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#C9F24D" }, reads: [], types: {} };

type FetchCall = { url: string; body: Record<string, unknown> };

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function makeEnv(founderId: string | null = FOUNDER) {
  const calls: FetchCall[] = [];
  async function fakeApnsFetch(url: string, init: RequestInit): Promise<Response> {
    calls.push({ url, body: JSON.parse(String(init.body)) });
    return new Response(null, { status: 200 });
  }
  const bundles = makeFakeR2({
    "sidekicks/water/current.json": JSON.stringify({ version: "w1", scriptHashes: [], tools: "tools.js" }),
    "sidekicks/water/w1/index.html": "<p>water</p>",
    "sidekicks/water/w1/manifest.json": JSON.stringify(WATER_MANIFEST),
    "sidekicks/water/w1/tools.js": "export const tools = {};",
    "sidekicks/reminders/current.json": JSON.stringify({ version: "r1", scriptHashes: [] }),
    "sidekicks/reminders/r1/index.html": "<p>reminders</p>",
    "sidekicks/reminders/r1/manifest.json": JSON.stringify(REMINDERS_MANIFEST),
  });
  const env = {
    DB: makeMigratedD1(),
    BUNDLES: bundles,
    FILES: makeFakeR2(),
    MAKE_FOUNDER_USER_ID: founderId ?? undefined,
    APNS_KEY_P8: KEY_P8,
    APNS_KEY_ID: "KEY1234567",
    APNS_TEAM_ID: "ZQ2JPFYL98",
    PUSH_FETCH: fakeApnsFetch,
  };
  return { env, calls };
}

type TestEnv = ReturnType<typeof makeEnv>["env"];

function addUserRow(env: TestEnv, userId: string) {
  env.DB.execute("INSERT OR IGNORE INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, NAMES[userId]);
}

// A user with one live session; the token is named by the given label.
function addSession(env: TestEnv, userId: string, label: string): string {
  addUserRow(env, userId);
  const token = `token-${userId}-${label}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

function assign(env: TestEnv, userId: string, sidekickId: string) {
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, ?)", userId, sidekickId, TIME);
}

function addDevice(env: TestEnv, userId: string, token: string) {
  addUserRow(env, userId);
  env.DB.execute("INSERT INTO push_devices (token, user_id, env, bundle_id, created_at, updated_at) VALUES (?, ?, 'sandbox', 'com.bhuvanrj.midas.test', 'then', 'then')", token, userId);
}

function seedOp(env: TestEnv, opId: string, userId: string, sidekickId: string, key: string, value: unknown) {
  const isDelete = value === null;
  const valueText = isDelete ? null : JSON.stringify(value);
  env.DB.execute("INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, received_at) VALUES (?, ?, ?, ?, ?, ?, 'then')", opId, userId, sidekickId, key, valueText, isDelete ? 1 : 0);
}

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

async function removeSidekick(env: TestEnv, token: string, sidekickId: string) {
  return app.request(`/sidekicks/${sidekickId}`, { method: "DELETE", headers: bearer(token) }, env);
}

async function postAccount(env: TestEnv, path: string, headers: Record<string, string>) {
  return app.request(`/account/${path}`, { method: "POST", headers }, env);
}

async function listedIds(env: TestEnv, token: string): Promise<unknown[]> {
  const response = await app.request("/sidekicks", { headers: bearer(token) }, env);
  expect(response.status).toBe(200);
  const body = (await response.json()) as { sidekicks: Array<{ id: unknown }> };
  const ids: unknown[] = [];
  for (const listing of body.sidekicks) {
    ids.push(listing.id);
  }
  return ids;
}

async function meStatus(env: TestEnv, token: string): Promise<number> {
  const response = await app.request("/auth/me", { headers: bearer(token) }, env);
  return response.status;
}

// The latest op per key of one user's Sidekick, the way a phone ends up after a full pull.
async function pulledRecords(env: TestEnv, token: string, sidekickId: string): Promise<Record<string, unknown>> {
  const response = await app.request("/sync/pull?after=0", { headers: bearer(token) }, env);
  expect(response.status).toBe(200);
  const body = (await response.json()) as { ops: Array<{ sidekickId: string; key: string; value: unknown; deleted: boolean }> };
  const records: Record<string, unknown> = {};
  for (const op of body.ops) {
    if (op.sidekickId !== sidekickId) {
      continue;
    }
    if (op.deleted) {
      delete records[op.key];
    } else {
      records[op.key] = op.value;
    }
  }
  return records;
}

// Priya has jess, Make, Water and Reminders, and records in Water and Reminders; Sam has Water too.
function personWithSidekicks(env: TestEnv) {
  const token = addSession(env, PERSON, "phone");
  for (const sidekickId of ["jess", "make", "reminders", "water"]) {
    assign(env, PERSON, sidekickId);
  }
  seedOp(env, "op-w-1", PERSON, "water", "drink:1", { $type: "water.drink", ml: 250 });
  seedOp(env, "op-w-2", PERSON, "water", "drink:2", { $type: "water.drink", ml: 300 });
  seedOp(env, "op-w-3", PERSON, "water", "drink:2", { $type: "water.drink", ml: 330 });
  seedOp(env, "op-w-4", PERSON, "water", "drink:3", { $type: "water.drink", ml: 100 });
  seedOp(env, "op-w-5", PERSON, "water", "drink:3", null);
  seedOp(env, "op-r-1", PERSON, "reminders", "reminder:a", { $type: "reminders.reminder", title: "Call mum" });
  const otherToken = addSession(env, OTHER, "phone");
  assign(env, OTHER, "water");
  seedOp(env, "op-s-1", OTHER, "water", "drink:1", { $type: "water.drink", ml: 500 });
  return { token, otherToken };
}

beforeEach(() => {
  resetApnsTokenCache();
});

describe("deleting a Sidekick (DELETE /sidekicks/:id)", () => {
  it("takes it off the person's list and stops its page and tools; the assignment row stays", async () => {
    const { env } = makeEnv();
    const { token } = personWithSidekicks(env);
    expect(await listedIds(env, token)).toEqual(["jess", "make", "reminders", "water"]);

    const response = await removeSidekick(env, token, "water");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ removed: true, recordsRemoved: 2 });

    expect(await listedIds(env, token)).toEqual(["jess", "make", "reminders"]);
    const bundle = await app.request("/sidekicks/water/bundle", { headers: bearer(token) }, env);
    expect(bundle.status).toBe(404);
    const tools = await app.request("/sidekicks/water/tools.js", { headers: bearer(token) }, env);
    expect(tools.status).toBe(404);
    const rows = env.DB.query("SELECT sidekick_id, removed_at IS NOT NULL AS removed FROM assignments WHERE user_id = ? ORDER BY sidekick_id", PERSON);
    expect(rows).toEqual([
      { sidekick_id: "jess", removed: 0 },
      { sidekick_id: "make", removed: 0 },
      { sidekick_id: "reminders", removed: 0 },
      { sidekick_id: "water", removed: 1 },
    ]);
  });

  it("appends one delete op per live record, so its data goes on the next pull; history stays", async () => {
    const { env } = makeEnv();
    const { token, otherToken } = personWithSidekicks(env);
    expect(Object.keys(await pulledRecords(env, token, "water"))).toEqual(["drink:1", "drink:2"]);
    const opsBefore = env.DB.query("SELECT COUNT(*) AS count FROM ops");

    await removeSidekick(env, token, "water");

    expect(await pulledRecords(env, token, "water")).toEqual({});
    const appended = env.DB.query("SELECT user_id, sidekick_id, key, value, deleted FROM ops WHERE op_id LIKE 'removed:%' ORDER BY key");
    expect(appended).toEqual([
      { user_id: PERSON, sidekick_id: "water", key: "drink:1", value: null, deleted: 1 },
      { user_id: PERSON, sidekick_id: "water", key: "drink:2", value: null, deleted: 1 },
    ]);
    const opsAfter = env.DB.query("SELECT COUNT(*) AS count FROM ops");
    expect(Number(opsAfter[0].count)).toBe(Number(opsBefore[0].count) + 2);
    // Every earlier op is still there
    const earlier = env.DB.query("SELECT op_id FROM ops WHERE op_id LIKE 'op-%' ORDER BY op_id");
    expect(earlier.length).toBe(7);
    // Other Sidekicks and other people keep theirs
    expect(Object.keys(await pulledRecords(env, token, "reminders"))).toEqual(["reminder:a"]);
    expect(Object.keys(await pulledRecords(env, otherToken, "water"))).toEqual(["drink:1"]);
    expect(await listedIds(env, otherToken)).toEqual(["water"]);
  });

  it("logs the removal with the number of records that went", async () => {
    const { env } = makeEnv();
    const { token } = personWithSidekicks(env);
    await removeSidekick(env, token, "water");
    await removeSidekick(env, token, "reminders");
    const removals = env.DB.query("SELECT user_id, sidekick_id, records_removed FROM sidekick_removals ORDER BY sidekick_id");
    expect(removals).toEqual([
      { user_id: PERSON, sidekick_id: "reminders", records_removed: 1 },
      { user_id: PERSON, sidekick_id: "water", records_removed: 2 },
    ]);
  });

  it("refuses jess, Make and the Inbox: they cannot be deleted", async () => {
    const { env } = makeEnv();
    const { token } = personWithSidekicks(env);
    for (const sidekickId of ["jess", "make", "make-inbox"]) {
      const response = await removeSidekick(env, token, sidekickId);
      expect(response.status).toBe(400);
    }
    expect(await listedIds(env, token)).toEqual(["jess", "make", "reminders", "water"]);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM sidekick_removals")).toEqual([{ count: 0 }]);
  });

  it("answers 404 for a Sidekick not assigned or already deleted, 400 for a bad id, 401 signed out", async () => {
    const { env } = makeEnv();
    const { token } = personWithSidekicks(env);
    expect((await removeSidekick(env, token, "plants")).status).toBe(404);
    expect((await removeSidekick(env, token, "water")).status).toBe(200);
    expect((await removeSidekick(env, token, "water")).status).toBe(404);
    expect((await removeSidekick(env, token, "Water!")).status).toBe(400);
    const signedOut = await app.request("/sidekicks/reminders", { method: "DELETE" }, env);
    expect(signedOut.status).toBe(401);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM sidekick_removals")).toEqual([{ count: 1 }]);
  });

  it("a deleted Sidekick cannot be sent for repair", async () => {
    const { env } = makeEnv();
    const { token } = personWithSidekicks(env);
    await removeSidekick(env, token, "water");
    const form = new FormData();
    form.set("sidekickId", "water");
    form.set("transcript", "Make the drop bigger");
    const response = await app.request("/repairs", { method: "POST", headers: bearer(token), body: form }, env);
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "no such sidekick" });
    expect(env.DB.query("SELECT COUNT(*) AS count FROM repair_reports")).toEqual([{ count: 0 }]);
  });

  it("Make's Built gives a deleted Sidekick back", async () => {
    const { env } = makeEnv();
    const founderToken = addSession(env, FOUNDER, "phone");
    const { token } = personWithSidekicks(env);
    await removeSidekick(env, token, "reminders");
    expect(await listedIds(env, token)).toEqual(["jess", "make", "water"]);

    const request = { $type: "make.request", title: "A lamp timer", status: "sent", createdAt: TIME, updatedAt: TIME };
    const message = { $type: "make.message", from: "person", text: "Turn my lamp off at 11", sentAt: TIME };
    const personOps = [
      { opId: "op-req-0001", sidekickId: "make", key: "req:req00001", value: request, deleted: false, clientTime: TIME },
      { opId: "op-msg-0001", sidekickId: "make", key: "message:req00001:msg00001", value: message, deleted: false, clientTime: TIME },
    ];
    const personPush = await app.request("/sync/push", { method: "POST", headers: { ...bearer(token), "Content-Type": "application/json" }, body: JSON.stringify({ ops: personOps }) }, env);
    expect(((await personPush.json()) as { rejected: unknown[] }).rejected).toEqual([]);
    const built = { ...request, status: "built", sidekickId: "reminders", plan: "Turns the lamp off at 11", builtAt: TIME };
    const founderOps = [{ opId: "op-inb-0001", sidekickId: "make-inbox", key: `req:${PERSON}:req00001`, value: built, deleted: false, clientTime: TIME }];
    const founderPush = await app.request("/sync/push", { method: "POST", headers: { ...bearer(founderToken), "Content-Type": "application/json" }, body: JSON.stringify({ ops: founderOps }) }, env);
    expect(((await founderPush.json()) as { rejected: unknown[] }).rejected).toEqual([]);

    expect(await listedIds(env, token)).toEqual(["jess", "make", "water", "reminders"]);
    const rows = env.DB.query("SELECT removed_at FROM assignments WHERE user_id = ? AND sidekick_id = 'reminders'", PERSON);
    expect(rows).toEqual([{ removed_at: null }]);
  });
});

describe("Sign Out (POST /account/sign-out)", () => {
  it("ends this phone's session only", async () => {
    const { env } = makeEnv();
    const phone = addSession(env, PERSON, "phone");
    const ipad = addSession(env, PERSON, "ipad");
    const response = await postAccount(env, "sign-out", bearer(phone));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ signedOut: true });
    expect(await meStatus(env, phone)).toBe(401);
    expect(await meStatus(env, ipad)).toBe(200);
    // The session row is kept, expired
    expect(env.DB.query("SELECT COUNT(*) AS count FROM sessions WHERE user_id = ?", PERSON)).toEqual([{ count: 2 }]);
  });

  it("needs a session", async () => {
    const { env } = makeEnv();
    const response = await postAccount(env, "sign-out", {});
    expect(response.status).toBe(401);
  });
});

describe("Delete Account (POST /account/delete-request)", () => {
  it("records the request, signs out every phone of theirs and pushes the founder", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, FOUNDER, "f".repeat(64));
    addDevice(env, PERSON, "e".repeat(64));
    const { token } = personWithSidekicks(env);
    const ipad = addSession(env, PERSON, "ipad");
    const founderToken = addSession(env, FOUNDER, "phone");

    const response = await postAccount(env, "delete-request", bearer(token));
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({ requested: true });

    const requests = env.DB.query("SELECT user_id, user_name, alert_result, carried_out_at FROM account_deletion_requests");
    expect(requests).toEqual([{ user_id: PERSON, user_name: "Priya", alert_result: "sent 1 of 1", carried_out_at: null }]);
    expect(await meStatus(env, token)).toBe(401);
    expect(await meStatus(env, ipad)).toBe(401);
    expect(await meStatus(env, founderToken)).toBe(200);

    // One push, to the founder's phone only
    expect(calls.length).toBe(1);
    expect(calls[0].url).toContain("f".repeat(64));
    expect(calls[0].body).toEqual({
      aps: { alert: { title: ACCOUNT_DELETION_PUSH_TITLE, body: accountDeletionPushBody("Priya") }, sound: "default" },
      founderAlert: { kind: "account-deletion", userId: PERSON },
    });
    expect(accountDeletionPushBody("Priya")).toBe("Priya asked to delete their account.");
  });

  it("deletes nothing: the user, their Sidekicks and records stay for the founder", async () => {
    const { env } = makeEnv();
    const { token } = personWithSidekicks(env);
    const opsBefore = env.DB.query("SELECT COUNT(*) AS count FROM ops WHERE user_id = ?", PERSON);
    await postAccount(env, "delete-request", bearer(token));
    expect(env.DB.query("SELECT name FROM users WHERE id = ?", PERSON)).toEqual([{ name: "Priya" }]);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM assignments WHERE user_id = ? AND removed_at IS NULL", PERSON)).toEqual([{ count: 4 }]);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM ops WHERE user_id = ?", PERSON)).toEqual(opsBefore);
  });

  it("asked again after signing back in: stored once, the founder pushed once", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, FOUNDER, "f".repeat(64));
    const first = addSession(env, PERSON, "first");
    expect((await postAccount(env, "delete-request", bearer(first))).status).toBe(201);
    const second = addSession(env, PERSON, "second");
    const again = await postAccount(env, "delete-request", bearer(second));
    expect(again.status).toBe(200);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM account_deletion_requests")).toEqual([{ count: 1 }]);
    expect(calls.length).toBe(1);
    expect(await meStatus(env, second)).toBe(401);
  });

  it("is still recorded when no founder is set or the founder has no phone", async () => {
    const noFounder = makeEnv(null);
    const priyaToken = addSession(noFounder.env, PERSON, "phone");
    expect((await postAccount(noFounder.env, "delete-request", bearer(priyaToken))).status).toBe(201);
    expect(noFounder.env.DB.query("SELECT alert_result FROM account_deletion_requests")).toEqual([{ alert_result: "no founder set" }]);

    const noPhone = makeEnv();
    const samToken = addSession(noPhone.env, OTHER, "phone");
    expect((await postAccount(noPhone.env, "delete-request", bearer(samToken))).status).toBe(201);
    expect(noPhone.env.DB.query("SELECT alert_result FROM account_deletion_requests")).toEqual([{ alert_result: "no devices" }]);
    expect(noPhone.calls.length).toBe(0);
  });

  it("needs a session", async () => {
    const { env } = makeEnv();
    const response = await postAccount(env, "delete-request", {});
    expect(response.status).toBe(401);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM account_deletion_requests")).toEqual([{ count: 0 }]);
  });
});

describe("migration 0013", () => {
  it("adds removed_at to assignments and the two new tables", () => {
    const db = makeMigratedD1();
    const columns = db.query("SELECT name FROM pragma_table_info('assignments') ORDER BY cid");
    expect(columns).toEqual([{ name: "user_id" }, { name: "sidekick_id" }, { name: "assigned_at" }, { name: "removed_at" }]);
    const tables = db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('sidekick_removals', 'account_deletion_requests') ORDER BY name");
    expect(tables).toEqual([{ name: "account_deletion_requests" }, { name: "sidekick_removals" }]);
  });
});
