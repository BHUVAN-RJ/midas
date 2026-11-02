import { createHash, generateKeyPairSync, randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { alertFounder } from "../src/account";
import {
  ACCOUNT_DELETED_PUSH_TITLE,
  ACCOUNT_DELETION_DUE_PUSH_TITLE,
  ACCOUNT_DELETION_INCOMPLETE_PUSH_TITLE,
  accountDeletedPushBody,
  accountDeletionDuePushBody,
  accountDeletionIncompletePushBody,
  countPersonData,
  dueDateText,
  isDeliveredAlert,
  isInboxKeyAbout,
  remindOpenDeletions,
  totalOf,
} from "../src/account-deletion";
import type { DeletionBindings, PersonCounts } from "../src/account-deletion";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Account deletion carried out in code (founder, 2026-11-02; docs/briefs/account-deletion-2026-11-02.md):
// all of the person's data goes, only theirs; the founder is told when someone asks, when it is
// done or stopped part way, and can check that nothing is left.

const FOUNDER = "u-founder";
// Look-alike ids: "ab_c" must never pick "abXc" (the _ is a LIKE wildcard) or "ab_cd" (a prefix).
const PERSON = "ab_c";
const LOOK_ALIKES = ["abXc", "ab_cd"];
const NAMES: Record<string, string> = { [FOUNDER]: "Bhuvan", ab_c: "Priya", abXc: "Sam", ab_cd: "Lena" };
const DELETION_TOKEN = "deletion-secret";
const RUNNER_TOKEN = "runner-secret";
const TIME = "2026-10-31T18:00:00.000Z";
const KEY_P8 = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();

type StoredObject = { bytes: Uint8Array; customMetadata?: Record<string, string> };

// An R2 stand-in with what the deletion uses: custom metadata, list with include and delimiter,
// delete of one key or a list. failDeleteOnCall makes the n-th delete call throw.
function makeR2() {
  const objects = new Map<string, StoredObject>();
  let deleteCalls = 0;
  const control = { failDeleteOnCall: 0 };

  async function put(key: string, value: string, options?: { customMetadata?: Record<string, string> }) {
    objects.set(key, { bytes: new TextEncoder().encode(value), customMetadata: options?.customMetadata });
    return { key };
  }
  async function get(key: string) {
    const stored = objects.get(key);
    if (stored === undefined) {
      return null;
    }
    const text = new TextDecoder().decode(stored.bytes);
    return { key, body: new Response(stored.bytes).body, text: async () => text, json: async () => JSON.parse(text), customMetadata: stored.customMetadata, httpMetadata: {} };
  }
  async function head(key: string) {
    const stored = objects.get(key);
    return stored === undefined ? null : { key, customMetadata: stored.customMetadata };
  }
  async function list(options: { prefix?: string; delimiter?: string; include?: string[] } = {}) {
    const prefix = options.prefix ?? "";
    const sortedKeys = Array.from(objects.keys()).sort();
    const listed = [];
    const prefixes = new Set<string>();
    for (const key of sortedKeys) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      const rest = key.slice(prefix.length);
      if (options.delimiter !== undefined && rest.includes(options.delimiter)) {
        prefixes.add(prefix + rest.slice(0, rest.indexOf(options.delimiter) + 1));
        continue;
      }
      const stored = objects.get(key) as StoredObject;
      const wantsMetadata = options.include?.includes("customMetadata") ?? false;
      listed.push({ key, customMetadata: wantsMetadata ? stored.customMetadata ?? {} : undefined });
    }
    return { objects: listed, delimitedPrefixes: Array.from(prefixes).sort(), truncated: false };
  }
  async function remove(keys: string | string[]) {
    deleteCalls += 1;
    if (control.failDeleteOnCall !== 0 && deleteCalls === control.failDeleteOnCall) {
      throw new Error("R2 is down");
    }
    const keyList = Array.isArray(keys) ? keys : [keys];
    for (const key of keyList) {
      objects.delete(key);
    }
  }
  function keys(): string[] {
    return Array.from(objects.keys()).sort();
  }
  return { put, get, head, list, delete: remove, keys, control };
}

type Pushed = { url: string; body: Record<string, unknown> };

function makeEnv() {
  const pushes: Pushed[] = [];
  async function fakeApnsFetch(url: string, init: RequestInit): Promise<Response> {
    pushes.push({ url, body: JSON.parse(String(init.body)) });
    return new Response(null, { status: 200 });
  }
  const env = {
    DB: makeMigratedD1(),
    BUNDLES: makeR2(),
    FILES: makeR2(),
    MAKE_FOUNDER_USER_ID: FOUNDER,
    ACCOUNT_DELETION_TOKEN: DELETION_TOKEN,
    REPAIR_RUNNER_TOKEN: RUNNER_TOKEN,
    APNS_KEY_P8: KEY_P8,
    APNS_KEY_ID: "KEY1234567",
    APNS_TEAM_ID: "ZQ2JPFYL98",
    PUSH_FETCH: fakeApnsFetch,
  };
  return { env, pushes };
}

