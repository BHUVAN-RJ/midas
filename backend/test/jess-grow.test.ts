// jess grows the Sidekick (founder 2026-10-21, docs/PRODUCT.md "jess grows the Sidekick"; brief
// Phase 7): a clear request the Sidekick has no option for files a feature request with the
// repair agent and is kept as a pending request; right after the runner publishes the repair to
// the user's own copy, the runner re-runs it once, with its original time, runs the new tools.js
// handler and appends its ops to the user's op log after checking them against the new version's
// schemas. The phone shows the result once. Everything sits behind JESS_GROW and is logged.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { GROW_TOOL, buildJessRequest, outcomeFromToolCall, parseSidekick } from "../src/jess";
import type { JessContext } from "../src/jess";
import { growRepairTranscript } from "../src/jess-pending";
import { formatGrowLogRows, growLogSql, parseGrowLogArgs } from "../scripts/jess-grow-log-tools.mjs";
import { contextFor, loadGolden } from "../scripts/eval-jess.mjs";
import { loadTools, opsBody, rerunPendingRequest, verbOf } from "../../runner/lib/jess-rerun.mjs";
import { makeMigratedD1 } from "./helpers/migrated-d1";

const ORIGINAL_NOW = "2026-10-20T17:00:00.000Z";
const ZONE = "America/Los_Angeles";
const REPO_ROOT = join(__dirname, "..", "..");
const RUNNER_TOKEN = "runner-secret-for-tests";
const REMINDERS_MANIFEST = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "manifest.json"), "utf8");
const REMINDERS_TOOLS = readFileSync(join(REPO_ROOT, "sidekicks", "reminders", "tools.js"), "utf8");
const REMINDERS_AGENT = JSON.parse(REMINDERS_MANIFEST).agent;

type Db = ReturnType<typeof makeMigratedD1>;
type Row = Record<string, unknown>;

/* ---------- Fakes ---------- */

function makeBucket() {
  const objectsByKey: Record<string, string> = {
    "sidekicks/reminders/current.json": JSON.stringify({ version: "b5", scriptHashes: [], contentHash: "hash-b5", baseVersion: null, tools: "tools.js" }),
    "sidekicks/reminders/b5/manifest.json": REMINDERS_MANIFEST,
  };
  async function getObject(key: string) {
    if (!(key in objectsByKey)) {
      return null;
    }
    const objectText = objectsByKey[key];
    return { body: new Response(objectText).body, json: async () => JSON.parse(objectText) };
  }
  return { get: getObject, objectsByKey };
}

// What the runner's publish does to R2: the user's own pointer moves to the repaired version
function publishUserCopy(bucket: ReturnType<typeof makeBucket>, userId: string, version: string) {
  bucket.objectsByKey[`sidekicks/reminders/users/${userId}/current.json`] = JSON.stringify({ version, scriptHashes: [], contentHash: "hash-" + version, baseVersion: "b5", tools: "tools.js" });
  bucket.objectsByKey[`sidekicks/reminders/users/${userId}/${version}/manifest.json`] = REMINDERS_MANIFEST;
}

function makeEnv(grow: boolean) {
  const env: Record<string, unknown> = { DB: makeMigratedD1(), BUNDLES: makeBucket(), OPENROUTER_API_KEY: "sk-or-test", REPAIR_RUNNER_TOKEN: RUNNER_TOKEN };
  if (grow) {
    env.JESS_GROW = "true";
  }
  return env as { DB: Db; BUNDLES: ReturnType<typeof makeBucket>; JESS_GROW?: string };
}

