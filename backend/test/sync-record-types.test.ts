import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// /sync/push checks every write against the schema of the Sidekick version that wrote it (plan
// section 5, "Server"): an op names its sidekickVersion; the manifest of that version is read
// from the user's copy, else the base. A shell that does not say its version is checked against
// the user's current version. A save from a version without a types block is refused (founder,
// 2026-10-20, docs/PRODUCT.md "Old formats retired"); a version that is not stored is not
// content-checked.

const baseManifest = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] };
const strictTypes = {
  "reminder:": {
    $type: "reminders.item",
    schema: { type: "object", required: ["title"], properties: { title: { type: "string", minLength: 1 }, at: { type: "string", format: "date-time" } } },
  },
};
// A user's repaired copy with a wider schema: it also allows a "mood" field with three values.
const repairedTypes = {
  "reminder:": {
    $type: "reminders.item",
    schema: { type: "object", required: ["title"], properties: { title: { type: "string" }, mood: { type: "string", enum: ["good", "ok", "bad"] } } },
  },
};

function pointer(version: string) {
  return JSON.stringify({ version, scriptHashes: [], contentHash: `hash-${version}`, baseVersion: null });
}

function makeEnv() {
  const bucket = makeFakeR2({
    // v1: before schemas. v2: the current base, with strict types.
    "sidekicks/reminders/current.json": pointer("v2"),
    "sidekicks/reminders/v1/manifest.json": JSON.stringify(baseManifest),
    "sidekicks/reminders/v2/manifest.json": JSON.stringify({ ...baseManifest, types: strictTypes }),
    // Amogh's copy was repaired on top of v2 with a wider schema, version a3.
    "sidekicks/reminders/users/u-amogh/current.json": pointer("a3"),
    "sidekicks/reminders/users/u-amogh/a3/manifest.json": JSON.stringify({ ...baseManifest, types: repairedTypes }),
  });
  return { DB: makeMigratedD1(), BUNDLES: bucket };
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string, name: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, name);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

type PushReply = { accepted: string[]; rejected: Array<{ opId: unknown; error: string }> };

async function push(env: TestEnv, token: string, ops: unknown[]): Promise<PushReply> {
  const headers = { "Content-Type": "application/json", Authorization: `Bearer ${token}` };
  const response = await app.request("/sync/push", { method: "POST", headers, body: JSON.stringify({ ops }) }, env);
  expect(response.status).toBe(200);
  return (await response.json()) as PushReply;
}

function storedKeys(env: TestEnv): string[] {
  const rows = env.DB.query("SELECT key FROM ops ORDER BY seq");
  return rows.map(keyOfRow);
}

function keyOfRow(row: Record<string, unknown>): string {
  return row.key as string;
}

function writeOp(opId: string, key: string, value: unknown, sidekickVersion?: string) {
  return { opId, sidekickId: "reminders", key, value, deleted: false, clientTime: "2026-10-15T09:00:00.000Z", sidekickVersion };
}

