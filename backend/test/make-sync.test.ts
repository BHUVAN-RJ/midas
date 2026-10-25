import { createHash, generateKeyPairSync } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { resetApnsTokenCache } from "../src/apns";
import { copyOpId, personRecordOpId, pushBodyText } from "../src/make";
import { makeFakeR2 } from "../test/helpers/fake-r2";
import { makeMigratedD1 } from "../test/helpers/migrated-d1";

// Make on /sync (founder, 2026-10-24; docs/briefs/make-contract.md sections 2-4). A person writes
// req:, message: and answer: records in their "make" store; each is copied into the founder's
// "make-inbox" under a key starting with the person's id. The founder writes status changes and
// messages in the inbox; they are copied back into the person's store. Built assigns the
// Sidekick. Pushes: a person's message or answer to the founder, Built to the person.

const FOUNDER = "u-founder";
const PERSON = "u-priya";
const OTHER = "u-sam";
const REQ = "req00001";
const MSG = "msg00001";
const CARD = "card0001";
const TIME = "2026-10-24T18:00:00.000Z";
const RUNNER_TOKEN = "runner-secret";
const KEY_P8 = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();

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
    "sidekicks/reminders/current.json": JSON.stringify({ version: "v2", scriptHashes: [] }),
    "sidekicks/reminders/v2/manifest.json": JSON.stringify({ id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [], types: {} }),
  });
  const env = {
    DB: makeMigratedD1(),
    BUNDLES: bundles,
    FILES: makeFakeR2(),
    MAKE_FOUNDER_USER_ID: founderId ?? undefined,
    REPAIR_RUNNER_TOKEN: RUNNER_TOKEN,
    APNS_KEY_P8: KEY_P8,
    APNS_KEY_ID: "KEY1234567",
    APNS_TEAM_ID: "ZQ2JPFYL98",
    PUSH_FETCH: fakeApnsFetch,
  };
  return { env, calls };
}

type TestEnv = ReturnType<typeof makeEnv>["env"];
type PushReply = { accepted: string[]; rejected: Array<{ opId: string; error: string }> };

const NAMES: Record<string, string> = { [FOUNDER]: "Bhuvan", [PERSON]: "Priya", [OTHER]: "Sam" };

function addUser(env: TestEnv, userId: string, name: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT OR IGNORE INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, name);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

function addDevice(env: TestEnv, userId: string, token: string) {
  env.DB.execute("INSERT OR IGNORE INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, NAMES[userId]);
  env.DB.execute("INSERT INTO push_devices (token, user_id, env, bundle_id, created_at, updated_at) VALUES (?, ?, 'sandbox', 'com.bhuvanrj.midas.test', 'then', 'then')", token, userId);
}

// Collects waitUntil work so a test can wait for the pushes sent after the response.
function makeExecutionContext() {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  async function settle() {
    await Promise.all(pending);
  }
  return { context: { waitUntil, passThroughOnException, props: {} }, pending, settle };
}

type Op = { opId: string; sidekickId: string; key: string; value?: unknown; deleted?: boolean };

async function push(env: TestEnv, token: string, ops: Op[]): Promise<PushReply> {
  const execution = makeExecutionContext();
  const fullOps = [];
  for (const op of ops) {
    fullOps.push({ deleted: false, clientTime: TIME, ...op });
  }
  const requestInit = { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ ops: fullOps }) };
  const response = await app.request("/sync/push", requestInit, env, execution.context as unknown as ExecutionContext);
  expect(response.status).toBe(200);
  await execution.settle();
  return (await response.json()) as PushReply;
}

function request(fields: Record<string, unknown> = {}) {
  return { $type: "make.request", title: "A lamp timer", status: "sent", createdAt: TIME, updatedAt: TIME, ...fields };
}

function message(from: string, text: string, fields: Record<string, unknown> = {}) {
  return { $type: "make.message", from, text, sentAt: TIME, ...fields };
}

function makeOp(opId: string, key: string, value: unknown): Op {
  return { opId, sidekickId: "make", key, value };
}

function inboxOp(opId: string, key: string, value: unknown): Op {
  return { opId, sidekickId: "make-inbox", key, value };
}

