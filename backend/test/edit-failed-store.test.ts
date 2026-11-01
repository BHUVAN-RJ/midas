import { createHash, generateKeyPairSync } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import app from "../src/index";
import { resetApnsTokenCache } from "../src/apns";
import { closingStatements, editFailedStatements, editRequestId, isEditRequestId, jobLink, reportIdFromEditRequest } from "../src/edit-failed";
import { USER_DONE_TEXT, USER_RESULT_TEXT } from "../src/repairs";
import { makeFakeR2 } from "../test/helpers/fake-r2";
import { makeMigratedD1 } from "../test/helpers/migrated-d1";

// Build 22 (founder, 2026-10-31; docs/briefs/build-22-2026-10-31.md, docs/briefs/edit-failed-contract.md):
// when an edit could not be made the person sees "Check back in some time." and the founder is
// alerted: a thread in his Make inbox with what was asked, why it failed and the job link, and a
// push. He fixes it by hand, publishes, and marks the thread Built: the person's edit turns fixed.

const FOUNDER = "u-founder";
const PERSON = "u-priya";
const OTHER = "u-sam";
const RUNNER_TOKEN = "runner-secret";
const TIME = "2026-10-31T18:00:00.000Z";
const KEY_P8 = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const PNG_HEADER = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

type FetchCall = { url: string; body: Record<string, unknown> };
type Notice = { reportId: string; kind: string; summary: string | null; text: string };

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

function addUser(env: TestEnv, userId: string, name: string, sidekicks: string[] = []): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'then')", userId, name);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'then', ?)", sha256Hex(token), userId, farFuture);
  for (const sidekickId of sidekicks) {
    env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, ?, 'then')", userId, sidekickId);
  }
  return token;
}

function addDevice(env: TestEnv, userId: string, deviceToken: string) {
  env.DB.execute("INSERT INTO push_devices (token, user_id, env, bundle_id, created_at, updated_at) VALUES (?, ?, 'sandbox', 'com.bhuvanrj.midas.test', 'then', 'then')", deviceToken, userId);
}

function runnerHeaders() {
  return { Authorization: `Runner ${RUNNER_TOKEN}`, "Content-Type": "application/json" };
}