type TestEnv = ReturnType<typeof makeEnv>["env"];

function asBindings(env: TestEnv): DeletionBindings {
  return env as unknown as DeletionBindings;
}

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addUser(env: TestEnv, userId: string) {
  env.DB.execute("INSERT OR IGNORE INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, NAMES[userId]);
}

function addSession(env: TestEnv, userId: string, label: string): string {
  addUser(env, userId);
  const token = `token-${userId}-${label}`;
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', ?)", sha256Hex(token), userId, Date.now() + 3600_000);
  return token;
}

function addDevice(env: TestEnv, userId: string, deviceToken: string) {
  addUser(env, userId);
  env.DB.execute(
    "INSERT INTO push_devices (token, user_id, env, bundle_id, created_at, updated_at) VALUES (?, ?, 'sandbox', 'com.bhuvanrj.midas.test', 'then', 'then')",
    deviceToken,
    userId,
  );
}

function seedOp(env: TestEnv, opId: string, userId: string, sidekickId: string, key: string, value: unknown) {
  const isDelete = value === null;
  env.DB.execute(
    "INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, received_at) VALUES (?, ?, ?, ?, ?, ?, 'then')",
    opId,
    userId,
    sidekickId,
    key,
    isDelete ? null : JSON.stringify(value),
    isDelete ? 1 : 0,
  );
}

const FOUNDER_DEVICE = "f".repeat(64);

// The founder: a phone, his own Reminders records, his own file and the base Water Sidekick.
async function seedFounder(env: TestEnv) {
  addDevice(env, FOUNDER, FOUNDER_DEVICE);
  seedOp(env, "f-own-1", FOUNDER, "reminders", "reminder:f1", { $type: "reminder", title: "Call mum" });
  await env.FILES.put(`${FOUNDER}/founder-own-file`, "mine", { customMetadata: { userId: FOUNDER } });
  await env.BUNDLES.put("sidekicks/water/current.json", JSON.stringify({ version: "w1" }));
  await env.BUNDLES.put("sidekicks/water/w1/index.html", "<p>water</p>");
}

// One of everything a person can have, with the counts a deletion should find.
async function seedPerson(env: TestEnv, userId: string): Promise<{ reportId: string; expected: PersonCounts }> {
  addUser(env, userId);
  const reportId = randomUUID();
  const requestKey = `req${userId.replace(/[^A-Za-z0-9]/g, "")}0000000`.slice(0, 12);
  env.DB.execute("INSERT INTO passkeys (credential_id, user_id, public_key, counter, created_at) VALUES (?, ?, 'pk', 0, 'then')", `cred-${userId}`, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', 0)", `old-session-${userId}`, userId);
  env.DB.execute("INSERT INTO auth_challenges (id, challenge, purpose, user_id, expires_at) VALUES (?, 'c', 'login', ?, 0)", `ch-${userId}`, userId);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'water', ?)", userId, TIME);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at, removed_at) VALUES (?, 'reminders', ?, ?)", userId, TIME, TIME);
  env.DB.execute("INSERT INTO sidekick_removals (id, user_id, sidekick_id, records_removed, removed_at) VALUES (?, ?, 'reminders', 1, ?)", `rm-${userId}`, userId, TIME);
  seedOp(env, `op-${userId}-1`, userId, "water", "drink:1", { $type: "hydration.drink", ml: 250 });
  seedOp(env, `op-${userId}-2`, userId, "water", "drink:2", { $type: "hydration.drink", ml: 300 });
  seedOp(env, `op-${userId}-3`, userId, "make", `req:${requestKey}`, { $type: "make.request", text: "a gym log" });
  env.DB.execute("INSERT INTO voice_logs (id, user_id, created_at, transcript, model, status) VALUES (?, ?, ?, 'remind me to stretch', 'm', 'done')", `vl-${userId}`, userId, TIME);
  env.DB.execute(
    "INSERT INTO jess_requests (user_id, request_id, state, sends, claimed_at, created_at, updated_at) VALUES (?, ?, 'answered', 1, ?, ?, ?)",
    userId,
    `jr-${userId}`,
    TIME,
    TIME,
    TIME,
  );
  env.DB.execute(
    "INSERT INTO repair_reports (id, user_id, sidekick_id, kind, transcript, status, screenshot_key, created_at, updated_at) VALUES (?, ?, 'water', 'change', 'bigger cups', 'deployed_live', ?, ?, ?)",
    reportId,
    userId,
    `repairs/${reportId}/screenshot.png`,
    TIME,
    TIME,
  );
  env.DB.execute("INSERT INTO repair_events (id, report_id, audience, kind, created_at) VALUES (?, ?, 'founder', 'request_received', ?)", `ev-${userId}`, reportId, TIME);
  env.DB.execute(
    "INSERT INTO jess_pending_requests (id, user_id, sidekick_id, report_id, log_id, transcript, feature, request_now, time_zone, status, steps, created_at, updated_at) VALUES (?, ?, 'water', ?, 'l', 't', 'f', ?, 'UTC', 'done', '[]', ?, ?)",
    `jp-${userId}`,
    userId,
    reportId,
    TIME,
    TIME,
    TIME,
  );
  env.DB.execute("INSERT INTO repair_blocked (id, user_id, sidekick_id, client_id, created_at) VALUES (?, ?, 'make', ?, ?)", `rb-${userId}`, userId, `cl-${userId}`, TIME);
  addDevice(env, userId, `device-${userId}`);
  env.DB.execute(
    "INSERT INTO make_events (id, audience, user_id, about_user_id, request_id, kind, title, body, created_at) VALUES (?, 'person', ?, ?, 'r', 'message', 'Make', 'hi', ?)",
    `me-p-${userId}`,
    userId,
    userId,
    TIME,
  );
  env.DB.execute(
    "INSERT INTO make_events (id, audience, user_id, about_user_id, request_id, kind, title, body, created_at) VALUES (?, 'founder', ?, ?, 'r', 'message', 'Inbox', 'a gym log', ?)",
    `me-f-${userId}`,
    FOUNDER,
    userId,
    TIME,
  );
  // The founder's inbox copies: two live keys and one key deleted earlier
  seedOp(env, `inb-${userId}-1`, FOUNDER, "make-inbox", `person:${userId}`, { $type: "make.person", name: NAMES[userId] });
  seedOp(env, `inb-${userId}-2`, FOUNDER, "make-inbox", `req:${userId}:${requestKey}`, { $type: "make.request", text: "a gym log" });
  seedOp(env, `inb-${userId}-3`, FOUNDER, "make-inbox", `message:${userId}:${requestKey}:msg0000001`, { $type: "make.message", text: "ok" });
  seedOp(env, `inb-${userId}-4`, FOUNDER, "make-inbox", `message:${userId}:${requestKey}:msg0000001`, null);
  // R2: their files, a picture they sent through Make (copied to the founder), their Sidekick copy,
  // their Edit's screenshot and strokes
  await env.FILES.put(`${userId}/photo1`, "p1", { customMetadata: { userId } });
  await env.FILES.put(`${userId}/photo2`, "p2", { customMetadata: { userId } });
  await env.FILES.put(`${FOUNDER}/from-${userId}`, "p1", { customMetadata: { userId: FOUNDER, copiedFrom: userId } });
  await env.BUNDLES.put(`sidekicks/water/users/${userId}/current.json`, JSON.stringify({ version: "u1" }));
  await env.BUNDLES.put(`sidekicks/water/users/${userId}/u1/index.html`, "<p>their water</p>");
  await env.BUNDLES.put(`repairs/${reportId}/screenshot.png`, "png");
  await env.BUNDLES.put(`repairs/${reportId}/strokes.json`, "[]");
  const expected: PersonCounts = {
    users: 1,
    passkeys: 1,
    sessions: 1,
    auth_challenges: 1,
    assignments: 2,
    sidekick_removals: 1,
    ops: 3,
    voice_logs: 1,
    jess_requests: 1,
    jess_pending_requests: 1,
    repair_reports: 1,
    repair_events: 1,
    repair_blocked: 1,
    push_devices: 1,
    make_events: 2,
    account_deletion_requests: 0,
    "make-inbox ops": 4,
    "R2 files": 2,
    "R2 founder copies": 1,
    "R2 sidekick copies": 2,
    "R2 edit files": 2,
  };
  return { reportId, expected };
}

