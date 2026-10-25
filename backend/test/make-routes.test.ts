import { createHash, generateKeyPairSync } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { beforeEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { resetApnsTokenCache } from "../src/apns";
import { EXPECTED_ORIGIN, RELYING_PARTY_ID } from "../src/auth";
import { JESS_LISTING } from "../src/jess-sidekick";
import { MAKE_INBOX_LISTING, MAKE_LISTING, MAKE_SENDER_NAME, NATIVE_SIDEKICK_IDS } from "../src/make-sidekick";
import { makeRecordChecker } from "../src/record-types";
import { assignToEveryoneSql } from "../scripts/db-tools.mjs";
import { cardBody, parseMakeCardArgs } from "../scripts/make-card.mjs";
import { makeFakeR2 } from "../test/helpers/fake-r2";
import { makeMigratedD1 } from "../test/helpers/migrated-d1";
import { makeSoftAuthenticator } from "../test/helpers/soft-authenticator";

// Make's routes and listings (founder, 2026-10-24; docs/briefs/make-contract.md sections 1, 2, 4,
// 5 and 6): Make for everyone and the founder's Inbox in the Sidekick list, the Built picker,
// question cards and their pictures sent by the server path, device registration for pushes,
// the repair-blocked log, and repair refused on the built-in Sidekicks.

const FOUNDER = "u-founder";
const PERSON = "u-priya";
const OTHER = "u-sam";
const REQ = "req00001";
const TIME = "2026-10-24T18:00:00.000Z";
const RUNNER_TOKEN = "runner-secret";
const KEY_P8 = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const NAMES: Record<string, string> = { [FOUNDER]: "Bhuvan", [PERSON]: "Priya", [OTHER]: "Sam" };

const REMINDERS_MANIFEST = { id: "reminders", name: "Reminders", icon: { symbol: "checklist", background: "#FF9500" }, reads: [], types: {} };

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
    "sidekicks/reminders/v2/index.html": "<p>reminders</p>",
    "sidekicks/reminders/v2/manifest.json": JSON.stringify(REMINDERS_MANIFEST),
    "sidekicks/reminders/users/u-priya/current.json": JSON.stringify({ version: "v2", scriptHashes: [] }),
    "sidekicks/reminders/users/u-priya/v2/manifest.json": JSON.stringify(REMINDERS_MANIFEST),
    "sidekicks/plants/current.json": JSON.stringify({ version: "p1", scriptHashes: [] }),
    "sidekicks/plants/p1/manifest.json": JSON.stringify({ id: "plants", name: "Plants", icon: { symbol: "leaf", background: "#00AA00" }, reads: [] }),
    "sidekicks/jess/current.json": JSON.stringify({ version: "j1", scriptHashes: [] }),
    "sidekicks/drafts/v1/manifest.json": JSON.stringify({ id: "drafts", name: "No pointer", reads: [] }),
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

function addUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, NAMES[userId]);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

function assign(env: TestEnv, userId: string, sidekickId: string) {
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, ?)", userId, sidekickId, TIME);
}

function addDevice(env: TestEnv, userId: string, token: string) {
  env.DB.execute("INSERT INTO push_devices (token, user_id, env, bundle_id, created_at, updated_at) VALUES (?, ?, 'sandbox', 'com.bhuvanrj.midas.test', 'then', 'then')", token, userId);
}

// The person's request as /sync/push stores it.
function seedRequest(env: TestEnv) {
  const value = { $type: "make.request", title: "A lamp timer", status: "sent", createdAt: TIME, updatedAt: TIME };
  env.DB.execute("INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, received_at) VALUES ('op-req-0001', ?, 'make', ?, ?, 0, 'then')", PERSON, `req:${REQ}`, JSON.stringify(value));
}

function bearer(token: string) {
  return { Authorization: `Bearer ${token}` };
}

function runner() {
  return { Authorization: `Runner ${RUNNER_TOKEN}` };
}