function storedValues(env: TestEnv, userId: string, sidekickId: string) {
  const rows = env.DB.query("SELECT op_id, key, value FROM ops WHERE user_id = ? AND sidekick_id = ? ORDER BY seq", userId, sidekickId);
  const values: Array<{ opId: unknown; key: unknown; value: unknown }> = [];
  for (const row of rows) {
    values.push({ opId: row.op_id, key: row.key, value: JSON.parse(String(row.value)) });
  }
  return values;
}

function opCount(env: TestEnv): number {
  const rows = env.DB.query("SELECT COUNT(*) AS count FROM ops");
  return Number(rows[0].count);
}

function events(env: TestEnv) {
  return env.DB.query("SELECT id, audience, user_id, about_user_id, request_id, kind, title, body FROM make_events ORDER BY id");
}

// A person with a request and its first message stored (and copied to the inbox).
async function personWithRequest(env: TestEnv) {
  const founderToken = addUser(env, FOUNDER, "Bhuvan");
  const personToken = addUser(env, PERSON, "Priya");
  const reply = await push(env, personToken, [makeOp("op-req-0001", `req:${REQ}`, request()), makeOp("op-msg-0001", `message:${REQ}:${MSG}`, message("person", "Turn my lamp off at 11"))]);
  expect(reply.rejected).toEqual([]);
  return { founderToken, personToken };
}

// A card the server wrote into the person's store (as POST /make/cards does).
function seedCard(env: TestEnv, cardFields: Record<string, unknown> = {}) {
  const card = {
    $type: "make.card",
    question: "Which one?",
    kind: "choice",
    options: [{ id: "opt00001", label: "Every night" }, { id: "opt00002", label: "Weekdays" }],
    allowsOwnWords: false,
    sentAt: TIME,
    ...cardFields,
  };
  env.DB.execute("INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, received_at) VALUES (?, ?, 'make', ?, ?, 0, 'then')", `mkcard-${CARD}-p`, PERSON, `card:${REQ}:${CARD}`, JSON.stringify(card));
}

function answer(fields: Record<string, unknown>) {
  return { $type: "make.answer", cardId: CARD, sentAt: TIME, ...fields };
}

beforeEach(() => {
  resetApnsTokenCache();
});