function addRequest(env: TestEnv, userId: string, requestedAt = TIME, alertResult: string | null = "sent 1 of 1") {
  env.DB.execute("INSERT INTO account_deletion_requests (user_id, user_name, requested_at, alert_result) VALUES (?, ?, ?, ?)", userId, NAMES[userId], requestedAt, alertResult);
}

function deletionHeaders(token = DELETION_TOKEN) {
  return { Authorization: `Deletion ${token}` };
}

async function carryOut(env: TestEnv, userId: string, headers: Record<string, string> = deletionHeaders()) {
  return worker.request(`/account-deletions/${userId}/carry-out`, { method: "POST", headers }, env);
}

async function countsVia(env: TestEnv, userId: string) {
  const response = await worker.request(`/account-deletions/${userId}`, { headers: deletionHeaders() }, env);
  expect(response.status).toBe(200);
  return (await response.json()) as { state: string; counts: PersonCounts; total: number; allZero: boolean; nonZero: string[] };
}

// Everyone's data as rows and keys, minus the person's: what must not change.
function everythingButPerson(env: TestEnv, reportId: string): unknown {
  const tables = [
    "users", "passkeys", "sessions", "auth_challenges", "assignments", "sidekick_removals", "voice_logs", "jess_requests",
    "jess_pending_requests", "repair_reports", "repair_events", "repair_blocked", "push_devices", "make_events",
  ];
  const snapshot: Record<string, unknown> = {};
  for (const table of tables) {
    snapshot[table] = env.DB.query(`SELECT * FROM ${table} ORDER BY rowid`);
  }
  snapshot.ops = env.DB.query("SELECT op_id, user_id, sidekick_id, key, value, deleted FROM ops ORDER BY seq");
  snapshot.files = env.FILES.keys();
  snapshot.bundles = env.BUNDLES.keys();
  return filterPerson(snapshot, reportId);
}