async function postJson(env: TestEnv, path: string, headers: Record<string, string>, body: unknown) {
  const requestInit = { method: "POST", headers: { ...headers, "Content-Type": "application/json" }, body: JSON.stringify(body) };
  return app.request(path, requestInit, env);
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

beforeEach(() => {
  resetApnsTokenCache();
});

describe("Make and Inbox in the Sidekick list", () => {
  it("lists jess, Make, then the rest, from the built-in listings", async () => {
    const { env } = makeEnv();
    const token = addUser(env, PERSON);
    assign(env, PERSON, "reminders");
    assign(env, PERSON, "make");
    assign(env, PERSON, "jess");
    expect(await listedIds(env, token)).toEqual(["jess", "make", "reminders"]);
    const response = await app.request("/sidekicks", { headers: bearer(token) }, env);
    const body = (await response.json()) as { sidekicks: unknown[] };
    expect(body.sidekicks[0]).toEqual(JESS_LISTING);
    expect(body.sidekicks[1]).toEqual(MAKE_LISTING);
    expect(MAKE_LISTING).toEqual({ id: "make", name: "Make", icon: { symbol: "plus", background: "#000000" }, reads: [], version: "built-in", builtIn: true });
  });

  it("the founder also gets the Inbox, after Make, without an assignment", async () => {
    const { env } = makeEnv();
    const token = addUser(env, FOUNDER);
    assign(env, FOUNDER, "reminders");
    assign(env, FOUNDER, "make");
    assign(env, FOUNDER, "jess");
    expect(await listedIds(env, token)).toEqual(["jess", "make", "make-inbox", "reminders"]);
    expect(MAKE_INBOX_LISTING).toMatchObject({ id: "make-inbox", name: "Inbox", version: "built-in", builtIn: true });
  });

  it("no one gets the Inbox when MAKE_FOUNDER_USER_ID is unset", async () => {
    const { env } = makeEnv(null);
    const token = addUser(env, FOUNDER);
    assign(env, FOUNDER, "make");
    expect(await listedIds(env, token)).toEqual(["make"]);
  });

  it("Make and Inbox have no bundle", async () => {
    const { env } = makeEnv();
    const token = addUser(env, FOUNDER);
    assign(env, FOUNDER, "make");
    const makeBundle = await app.request("/sidekicks/make/bundle", { headers: bearer(token) }, env);
    const inboxBundle = await app.request("/sidekicks/make-inbox/bundle", { headers: bearer(token) }, env);
    expect(makeBundle.status).toBe(404);
    expect(inboxBundle.status).toBe(404);
  });
});

describe("Make for everyone", () => {
  it("assigns Make at sign-up, in the same step as jess", async () => {
    const { env } = makeEnv();
    const authenticator = await makeSoftAuthenticator({ rpId: RELYING_PARTY_ID, origin: EXPECTED_ORIGIN });
    const optionsResponse = await postJson(env, "/auth/register/options", {}, { name: "Priya" });
    const optionsReply = (await optionsResponse.json()) as { challengeId: string; options: Parameters<typeof authenticator.register>[0] };
    const credential = await authenticator.register(optionsReply.options);
    const verifyResponse = await postJson(env, "/auth/register/verify", {}, { challengeId: optionsReply.challengeId, credential });
    expect(verifyResponse.status).toBe(200);
    const session = (await verifyResponse.json()) as { token: string; user: { id: string } };
    const rows = env.DB.query("SELECT sidekick_id FROM assignments WHERE user_id = ? ORDER BY sidekick_id", session.user.id);
    expect(rows).toEqual([{ sidekick_id: "jess" }, { sidekick_id: "make" }]);
    expect(await listedIds(env, session.token)).toEqual(["jess", "make"]);
  });

  it("the script gives every existing user Make, insert only, on the environment named", () => {
    const script = readFileSync(new URL("../scripts/assign-make-to-everyone.mjs", import.meta.url), "utf8");
    expect(script).toContain("environmentFromArgs");
    expect(script).toContain("assignToEveryoneSql(MAKE_SIDEKICK_ID");
    expect(script).toContain('const MAKE_SIDEKICK_ID = "make";');
    expect(script).not.toMatch(/DELETE|UPDATE|DROP/);
    const { env } = makeEnv();
    addUser(env, PERSON);
    addUser(env, OTHER);
    const sql = assignToEveryoneSql("make", new Date(TIME));
    env.DB.execute(sql);
    env.DB.execute(sql);
    const rows = env.DB.query("SELECT user_id FROM assignments WHERE sidekick_id = 'make' ORDER BY user_id");
    expect(rows).toEqual([{ user_id: PERSON }, { user_id: OTHER }]);
  });
});

describe("the Built picker", () => {
  it("lists every base Sidekick with its name and version, built-in ones and pointerless ones left out", async () => {
    const { env } = makeEnv();
    const token = addUser(env, FOUNDER);
    const response = await app.request("/make/sidekicks", { headers: bearer(token) }, env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      sidekicks: [
        { id: "plants", name: "Plants", version: "p1" },
        { id: "reminders", name: "Reminders", version: "v2" },
      ],
    });
  });

  it("is the founder's only: anyone else gets 404, no session 401", async () => {
    const { env } = makeEnv();
    const token = addUser(env, PERSON);
    const asPerson = await app.request("/make/sidekicks", { headers: bearer(token) }, env);
    const asNobody = await app.request("/make/sidekicks", {}, env);
    expect(asPerson.status).toBe(404);
    expect(asNobody.status).toBe(401);
  });
});