describe("a person's request reaches the founder's inbox", () => {
  it("stores the request and message and copies both, with userId, plus person:<userId>", async () => {
    const { env } = makeEnv();
    await personWithRequest(env);
    const inbox = storedValues(env, FOUNDER, "make-inbox");
    expect(inbox).toEqual([
      { opId: personRecordOpId(PERSON), key: `person:${PERSON}`, value: { $type: "make.person", userId: PERSON, name: "Priya", firstAt: expect.any(String) } },
      { opId: await copyOpId("op-req-0001", FOUNDER), key: `req:${PERSON}:${REQ}`, value: { ...request(), userId: PERSON } },
      { opId: await copyOpId("op-msg-0001", FOUNDER), key: `message:${PERSON}:${REQ}:${MSG}`, value: { ...message("person", "Turn my lamp off at 11"), userId: PERSON } },
    ]);
    expect(storedValues(env, PERSON, "make")).toHaveLength(2);
  });

  it("copy op ids are mk plus the first 40 hex of SHA-256(source > target)", async () => {
    const expected = `mk${sha256Hex(`op-req-0001>${FOUNDER}`).slice(0, 40)}`;
    expect(await copyOpId("op-req-0001", FOUNDER)).toBe(expected);
    expect(personRecordOpId("x".repeat(80))).toHaveLength(64);
  });

  it("a retried push is accepted again and stores nothing twice", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, FOUNDER, "f".repeat(64));
    const { personToken } = await personWithRequest(env);
    const countBefore = opCount(env);
    const callsBefore = calls.length;
    const reply = await push(env, personToken, [makeOp("op-req-0001", `req:${REQ}`, request()), makeOp("op-msg-0001", `message:${REQ}:${MSG}`, message("person", "Turn my lamp off at 11"))]);
    expect(reply.accepted).toEqual(["op-req-0001", "op-msg-0001"]);
    expect(opCount(env)).toBe(countBefore);
    expect(calls.length).toBe(callsBefore);
  });

  it("writes person:<userId> once, from the first copy", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    await push(env, personToken, [makeOp("op-msg-0002", `message:${REQ}:msg00002`, message("person", "And on weekends"))]);
    const personRecords = env.DB.query("SELECT op_id FROM ops WHERE key = ?", `person:${PERSON}`);
    expect(personRecords).toHaveLength(1);
  });

  it("the person's message pushes the founder: Inbox / <name>: <text>", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, FOUNDER, "f".repeat(64));
    await personWithRequest(env);
    expect(events(env)).toEqual([
      { id: "msg:op-msg-0001", audience: "founder", user_id: FOUNDER, about_user_id: PERSON, request_id: REQ, kind: "message", title: "Inbox", body: "Priya: Turn my lamp off at 11" },
    ]);
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toContain("f".repeat(64));
    expect(calls[0].body).toEqual({
      aps: { alert: { title: "Inbox", body: "Priya: Turn my lamp off at 11" }, sound: "default", "thread-id": `${PERSON}:${REQ}` },
      make: { kind: "message", requestId: REQ, userId: PERSON },
    });
  });

  it("cuts a long push body to 120 characters", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    await push(env, personToken, [makeOp("op-msg-0003", `message:${REQ}:msg00003`, message("person", "a".repeat(300)))]);
    const body = String(events(env)[1].body);
    expect(Array.from(body)).toHaveLength(120);
    expect(body.endsWith("…")).toBe(true);
    expect(pushBodyText("short")).toBe("short");
  });

  it("sends the push in waitUntil, after the response", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, FOUNDER, "f".repeat(64));
    const { personToken } = await personWithRequest(env);
    const execution = makeExecutionContext();
    const op = { ...makeOp("op-msg-0004", `message:${REQ}:msg00004`, message("person", "Thanks")), deleted: false, clientTime: TIME };
    const requestInit = { method: "POST", headers: { Authorization: `Bearer ${personToken}`, "Content-Type": "application/json" }, body: JSON.stringify({ ops: [op] }) };
    const callsBefore = calls.length;
    const response = await app.request("/sync/push", requestInit, env, execution.context as unknown as ExecutionContext);
    expect(response.status).toBe(200);
    expect(execution.pending).toHaveLength(1);
    await execution.settle();
    expect(calls.length).toBe(callsBefore + 1);
  });

  it("the person pulls only their own records; the founder pulls the inbox", async () => {
    const { env } = makeEnv();
    const { founderToken, personToken } = await personWithRequest(env);
    const personPull = await app.request("/sync/pull", { headers: { Authorization: `Bearer ${personToken}` } }, env);
    const personOps = ((await personPull.json()) as { ops: Array<{ sidekickId: string }> }).ops;
    const founderPull = await app.request("/sync/pull", { headers: { Authorization: `Bearer ${founderToken}` } }, env);
    const founderOps = ((await founderPull.json()) as { ops: Array<{ sidekickId: string; key: string }> }).ops;
    expect(personOps).toHaveLength(2);
    expect(founderOps).toHaveLength(3);
    for (const op of founderOps) {
      expect(op.sidekickId).toBe("make-inbox");
    }
  });
});