function filterPerson(snapshot: Record<string, unknown>, reportId: string): unknown {
  const filtered: Record<string, unknown> = {};
  for (const [name, value] of Object.entries(snapshot)) {
    const items = value as unknown[];
    filtered[name] = items.filter(function isNotThePersons(item) {
      return !belongsToPerson(item, reportId);
    });
  }
  return filtered;
}

function belongsToPerson(item: unknown, reportId: string): boolean {
  if (typeof item === "string") {
    return item.startsWith(`${PERSON}/`) || item.includes(`/users/${PERSON}/`) || item.startsWith(`repairs/${reportId}/`) || item === `${FOUNDER}/from-${PERSON}`;
  }
  const row = item as Record<string, unknown>;
  if (row.user_id === PERSON || row.id === PERSON || row.about_user_id === PERSON || row.report_id === reportId) {
    return true;
  }
  return typeof row.key === "string" && row.user_id === FOUNDER && isInboxKeyAbout(row.key, PERSON);
}

async function seededWorld() {
  const { env, pushes } = makeEnv();
  await seedFounder(env);
  const person = await seedPerson(env, PERSON);
  for (const otherId of LOOK_ALIKES) {
    await seedPerson(env, otherId);
  }
  addRequest(env, PERSON);
  return { env, pushes, reportId: person.reportId, expected: person.expected };
}

type PulledOp = { key: string; deleted: boolean; value?: unknown };

function keysStartingWith(keys: string[], prefix: string): string[] {
  const matching: string[] = [];
  for (const key of keys) {
    if (key.startsWith(prefix)) {
      matching.push(key);
    }
  }
  return matching;
}

function keyAndDeleted(op: PulledOp): string {
  return `${op.key}:${op.deleted}`;
}

function liveInboxOpsAbout(ops: PulledOp[], userId: string): PulledOp[] {
  const live: PulledOp[] = [];
  for (const op of ops) {
    if (isInboxKeyAbout(op.key, userId) && op.value !== null) {
      live.push(op);
    }
  }
  return live;
}

function isFounderReminder(op: PulledOp): boolean {
  return op.key === "reminder:f1";
}

function pushTitle(push: Pushed): string {
  const aps = push.body.aps as { alert: { title: string } };
  return aps.alert.title;
}

function columnName(column: Record<string, unknown>): unknown {
  return column.name;
}

describe("carry-out: all of the person's data goes", () => {
  it("removes every row and object of theirs, counts what went and the check comes back all zero", async () => {
    const { env, reportId, expected } = await seededWorld();
    const response = await carryOut(env, PERSON);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { deleted: boolean; counts: PersonCounts; allZero: boolean; check: PersonCounts };
    expect(body.deleted).toBe(true);
    expect(body.allZero).toBe(true);
    expect(totalOf(body.check)).toBe(0);
    const expectedRemoved = { ...expected, account_deletion_requests: 1 };
    expect(body.counts).toEqual(expectedRemoved);

    expect(env.DB.query("SELECT COUNT(*) AS count FROM users WHERE id = ?", PERSON)).toEqual([{ count: 0 }]);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM ops WHERE user_id = ?", PERSON)).toEqual([{ count: 0 }]);
    expect(keysStartingWith(env.FILES.keys(), `${PERSON}/`)).toEqual([]);
    expect(keysStartingWith(env.BUNDLES.keys(), `repairs/${reportId}/`)).toEqual([]);
    const check = await countsVia(env, PERSON);
    expect(check.state).toBe("done");
    expect(check.allZero).toBe(true);
    expect(check.nonZero).toEqual([]);
  });

  it("the done row keeps no name, the counts and the person's Edit job ids", async () => {
    const { env, reportId } = await seededWorld();
    await carryOut(env, PERSON);
    const done = env.DB.query("SELECT * FROM account_deletions_done") as Array<Record<string, unknown>>;
    expect(done.length).toBe(1);
    expect(done[0].user_id).toBe(PERSON);
    expect(done[0].requested_at).toBe(TIME);
    expect(JSON.parse(String(done[0].report_ids))).toEqual([reportId]);
    expect(JSON.parse(String(done[0].counts)).ops).toBe(3);
    expect(JSON.stringify(done[0])).not.toContain("Priya");
    expect(env.DB.query("SELECT COUNT(*) AS count FROM account_deletion_requests")).toEqual([{ count: 0 }]);
  });

  it("the preview changes nothing and finds exactly the seeded data", async () => {
    const { env, expected } = await seededWorld();
    const before = env.DB.query("SELECT COUNT(*) AS count FROM ops");
    const preview = await countsVia(env, PERSON);
    expect(preview.state).toBe("open");
    expect(preview.counts).toEqual({ ...expected, account_deletion_requests: 1 });
    expect(preview.allZero).toBe(false);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM ops")).toEqual(before);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM users WHERE id = ?", PERSON)).toEqual([{ count: 1 }]);
  });
});