function sessionHeaders(token: string) {
  return { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
}

// The founder, his phone, and a person who has Reminders.
function people(env: TestEnv) {
  const founderToken = addUser(env, FOUNDER, "Bhuvan");
  addDevice(env, FOUNDER, "a".repeat(64));
  const personToken = addUser(env, PERSON, "Priya", ["reminders"]);
  return { founderToken, personToken };
}

async function createReport(env: TestEnv, token: string, typedText: string | null = null): Promise<string> {
  const form = new FormData();
  form.set("sidekickId", "reminders");
  form.set("kind", "change");
  form.set("transcript", "make the list colours bigger");
  form.set("screenshot", new Blob([PNG_HEADER], { type: "image/png" }), "screenshot.png");
  if (typedText !== null) {
    form.set("typedText", typedText);
  }
  const response = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
  expect(response.status).toBe(201);
  const reply = (await response.json()) as { id: string };
  return reply.id;
}

async function claim(env: TestEnv) {
  const response = await app.request("/repairs/jobs/claim", { method: "POST", headers: runnerHeaders(), body: JSON.stringify({ runnerId: "mac-mini" }) }, env);
  return response;
}

async function postStatus(env: TestEnv, reportId: string, body: Record<string, unknown>) {
  return app.request(`/repairs/${reportId}/status`, { method: "POST", headers: runnerHeaders(), body: JSON.stringify(body) }, env);
}

async function failedReport(env: TestEnv, personToken: string): Promise<string> {
  const reportId = await createReport(env, personToken);
  await claim(env);
  const response = await postStatus(env, reportId, { status: "failed", reason: "check failed", detail: "manifest.json is not JSON" });
  expect(response.status).toBe(200);
  return reportId;
}

async function noticesFor(env: TestEnv, token: string): Promise<Notice[]> {
  const response = await app.request("/repairs/notices", { headers: sessionHeaders(token) }, env);
  expect(response.status).toBe(200);
  const reply = (await response.json()) as { notices: Notice[] };
  return reply.notices;
}

function storedValues(env: TestEnv, userId: string, sidekickId: string) {
  const rows = env.DB.query("SELECT op_id, key, value FROM ops WHERE user_id = ? AND sidekick_id = ? ORDER BY seq", userId, sidekickId);
  const values: Array<{ opId: string; key: string; value: Record<string, unknown> }> = [];
  for (const row of rows) {
    values.push({ opId: String(row.op_id), key: String(row.key), value: JSON.parse(String(row.value)) });
  }
  return values;
}

function valueAt(env: TestEnv, userId: string, sidekickId: string, key: string): Record<string, unknown> | undefined {
  const values = storedValues(env, userId, sidekickId);
  const matching = values.filter(function hasKey(entry) {
    return entry.key === key;
  });
  return matching.length === 0 ? undefined : matching[matching.length - 1].value;
}

function makeEvents(env: TestEnv) {
  return env.DB.query("SELECT id, audience, user_id, about_user_id, request_id, kind, title, body, sent_at FROM make_events ORDER BY id");
}

function reportRow(env: TestEnv, reportId: string): Record<string, unknown> {
  return env.DB.query("SELECT * FROM repair_reports WHERE id = ?", reportId)[0];
}

type Op = { opId: string; sidekickId: string; key: string; value?: unknown; deleted?: boolean };

async function pushOps(env: TestEnv, token: string, ops: Op[]) {
  const fullOps = [];
  for (const op of ops) {
    fullOps.push({ deleted: false, clientTime: TIME, ...op });
  }
  const response = await app.request("/sync/push", { method: "POST", headers: sessionHeaders(token), body: JSON.stringify({ ops: fullOps }) }, env);
  expect(response.status).toBe(200);
  return (await response.json()) as { accepted: string[]; rejected: Array<{ opId: string; error: string }> };
}

function inboxStatus(status: string, fields: Record<string, unknown> = {}) {
  return { $type: "make.request", title: "reminders: make the list colours bigger", status, createdAt: TIME, updatedAt: TIME, ...fields };
}

beforeEach(() => {
  resetApnsTokenCache();
});

describe("edit thread ids", () => {
  it("an edit thread's id carries the report id and comes back out of it", () => {
    const reportId = "0f1e2d3c-4b5a-4987-8a6b-5c4d3e2f1a0b";
    const requestId = editRequestId(reportId);
    expect(requestId).toBe("edit-0f1e2d3c4b5a49878a6b5c4d3e2f1a0b");
    expect(requestId).toMatch(/^[A-Za-z0-9_-]{8,40}$/);
    expect(reportIdFromEditRequest(requestId)).toBe(reportId);
    expect(isEditRequestId(requestId)).toBe(true);
  });

  it("a phone's own request id is never an edit thread", () => {
    expect(isEditRequestId("3f2a9c0d1b4e4a7f9e2d1c0b9a8f7e6d")).toBe(false);
    expect(isEditRequestId("edit-notahexid")).toBe(false);
    expect(isEditRequestId("req00001")).toBe(false);
    expect(reportIdFromEditRequest(null)).toBeNull();
  });
});

describe("an edit that could not be made", () => {
  it("tells the person Check back in some time., never the founder's reason", async () => {
    const { env } = makeEnv();
    const { personToken } = people(env);
    const reportId = await failedReport(env, personToken);

    const notices = await noticesFor(env, personToken);
    expect(USER_RESULT_TEXT.couldnt_fix).toBe("Check back in some time.");
    expect(notices).toEqual([expect.objectContaining({ reportId, kind: "couldnt_fix", summary: null, text: "Check back in some time." })]);
    expect(JSON.stringify(notices)).not.toContain("check failed");
    expect(JSON.stringify(notices)).not.toContain("manifest.json");
  });

  it("opens a thread in the founder's inbox with what was asked, why it failed and the job link", async () => {
    const { env } = makeEnv();
    const { personToken } = people(env);
    const reportId = await failedReport(env, personToken);
    const requestId = editRequestId(reportId);

    const person = valueAt(env, FOUNDER, "make-inbox", `person:${PERSON}`);
    expect(person).toMatchObject({ $type: "make.person", userId: PERSON, name: "Priya" });
    const request = valueAt(env, FOUNDER, "make-inbox", `req:${PERSON}:${requestId}`);
    expect(request).toMatchObject({ $type: "make.request", userId: PERSON, status: "sent", title: "reminders: make the list colours bigger", editReportId: reportId, editSidekickId: "reminders" });
    const messages = storedValues(env, FOUNDER, "make-inbox").filter(function isThreadMessage(entry) {
      return entry.key.startsWith(`message:${PERSON}:${requestId}:`);
    });
    expect(messages).toHaveLength(1);
    const text = String(messages[0].value.text);
    expect(messages[0].value).toMatchObject({ $type: "make.message", from: "person", userId: PERSON });
    expect(text).toContain("Asked: make the list colours bigger");
    expect(text).toContain("Why: check failed: manifest.json is not JSON");
    expect(text).toContain(`Job: ${jobLink(reportId)}`);
    expect(jobLink(reportId)).toBe(`~/Library/Application Support/midas-runner/log/${reportId}`);
    // Nothing lands in the person's own Make store
    expect(storedValues(env, PERSON, "make")).toEqual([]);
  });

  it("pushes to the founder's phone, and a tap opens that inbox thread", async () => {
    const { env, calls } = makeEnv();
    const { personToken } = people(env);
    const reportId = await failedReport(env, personToken);

    const events = makeEvents(env);
    expect(events).toEqual([expect.objectContaining({ id: `editfail:${reportId}`, audience: "founder", user_id: FOUNDER, about_user_id: PERSON, request_id: editRequestId(reportId), kind: "message", title: "Inbox" })]);
    expect(events[0].sent_at).not.toBeNull();
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe(`https://api.sandbox.push.apple.com/3/device/${"a".repeat(64)}`);
    expect(calls[0].body).toEqual({
      aps: { alert: { title: "Inbox", body: "Priya · reminders: make the list colours bigger" }, sound: "default", "thread-id": `${PERSON}:${editRequestId(reportId)}` },
      make: { kind: "message", requestId: editRequestId(reportId), userId: PERSON },
    });
  });

  it("a deploy that failed after fix_ready alerts the founder too", async () => {
    const { env } = makeEnv();
    const { personToken } = people(env);
    const reportId = await createReport(env, personToken);
    await claim(env);
    await postStatus(env, reportId, { status: "fix_ready" });
    await postStatus(env, reportId, { status: "failed", reason: "deploy failed", detail: "read-back mismatch" });

    const messages = storedValues(env, FOUNDER, "make-inbox").filter(function isMessage(entry) {
      return entry.key.startsWith("message:");
    });
    expect(String(messages[0].value.text)).toContain("Why: deploy failed: read-back mismatch");
  });

  it("a job whose lease ran out every time alerts the founder with that reason", async () => {
    const { env, calls } = makeEnv();
    const { personToken } = people(env);
    const reportId = await createReport(env, personToken);
    for (let attempt = 0; attempt < 3; attempt += 1) {
      await claim(env);
      env.DB.execute("UPDATE repair_reports SET lease_until = ? WHERE id = ?", Date.now() - 1000, reportId);
    }

    await claim(env);

    expect(reportRow(env, reportId).result_kind).toBe("couldnt_fix");
    const messages = storedValues(env, FOUNDER, "make-inbox").filter(function isMessage(entry) {
      return entry.key.startsWith("message:");
    });
    expect(String(messages[0].value.text)).toContain("Why: lease expired 3 times");
    expect(calls).toHaveLength(1);
  });

  it("Already There is not a failure: no thread, no push", async () => {
    const { env, calls } = makeEnv();
    const { personToken } = people(env);
    const reportId = await createReport(env, personToken);
    await claim(env);
    await postStatus(env, reportId, { status: "no_change", summary: "Already there." });

    expect(storedValues(env, FOUNDER, "make-inbox")).toEqual([]);
    expect(makeEvents(env)).toEqual([]);
    expect(calls).toEqual([]);
  });

  it("with no founder set on the server the failure is still stored, without a thread", async () => {
    const { env, calls } = makeEnv(null);
    const { personToken } = people(env);
    const reportId = await failedReport(env, personToken);

    expect(reportRow(env, reportId)).toMatchObject({ status: "failed", result_kind: "couldnt_fix" });
    expect(env.DB.query("SELECT COUNT(*) AS n FROM ops")[0].n).toBe(0);
    expect(calls).toEqual([]);
  });

  it("the thread's records fit the Make inbox schemas", async () => {
    const { env } = makeEnv();
    const { founderToken, personToken } = people(env);
    const reportId = await failedReport(env, personToken);
    const requestId = editRequestId(reportId);

    // The founder's phone pulls the inbox: every record arrives (none refused by the shell's schema check)
    const response = await app.request("/sync/pull?since=0", { headers: sessionHeaders(founderToken) }, env);
    expect(response.status).toBe(200);
    const pulled = JSON.stringify(await response.json());
    expect(pulled).toContain(`req:${PERSON}:${requestId}`);
    expect(pulled).toContain(`person:${PERSON}`);
  });

  it("building the alert twice stores it once", async () => {
    const { env } = makeEnv();
    people(env);
    const report = { id: "0f1e2d3c-4b5a-4987-8a6b-5c4d3e2f1a0b", user_id: PERSON, sidekick_id: "reminders", transcript: "bigger text", typed_text: null };
    for (let round = 0; round < 2; round += 1) {
      const plan = await editFailedStatements(env.DB as unknown as D1Database, env, report, { reason: "check failed", detail: null }, TIME);
      expect(plan).not.toBeNull();
      await env.DB.batch(plan!.statements as never);
    }
    expect(storedValues(env, FOUNDER, "make-inbox")).toHaveLength(3);
    expect(makeEvents(env)).toHaveLength(1);
  });
});

describe("the founder fixes it by hand", () => {
  it("can reply in the edit thread and move its status; nothing reaches the person's Make", async () => {
    const { env } = makeEnv();
    const { founderToken, personToken } = people(env);
    const reportId = await failedReport(env, personToken);
    const requestId = editRequestId(reportId);

    const reply = await pushOps(env, founderToken, [
      { opId: "op-f-msg-01", sidekickId: "make-inbox", key: `message:${PERSON}:${requestId}:msg00001`, value: { $type: "make.message", from: "maker", text: "On it", sentAt: TIME } },
      { opId: "op-f-req-01", sidekickId: "make-inbox", key: `req:${PERSON}:${requestId}`, value: inboxStatus("building") },
    ]);

    expect(reply.rejected).toEqual([]);
    expect(storedValues(env, PERSON, "make")).toEqual([]);
    expect(reportRow(env, reportId).result_kind).toBe("couldnt_fix");
  });

  it("Built on the edit thread turns the edit fixed and tells the person, once", async () => {
    const { env } = makeEnv();
    const { founderToken, personToken } = people(env);
    const reportId = await failedReport(env, personToken);
    const requestId = editRequestId(reportId);
    const failureNotices = await noticesFor(env, personToken);
    await app.request(`/repairs/notices/${(failureNotices[0] as unknown as { id: string }).id}/seen`, { method: "POST", headers: sessionHeaders(personToken) }, env);

    const built = inboxStatus("built", { sidekickId: "reminders", plan: "Bigger list colours.", builtAt: TIME });
    const first = await pushOps(env, founderToken, [{ opId: "op-f-built-1", sidekickId: "make-inbox", key: `req:${PERSON}:${requestId}`, value: built }]);
    const second = await pushOps(env, founderToken, [{ opId: "op-f-built-2", sidekickId: "make-inbox", key: `req:${PERSON}:${requestId}`, value: built }]);

    expect(first.rejected).toEqual([]);
    expect(second.rejected).toEqual([]);
    expect(reportRow(env, reportId)).toMatchObject({ status: "deployed_live", result_kind: "fixed", result_summary: "Bigger list colours." });
    const notices = await noticesFor(env, personToken);
    expect(notices).toEqual([expect.objectContaining({ reportId, kind: "fixed", summary: "Bigger list colours.", text: USER_DONE_TEXT })]);
    // No Make request or Built screen for the person: the edit thread stays in the inbox
    expect(storedValues(env, PERSON, "make")).toEqual([]);
  });

  it("an edit thread under another person's id is refused", async () => {
    const { env } = makeEnv();
    const { founderToken, personToken } = people(env);
    addUser(env, OTHER, "Sam", ["reminders"]);
    const reportId = await failedReport(env, personToken);
    const requestId = editRequestId(reportId);

    const built = inboxStatus("built", { sidekickId: "reminders", plan: "x", builtAt: TIME });
    const reply = await pushOps(env, founderToken, [{ opId: "op-f-wrong-1", sidekickId: "make-inbox", key: `req:${OTHER}:${requestId}`, value: built }]);

    expect(reply.rejected).toEqual([{ opId: "op-f-wrong-1", error: "no such request" }]);
    expect(reportRow(env, reportId).result_kind).toBe("couldnt_fix");
  });

  it("closing never touches a report that is not a failure, nor another person's", async () => {
    const { env } = makeEnv();
    const { personToken } = people(env);
    addUser(env, OTHER, "Sam", ["reminders"]);
    const reportId = await createReport(env, personToken);
    await claim(env);
    await postStatus(env, reportId, { status: "no_change", summary: "Already there." });

    await env.DB.batch(closingStatements(env.DB as unknown as D1Database, reportId, PERSON, "x", TIME) as never);
    expect(reportRow(env, reportId)).toMatchObject({ status: "failed", result_kind: "already_there" });

    const failedId = await failedReport(env, personToken);
    await env.DB.batch(closingStatements(env.DB as unknown as D1Database, failedId, OTHER, "x", TIME) as never);
    expect(reportRow(env, failedId)).toMatchObject({ status: "failed", result_kind: "couldnt_fix" });
  });
});