describe("pictures for question cards", () => {
  it("stores the bytes in the founder's folder and copies them to the person's", async () => {
    const { env } = makeEnv();
    addUser(env, FOUNDER);
    addUser(env, PERSON);
    const requestInit = { method: "POST", headers: { ...runner(), "Content-Type": "image/png", "X-Midas-File-Id": "img00001" }, body: "png bytes" };
    const response = await app.request(`/make/files?userId=${PERSON}`, requestInit, env);
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({ id: "img00001", ref: "file:img00001" });
    const founderCopy = await env.FILES.get(`${FOUNDER}/img00001`);
    const personCopy = await env.FILES.get(`${PERSON}/img00001`);
    expect(await founderCopy?.text()).toBe("png bytes");
    expect(await personCopy?.text()).toBe("png bytes");
    expect(personCopy?.httpMetadata.contentType).toBe("image/png");

    const retryInit = { method: "POST", headers: { ...runner(), "Content-Type": "image/png", "X-Midas-File-Id": "img00001" }, body: "other bytes" };
    const retry = await app.request(`/make/files?userId=${PERSON}`, retryInit, env);
    expect(retry.status).toBe(200);
    expect(await (await env.FILES.get(`${FOUNDER}/img00001`))?.text()).toBe("png bytes");
  });

  it("refuses an unknown person, an empty file, other users, and a server with no founder", async () => {
    const { env } = makeEnv();
    addUser(env, FOUNDER);
    const personToken = addUser(env, PERSON);
    const unknownPerson = await app.request(`/make/files?userId=u-nobody`, { method: "POST", headers: runner(), body: "x" }, env);
    const empty = await app.request(`/make/files?userId=${PERSON}`, { method: "POST", headers: runner(), body: "" }, env);
    const asPerson = await app.request(`/make/files?userId=${PERSON}`, { method: "POST", headers: bearer(personToken), body: "x" }, env);
    expect(unknownPerson.status).toBe(404);
    expect(empty.status).toBe(400);
    expect(asPerson.status).toBe(404);
    const { env: unsetEnv } = makeEnv(null);
    const unset = await app.request(`/make/files?userId=${PERSON}`, { method: "POST", headers: runner(), body: "x" }, unsetEnv);
    expect(unset.status).toBe(503);
  });
});