describe("carry-out: nothing else is touched", () => {
  it("other people (look-alike ids too), the founder's own data and the shared Sidekick pages stay exactly as they were", async () => {
    const { env, reportId } = await seededWorld();
    const before = everythingButPerson(env, reportId);
    const othersBefore: Record<string, PersonCounts> = {};
    for (const otherId of LOOK_ALIKES) {
      othersBefore[otherId] = await countPersonData(asBindings(env), otherId, []);
    }
    await carryOut(env, PERSON);
    expect(everythingButPerson(env, reportId)).toEqual(before);
    // The founder's inbox gains only delete markers: one per live inbox key of the person's, no value
    const writtenMarkers = env.DB.query("SELECT user_id, key, value, deleted FROM ops WHERE op_id LIKE 'account-deleted:%' ORDER BY key");
    expect(writtenMarkers).toEqual([
      { user_id: FOUNDER, key: `person:${PERSON}`, value: null, deleted: 1 },
      { user_id: FOUNDER, key: `req:${PERSON}:reqabc000000`, value: null, deleted: 1 },
    ]);
    for (const otherId of LOOK_ALIKES) {
      expect(await countPersonData(asBindings(env), otherId, [])).toEqual(othersBefore[otherId]);
      expect(totalOf(othersBefore[otherId])).toBeGreaterThan(10);
    }
    expect(env.BUNDLES.keys()).toContain("sidekicks/water/current.json");
    expect(env.BUNDLES.keys()).toContain("sidekicks/water/w1/index.html");
    expect(env.FILES.keys()).toContain(`${FOUNDER}/founder-own-file`);
  });

  it("a file id the founder and the person share: the founder's original stays, only the copy from the person goes", async () => {
    const { env } = await seededWorld();
    // The founder sent the person a picture (his original, copied to them), and another person's
    // picture sits in the founder's folder; both stay
    await env.FILES.put(`${FOUNDER}/shared01`, "founder's", { customMetadata: { userId: FOUNDER } });
    await env.FILES.put(`${PERSON}/shared01`, "founder's", { customMetadata: { userId: PERSON, copiedFrom: FOUNDER } });
    await env.FILES.put(`${FOUNDER}/fromsam01`, "sam's", { customMetadata: { userId: FOUNDER, copiedFrom: "abXc" } });
    await carryOut(env, PERSON);
    const keys = env.FILES.keys();
    expect(keys).toContain(`${FOUNDER}/shared01`);
    expect(keys).toContain(`${FOUNDER}/fromsam01`);
    expect(keys).not.toContain(`${PERSON}/shared01`);
    expect(keys).not.toContain(`${FOUNDER}/from-${PERSON}`);
  });

  it("the founder's phone drops the inbox copies on its next pull; his other records stay", async () => {
    const { env } = await seededWorld();
    const founderToken = addSession(env, FOUNDER, "phone");
    const beforePull = await worker.request("/sync/pull?after=0", { headers: { Authorization: `Bearer ${founderToken}` } }, env);
    const beforeBody = (await beforePull.json()) as { lastSeq: number };
    await carryOut(env, PERSON);
    const nextPull = await worker.request(`/sync/pull?after=${beforeBody.lastSeq}`, { headers: { Authorization: `Bearer ${founderToken}` } }, env);
    const nextBody = (await nextPull.json()) as { ops: Array<{ key: string; deleted: boolean }> };
    const droppedKeys = nextBody.ops.map(keyAndDeleted);
    droppedKeys.sort();
    expect(droppedKeys).toEqual([`person:${PERSON}:true`, `req:${PERSON}:reqabc000000:true`].sort());

    const fullPull = await worker.request("/sync/pull?after=0", { headers: { Authorization: `Bearer ${founderToken}` } }, env);
    const fullBody = (await fullPull.json()) as { ops: Array<{ key: string; deleted: boolean; value: unknown }> };
    const personValues = liveInboxOpsAbout(fullBody.ops, PERSON);
    expect(personValues).toEqual([]);
    expect(fullBody.ops.some(isFounderReminder)).toBe(true);
    expect(liveInboxOpsAbout(fullBody.ops, "abXc").length).toBeGreaterThan(0);
  });

  it("inbox keys are matched on the whole user id", () => {
    expect(isInboxKeyAbout("req:ab_c:r1", "ab_c")).toBe(true);
    expect(isInboxKeyAbout("person:ab_c", "ab_c")).toBe(true);
    expect(isInboxKeyAbout("req:ab_cd:r1", "ab_c")).toBe(false);
    expect(isInboxKeyAbout("req:abXc:r1", "ab_c")).toBe(false);
    expect(isInboxKeyAbout("note:ab_c:r1", "ab_c")).toBe(false);
  });
});

