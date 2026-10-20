import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import app from "../src/index";
import { MAX_OPS_PER_PUSH, MAX_VALUE_BYTES, PULL_PAGE_SIZE } from "../src/sync";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// D4, 2026-10-10: records backed up to the server, append only. Done when: the same op sent
// twice is stored once; a reinstall pulls every record back; nothing deletes from ops.

function makeEnv() {
  return { DB: makeMigratedD1(), BUNDLES: {} };
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

type Op = { opId: string; sidekickId: string; key: string; value?: unknown; deleted: boolean; clientTime?: string };
type PushReply = { accepted: string[]; rejected: Array<{ opId: unknown; error: string }> };
type PulledOp = { seq: number; opId: string; sidekickId: string; key: string; value: unknown; deleted: boolean; clientTime: string | null };
type PullReply = { ops: PulledOp[]; lastSeq: number; more: boolean };

function writeOp(opId: string, key: string, value: unknown, sidekickId = "reminders"): Op {
  return { opId, sidekickId, key, value, deleted: false, clientTime: "2026-10-13T09:00:00.000Z" };
}

function deleteOp(opId: string, key: string, sidekickId = "reminders"): Op {
  return { opId, sidekickId, key, deleted: true };
}

async function push(env: TestEnv, token: string | null, body: unknown) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token !== null) {
    headers.Authorization = `Bearer ${token}`;
  }
  return app.request("/sync/push", { method: "POST", headers, body: JSON.stringify(body) }, env);
}

async function pushOps(env: TestEnv, token: string, ops: Op[]): Promise<PushReply> {
  const response = await push(env, token, { ops });
  expect(response.status).toBe(200);
  return (await response.json()) as PushReply;
}

async function pull(env: TestEnv, token: string | null, after?: string) {
  const headers: Record<string, string> = token === null ? {} : { Authorization: `Bearer ${token}` };
  const query = after === undefined ? "" : `?after=${after}`;
  return app.request(`/sync/pull${query}`, { headers }, env);
}

async function pullAll(env: TestEnv, token: string): Promise<PulledOp[]> {
  const allOps: PulledOp[] = [];
  let after = 0;
  for (;;) {
    const response = await pull(env, token, String(after));
    const reply = (await response.json()) as PullReply;
    allOps.push(...reply.ops);
    after = reply.lastSeq;
    if (!reply.more) {
      return allOps;
    }
  }
}

// What a fresh install rebuilds: replay in seq order, last write wins per key, deletes remove.
function replay(ops: PulledOp[]): Record<string, unknown> {
  const records: Record<string, unknown> = {};
  for (const op of ops) {
    const recordKey = `${op.sidekickId}/${op.key}`;
    if (op.deleted) {
      delete records[recordKey];
    } else {
      records[recordKey] = op.value;
    }
  }
  return records;
}

describe("sign-in", () => {
  it("push and pull both require a session", async () => {
    const env = makeEnv();
    const pushResponse = await push(env, null, { ops: [writeOp("op-00000001", "reminder:1", { title: "x" })] });
    const pullResponse = await pull(env, null);
    expect(pushResponse.status).toBe(401);
    expect(pullResponse.status).toBe(401);
    expect(env.DB.query("SELECT seq FROM ops")).toHaveLength(0);
  });
});