describe("question cards", () => {
  function choiceCard(fields: Record<string, unknown> = {}) {
    return {
      userId: PERSON,
      requestId: REQ,
      cardId: "card0001",
      question: "Which nights?",
      kind: "choice",
      options: [{ id: "opt00001", label: "Every night" }, { id: "opt00002", label: "Weekdays" }],
      allowsOwnWords: true,
      ...fields,
    };
  }

  it("writes the card to the person and the inbox in one batch, and pushes the person", async () => {
    const { env, calls } = makeEnv();
    addUser(env, FOUNDER);
    const personToken = addUser(env, PERSON);
    addDevice(env, PERSON, "e".repeat(64));
    seedRequest(env);
    const response = await postJson(env, "/make/cards", runner(), choiceCard());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ cardId: "card0001" });

    const personCard = env.DB.query("SELECT op_id, sidekick_id, value FROM ops WHERE user_id = ? AND key = ?", PERSON, `card:${REQ}:card0001`);
    expect(personCard).toHaveLength(1);
    expect(personCard[0].op_id).toBe("mkcard-card0001-p");
    expect(personCard[0].sidekick_id).toBe("make");
    const cardValue = JSON.parse(String(personCard[0].value));
    expect(cardValue).toMatchObject({ $type: "make.card", question: "Which nights?", kind: "choice", allowsOwnWords: true, sentAt: expect.any(String) });
    expect(cardValue.userId).toBeUndefined();
    const inboxCard = env.DB.query("SELECT op_id, sidekick_id, value FROM ops WHERE user_id = ? AND key = ?", FOUNDER, `card:${PERSON}:${REQ}:card0001`);
    expect(inboxCard[0].op_id).toBe("mkcard-card0001-f");
    expect(inboxCard[0].sidekick_id).toBe("make-inbox");
    expect(JSON.parse(String(inboxCard[0].value))).toEqual({ ...cardValue, userId: PERSON });

    expect(calls).toHaveLength(1);
    expect(calls[0].body).toEqual({
      aps: { alert: { title: MAKE_SENDER_NAME, body: "Which nights?" }, sound: "default", "thread-id": `${PERSON}:${REQ}` },
      make: { kind: "card", requestId: REQ, userId: PERSON, cardId: "card0001" },
    });
    expect(MAKE_SENDER_NAME).toBe("Bhuvan");

    // The person can now answer it through /sync.
    const answerOp = { opId: "op-ans-0001", sidekickId: "make", key: `answer:${REQ}:card0001`, value: { $type: "make.answer", cardId: "card0001", optionId: "opt00002", sentAt: TIME }, deleted: false };
    const pushResponse = await postJson(env, "/sync/push", bearer(personToken), { ops: [answerOp] });
    expect(await pushResponse.json()).toEqual({ accepted: ["op-ans-0001"], rejected: [] });
  });

  it("the same cardId again changes nothing and pushes nothing", async () => {
    const { env, calls } = makeEnv();
    addUser(env, FOUNDER);
    addUser(env, PERSON);
    addDevice(env, PERSON, "e".repeat(64));
    seedRequest(env);
    await postJson(env, "/make/cards", runner(), choiceCard());
    const again = await postJson(env, "/make/cards", runner(), choiceCard({ question: "Changed?" }));
    expect(await again.json()).toEqual({ cardId: "card0001" });
    const cards = env.DB.query("SELECT value FROM ops WHERE key LIKE 'card:%'");
    expect(cards).toHaveLength(2);
    expect(calls).toHaveLength(1);
  });

  it("makes a card id when none is given", async () => {
    const { env } = makeEnv();
    addUser(env, FOUNDER);
    addUser(env, PERSON);
    seedRequest(env);
    const card = choiceCard();
    delete (card as { cardId?: string }).cardId;
    const response = await postJson(env, "/make/cards", runner(), card);
    const reply = (await response.json()) as { cardId: string };
    expect(reply.cardId).toMatch(/^[A-Za-z0-9_-]{8,40}$/);
  });

  it("a design card pushes '<n> designs' and copies its pictures to the person", async () => {
    const { env, calls } = makeEnv();
    addUser(env, FOUNDER);
    addUser(env, PERSON);
    addDevice(env, PERSON, "e".repeat(64));
    seedRequest(env);
    await env.FILES.put(`${FOUNDER}/img00001`, "first", { httpMetadata: { contentType: "image/png" } });
    await env.FILES.put(`${FOUNDER}/img00002`, "second", { httpMetadata: { contentType: "image/png" } });
    const design = choiceCard({ kind: "design", options: [{ id: "opt00001", image: "file:img00001" }, { id: "opt00002", image: "file:img00002" }], allowsOwnWords: false });
    const response = await postJson(env, "/make/cards", bearer(`token-${FOUNDER}`), design);
    expect(response.status).toBe(200);
    expect(await (await env.FILES.get(`${PERSON}/img00002`))?.text()).toBe("second");
    const cardEvent = env.DB.query("SELECT body FROM make_events WHERE id = 'card:card0001'");
    expect(cardEvent).toEqual([{ body: "2 designs" }]);
    expect(calls).toHaveLength(1);
  });

  it("refuses a missing request, a bad card, a missing picture, and anyone but the runner or founder", async () => {
    const { env } = makeEnv();
    addUser(env, FOUNDER);
    const personToken = addUser(env, PERSON);
    const noRequest = await postJson(env, "/make/cards", runner(), choiceCard());
    expect(noRequest.status).toBe(404);
    seedRequest(env);
    const designWithoutImage = await postJson(env, "/make/cards", runner(), choiceCard({ kind: "design" }));
    expect(designWithoutImage.status).toBe(400);
    expect(await designWithoutImage.json()).toEqual({ error: "make.card.options.0.image is required" });
    const missingPicture = await postJson(env, "/make/cards", runner(), choiceCard({ kind: "design", options: [{ id: "opt00001", image: "file:img99999" }] }));
    expect(missingPicture.status).toBe(400);
    expect(await missingPicture.json()).toEqual({ error: "no such file: img99999" });
    const asPerson = await postJson(env, "/make/cards", bearer(personToken), choiceCard());
    expect(asPerson.status).toBe(404);
    const wrongRunner = await postJson(env, "/make/cards", { Authorization: "Runner wrong" }, choiceCard());
    expect(wrongRunner.status).toBe(401);
    const cards = env.DB.query("SELECT op_id FROM ops WHERE key LIKE 'card:%'");
    expect(cards).toEqual([]);
  });

  it("the test script builds the card body from its flags", () => {
    const parsed = parseMakeCardArgs(["--env", "staging", "--user", PERSON, "--request", REQ, "--question", "Which one?", "--option", "A", "--option", "B", "--own-words", "--card-id", "card0001"]);
    let nextId = 0;
    function fixedOptionId() {
      nextId += 1;
      return `opt0000${nextId}`;
    }
    expect(cardBody(parsed, "card0001", [], fixedOptionId)).toEqual({
      userId: PERSON,
      requestId: REQ,
      cardId: "card0001",
      question: "Which one?",
      kind: "choice",
      options: [{ id: "opt00001", label: "A" }, { id: "opt00002", label: "B" }],
      allowsOwnWords: true,
    });
    const designParsed = parseMakeCardArgs(["--user", PERSON, "--request", REQ, "--question", "Look?", "--image", "a.png", "--label", "Light"]);
    const designBody = cardBody(designParsed, "card0002", ["file:img00001"], fixedOptionId);
    expect(designBody.kind).toBe("design");
    expect(designBody.options).toEqual([{ id: "opt00003", image: "file:img00001", label: "Light" }]);
    expect(() => parseMakeCardArgs(["--nope"])).toThrow();
  });
});