describe("carry-out: who may, and for whom", () => {
  it("refuses the founder's own account, changing nothing", async () => {
    const { env } = await seededWorld();
    addRequest(env, FOUNDER);
    const opsBefore = env.DB.query("SELECT COUNT(*) AS count FROM ops");
    const response = await carryOut(env, FOUNDER);
    expect(response.status).toBe(409);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM ops")).toEqual(opsBefore);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM users WHERE id = ?", FOUNDER)).toEqual([{ count: 1 }]);
  });

  it("only for a person who asked: no request is 404 and nothing goes", async () => {
    const { env } = await seededWorld();
    const response = await carryOut(env, "abXc");
    expect(response.status).toBe(404);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM users WHERE id = 'abXc'")).toEqual([{ count: 1 }]);
  });

  it("a second run says already deleted", async () => {
    const { env } = await seededWorld();
    expect((await carryOut(env, PERSON)).status).toBe(200);
    const again = await carryOut(env, PERSON);
    expect(again.status).toBe(409);
  });

  it("needs the deletion token: none, a wrong one, a session or the runner's are refused", async () => {
    const { env } = await seededWorld();
    const personToken = addSession(env, PERSON, "phone");
    const founderToken = addSession(env, FOUNDER, "phone");
    const refusedHeaders = [
      {},
      deletionHeaders("wrong"),
      { Authorization: `Bearer ${personToken}` },
      { Authorization: `Bearer ${founderToken}` },
      { Authorization: `Runner ${RUNNER_TOKEN}` },
      { Authorization: `Deletion ${RUNNER_TOKEN}` },
    ];
    for (const headers of refusedHeaders) {
      expect((await carryOut(env, PERSON, headers)).status).toBe(401);
      expect((await worker.request(`/account-deletions/${PERSON}`, { headers }, env)).status).toBe(401);
    }
    expect(env.DB.query("SELECT COUNT(*) AS count FROM users WHERE id = ?", PERSON)).toEqual([{ count: 1 }]);
    const unset = { ...env, ACCOUNT_DELETION_TOKEN: undefined };
    expect((await carryOut(unset as TestEnv, PERSON)).status).toBe(401);
  });

  it("refuses a user id outside the id pattern", async () => {
    const { env } = await seededWorld();
    const response = await worker.request("/account-deletions/ab%25c/carry-out", { method: "POST", headers: deletionHeaders() }, env);
    expect(response.status).toBe(400);
  });
});