describe("POST /sync/push", () => {
  it("stores the same op sent twice only once", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    const op = writeOp("op-00000001", "reminder:dentist", { at: "2026-10-14T16:30:00.000Z", title: "Dentist" });

    const first = await pushOps(env, token, [op]);
    const second = await pushOps(env, token, [op, op]);
    expect(first.accepted).toEqual(["op-00000001"]);
    expect(second.accepted).toEqual(["op-00000001", "op-00000001"]);
    expect(env.DB.query("SELECT op_id, user_id, key FROM ops")).toEqual([
      { op_id: "op-00000001", user_id: "u1", key: "reminder:dentist" },
    ]);
  });

  it("a resent op does not overwrite the stored one, even with a different value", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    await pushOps(env, token, [writeOp("op-00000001", "note:1", "first")]);
    await pushOps(env, token, [writeOp("op-00000001", "note:1", "changed")]);
    expect(env.DB.query("SELECT value FROM ops")).toEqual([{ value: '"first"' }]);
  });

  it("assigns seq in the order the ops were sent", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    await pushOps(env, token, [writeOp("op-0000000c", "a", 1), writeOp("op-0000000a", "b", 2), writeOp("op-0000000b", "c", 3)]);
    const rows = env.DB.query("SELECT op_id FROM ops ORDER BY seq");
    expect(rows).toEqual([{ op_id: "op-0000000c" }, { op_id: "op-0000000a" }, { op_id: "op-0000000b" }]);
  });

  it("stores a delete as a new op and keeps the earlier ones", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    await pushOps(env, token, [writeOp("op-00000001", "reminder:laundry", { title: "Laundry" })]);
    await pushOps(env, token, [deleteOp("op-00000002", "reminder:laundry")]);
    expect(env.DB.query("SELECT op_id, value, deleted FROM ops ORDER BY seq")).toEqual([
      { op_id: "op-00000001", value: '{"title":"Laundry"}', deleted: 0 },
      { op_id: "op-00000002", value: null, deleted: 1 },
    ]);
  });

  it("carries a reminder record exactly as the Sidekick wrote it, extra fields included", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    const reminder = {
      $type: "reminders.item", at: "2026-10-12T16:30:00.000Z", title: "Standup", notes: "", repeat: { every: "week", interval: 2, weekdays: [1, 3, 5], until: "2026-12-31T23:59:59.000Z" },
      timeZone: "America/New_York", done: false, snoozedUntil: "2025-10-09T08:53:20.000Z", lastDoneAt: "2026-10-11T09:00:00.000Z", list: "Work", nested: { a: [null, true, 1.5] },
    };
    await pushOps(env, token, [writeOp("op-00000001", "reminder:standup", reminder)]);
    const pulled = await pullAll(env, token);
    expect(pulled[0].value).toEqual(reminder);
    expect(pulled[0].sidekickId).toBe("reminders");
  });

  it("keeps values that are null, false, 0, strings and lists", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    const values = [null, false, 0, "text", [1, "two"]];
    const ops: Op[] = [];
    for (let index = 0; index < values.length; index += 1) {
      ops.push(writeOp(`op-0000000${index}`, `k:${index}`, values[index]));
    }
    await pushOps(env, token, ops);
    const pulled = await pullAll(env, token);
    const pulledValues = [];
    for (const op of pulled) {
      pulledValues.push(op.value);
    }
    expect(pulledValues).toEqual(values);
  });

  it("rejects bad ops one by one and stores the good ones", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    const reply = await pushOps(env, token, [
      writeOp("op-00000001", "ok", 1),
      writeOp("short", "k", 1),
      { opId: "op-00000003", sidekickId: "../x", key: "k", value: 1, deleted: false },
      { opId: "op-00000004", sidekickId: "reminders", key: "", value: 1, deleted: false },
      { opId: "op-00000005", sidekickId: "reminders", key: "k", deleted: false },
      writeOp("op-00000006", "big", "x".repeat(MAX_VALUE_BYTES)),
      { opId: "op-00000007", sidekickId: "reminders", key: "k", value: 1, deleted: "no" } as unknown as Op,
    ]);
    expect(reply.accepted).toEqual(["op-00000001"]);
    const rejectedIds = [];
    for (const rejection of reply.rejected) {
      rejectedIds.push(rejection.opId);
    }
    expect(rejectedIds).toEqual(["short", "op-00000003", "op-00000004", "op-00000005", "op-00000006", "op-00000007"]);
    expect(env.DB.query("SELECT op_id FROM ops")).toEqual([{ op_id: "op-00000001" }]);
  });

  it("refuses a push over the size limits and a body without ops", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    const tooMany: Op[] = [];
    for (let index = 0; index <= MAX_OPS_PER_PUSH; index += 1) {
      tooMany.push(writeOp(`op-${String(index).padStart(8, "0")}`, `k:${index}`, index));
    }
    const tooManyResponse = await push(env, token, { ops: tooMany });
    expect(tooManyResponse.status).toBe(413);

    const tooBig: Op[] = [];
    for (let index = 0; index < 20; index += 1) {
      tooBig.push(writeOp(`op-${String(index).padStart(8, "0")}`, `k:${index}`, "x".repeat(60 * 1024)));
    }
    const tooBigResponse = await push(env, token, { ops: tooBig });
    expect(tooBigResponse.status).toBe(413);

    const noOps = await push(env, token, { nope: true });
    expect(noOps.status).toBe(400);
    expect(env.DB.query("SELECT op_id FROM ops")).toHaveLength(0);
  });
});