describe("push device registration", () => {
  it("stores the token for the signed-in user, and moves and revives a known token", async () => {
    const { env } = makeEnv();
    const personToken = addUser(env, PERSON);
    const otherToken = addUser(env, OTHER);
    const deviceToken = "AB".repeat(32);
    const first = await postJson(env, "/push/register", bearer(personToken), { token: deviceToken, env: "sandbox", bundleId: "com.bhuvanrj.midas.test" });
    expect(first.status).toBe(200);
    expect(await first.json()).toEqual({ ok: true });
    expect(env.DB.query("SELECT user_id, env, bundle_id, disabled_at FROM push_devices")).toEqual([
      { user_id: PERSON, env: "sandbox", bundle_id: "com.bhuvanrj.midas.test", disabled_at: null },
    ]);
    env.DB.execute("UPDATE push_devices SET disabled_at = 'earlier', disabled_reason = '410'");
    await postJson(env, "/push/register", bearer(otherToken), { token: deviceToken, env: "production", bundleId: "com.bhuvanrj.midas" });
    expect(env.DB.query("SELECT token, user_id, env, bundle_id, disabled_at, disabled_reason FROM push_devices")).toEqual([
      { token: deviceToken.toLowerCase(), user_id: OTHER, env: "production", bundle_id: "com.bhuvanrj.midas", disabled_at: null, disabled_reason: null },
    ]);
  });

  it("refuses a bad token, env or bundle id, and requests without a session", async () => {
    const { env } = makeEnv();
    const token = addUser(env, PERSON);
    const goodToken = "ab".repeat(32);
    const badToken = await postJson(env, "/push/register", bearer(token), { token: "not-hex", env: "sandbox", bundleId: "com.bhuvanrj.midas" });
    const badEnv = await postJson(env, "/push/register", bearer(token), { token: goodToken, env: "development", bundleId: "com.bhuvanrj.midas" });
    const badBundle = await postJson(env, "/push/register", bearer(token), { token: goodToken, env: "sandbox", bundleId: "com.example.app" });
    const noSession = await postJson(env, "/push/register", {}, { token: goodToken, env: "sandbox", bundleId: "com.bhuvanrj.midas" });
    expect([badToken.status, badEnv.status, badBundle.status, noSession.status]).toEqual([400, 400, 400, 401]);
    expect(env.DB.query("SELECT token FROM push_devices")).toEqual([]);
  });
});