describe("the founder is told", () => {
  it("done: one push \"Account Deleted\" with what went, stored on the done row", async () => {
    const { env, pushes } = await seededWorld();
    await carryOut(env, PERSON);
    expect(pushes.length).toBe(1);
    expect(pushes[0].url).toContain(FOUNDER_DEVICE);
    const aps = pushes[0].body.aps as { alert: { title: string; body: string } };
    expect(aps.alert).toEqual({ title: ACCOUNT_DELETED_PUSH_TITLE, body: accountDeletedPushBody("Priya") });
    expect(accountDeletedPushBody("Priya")).toBe("Priya's account is deleted.");
    const founderAlert = pushes[0].body.founderAlert as { kind: string; userId: string; counts: PersonCounts; allZero: boolean };
    expect(founderAlert.kind).toBe("account-deleted");
    expect(founderAlert.userId).toBe(PERSON);
    expect(founderAlert.counts.ops).toBe(3);
    expect(founderAlert.allZero).toBe(true);
    expect(env.DB.query("SELECT alert_result FROM account_deletions_done")).toEqual([{ alert_result: "sent 1 of 1" }]);
  });

  it("stopped part way (R2 fails): the request stays open with the error, the founder is told how much is left, a second run finishes", async () => {
    const { env, pushes } = await seededWorld();
    env.FILES.control.failDeleteOnCall = 2;
    const first = await carryOut(env, PERSON);
    expect(first.status).toBe(500);
    const firstBody = (await first.json()) as { deleted: boolean; error: string; remaining: PersonCounts };
    expect(firstBody.deleted).toBe(false);
    expect(firstBody.error).toBe("R2 is down");
    expect(firstBody.remaining.users).toBe(1);
    expect(firstBody.remaining["R2 founder copies"]).toBe(1);
    expect(firstBody.remaining["R2 files"]).toBe(0);
    expect(env.DB.query("SELECT last_error FROM account_deletion_requests WHERE user_id = ?", PERSON)).toEqual([{ last_error: "R2 is down" }]);
    expect(env.DB.query("SELECT COUNT(*) AS count FROM account_deletions_done")).toEqual([{ count: 0 }]);
    expect(pushes.length).toBe(1);
    const left = totalOf(firstBody.remaining);
    const aps = pushes[0].body.aps as { alert: { title: string; body: string } };
    expect(aps.alert).toEqual({ title: ACCOUNT_DELETION_INCOMPLETE_PUSH_TITLE, body: accountDeletionIncompletePushBody("Priya", left) });
    expect(accountDeletionIncompletePushBody("Priya", 3)).toBe("Priya: 3 items left. Run it again.");

    env.FILES.control.failDeleteOnCall = 0;
    const second = await carryOut(env, PERSON);
    expect(second.status).toBe(200);
    expect(((await second.json()) as { allZero: boolean }).allZero).toBe(true);
    expect((await countsVia(env, PERSON)).allZero).toBe(true);
  });

  it("the check names what is left when something was put back after", async () => {
    const { env } = await seededWorld();
    await carryOut(env, PERSON);
    await env.FILES.put(`${PERSON}/late`, "x", { customMetadata: { userId: PERSON } });
    const check = await countsVia(env, PERSON);
    expect(check.allZero).toBe(false);
    expect(check.nonZero).toEqual(["R2 files"]);
  });

  it("asked again after an alert that reached no phone: sent again; after one that did: not", async () => {
    const { env, pushes } = makeEnv();
    const first = addSession(env, PERSON, "first");
    expect((await worker.request("/account/delete-request", { method: "POST", headers: { Authorization: `Bearer ${first}` } }, env)).status).toBe(201);
    expect(env.DB.query("SELECT alert_result FROM account_deletion_requests")).toEqual([{ alert_result: "no devices" }]);
    expect(pushes.length).toBe(0);
    addDevice(env, FOUNDER, FOUNDER_DEVICE);
    const second = addSession(env, PERSON, "second");
    expect((await worker.request("/account/delete-request", { method: "POST", headers: { Authorization: `Bearer ${second}` } }, env)).status).toBe(200);
    expect(pushes.length).toBe(1);
    expect(env.DB.query("SELECT alert_result FROM account_deletion_requests")).toEqual([{ alert_result: "sent 1 of 1" }]);
    const third = addSession(env, PERSON, "third");
    await worker.request("/account/delete-request", { method: "POST", headers: { Authorization: `Bearer ${third}` } }, env);
    expect(pushes.length).toBe(1);
  });

  it("delivered means at least one phone got it", () => {
    expect(isDeliveredAlert("sent 1 of 1")).toBe(true);
    expect(isDeliveredAlert("sent 2 of 3; failed 1 (x)")).toBe(true);
    expect(isDeliveredAlert("sent 0 of 1; failed 1 (x)")).toBe(false);
    expect(isDeliveredAlert("no devices")).toBe(false);
    expect(isDeliveredAlert("apns not set up")).toBe(false);
    expect(isDeliveredAlert(null)).toBe(false);
  });

  it("the list shows each open request's age, due date and whether the alert arrived, and the done ones", async () => {
    const { env } = await seededWorld();
    addRequest(env, "abXc", new Date(Date.now() - 2 * 86400_000).toISOString(), "no devices");
    await carryOut(env, PERSON);
    const response = await worker.request("/account-deletions", { headers: deletionHeaders() }, env);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      founderSet: boolean;
      founderDevices: number;
      open: Array<{ userId: string; userName: string; ageDays: number; alertDelivered: boolean }>;
      done: Array<{ userId: string; runnerCleanedAt: string | null }>;
    };
    expect(body.founderSet).toBe(true);
    expect(body.founderDevices).toBe(1);
    expect(body.open.length).toBe(1);
    expect(body.open[0]).toMatchObject({ userId: "abXc", userName: "Sam", ageDays: 2, alertDelivered: false });
    expect(body.done.length).toBe(1);
    expect(body.done[0]).toMatchObject({ userId: PERSON, runnerCleanedAt: null });
  });
});