describe("records are checked against the writer's version", () => {
  it("an op from the current base version must fit its schema and carry $type; a delete is never content-checked", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-rj", "R J");
    const reply = await push(env, token, [
      writeOp("op-good-1", "reminder:1", { $type: "reminders.item", title: "Call" }, "v2"),
      writeOp("op-no-type", "reminder:2", { title: "Call" }, "v2"),
      writeOp("op-empty-1", "reminder:3", { $type: "reminders.item", title: "" }, "v2"),
      writeOp("op-epoch-1", "reminder:4", { $type: "reminders.item", title: "x", at: 1760515200000 }, "v2"),
      writeOp("op-task-01", "task:5", { $type: "reminders.item", title: "x" }, "v2"),
      { opId: "op-del-001", sidekickId: "reminders", key: "task:9", deleted: true, sidekickVersion: "v2" },
    ]);
    expect(reply.accepted).toEqual(["op-good-1", "op-del-001"]);
    expect(reply.rejected).toEqual([
      { opId: "op-no-type", error: 'reminders.item.$type must be "reminders.item"' },
      { opId: "op-empty-1", error: "reminders.item.title must not be empty" },
      { opId: "op-epoch-1", error: "reminders.item.at must be a string, not a number" },
      { opId: "op-task-01", error: "no record type is declared for task:5" },
    ]);
    expect(storedKeys(env)).toEqual(["reminder:1", "task:9"]);
  });

  it("an older phone still on a version without schemas is refused; a version that is not stored is checked against nothing", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-rj", "R J");
    const reply = await push(env, token, [
      writeOp("op-old-001", "reminder:5", { $type: "reminders.item", title: "x" }, "v1"),
      writeOp("op-gone-01", "reminder:6", { $type: "reminders.item", title: "x" }, "v-never-deployed"),
    ]);
    expect(reply.accepted).toEqual(["op-gone-01"]);
    expect(reply.rejected).toEqual([{ opId: "op-old-001", error: "reminders version v1 has no record schema types" }]);
  });

  it("without a version the user's current copy decides: Amogh's repaired schema allows mood, the base refuses it", async () => {
    const env = makeEnv();
    const amoghToken = addSignedInUser(env, "u-amogh", "Amogh");
    const rjToken = addSignedInUser(env, "u-rj", "R J");
    const moody = { $type: "reminders.item", title: "Walk", mood: "good" };
    const grumpy = { $type: "reminders.item", title: "Walk", mood: "furious" };

    const amoghReply = await push(env, amoghToken, [writeOp("op-amogh-1", "reminder:1", moody), writeOp("op-amogh-2", "reminder:2", grumpy)]);
    expect(amoghReply.accepted).toEqual(["op-amogh-1"]);
    expect(amoghReply.rejected).toEqual([{ opId: "op-amogh-2", error: 'reminders.item.mood must be one of ["good","ok","bad"]' }]);

    // The base v2 schema does not know mood but keeps unknown fields (rule 4), so RJ's op passes
    // too; what RJ cannot do is write an empty title.
    const rjReply = await push(env, rjToken, [writeOp("op-rj-0001", "reminder:1", moody), writeOp("op-rj-0002", "reminder:2", { $type: "reminders.item", title: "" })]);
    expect(rjReply.accepted).toEqual(["op-rj-0001"]);
    expect(rjReply.rejected).toEqual([{ opId: "op-rj-0002", error: "reminders.item.title must not be empty" }]);
  });

  it("a version named by the op wins over the current pointer: Amogh's old v2 op is checked against v2, not a3", async () => {
    const env = makeEnv();
    const amoghToken = addSignedInUser(env, "u-amogh", "Amogh");
    const reply = await push(env, amoghToken, [writeOp("op-amogh-3", "reminder:3", { $type: "reminders.item", title: "Walk", mood: "furious" }, "v2")]);
    expect(reply.accepted).toEqual(["op-amogh-3"]);
  });

  it("shell types are checked for every Sidekick, versions or not, and a bad sidekickVersion is refused", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-rj", "R J");
    const reply = await push(env, token, [
      { ...writeOp("op-widget-1", "widget:meds", { $type: "midas.widget", name: "Meds today", small: {} }), sidekickId: "care-reminders" },
      { ...writeOp("op-widget-2", "widget:meds", { $type: "midas.widget", small: {} }), sidekickId: "care-reminders" },
      writeOp("op-request1", "request:r1", { $type: "midas.request", kind: "import.apple-reminders", status: "pending" }, "v1"),
      writeOp("op-request2", "request:r2", { kind: "import.apple-reminders" }, "v1"),
      writeOp("op-badver-1", "reminder:1", { $type: "reminders.item", title: "x" }, "../../etc"),
    ]);
    expect(reply.accepted).toEqual(["op-widget-1", "op-request1"]);
    expect(reply.rejected).toEqual([
      { opId: "op-widget-2", error: "midas.widget.name is required" },
      { opId: "op-request2", error: 'midas.request.$type must be "midas.request"' },
      { opId: "op-badver-1", error: "bad sidekickVersion" },
    ]);
  });

  it("a Sidekick with no deployed version is not content-checked, as before schemas", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-rj", "R J");
    const reply = await push(env, token, [{ ...writeOp("op-notes-01", "note:1", { text: "hi" }), sidekickId: "notes" }]);
    expect(reply.accepted).toEqual(["op-notes-01"]);
  });
});