describe("repair on built-in Sidekicks", () => {
  it("logs a blocked repair once per clientId: 201, then 200", async () => {
    const { env } = makeEnv();
    const token = addUser(env, PERSON);
    const body = { sidekickId: "make", clientId: "client0001", appVersion: "1.0", appBuild: "9" };
    const first = await postJson(env, "/repairs/blocked", bearer(token), body);
    const again = await postJson(env, "/repairs/blocked", bearer(token), body);
    expect(first.status).toBe(201);
    expect(await first.json()).toEqual({ logged: true });
    expect(again.status).toBe(200);
    expect(await again.json()).toEqual({ logged: true });
    expect(env.DB.query("SELECT user_id, sidekick_id, client_id, app_version, app_build FROM repair_blocked")).toEqual([
      { user_id: PERSON, sidekick_id: "make", client_id: "client0001", app_version: "1.0", app_build: "9" },
    ]);
  });

  it("refuses a bad body and requests without a session", async () => {
    const { env } = makeEnv();
    const token = addUser(env, PERSON);
    const badSidekick = await postJson(env, "/repairs/blocked", bearer(token), { sidekickId: "Make!", clientId: "client0001" });
    const badClient = await postJson(env, "/repairs/blocked", bearer(token), { sidekickId: "make", clientId: "x" });
    const noSession = await postJson(env, "/repairs/blocked", {}, { sidekickId: "make", clientId: "client0001" });
    expect([badSidekick.status, badClient.status, noSession.status]).toEqual([400, 400, 401]);
  });

  it("POST /repairs refuses jess, Make and Inbox", async () => {
    const { env } = makeEnv();
    const token = addUser(env, PERSON);
    assign(env, PERSON, "make");
    assign(env, PERSON, "jess");
    expect(NATIVE_SIDEKICK_IDS).toEqual(["jess", "make", "make-inbox"]);
    for (const sidekickId of NATIVE_SIDEKICK_IDS) {
      const form = new FormData();
      form.set("sidekickId", sidekickId);
      form.set("transcript", "make the button bigger");
      const response = await app.request("/repairs", { method: "POST", headers: bearer(token), body: form }, env);
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({ error: "repair not available" });
    }
    expect(env.DB.query("SELECT id FROM repair_reports")).toEqual([]);
  });
});