describe("GET /sync/pull", () => {
  it("returns only the user's own ops, after the given seq, in seq order", async () => {
    const env = makeEnv();
    const priya = addSignedInUser(env, "u1", "Priya");
    const sam = addSignedInUser(env, "u2", "Sam");
    await pushOps(env, priya, [writeOp("op-0000000a", "a", 1)]);
    await pushOps(env, sam, [writeOp("op-0000000b", "secret", "sam's")]);
    await pushOps(env, priya, [writeOp("op-0000000c", "c", 3)]);

    const allForPriya = (await (await pull(env, priya)).json()) as PullReply;
    const keys = [];
    for (const op of allForPriya.ops) {
      keys.push(op.key);
    }
    expect(keys).toEqual(["a", "c"]);
    expect(allForPriya.more).toBe(false);

    const afterFirst = (await (await pull(env, priya, String(allForPriya.ops[0].seq))).json()) as PullReply;
    expect(afterFirst.ops).toHaveLength(1);
    expect(afterFirst.ops[0].key).toBe("c");
    expect(afterFirst.lastSeq).toBe(allForPriya.lastSeq);

    const nothingNew = (await (await pull(env, priya, String(allForPriya.lastSeq))).json()) as PullReply;
    expect(nothingNew).toEqual({ ops: [], lastSeq: allForPriya.lastSeq, more: false });
  });

  it("pages through more ops than fit in one reply", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    const total = PULL_PAGE_SIZE + 5;
    for (let start = 0; start < total; start += MAX_OPS_PER_PUSH) {
      const batch: Op[] = [];
      for (let index = start; index < Math.min(start + MAX_OPS_PER_PUSH, total); index += 1) {
        batch.push(writeOp(`op-${String(index).padStart(8, "0")}`, `k:${index}`, index));
      }
      await pushOps(env, token, batch);
    }
    const firstPage = (await (await pull(env, token, "0")).json()) as PullReply;
    expect(firstPage.ops).toHaveLength(PULL_PAGE_SIZE);
    expect(firstPage.more).toBe(true);
    expect(await pullAll(env, token)).toHaveLength(total);
  });

  it("rejects a malformed cursor", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    expect((await pull(env, token, "-1")).status).toBe(400);
    expect((await pull(env, token, "abc")).status).toBe(400);
  });
});

describe("a reinstall gets every record back", () => {
  it("rebuilds the latest state from the pulled ops, across Sidekicks, with deletes applied", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "u1", "Priya");
    await pushOps(env, token, [
      writeOp("op-00000001", "reminder:dentist", { at: "2026-10-14T16:30:00.000Z", title: "Dentist" }),
      writeOp("op-00000002", "reminder:laundry", { at: "2026-10-14T18:00:00.000Z", title: "Laundry" }),
      writeOp("op-00000003", "birthday:sam", { name: "Sam", date: "05-02" }, "birthdays"),
    ]);
    await pushOps(env, token, [
      writeOp("op-00000004", "reminder:dentist", { at: "2026-10-15T16:30:00.000Z", title: "Dentist", snoozedUntil: "2026-10-15T16:40:00.000Z" }),
      deleteOp("op-00000005", "reminder:laundry"),
    ]);

    const restored = replay(await pullAll(env, token));
    expect(restored).toEqual({
      "reminders/reminder:dentist": { at: "2026-10-15T16:30:00.000Z", title: "Dentist", snoozedUntil: "2026-10-15T16:40:00.000Z" },
      "birthdays/birthday:sam": { name: "Sam", date: "05-02" },
    });
    // Nothing was removed from the table to get there.
    expect(env.DB.query("SELECT seq FROM ops")).toHaveLength(5);
  });
});

describe("the ops table itself", () => {
  it("refuses to rewrite an op", () => {
    const db = makeMigratedD1();
    db.execute("INSERT INTO users (id, name, created_at) VALUES ('u1', 'Priya', 'now')");
    db.execute("INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, received_at) VALUES ('op-1', 'u1', 'r', 'k', '1', 0, 'now')");
    function rewriteOp() {
      db.execute("UPDATE ops SET value = '2'");
    }
    expect(rewriteOp).toThrow(/append only/);
    expect(db.query("SELECT value FROM ops")).toEqual([{ value: "1" }]);
  });

  it("never reuses a seq", () => {
    const db = makeMigratedD1();
    const schema = db.query("SELECT sql FROM sqlite_master WHERE name = 'ops'");
    expect(String(schema[0].sql)).toMatch(/seq INTEGER PRIMARY KEY AUTOINCREMENT/);
  });
});
