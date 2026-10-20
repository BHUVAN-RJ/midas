import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// GET /repairs/:id/records (founder, 2026-10-19; docs/briefs/repair-data-2026-10-19.md item 3):
// the runner reads the reporter's records to check them against a repaired copy's new schema
// before publishing. Runner token only; only that report's user and Sidekick; the latest value
// per key; a key whose latest op is a delete is gone. Nothing is written.

const RUNNER_TOKEN = "runner-secret-for-records";

function makeEnv() {
  return { DB: makeMigratedD1(), BUNDLES: makeFakeR2(), REPAIR_RUNNER_TOKEN: RUNNER_TOKEN };
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string, assignedSidekicks: string[]): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  for (const sidekickId of assignedSidekicks) {
    env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, 'now')", userId, sidekickId);
  }
  return token;
}

let opCounter = 0;

function addOp(env: TestEnv, userId: string, sidekickId: string, key: string, value: unknown) {
  opCounter += 1;
  const deleted = value === null ? 1 : 0;
  const valueText = value === null ? null : JSON.stringify(value);
  env.DB.execute(
    "INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, client_time, received_at) VALUES (?, ?, ?, ?, ?, ?, 'now', 'now')",
    `op-${opCounter}`,
    userId,
    sidekickId,
    key,
    valueText,
    deleted,
  );
}

async function fileReport(env: TestEnv, token: string, sidekickId: string): Promise<string> {
  const form = new FormData();
  form.set("sidekickId", sidekickId);
  form.set("kind", "change");
  form.set("transcript", "keep typing on the next line");
  form.set("bundleVersion", "v1");
  const response = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
  expect(response.status).toBe(201);
  const reply = (await response.json()) as { id: string };
  return reply.id;
}

function getRecords(env: TestEnv, reportId: string, authorization: string) {
  return app.request(`/repairs/${reportId}/records`, { headers: { Authorization: authorization } }, env);
}

function keysOf(records: Array<{ key: string }>): string[] {
  const keys: string[] = [];
  for (const record of records) {
    keys.push(record.key);
  }
  return keys;
}

describe("GET /repairs/:id/records", () => {
  it("gives the runner the reporter's latest non-deleted records for that Sidekick only", async () => {
    const env = makeEnv();
    const reporterToken = addSignedInUser(env, "reporter", ["reminders", "care-reminders"]);
    addSignedInUser(env, "someone-else", ["reminders"]);
    addOp(env, "reporter", "reminders", "reminder:1", { $type: "reminders.item", title: "Old title" });
    addOp(env, "reporter", "reminders", "reminder:1", { $type: "reminders.item", title: "New title" });
    addOp(env, "reporter", "reminders", "reminder:2", { $type: "reminders.item", title: "Deleted later" });
    addOp(env, "reporter", "reminders", "reminder:2", null);
    addOp(env, "reporter", "reminders", "list:home", { $type: "reminders.list", name: "Home" });
    addOp(env, "reporter", "care-reminders", "reminder:9", { $type: "care.item", title: "Other Sidekick", at: "2026-10-20T09:00:00.000Z" });
    addOp(env, "someone-else", "reminders", "reminder:5", { $type: "reminders.item", title: "Not the reporter's" });
    const reportId = await fileReport(env, reporterToken, "reminders");

    const response = await getRecords(env, reportId, `Runner ${RUNNER_TOKEN}`);
    expect(response.status).toBe(200);
    const reply = (await response.json()) as { userId: string; sidekickId: string; records: Array<{ key: string; value: { title?: string } }> };
    expect(reply.userId).toBe("reporter");
    expect(reply.sidekickId).toBe("reminders");
    expect(keysOf(reply.records)).toEqual(["list:home", "reminder:1"]);
    expect(reply.records[1].value.title).toBe("New title");
  });

  it("refuses a user session, even the reporter's own, and a wrong runner token", async () => {
    const env = makeEnv();
    const reporterToken = addSignedInUser(env, "reporter", ["reminders"]);
    addOp(env, "reporter", "reminders", "reminder:1", { $type: "reminders.item", title: "Mine" });
    const reportId = await fileReport(env, reporterToken, "reminders");

    const asUser = await getRecords(env, reportId, `Bearer ${reporterToken}`);
    expect(asUser.status).toBe(401);
    const wrongToken = await getRecords(env, reportId, "Runner not-the-token");
    expect(wrongToken.status).toBe(401);
  });

  it("answers 400 for a malformed id and 404 for an unknown report", async () => {
    const env = makeEnv();
    const badId = await getRecords(env, "not-a-report-id", `Runner ${RUNNER_TOKEN}`);
    expect(badId.status).toBe(400);
    const unknown = await getRecords(env, "00000000-0000-0000-0000-000000000000", `Runner ${RUNNER_TOKEN}`);
    expect(unknown.status).toBe(404);
  });

  it("writes nothing to the ops table", async () => {
    const env = makeEnv();
    const reporterToken = addSignedInUser(env, "reporter", ["reminders"]);
    addOp(env, "reporter", "reminders", "reminder:1", { $type: "reminders.item", title: "Mine" });
    const reportId = await fileReport(env, reporterToken, "reminders");
    const before = env.DB.query("SELECT COUNT(*) AS n FROM ops");
    await getRecords(env, reportId, `Runner ${RUNNER_TOKEN}`);
    const after = env.DB.query("SELECT COUNT(*) AS n FROM ops");
    expect(after).toEqual(before);
  });
});
