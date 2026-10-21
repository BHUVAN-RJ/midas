import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// The server stores nothing unchecked (founder, 2026-10-20, docs/PRODUCT.md "Old formats
// retired"): a save from a Sidekick version whose manifest has no schema types (the bundles from
// before the unified data rework, build 2 and older) is refused with a clear reason.
// A refused op stays queued on the phone. Each case fails if such a save is accepted.

const baseManifest = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [] };
const currentTypes = {
  "reminder:": {
    $type: "reminders.item",
    schema: { type: "object", required: ["title"], properties: { title: { type: "string", minLength: 1 } } },
  },
};
// A value that fits today's schema, so a refusal can only come from the version it was saved by.
const fittingValue = { $type: "reminders.item", title: "Call mom" };

function pointer(version: string) {
  return JSON.stringify({ version, scriptHashes: [], contentHash: `hash-${version}`, baseVersion: null });
}

function makeEnv() {
  const bucket = makeFakeR2({
    // v1: a bundle from before the rework, no types. v2: the current base, typed.
    "sidekicks/reminders/current.json": pointer("v2"),
    "sidekicks/reminders/v1/manifest.json": JSON.stringify(baseManifest),
    "sidekicks/reminders/v2/manifest.json": JSON.stringify({ ...baseManifest, types: currentTypes }),
    // A user whose own copy is an untyped version.
    "sidekicks/reminders/users/u-old/current.json": pointer("u1"),
    "sidekicks/reminders/users/u-old/u1/manifest.json": JSON.stringify(baseManifest),
  });
  return { DB: makeMigratedD1(), BUNDLES: bucket };
}

type TestEnv = ReturnType<typeof makeEnv>;
type PushReply = { accepted: string[]; rejected: Array<{ opId: unknown; error: string }> };

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

async function push(env: TestEnv, token: string, ops: unknown[]): Promise<PushReply> {
  const headers = { "Content-Type": "application/json", Authorization: `Bearer ${token}` };
  const response = await app.request("/sync/push", { method: "POST", headers, body: JSON.stringify({ ops }) }, env);
  expect(response.status).toBe(200);
  return (await response.json()) as PushReply;
}

function storedKeys(env: TestEnv): string[] {
  const rows = env.DB.query("SELECT key FROM ops ORDER BY seq");
  return rows.map(function keyOfRow(row: Record<string, unknown>) {
    return row.key as string;
  });
}

function saveOp(opId: string, key: string, sidekickVersion?: string, sidekickId = "reminders") {
  return { opId, sidekickId, key, value: fittingValue, deleted: false, clientTime: "2026-10-20T09:00:00.000Z", sidekickVersion };
}

describe("saves from a Sidekick version without schema types are refused (founder, 2026-10-20)", () => {
  it("refuses every save from an untyped version with its reason, stores none, and still takes the same save from a typed version", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-rj", "R J");
    const reply = await push(env, token, [saveOp("op-untyped-1", "reminder:1", "v1"), saveOp("op-untyped-2", "reminder:2", "v1"), saveOp("op-typed-01", "reminder:3", "v2")]);
    expect(reply.rejected).toEqual([
      { opId: "op-untyped-1", error: "reminders version v1 has no record schema types" },
      { opId: "op-untyped-2", error: "reminders version v1 has no record schema types" },
    ]);
    expect(reply.accepted).toEqual(["op-typed-01"]);
    expect(storedKeys(env)).toEqual(["reminder:3"]);
  });

  it("refuses a save without a version when the user's own copy is an untyped version", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u-old", "Old phone");
    const reply = await push(env, token, [saveOp("op-oldcopy-1", "reminder:1")]);
    expect(reply.accepted).toEqual([]);
    expect(reply.rejected).toEqual([{ opId: "op-oldcopy-1", error: "reminders version u1 has no record schema types" }]);
    expect(storedKeys(env)).toEqual([]);
  });
});