describe("the person's write rules", () => {
  it("a request is created once: another op for the same key is refused", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    const reply = await push(env, personToken, [makeOp("op-req-0002", `req:${REQ}`, request({ title: "Changed" }))]);
    expect(reply.rejected).toEqual([{ opId: "op-req-0002", error: "request already exists" }]);
  });

  it("two creates of one request in one push: the second is refused", async () => {
    const { env } = makeEnv();
    const personToken = addUser(env, PERSON, "Priya");
    const reply = await push(env, personToken, [makeOp("op-req-0001", `req:${REQ}`, request()), makeOp("op-req-0002", `req:${REQ}`, request())]);
    expect(reply.accepted).toEqual(["op-req-0001"]);
    expect(reply.rejected).toEqual([{ opId: "op-req-0002", error: "request already exists" }]);
  });

  it("a new request is sent, without sidekickId, plan or builtAt", async () => {
    const { env } = makeEnv();
    const personToken = addUser(env, PERSON, "Priya");
    const reply = await push(env, personToken, [
      makeOp("op-req-0001", "req:req00001", request({ status: "building" })),
      makeOp("op-req-0002", "req:req00002", request({ plan: "A timer" })),
    ]);
    expect(reply.rejected).toEqual([
      { opId: "op-req-0001", error: "a new request has status sent" },
      { opId: "op-req-0002", error: "sidekickId, plan and builtAt are set by Make only" },
    ]);
  });

  it("a message needs its request and comes from the person", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    const reply = await push(env, personToken, [
      makeOp("op-msg-0010", `message:req99999:${MSG}`, message("person", "Hello")),
      makeOp("op-msg-0011", `message:${REQ}:msg00011`, message("maker", "Pretending")),
    ]);
    expect(reply.rejected).toEqual([
      { opId: "op-msg-0010", error: "no such request" },
      { opId: "op-msg-0011", error: "from must be person" },
    ]);
  });

  it("cards are written by the server only, deletes are refused, keys must have Make's shape", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    const card = { $type: "make.card", question: "Q?", kind: "choice", options: [{ id: "opt00001", label: "A" }], allowsOwnWords: false, sentAt: TIME };
    const reply = await push(env, personToken, [
      makeOp("op-card-001", `card:${REQ}:${CARD}`, card),
      { opId: "op-del-0001", sidekickId: "make", key: `message:${REQ}:${MSG}`, deleted: true },
      makeOp("op-key-0001", "req:short", request()),
      makeOp("op-key-0002", `req:${REQ}:extra`, request()),
    ]);
    expect(reply.rejected).toEqual([
      { opId: "op-card-001", error: "written by Make only" },
      { opId: "op-del-0001", error: "Make records cannot be deleted" },
      { opId: "op-key-0001", error: "bad Make key" },
      { opId: "op-key-0002", error: "bad Make key" },
    ]);
  });

  it("records are checked against Make's schemas", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    const reply = await push(env, personToken, [
      makeOp("op-msg-0020", `message:${REQ}:msg00020`, { $type: "make.message", from: "person", sentAt: TIME }),
      makeOp("op-req-0020", "req:req00020", { ...request(), title: "" }),
    ]);
    expect(reply.rejected).toEqual([
      { opId: "op-msg-0020", error: "make.message.text is required" },
      { opId: "op-req-0020", error: "make.request.title must not be empty" },
    ]);
  });
});