describe("Make's record types and migrations", () => {
  it("native-types.js loads as a plain CommonJS script, one types block for both stores", () => {
    const requireScript = createRequire(import.meta.url);
    const nativeTypes = requireScript("../../shell/sdk/native-types.js") as Record<string, Record<string, { $type: string }>>;
    expect(Object.keys(nativeTypes)).toEqual(["make", "make-inbox"]);
    expect(nativeTypes.make).toBe(nativeTypes["make-inbox"]);
    const typeNames: Record<string, string> = {};
    for (const [prefix, entry] of Object.entries(nativeTypes.make)) {
      typeNames[prefix] = entry.$type;
    }
    expect(typeNames).toEqual({ "req:": "make.request", "message:": "make.message", "card:": "make.card", "answer:": "make.answer", "person:": "make.person" });
  });

  it("record checks use Make's types even with no bundle to read, and the shell's request: type still wins", async () => {
    const checker = makeRecordChecker({}, PERSON);
    const missingTitle = await checker.recordProblem("make", null, `req:${REQ}`, { $type: "make.request", status: "sent", createdAt: TIME, updatedAt: TIME });
    expect(missingTitle).toBe("make.request.title is required");
    const builtWithoutPlan = await checker.recordProblem("make-inbox", null, `req:${PERSON}:${REQ}`, { $type: "make.request", title: "T", status: "built", sidekickId: "reminders", createdAt: TIME, updatedAt: TIME });
    expect(builtWithoutPlan).toBe("make.request.plan is required");
    const unknownPrefix = await checker.recordProblem("make", null, "note:abc", { $type: "make.note" });
    expect(unknownPrefix).toBe("no record type is declared for note:abc");
    const shellRequest = await checker.recordProblem("make", null, "request:abc", { $type: "midas.request", kind: "import" });
    expect(shellRequest).toBeNull();
    const card = { $type: "make.card", question: "Q?", kind: "choice", options: [], allowsOwnWords: false, sentAt: TIME };
    expect(await checker.recordProblem("make", null, `card:${REQ}:card0001`, card)).toBe("make.card.options must not be empty");
    const person = await checker.recordProblem("make-inbox", null, `person:${PERSON}`, { $type: "make.person", userId: PERSON, name: "Priya", firstAt: TIME });
    expect(person).toBeNull();
  });

  it("0011 and 0012 add the push, event and repair-blocked tables", () => {
    const db = makeMigratedD1();
    const tables = db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('push_devices', 'make_events', 'repair_blocked') ORDER BY name");
    expect(tables).toEqual([{ name: "make_events" }, { name: "push_devices" }, { name: "repair_blocked" }]);
    const indexes = db.query("SELECT name FROM sqlite_master WHERE type = 'index' AND name IN ('push_devices_by_user', 'make_events_unsent', 'repair_blocked_client') ORDER BY name");
    expect(indexes).toHaveLength(3);
    const migration = readFileSync(new URL("../migrations/0011_make_push.sql", import.meta.url), "utf8");
    expect(migration).not.toMatch(/DROP|DELETE|ALTER TABLE \w+ DROP/);
  });
});