function signIn(db: Db, userId: string): string {
  const token = `token-${userId}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  db.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  db.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", tokenHash, userId, Date.now() + 3_600_000);
  db.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'reminders', 'now')", userId);
  return token;
}

async function call(env: object, path: string, method: string, authorization: string, body?: unknown) {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  const executionContext = { waitUntil, passThroughOnException, props: {} };
  const headers: Record<string, string> = { Authorization: authorization };
  const init: RequestInit = { method, headers };
  if (body !== undefined) {
    headers["content-type"] = "application/json";
    init.body = JSON.stringify(body);
  }
  const response = await app.request(path, init, env, executionContext as unknown as ExecutionContext);
  await Promise.all(pending);
  return response;
}

function ask(env: object, token: string, transcript: string) {
  const body = { transcript, now: ORIGINAL_NOW, timeZone: ZONE, locale: "en-US", sidekicks: [{ id: "reminders", context: { lists: [], items: [] } }] };
  return call(env, "/voice/jess", "POST", `Bearer ${token}`, body);
}

function runnerCall(env: object, path: string, body: unknown) {
  return call(env, path, "POST", `Runner ${RUNNER_TOKEN}`, body);
}

function modelCalls(...calls: Array<{ name: string; args: Record<string, unknown> }>) {
  const queue = [...calls];
  async function answer() {
    const next = queue.shift();
    if (next === undefined) {
      return new Response("no more answers", { status: 500 });
    }
    const message = { role: "assistant", content: null, tool_calls: [{ id: "c1", type: "function", function: { name: next.name, arguments: JSON.stringify(next.args) } }] };
    return new Response(JSON.stringify({ choices: [{ message }] }), { status: 200, headers: { "content-type": "application/json" } });
  }
  return answer;
}

const GROW_CALL = { name: "midas__grow_sidekick", args: { sidekick: "reminders", feature: " flag a reminder " } };
const ADD_CALL = {
  name: "reminders__add",
  args: { title: "Call the bank", notes: null, list: null, reminderType: null, when: { whenKind: "absolute", minutesFromNow: null, daysFromNow: null, date: "2026-10-21", yearMissing: false, weekday: null, weekdayNext: false, time: "09:00", ampmStated: true, partOfDay: null, repeat: null, whenText: "tomorrow at 9am" } },
};

function rows(db: Db, sql: string, ...params: Array<string | number | null>): Row[] {
  return db.query(sql, ...params);
}

function setReportStatus(db: Db, reportId: string, status: string, failReason: string | null = null, updatedAt = new Date().toISOString()) {
  db.execute("UPDATE repair_reports SET status = ?, fail_reason = ?, updated_at = ? WHERE id = ?", status, failReason, updatedAt, reportId);
}

// The runner's backend client, talking to the real routes
function runnerBackend(env: object) {
  async function rerunJess(reportId: string, body: unknown) {
    const response = await runnerCall(env, `/repairs/${reportId}/jess-rerun`, body);
    if (response.status === 204) {
      return null;
    }
    expect(response.status).toBe(200);
    return response.json();
  }
  async function sendJessOps(reportId: string, body: unknown) {
    const response = await runnerCall(env, `/repairs/${reportId}/jess-rerun/ops`, body);
    return { httpStatus: response.status, ...(await response.json()) };
  }
  return { rerunJess, sendJessOps };
}

let fetchMock: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  fetchMock = vi.spyOn(globalThis, "fetch");
});

afterEach(() => {
  fetchMock.mockRestore();
});

// One user who asked for something Reminders cannot do; the grow is filed
async function grown(env: ReturnType<typeof makeEnv>) {
  const token = signIn(env.DB, "u1");
  fetchMock.mockImplementation(modelCalls(GROW_CALL));
  const reply = await (await ask(env, token, "add call the bank tomorrow at 9am and flag it")).json();
  return { token, reply };
}

/* ---------- The grow decision ---------- */

function jessContext(grow: boolean): JessContext {
  const sidekick = parseSidekick({ id: "reminders", name: "Reminders", version: "b5", agent: REMINDERS_AGENT, context: { lists: [], items: [] } });
  return { transcript: "add call the bank and flag it", now: ORIGINAL_NOW, timeZone: ZONE, sidekicks: sidekick === null ? [] : [sidekick], grow };
}

function toolNames(context: JessContext): string[] {
  const names: string[] = [];
  for (const tool of buildJessRequest(context, { reasoning: "off" }).tools as Array<{ function: { name: string } }>) {
    names.push(tool.function.name);
  }
  return names;
}

describe("the grow decision", () => {
  it("offers midas.grow_sidekick and its rules only when grow is on; cannot_act and repair stay", () => {
    const withGrow = buildJessRequest(jessContext(true), { reasoning: "off" });
    const withoutGrow = buildJessRequest(jessContext(false), { reasoning: "off" });
    expect(toolNames(jessContext(true))).toContain("midas__grow_sidekick");
    expect(toolNames(jessContext(false))).not.toContain("midas__grow_sidekick");
    expect(toolNames(jessContext(true))).toEqual(expect.arrayContaining(["midas__cannot_act", "midas__repair_request"]));
    expect(withGrow.messages[0].content).toContain("midas__grow_sidekick when the sentence is clear");
    expect(withGrow.messages[0].content).toContain("Not for unclear words, a question, a sentence that is cut");
    expect(withoutGrow.messages[0].content).not.toContain("grow_sidekick");
  });

  it("a grow call is a grow outcome with the person's words and the trimmed feature line", () => {
    const outcome = outcomeFromToolCall({ name: "midas__grow_sidekick", argumentsText: JSON.stringify(GROW_CALL.args) }, jessContext(true));
    expect(outcome).toEqual({ status: "grow", sidekickId: "reminders", feature: "flag a reminder", transcript: "add call the bank and flag it" });
  });

  it("unclear words stay Not Done with grow on; a grow the model was not offered, or with no feature, is not done", () => {
    const unclear = outcomeFromToolCall({ name: "midas__cannot_act", argumentsText: JSON.stringify({ reason: "not-confident" }) }, jessContext(true));
    expect(unclear).toMatchObject({ status: "not-done", reason: "not-confident" });
    const notOffered = outcomeFromToolCall({ name: "midas__grow_sidekick", argumentsText: JSON.stringify(GROW_CALL.args) }, jessContext(false));
    expect(notOffered).toMatchObject({ status: "not-done", reason: "unknown-tool" });
    const noFeature = outcomeFromToolCall({ name: "midas__grow_sidekick", argumentsText: JSON.stringify({ sidekick: "reminders", feature: "  " }) }, jessContext(true));
    expect(noFeature).toMatchObject({ status: "not-done", reason: "bad-arguments" });
    const otherSidekick = outcomeFromToolCall({ name: "midas__grow_sidekick", argumentsText: JSON.stringify({ sidekick: "notes", feature: "x" }) }, jessContext(true));
    expect(otherSidekick).toMatchObject({ status: "not-done", reason: "unknown-sidekick" });
  });

  it("the golden set's grow cases are scored in a grow context only, and none grows for snooze", () => {
    const golden = loadGolden();
    let growCases = 0;
    for (const goldenCase of golden.cases) {
      const context = contextFor(golden, goldenCase);
      if (goldenCase.call.tool === GROW_TOOL) {
        growCases += 1;
        expect(context.grow, goldenCase.id).toBe(true);
        expect(goldenCase.say.toLowerCase()).not.toContain("snooze");
      }
    }
    expect(growCases).toBeGreaterThanOrEqual(6);
    expect(golden.contexts.home.grow).toBeUndefined();
  });
});

/* ---------- Filing ---------- */

describe("POST /voice/jess with the flag off", () => {
  it("offers no grow tool, and a request no tool fits is the Not Done card as before, with nothing filed", async () => {
    const env = makeEnv(false);
    const token = signIn(env.DB, "u1");
    fetchMock.mockImplementation(modelCalls({ name: "midas__cannot_act", args: { reason: "no-tool-fits" } }));
    const reply = await (await ask(env, token, "add call the bank and flag it")).json();
    expect(reply).toMatchObject({ status: "not-done", reason: "no-tool-fits", transcript: "add call the bank and flag it" });
    const sentBody = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    const offered: string[] = [];
    for (const tool of sentBody.tools) {
      offered.push(tool.function.name);
    }
    expect(offered).not.toContain("midas__grow_sidekick");
    expect(rows(env.DB, "SELECT * FROM jess_pending_requests")).toEqual([]);
    expect(rows(env.DB, "SELECT * FROM repair_reports")).toEqual([]);
    const listed = await (await call(env, "/voice/jess/pending", "GET", `Bearer ${token}`)).json();
    expect(listed).toEqual({ pending: [] });
  });
});

describe("POST /voice/jess with the flag on: a grow", () => {
  it("files a feature request and a pending request linked to it, with the original time, and logs both", async () => {
    const env = makeEnv(true);
    const { reply } = await grown(env);
    expect(reply).toMatchObject({ status: "grow", sidekickId: "reminders" });
    expect(typeof reply.reportId).toBe("string");
    expect(typeof reply.pendingId).toBe("string");

    const report = rows(env.DB, "SELECT * FROM repair_reports")[0];
    expect(report).toMatchObject({ id: reply.reportId, user_id: "u1", sidekick_id: "reminders", kind: "feature", status: "queued", bundle_version: "b5" });
    expect(report.transcript).toBe(growRepairTranscript("add call the bank tomorrow at 9am and flag it", "flag a reminder"));
    expect(String(report.transcript).startsWith("add call the bank tomorrow at 9am and flag it\n\n")).toBe(true);
    expect(rows(env.DB, "SELECT kind FROM repair_events WHERE report_id = ?", reply.reportId as string)).toEqual([{ kind: "request_received" }]);

    const pending = rows(env.DB, "SELECT * FROM jess_pending_requests")[0];
    expect(pending).toMatchObject({ id: reply.pendingId, user_id: "u1", sidekick_id: "reminders", report_id: reply.reportId, log_id: reply.logId, transcript: "add call the bank tomorrow at 9am and flag it", feature: "flag a reminder", request_now: ORIGINAL_NOW, time_zone: ZONE, locale: "en-US", status: "waiting", rerun_log_id: null });
    expect(JSON.parse(String(pending.steps))).toEqual([expect.objectContaining({ step: "sent-to-repair", reportId: reply.reportId, logId: reply.logId })]);

    const log = rows(env.DB, "SELECT * FROM voice_logs WHERE id = ?", reply.logId as string)[0];
    expect(log).toMatchObject({ status: "done", tool: "midas.grow_sidekick", sidekick_id: "reminders", pending_id: reply.pendingId });
    expect(JSON.parse(String(log.result))).toEqual({ reportId: reply.reportId, pendingId: reply.pendingId });
  });
});

/* ---------- The re-run ---------- */

describe("the runner's re-run", () => {
  it("needs the runner token", async () => {
    const env = makeEnv(true);
    const { token, reply } = await grown(env);
    const asUser = await call(env, `/repairs/${reply.reportId}/jess-rerun`, "POST", `Bearer ${token}`, { context: {} });
    expect(asUser.status).toBe(401);
  });

  it("is ready only after the repair is live on that user's copy, then runs once with the original time and only that Sidekick", async () => {
    const env = makeEnv(true);
    const { reply } = await grown(env);
    fetchMock.mockImplementation(modelCalls(ADD_CALL));
    const reportId = reply.reportId as string;

    setReportStatus(env.DB, reportId, "fix_ready");
    expect((await runnerCall(env, `/repairs/${reportId}/jess-rerun`, { context: { lists: [], items: [] } })).status).toBe(204);
    expect(rows(env.DB, "SELECT status FROM jess_pending_requests")).toEqual([{ status: "waiting" }]);
    expect(fetchMock).toHaveBeenCalledTimes(1);

    publishUserCopy(env.BUNDLES, "u1", "u6");
    setReportStatus(env.DB, reportId, "deployed_live");
    const rerun = await (await runnerCall(env, `/repairs/${reportId}/jess-rerun`, { context: { lists: [], items: [] } })).json();
    expect(rerun).toMatchObject({ pendingId: reply.pendingId, status: "done", sidekickId: "reminders", version: "u6", tool: "reminders.add" });
    expect(rerun.input.when).toMatchObject({ date: "2026-10-21", time: "09:00", timeZone: ZONE });

    const modelBody = JSON.parse(String(fetchMock.mock.calls[1][1]?.body));
    expect(JSON.parse(modelBody.messages[1].content)).toEqual({ sentence: "add call the bank tomorrow at 9am and flag it" });
    expect(modelBody.messages[0].content).toContain("Today is Tuesday 2026-10-20, the time is 10:00, time zone America/Los_Angeles.");
    const offered: string[] = [];
    for (const tool of modelBody.tools) {
      offered.push(tool.function.name);
    }
    expect(offered).not.toContain("midas__grow_sidekick");

    const pending = rows(env.DB, "SELECT * FROM jess_pending_requests")[0];
    expect(pending).toMatchObject({ status: "re-running", rerun_log_id: rerun.logId });
    const log = rows(env.DB, "SELECT * FROM voice_logs WHERE id = ?", rerun.logId)[0];
    expect(log).toMatchObject({ pending_id: reply.pendingId, tool: "reminders.add", request_now: ORIGINAL_NOW, device: "runner" });

    // Exactly once: a second call finds nothing to run and the model is not asked again
    expect((await runnerCall(env, `/repairs/${reportId}/jess-rerun`, { context: {} })).status).toBe(204);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("appends the handler's ops to the user's op log once, checked against the new version, and the phone shows the line once", async () => {
    const env = makeEnv(true);
    const { token, reply } = await grown(env);
    publishUserCopy(env.BUNDLES, "u1", "u6");
    setReportStatus(env.DB, reply.reportId as string, "deployed_live");
    fetchMock.mockImplementation(modelCalls(ADD_CALL));
    const backend = runnerBackend(env);
    const job = { id: reply.reportId, sidekickId: "reminders" };
    function laterNow() {
      return new Date("2026-10-20T19:30:00.000Z");
    }
    const result = await rerunPendingRequest({ backend, job, toolsText: REMINDERS_TOOLS, records: [], now: laterNow });
    expect(result).toMatchObject({ httpStatus: 200, status: "done", ops: 1 });

    const ops = rows(env.DB, "SELECT * FROM ops WHERE user_id = 'u1'");
    expect(ops).toHaveLength(1);
    expect(ops[0]).toMatchObject({ op_id: `jess-${reply.pendingId}-0`, sidekick_id: "reminders", deleted: 0 });
    expect(JSON.parse(String(ops[0].value))).toMatchObject({ $type: "reminders.item", title: "Call the bank" });
    const pending = rows(env.DB, "SELECT * FROM jess_pending_requests")[0];
    expect(pending).toMatchObject({ status: "done", result_text: "Added Call the bank" });
    expect(rows(env.DB, "SELECT phone_outcome FROM voice_logs WHERE id = ?", pending.rerun_log_id as string)).toEqual([{ phone_outcome: "applied" }]);

    // The same ops sent again change nothing
    const again = await backend.sendJessOps(reply.reportId as string, { pendingId: reply.pendingId, version: "u6", ops: [{ op: "set", key: "reminder:x", value: {} }], text: "x" });
    expect(again.httpStatus).toBe(409);
    expect(rows(env.DB, "SELECT * FROM ops")).toHaveLength(1);

    const listed = await (await call(env, "/voice/jess/pending", "GET", `Bearer ${token}`)).json();
    expect(listed).toEqual({ pending: [{ id: reply.pendingId, sidekickId: "reminders", state: "done", text: "Added Call the bank", transcript: "add call the bank tomorrow at 9am and flag it" }] });
    expect((await call(env, `/voice/jess/pending/${reply.pendingId}/seen`, "POST", `Bearer ${token}`, {})).status).toBe(204);
    expect(await (await call(env, "/voice/jess/pending", "GET", `Bearer ${token}`)).json()).toEqual({ pending: [] });
    expect((await call(env, `/voice/jess/pending/${reply.pendingId}/seen`, "POST", `Bearer ${token}`, {})).status).toBe(404);
  });
});

/* ---------- Failure paths ---------- */

async function rerunReady() {
  const env = makeEnv(true);
  const grownRequest = await grown(env);
  publishUserCopy(env.BUNDLES, "u1", "u6");
  setReportStatus(env.DB, grownRequest.reply.reportId as string, "deployed_live");
  return { env, ...grownRequest };
}

function pendingRow(db: Db): Row {
  return rows(db, "SELECT * FROM jess_pending_requests")[0];
}

describe("failures show the Not Done card with what was said", () => {
  it("the re-run still cannot act: failed with the reason, nothing filed again", async () => {
    const { env, token, reply } = await rerunReady();
    fetchMock.mockImplementation(modelCalls({ name: "midas__cannot_act", args: { reason: "no-tool-fits" } }));
    const rerun = await (await runnerCall(env, `/repairs/${reply.reportId}/jess-rerun`, { context: {} })).json();
    expect(rerun).toMatchObject({ status: "not-done", reason: "no-tool-fits" });
    expect(pendingRow(env.DB)).toMatchObject({ status: "failed", fail_reason: "still cannot act: no-tool-fits" });
    const listed = await (await call(env, "/voice/jess/pending", "GET", `Bearer ${token}`)).json();
    expect(listed.pending).toEqual([expect.objectContaining({ state: "failed", transcript: "add call the bank tomorrow at 9am and flag it" })]);
  });

  it("the re-run asks for a repair instead: still cannot act, and no second report", async () => {
    const { env, reply } = await rerunReady();
    fetchMock.mockImplementation(modelCalls({ name: "midas__repair_request", args: { sidekick: "reminders", kind: "feature", request: "x" } }));
    const rerun = await (await runnerCall(env, `/repairs/${reply.reportId}/jess-rerun`, { context: {} })).json();
    expect(rerun).toMatchObject({ status: "not-done", reason: "still-cannot-act" });
    expect(rows(env.DB, "SELECT * FROM repair_reports")).toHaveLength(1);
    expect(pendingRow(env.DB)).toMatchObject({ status: "failed" });
  });

  it("the handler refuses, or an op does not fit the new schema: failed, and nothing is appended", async () => {
    const refusedCase = await rerunReady();
    fetchMock.mockImplementation(modelCalls(ADD_CALL));
    const routed = await (await runnerCall(refusedCase.env, `/repairs/${refusedCase.reply.reportId}/jess-rerun`, { context: {} })).json();
    const refused = await runnerCall(refusedCase.env, `/repairs/${refusedCase.reply.reportId}/jess-rerun/ops`, { pendingId: routed.pendingId, version: "u6", refused: "past", text: "That time has passed" });
    expect(await refused.json()).toEqual({ status: "failed", reason: "handler refused: past" });
    expect(pendingRow(refusedCase.env.DB)).toMatchObject({ status: "failed", fail_reason: "handler refused: past" });
    expect(rows(refusedCase.env.DB, "SELECT phone_outcome FROM voice_logs WHERE id = ?", routed.logId)).toEqual([{ phone_outcome: "refused:past" }]);

    const badOpCase = await rerunReady();
    fetchMock.mockImplementation(modelCalls(ADD_CALL));
    const routedAgain = await (await runnerCall(badOpCase.env, `/repairs/${badOpCase.reply.reportId}/jess-rerun`, { context: {} })).json();
    const goodValue = { op: "delete", key: "reminder:old" };
    const badValue = { op: "set", key: "reminder:abc", value: { $type: "reminders.item", title: 7 } };
    const badOps = await runnerCall(badOpCase.env, `/repairs/${badOpCase.reply.reportId}/jess-rerun/ops`, { pendingId: routedAgain.pendingId, version: "u6", ops: [goodValue, badValue], text: "Added x" });
    const badReply = await badOps.json();
    expect(badReply.status).toBe("failed");
    expect(badReply.reason).toMatch(/^op refused: reminder:abc: /);
    expect(rows(badOpCase.env.DB, "SELECT * FROM ops")).toEqual([]);
    expect(pendingRow(badOpCase.env.DB)).toMatchObject({ status: "failed" });
  });

  it("the version changed between the re-run and its ops: failed, nothing appended", async () => {
    const { env, reply } = await rerunReady();
    fetchMock.mockImplementation(modelCalls(ADD_CALL));
    const routed = await (await runnerCall(env, `/repairs/${reply.reportId}/jess-rerun`, { context: {} })).json();
    publishUserCopy(env.BUNDLES, "u1", "u7");
    const ops = await runnerCall(env, `/repairs/${reply.reportId}/jess-rerun/ops`, { pendingId: routed.pendingId, version: "u6", ops: [{ op: "delete", key: "reminder:old" }], text: "Deleted old" });
    expect(await ops.json()).toEqual({ status: "failed", reason: "version changed" });
    expect(rows(env.DB, "SELECT * FROM ops")).toEqual([]);
  });

  it("the repair failed, went live but was never re-run, or the runner never finished: failed when the phone asks", async () => {
    const repairFailed = makeEnv(true);
    const failedRequest = await grown(repairFailed);
    setReportStatus(repairFailed.DB, failedRequest.reply.reportId as string, "failed", "unsupported");
    const listed = await (await call(repairFailed, "/voice/jess/pending", "GET", `Bearer ${failedRequest.token}`)).json();
    expect(listed.pending).toEqual([expect.objectContaining({ state: "failed", transcript: "add call the bank tomorrow at 9am and flag it" })]);
    expect(pendingRow(repairFailed.DB)).toMatchObject({ status: "failed", fail_reason: "repair failed: unsupported" });

    const neverRerun = makeEnv(true);
    const liveRequest = await grown(neverRerun);
    const longAgo = new Date(Date.now() - 11 * 60 * 1000).toISOString();
    setReportStatus(neverRerun.DB, liveRequest.reply.reportId as string, "deployed_live", null, longAgo);
    await call(neverRerun, "/voice/jess/pending", "GET", `Bearer ${liveRequest.token}`);
    expect(pendingRow(neverRerun.DB)).toMatchObject({ status: "failed", fail_reason: "live but not run again" });

    const unfinished = await rerunReady();
    fetchMock.mockImplementation(modelCalls(ADD_CALL));
    await runnerCall(unfinished.env, `/repairs/${unfinished.reply.reportId}/jess-rerun`, { context: {} });
    unfinished.env.DB.execute("UPDATE jess_pending_requests SET rerun_at = ?", longAgo);
    await call(unfinished.env, "/voice/jess/pending", "GET", `Bearer ${unfinished.token}`);
    expect(pendingRow(unfinished.env.DB)).toMatchObject({ status: "failed", fail_reason: "runner did not finish the re-run" });
  });

  it("another user never sees or marks the request", async () => {
    const env = makeEnv(true);
    const { reply } = await grown(env);
    setReportStatus(env.DB, reply.reportId as string, "failed", "unsupported");
    const otherToken = signIn(env.DB, "u2");
    expect(await (await call(env, "/voice/jess/pending", "GET", `Bearer ${otherToken}`)).json()).toEqual({ pending: [] });
    expect((await call(env, `/voice/jess/pending/${reply.pendingId}/seen`, "POST", `Bearer ${otherToken}`, {})).status).toBe(404);
  });

  it("with the flag off the runner re-runs nothing", async () => {
    const env = makeEnv(true);
    const { reply } = await grown(env);
    setReportStatus(env.DB, reply.reportId as string, "deployed_live");
    delete env.JESS_GROW;
    expect((await runnerCall(env, `/repairs/${reply.reportId}/jess-rerun`, { context: {} })).status).toBe(204);
    expect(pendingRow(env.DB)).toMatchObject({ status: "waiting" });
  });
});

/* ---------- The runner's part ---------- */

describe("the runner's re-run module", () => {
  it("loads tools.js in node:vm, names verbs for its Sidekick only, and turns a reply into the ops body", () => {
    const tools = loadTools(REMINDERS_TOOLS);
    expect(typeof tools.handlers.add).toBe("function");
    expect(() => loadTools("var x = 1;")).toThrow("sets no MidasSidekickTools");
    expect(verbOf("reminders.add", "reminders")).toBe("add");
    expect(verbOf("care-reminders.add", "reminders")).toBeNull();
    expect(opsBody({ pendingId: "p", version: "u6", reply: { refused: "past", result: { text: "No" } } })).toEqual({ pendingId: "p", version: "u6", refused: "past", text: "No" });
    expect(opsBody({ pendingId: "p", version: "u6", reply: { result: { text: "?" } } })).toMatchObject({ failed: "handler gave neither ops nor refused" });
  });

  it("sends the new tools' context of the user's records, and does nothing more when none waits", async () => {
    const sent: unknown[] = [];
    async function rerunJess(_reportId: string, body: unknown) {
      sent.push(body);
      return null;
    }
    async function sendJessOps() {
      throw new Error("not expected");
    }
    const records = [{ key: "list:groc0000001", value: { $type: "reminders.list", name: "Groceries" } }];
    const result = await rerunPendingRequest({ backend: { rerunJess, sendJessOps }, job: { id: "r", sidekickId: "reminders" }, toolsText: REMINDERS_TOOLS, records });
    expect(result).toEqual({ status: "none" });
    expect(sent).toHaveLength(1);
    expect((sent[0] as { context: { lists: string[] } }).context.lists).toEqual(["Groceries"]);
  });

  it("a handler that throws is reported as a runner failure, not left re-running", async () => {
    const reported: Array<Record<string, unknown>> = [];
    async function rerunJess() {
      return { pendingId: "p1", status: "done", version: "u6", tool: "reminders.add", input: {}, logId: "l" };
    }
    async function sendJessOps(_reportId: string, body: Record<string, unknown>) {
      reported.push(body);
      return { status: "failed" };
    }
    const throwingTools = "var MidasSidekickTools = { context: function () { return {}; }, handlers: { add: function () { throw new Error('boom'); } } };";
    await rerunPendingRequest({ backend: { rerunJess, sendJessOps }, job: { id: "r", sidekickId: "reminders" }, toolsText: throwingTools, records: [] });
    expect(reported).toEqual([{ pendingId: "p1", version: "u6", failed: "handler threw: boom", text: "" }]);
  });
});

/* ---------- The founder's log ---------- */

describe("backend/scripts/jess-grow-log.mjs", () => {
  it("reads options, joins the repair and the re-run, and prints every step", () => {
    const now = new Date("2026-10-21T12:00:00Z");
    expect(parseGrowLogArgs(["--env", "staging", "--since", "24h", "--limit", "5"], now)).toEqual({ options: { since: "2026-10-20T12:00:00.000Z", limit: 5 } });
    expect(parseGrowLogArgs(["--fast"], now)).toEqual({ problem: "unknown argument --fast" });
    const sql = growLogSql({ since: "2026-10-20T12:00:00.000Z", limit: 5 });
    expect(sql).toContain("FROM jess_pending_requests p JOIN repair_reports r ON r.id = p.report_id LEFT JOIN voice_logs v ON v.id = p.rerun_log_id");
    expect(sql).toContain("p.created_at >= '2026-10-20T12:00:00.000Z'");
    expect(sql).toContain("LIMIT 5");
    const text = formatGrowLogRows([
      {
        id: "p1",
        created_at: "2026-10-21T10:00:00Z",
        user_id: "u1",
        sidekick_id: "reminders",
        transcript: "add call the bank and flag it",
        feature: "flag a reminder",
        request_now: ORIGINAL_NOW,
        time_zone: ZONE,
        status: "done",
        fail_reason: null,
        steps: JSON.stringify([{ step: "sent-to-repair", at: "2026-10-21T10:00:00Z", reportId: "r1" }, { step: "applied", at: "2026-10-21T10:20:00Z", ops: 1 }]),
        report_id: "r1",
        repair_status: "deployed_live",
        repair_fail_reason: null,
        rerun_tool: "reminders.add",
        rerun_input: "{}",
        rerun_reason: null,
        rerun_phone_outcome: "applied",
      },
    ]);
    expect(text).toContain('said: "add call the bank and flag it"');
    expect(text).toContain("missing: flag a reminder");
    expect(text).toContain("repair r1: deployed_live");
    expect(text).toContain("re-run: reminders.add {}  phone: applied");
    expect(text).toContain("2026-10-21T10:20:00Z  applied ops=1");
    expect(formatGrowLogRows([])).toBe("No pending requests.");
  });
});