describe("answers to question cards", () => {
  it("an answer with one of the card's options is stored, copied and pushed with its label", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, FOUNDER, "f".repeat(64));
    const { personToken } = await personWithRequest(env);
    seedCard(env);
    const reply = await push(env, personToken, [makeOp("op-ans-0001", `answer:${REQ}:${CARD}`, answer({ optionId: "opt00002" }))]);
    expect(reply.rejected).toEqual([]);
    const inboxAnswer = env.DB.query("SELECT value FROM ops WHERE user_id = ? AND key = ?", FOUNDER, `answer:${PERSON}:${REQ}:${CARD}`);
    expect(JSON.parse(String(inboxAnswer[0].value))).toEqual({ ...answer({ optionId: "opt00002" }), userId: PERSON });
    const answerEvent = env.DB.query("SELECT title, body, kind FROM make_events WHERE id = ?", "ans:op-ans-0001");
    expect(answerEvent).toEqual([{ title: "Inbox", body: "Priya: Weekdays", kind: "answer" }]);
    expect(calls[calls.length - 1].body.make).toEqual({ kind: "answer", requestId: REQ, userId: PERSON });
  });

  it("a design option without a label is named by its place", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    seedCard(env, { kind: "design", options: [{ id: "opt00001", image: "file:img00001" }, { id: "opt00002", image: "file:img00002" }] });
    await push(env, personToken, [makeOp("op-ans-0001", `answer:${REQ}:${CARD}`, answer({ optionId: "opt00002" }))]);
    const answerEvent = env.DB.query("SELECT body FROM make_events WHERE id = ?", "ans:op-ans-0001");
    expect(answerEvent).toEqual([{ body: "Priya: Design 2" }]);
  });

  it("a card is answered once", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    seedCard(env);
    await push(env, personToken, [makeOp("op-ans-0001", `answer:${REQ}:${CARD}`, answer({ optionId: "opt00001" }))]);
    const reply = await push(env, personToken, [makeOp("op-ans-0002", `answer:${REQ}:${CARD}`, answer({ optionId: "opt00002" }))]);
    expect(reply.rejected).toEqual([{ opId: "op-ans-0002", error: "card already answered" }]);
  });

  it("refuses an answer to no card, a wrong cardId, an unknown option, or words the card does not take", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    const missingCard = await push(env, personToken, [makeOp("op-ans-0001", `answer:${REQ}:${CARD}`, answer({ optionId: "opt00001" }))]);
    expect(missingCard.rejected).toEqual([{ opId: "op-ans-0001", error: "no such card" }]);
    seedCard(env);
    const reply = await push(env, personToken, [
      makeOp("op-ans-0002", `answer:${REQ}:${CARD}`, answer({ cardId: "card9999", optionId: "opt00001" })),
      makeOp("op-ans-0003", `answer:${REQ}:${CARD}`, answer({ optionId: "opt99999" })),
      makeOp("op-ans-0004", `answer:${REQ}:${CARD}`, answer({ text: "Only on Fridays" })),
      makeOp("op-ans-0005", `answer:${REQ}:${CARD}`, answer({ optionId: "opt00001", text: "Both" })),
    ]);
    expect(reply.rejected).toEqual([
      { opId: "op-ans-0002", error: "cardId must match the key" },
      { opId: "op-ans-0003", error: "optionId is not an option of this card" },
      { opId: "op-ans-0004", error: "this card takes a pick" },
      { opId: "op-ans-0005", error: "make.answer fits more than one of its allowed forms" },
    ]);
  });

  it("own words are taken when the card allows them, and pushed as they are", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    seedCard(env, { allowsOwnWords: true });
    const reply = await push(env, personToken, [makeOp("op-ans-0001", `answer:${REQ}:${CARD}`, answer({ text: "Only on Fridays" }))]);
    expect(reply.rejected).toEqual([]);
    const answerEvent = env.DB.query("SELECT body FROM make_events WHERE id = ?", "ans:op-ans-0001");
    expect(answerEvent).toEqual([{ body: "Priya: Only on Fridays" }]);
  });
});