describe("the daily reminder", () => {
  it("day 6: one \"Delete Account Due\" push, once; a newer request gets none", async () => {
    const { env, pushes } = makeEnv();
    addDevice(env, FOUNDER, FOUNDER_DEVICE);
    addUser(env, PERSON);
    addUser(env, "abXc");
    addRequest(env, PERSON, "2026-10-31T18:00:00.000Z");
    addRequest(env, "abXc", "2026-11-05T18:00:00.000Z");
    const now = Date.parse("2026-11-06T19:00:00.000Z");
    await remindOpenDeletions(asBindings(env), now, alertFounder);
    expect(pushes.length).toBe(1);
    const aps = pushes[0].body.aps as { alert: { title: string; body: string } };
    expect(aps.alert).toEqual({ title: ACCOUNT_DELETION_DUE_PUSH_TITLE, body: accountDeletionDuePushBody("Priya", "Sat 7 Nov") });
    expect(accountDeletionDuePushBody("Priya", "Sat 7 Nov")).toBe("Priya's account must be deleted by Sat 7 Nov.");
    await remindOpenDeletions(asBindings(env), now + 86400_000 / 2, alertFounder);
    expect(pushes.length).toBe(1);
  });

  it("an alert that reached no phone is sent again; a reminder that reached none is tried again", async () => {
    const { env, pushes } = makeEnv();
    addUser(env, PERSON);
    addRequest(env, PERSON, "2026-10-31T18:00:00.000Z", "no devices");
    const now = Date.parse("2026-11-06T19:00:00.000Z");
    await remindOpenDeletions(asBindings(env), now, alertFounder);
    expect(pushes.length).toBe(0);
    expect(env.DB.query("SELECT reminded_at FROM account_deletion_requests")).toEqual([{ reminded_at: null }]);
    addDevice(env, FOUNDER, FOUNDER_DEVICE);
    await remindOpenDeletions(asBindings(env), now, alertFounder);
    const titles = pushes.map(pushTitle);
    expect(titles).toEqual(["Delete Account", ACCOUNT_DELETION_DUE_PUSH_TITLE]);
    expect(env.DB.query("SELECT alert_result FROM account_deletion_requests")).toEqual([{ alert_result: "sent 1 of 1" }]);
  });

  it("the Worker's cron handler runs it", async () => {
    const { env, pushes } = makeEnv();
    addDevice(env, FOUNDER, FOUNDER_DEVICE);
    addUser(env, PERSON);
    addRequest(env, PERSON, new Date(Date.now() - 6.5 * 86400_000).toISOString());
    const waited: Promise<unknown>[] = [];
    const executionContext = { waitUntil: (promise: Promise<unknown>) => waited.push(promise), passThroughOnException: () => {} };
    await worker.scheduled({ cron: "0 16 * * *", scheduledTime: Date.now(), noRetry: () => {} } as unknown as ScheduledController, env as never, executionContext as unknown as ExecutionContext);
    expect(pushes.length).toBe(1);
    expect(waited.length).toBe(1);
  });

  it("the due date is the 7th day", () => {
    expect(dueDateText("2026-11-02T10:00:00.000Z")).toBe("Mon 9 Nov");
  });
});

describe("the runner's clean-up routes", () => {
  it("lists done deletions with their job ids until the runner reports them cleaned", async () => {
    const { env, reportId } = await seededWorld();
    await carryOut(env, PERSON);
    const runnerHeaders = { Authorization: `Runner ${RUNNER_TOKEN}` };
    const pending = await worker.request("/account-deletions/runner/pending", { headers: runnerHeaders }, env);
    expect(await pending.json()).toEqual({ deletions: [{ userId: PERSON, reportIds: [reportId] }] });
    const cleaned = await worker.request(
      `/account-deletions/runner/${PERSON}/cleaned`,
      { method: "POST", headers: { ...runnerHeaders, "Content-Type": "application/json" }, body: JSON.stringify({ result: "removed 4 folders for 1 jobs" }) },
      env,
    );
    expect(cleaned.status).toBe(200);
    const after = await worker.request("/account-deletions/runner/pending", { headers: runnerHeaders }, env);
    expect(await after.json()).toEqual({ deletions: [] });
    const again = await worker.request(`/account-deletions/runner/${PERSON}/cleaned`, { method: "POST", headers: runnerHeaders }, env);
    expect(again.status).toBe(404);
    const check = await countsVia(env, PERSON);
    expect((check as unknown as { runner: { result: string } }).runner.result).toBe("removed 4 folders for 1 jobs");
  });

  it("needs the runner token", async () => {
    const { env } = await seededWorld();
    expect((await worker.request("/account-deletions/runner/pending", { headers: deletionHeaders() }, env)).status).toBe(401);
    expect((await worker.request("/account-deletions/runner/pending", {}, env)).status).toBe(401);
  });
});

describe("migration 0014", () => {
  it("adds the done table and two columns to the request", () => {
    const db = makeMigratedD1();
    const doneColumns = db.query("SELECT name FROM pragma_table_info('account_deletions_done') ORDER BY cid");
    expect(doneColumns).toEqual([
      { name: "user_id" }, { name: "requested_at" }, { name: "carried_out_at" }, { name: "counts" },
      { name: "report_ids" }, { name: "alert_result" }, { name: "runner_cleaned_at" }, { name: "runner_result" },
    ]);
    const requestColumns = db.query("SELECT name FROM pragma_table_info('account_deletion_requests') ORDER BY cid");
    expect(requestColumns.map(columnName)).toEqual(["user_id", "user_name", "requested_at", "alert_result", "carried_out_at", "last_error", "reminded_at"]);
    const foreignKeys = db.query("SELECT * FROM pragma_foreign_key_list('account_deletions_done')");
    expect(foreignKeys).toEqual([]);
  });
});