describe("the founder's inbox writes", () => {
  it("only the founder writes the inbox", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    const reply = await push(env, personToken, [inboxOp("op-inb-0001", `req:${PERSON}:${REQ}`, request({ status: "looking" }))]);
    expect(reply.rejected).toEqual([{ opId: "op-inb-0001", error: "not allowed" }]);
  });

  it("a status change goes back to the person's request, without userId, and pushes nothing", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, PERSON, "e".repeat(64));
    const { founderToken } = await personWithRequest(env);
    const reply = await push(env, founderToken, [inboxOp("op-inb-0001", `req:${PERSON}:${REQ}`, request({ status: "looking", userId: PERSON, updatedAt: "2026-10-24T19:00:00.000Z" }))]);
    expect(reply.rejected).toEqual([]);
    const personRequests = env.DB.query("SELECT op_id, value FROM ops WHERE user_id = ? AND key = ? ORDER BY seq", PERSON, `req:${REQ}`);
    expect(personRequests).toHaveLength(2);
    expect(personRequests[1].op_id).toBe(await copyOpId("op-inb-0001", PERSON));
    expect(JSON.parse(String(personRequests[1].value))).toEqual(request({ status: "looking", updatedAt: "2026-10-24T19:00:00.000Z" }));
    expect(calls).toHaveLength(0);
    expect(events(env)).toHaveLength(1);
  });

  it("the founder's message reaches the person and pushes nothing", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, PERSON, "e".repeat(64));
    const { founderToken } = await personWithRequest(env);
    const reply = await push(env, founderToken, [
      inboxOp("op-inb-0002", `message:${PERSON}:${REQ}:msg00002`, message("maker", "On it", { userId: PERSON })),
      inboxOp("op-inb-0003", `message:${PERSON}:${REQ}:msg00003`, message("person", "Pretending")),
    ]);
    expect(reply.rejected).toEqual([{ opId: "op-inb-0003", error: "from must be maker" }]);
    const personMessage = env.DB.query("SELECT value FROM ops WHERE user_id = ? AND key = ?", PERSON, `message:${REQ}:msg00002`);
    expect(JSON.parse(String(personMessage[0].value))).toEqual(message("maker", "On it"));
    expect(calls).toHaveLength(0);
  });

  it("refuses writes about a request the person does not have, a wrong userId, and server-only types", async () => {
    const { env } = makeEnv();
    const { founderToken } = await personWithRequest(env);
    const card = { $type: "make.card", question: "Q?", kind: "choice", options: [{ id: "opt00001", label: "A" }], allowsOwnWords: false, sentAt: TIME };
    const reply = await push(env, founderToken, [
      inboxOp("op-inb-0010", `req:${PERSON}:req99999`, request({ status: "looking" })),
      inboxOp("op-inb-0011", `req:${PERSON}:${REQ}`, request({ status: "looking", userId: OTHER })),
      inboxOp("op-inb-0012", `card:${PERSON}:${REQ}:${CARD}`, card),
      inboxOp("op-inb-0013", `person:${PERSON}`, { $type: "make.person", name: "Priya", firstAt: TIME }),
      { opId: "op-inb-0014", sidekickId: "make-inbox", key: `req:${PERSON}:${REQ}`, deleted: true },
    ]);
    expect(reply.rejected).toEqual([
      { opId: "op-inb-0010", error: "no such request" },
      { opId: "op-inb-0011", error: "userId must match the key" },
      { opId: "op-inb-0012", error: "written by Make only" },
      { opId: "op-inb-0013", error: "written by Make only" },
      { opId: "op-inb-0014", error: "Make records cannot be deleted" },
    ]);
  });

  it("Built needs a deployed Sidekick that is not built in", async () => {
    const { env } = makeEnv();
    const { founderToken } = await personWithRequest(env);
    const reply = await push(env, founderToken, [
      inboxOp("op-inb-0020", `req:${PERSON}:${REQ}`, request({ status: "built", plan: "A timer" })),
      inboxOp("op-inb-0021", `req:${PERSON}:${REQ}`, request({ status: "built", sidekickId: "jess", plan: "A timer" })),
      inboxOp("op-inb-0022", `req:${PERSON}:${REQ}`, request({ status: "built", sidekickId: "lamp-timer", plan: "A timer" })),
    ]);
    expect(reply.rejected).toEqual([
      { opId: "op-inb-0020", error: "make.request.sidekickId is required" },
      { opId: "op-inb-0021", error: "a request cannot be built into a built-in Sidekick" },
      { opId: "op-inb-0022", error: "no such Sidekick" },
    ]);
    const assignments = env.DB.query("SELECT sidekick_id FROM assignments WHERE user_id = ?", PERSON);
    expect(assignments).toEqual([]);
  });

  it("Built assigns the Sidekick, copies the request and pushes the person once", async () => {
    const { env, calls } = makeEnv();
    addDevice(env, PERSON, "e".repeat(64));
    const { founderToken } = await personWithRequest(env);
    const built = request({ status: "built", sidekickId: "reminders", plan: "Turns the lamp off at 11", builtAt: TIME });
    const reply = await push(env, founderToken, [inboxOp("op-inb-0030", `req:${PERSON}:${REQ}`, built)]);
    expect(reply.rejected).toEqual([]);
    const assignments = env.DB.query("SELECT sidekick_id FROM assignments WHERE user_id = ?", PERSON);
    expect(assignments).toEqual([{ sidekick_id: "reminders" }]);
    const personRequest = env.DB.query("SELECT value FROM ops WHERE user_id = ? AND key = ? ORDER BY seq DESC LIMIT 1", PERSON, `req:${REQ}`);
    expect(JSON.parse(String(personRequest[0].value))).toEqual(built);
    const builtEvents = env.DB.query("SELECT audience, user_id, title, body FROM make_events WHERE id = ?", `built:${PERSON}:${REQ}`);
    expect(builtEvents).toEqual([{ audience: "person", user_id: PERSON, title: "Bhuvan", body: "A lamp timer: Built" }]);
    expect(calls).toHaveLength(1);
    expect(calls[0].body).toEqual({
      aps: { alert: { title: "Bhuvan", body: "A lamp timer: Built" }, sound: "default", "thread-id": `${PERSON}:${REQ}` },
      make: { kind: "built", requestId: REQ, userId: PERSON },
    });

    await push(env, founderToken, [inboxOp("op-inb-0031", `req:${PERSON}:${REQ}`, { ...built, plan: "Turns the lamp off at 11 every night" })]);
    expect(calls).toHaveLength(1);
    expect(env.DB.query("SELECT sidekick_id FROM assignments WHERE user_id = ?", PERSON)).toHaveLength(1);
  });

  it("on staging the founder is also a person: his own request lands in his own inbox", async () => {
    const { env } = makeEnv();
    const founderToken = addUser(env, FOUNDER, "Bhuvan");
    const reply = await push(env, founderToken, [makeOp("op-req-0001", `req:${REQ}`, request())]);
    expect(reply.rejected).toEqual([]);
    const inboxKeys = env.DB.query("SELECT key FROM ops WHERE user_id = ? AND sidekick_id = 'make-inbox' ORDER BY seq", FOUNDER);
    expect(inboxKeys).toEqual([{ key: `person:${FOUNDER}` }, { key: `req:${FOUNDER}:${REQ}` }]);
  });
});

describe("files in copied records", () => {
  it("copies each file:<id> to the other side before the batch, keeping its type, never overwriting", async () => {
    const { env } = makeEnv();
    const { personToken } = await personWithRequest(env);
    await env.FILES.put(`${PERSON}/photo0001`, "lamp photo", { httpMetadata: { contentType: "image/jpeg" } });
    await env.FILES.put(`${PERSON}/photo0002`, "second photo", { httpMetadata: { contentType: "image/png" } });
    await env.FILES.put(`${FOUNDER}/photo0002`, "already there", { httpMetadata: { contentType: "image/png" } });
    await push(env, personToken, [
      makeOp("op-msg-0040", `message:${REQ}:msg00040`, message("person", "Like this", { photos: ["file:photo0001", "file:photo0002"] })),
    ]);
    const copied = await env.FILES.get(`${FOUNDER}/photo0001`);
    expect(await copied?.text()).toBe("lamp photo");
    expect(copied?.httpMetadata.contentType).toBe("image/jpeg");
    const kept = await env.FILES.get(`${FOUNDER}/photo0002`);
    expect(await kept?.text()).toBe("already there");
  });
});

describe("a MAKE_FOUNDER_USER_ID that names no user", () => {
  it("stores the person's writes and copies nothing, rather than failing the push", async () => {
    const { env } = makeEnv("u-nobody");
    const personToken = addUser(env, PERSON, "Priya");
    const reply = await push(env, personToken, [makeOp("op-req-0001", `req:${REQ}`, request())]);
    expect(reply.accepted).toEqual(["op-req-0001"]);
    expect(opCount(env)).toBe(1);
  });
});

describe("without MAKE_FOUNDER_USER_ID", () => {
  it("stores the person's writes, copies nothing, and refuses inbox writes", async () => {
    const { env, calls } = makeEnv(null);
    const personToken = addUser(env, PERSON, "Priya");
    const reply = await push(env, personToken, [
      makeOp("op-req-0001", `req:${REQ}`, request()),
      makeOp("op-msg-0001", `message:${REQ}:${MSG}`, message("person", "Hello")),
      inboxOp("op-inb-0001", `req:${PERSON}:${REQ}`, request({ status: "looking" })),
    ]);
    expect(reply.accepted).toEqual(["op-req-0001", "op-msg-0001"]);
    expect(reply.rejected).toEqual([{ opId: "op-inb-0001", error: "not allowed" }]);
    expect(opCount(env)).toBe(2);
    expect(events(env)).toEqual([]);
    expect(calls).toHaveLength(0);
  });
});
