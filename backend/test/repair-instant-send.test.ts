import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { CHAT_URL, DECISIONS_URL } from "../src/repair-sort-model";
import { STUCK_SORT_MS, isStuckSort } from "../src/repair-sort";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Send closes repair mode at once (founder, 2026-11-22; docs/briefs/repair-lanes.md "Change
// 2026-11-22"). A phone that follows the lane (form field laneFollow=1) gets the answer to its
// upload at once; the sort and the setting lane run after the reply, in waitUntil, and the phone
// learns the lane from GET /repairs/lanes/:clientReportId. Phones that do not follow (builds before
// this change) and runs without an execution context still get the lane in the upload's reply.
// OpenRouter is a stand-in (globalThis.fetch spied); Jev's answer can be held back to show the
// reply does not wait for it.

const HYDRATION_MANIFEST = readFileSync(new URL("../../sidekicks/hydration/manifest.json", import.meta.url), "utf8");

function makeEnv() {
  const bundles = makeFakeR2({
    "sidekicks/hydration/current.json": JSON.stringify({ version: "v3", scriptHashes: [] }),
    "sidekicks/hydration/v3/manifest.json": HYDRATION_MANIFEST,
  });
  return { DB: makeMigratedD1(), BUNDLES: bundles, REPAIR_RUNNER_TOKEN: "runner-secret-for-tests", OPENROUTER_API_KEY: "test-key" };
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'hydration', 'now')", userId);
  return token;
}

function makeForm(transcript: string, clientReportId: string, followsLane: boolean): FormData {
  const form = new FormData();
  form.set("sidekickId", "hydration");
  form.set("kind", "change");
  form.set("transcript", transcript);
  form.set("clientReportId", clientReportId);
  form.set("strokes", JSON.stringify([[[150, 300, 0], [250, 400, 50]]]));
  if (followsLane) {
    form.set("laneFollow", "1");
  }
  return form;
}

type LaneReply = {
  id: string;
  status: string;
  sortStatus?: string | null;
  lane: string | null;
  question?: { text: string; options: Array<{ id: string }> };
  message?: string;
  setting?: { changes: Array<{ key: string; value: unknown }> };
};

// A Worker execution context that keeps what was handed to waitUntil
function makeExecutionContext() {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  const context = { waitUntil, passThroughOnException, props: {} };
  async function settle() {
    await Promise.all(pending);
  }
  return { context: context as unknown as ExecutionContext, pending, settle };
}

async function postReport(env: TestEnv, token: string, transcript: string, clientReportId: string, options: { followsLane: boolean; context?: ExecutionContext }) {
  const init = { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: makeForm(transcript, clientReportId, options.followsLane) };
  const response = await app.request("/repairs", init, env, options.context);
  const reply = (await response.json()) as LaneReply;
  return { response, reply };
}

async function getLane(env: TestEnv, token: string, clientReportId: string) {
  const response = await app.request(`/repairs/lanes/${clientReportId}`, { headers: { Authorization: `Bearer ${token}` } }, env);
  return { response, reply: (await response.json()) as LaneReply };
}

function reportRow(env: TestEnv, reportId: string): Record<string, unknown> {
  return env.DB.query("SELECT * FROM repair_reports WHERE id = ?", reportId)[0];
}

function founderEventCount(env: TestEnv, reportId: string): number {
  return env.DB.query("SELECT id FROM repair_events WHERE report_id = ? AND audience = 'founder'", reportId).length;
}

function settingsOpCount(env: TestEnv, userId: string): number {
  return env.DB.query("SELECT seq FROM ops WHERE user_id = ? AND key = 'settings:self'", userId).length;
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
}

// The plan for OpenRouter: Jev's lane (and guesses), Haiku's setting answers, and an optional gate
// that holds Jev's answer back until the test opens it.
let jevLane: string;
let jevGuesses: Record<string, number>;
let haikuAnswers: string[];
let jevCalls: number;
let jevGate: Promise<void> | null;
let openJevGate: () => void;
let fetchSpy: ReturnType<typeof vi.spyOn>;

function holdJev() {
  jevGate = new Promise<void>(function makeGate(resolve) {
    openJevGate = resolve;
  });
}

async function planFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const url = String(input);
  if (url === DECISIONS_URL) {
    jevCalls += 1;
    if (jevGate !== null) {
      await jevGate;
    }
    return jsonResponse({ answers: { lane: { choice: jevLane, confidence: 0.95 }, guess: { probabilities: jevGuesses } }, usage: { cost: 0.00003 } });
  }
  if (url === CHAT_URL) {
    const body = JSON.parse(String(init?.body)) as { messages?: Array<{ content: string }> };
    expect(String(body.messages?.[0]?.content)).toContain("asked to change how it looks");
    const content = haikuAnswers.shift();
    return jsonResponse({ choices: [{ message: { content: content ?? "" } }], usage: { cost: 0.0001 } });
  }
  throw new Error(`unexpected fetch ${url}`);
}

beforeEach(function spyOnFetch() {
  jevLane = "setting";
  jevGuesses = {};
  haikuAnswers = [];
  jevCalls = 0;
  jevGate = null;
  fetchSpy = vi.spyOn(globalThis, "fetch");
  fetchSpy.mockImplementation(planFetch);
});

afterEach(function restoreFetch() {
  fetchSpy.mockRestore();
});

describe("Send is answered at once; the sort runs after the reply", () => {
  it("answers 201 while Jev has not answered, then the lane route gives the setting result", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": [{"key": "sea.colour", "value": "#d93025"}]}');
    holdJev();
    const worker = makeExecutionContext();

    const { response, reply } = await postReport(env, token, "can you change the color to red", "phone-1", { followsLane: true, context: worker.context });

    expect(response.status).toBe(201);
    expect(reply.sortStatus).toBe("sorting");
    expect(reply.lane).toBeNull();
    expect(reply.status).toBe("received");
    expect(worker.pending).toHaveLength(1);
    const rowWhileSorting = reportRow(env, reply.id);
    expect(rowWhileSorting.sort_status).toBe("sorting");
    expect(settingsOpCount(env, "amogh")).toBe(0);

    const early = await getLane(env, token, "phone-1");
    expect(early.response.status).toBe(200);
    expect(early.reply.id).toBe(reply.id);
    expect(early.reply.sortStatus).toBe("sorting");
    expect(early.reply.lane).toBeNull();

    openJevGate();
    await worker.settle();

    const done = await getLane(env, token, "phone-1");
    expect(done.reply.sortStatus).toBe("sorted");
    expect(done.reply.lane).toBe("setting");
    expect(done.reply.message).toBe("Changed");
    expect(done.reply.setting?.changes).toEqual([{ key: "sea.colour", label: "Sea (the rising water) colour", value: "#D93025" }]);
    expect(settingsOpCount(env, "amogh")).toBe(1);
    expect(founderEventCount(env, reply.id)).toBe(0);
  });

  it("a code lane found after the reply queues the job with the founder's event", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevLane = "code";
    const worker = makeExecutionContext();

    const { reply } = await postReport(env, token, "add a weekly chart", "phone-2", { followsLane: true, context: worker.context });
    expect(reply.sortStatus).toBe("sorting");
    await worker.settle();

    const lane = await getLane(env, token, "phone-2");
    expect(lane.reply.lane).toBe("code");
    expect(lane.reply.status).toBe("queued");
    expect(founderEventCount(env, reply.id)).toBe(1);
  });

  it("ask_back after the reply: the lane route carries the card's question and the report id", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevLane = "ask_back";
    jevGuesses = { bigger: 0.6, other_colour: 0.3 };
    const worker = makeExecutionContext();

    const { reply } = await postReport(env, token, "change this", "phone-3", { followsLane: true, context: worker.context });
    await worker.settle();

    const lane = await getLane(env, token, "phone-3");
    expect(lane.reply.sortStatus).toBe("asking");
    expect(lane.reply.lane).toBe("ask_back");
    expect(lane.reply.id).toBe(reply.id);
    expect(lane.reply.question?.text).toBe("What should it be?");
    expect(lane.reply.question?.options.map(function idOf(option) { return option.id; })).toEqual(["bigger", "other_colour", "other_icon"]);

    // The existing answer route still answers that card
    const answered = await app.request(`/repairs/${reply.id}/answer`, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ optionId: "bigger" }) }, env);
    expect(answered.status).toBe(200);
  });

  it("not a request after the reply: the lane route carries the message, and no job is made", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevLane = "not_a_request";
    const worker = makeExecutionContext();

    const { reply } = await postReport(env, token, "how are you", "phone-4", { followsLane: true, context: worker.context });
    await worker.settle();

    const lane = await getLane(env, token, "phone-4");
    expect(lane.reply.lane).toBe("not_a_request");
    expect(lane.reply.message).toBe("Say or draw what to change.");
    expect(founderEventCount(env, reply.id)).toBe(0);
  });

  it("jess_command after the reply: lane jess_command, no job", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevLane = "jess_command";
    const worker = makeExecutionContext();

    const { reply } = await postReport(env, token, "log a glass of water", "phone-5", { followsLane: true, context: worker.context });
    await worker.settle();

    const lane = await getLane(env, token, "phone-5");
    expect(lane.reply.lane).toBe("jess_command");
    expect(founderEventCount(env, reply.id)).toBe(0);
  });

  it("a retry while the sort runs says it is still sorting and sorts nothing twice", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevLane = "code";
    holdJev();
    const worker = makeExecutionContext();
    const first = await postReport(env, token, "add a chart", "phone-6", { followsLane: true, context: worker.context });

    const retry = await postReport(env, token, "add a chart", "phone-6", { followsLane: true, context: worker.context });

    expect(retry.response.status).toBe(200);
    expect(retry.reply.id).toBe(first.reply.id);
    expect(retry.reply.sortStatus).toBe("sorting");
    expect(worker.pending).toHaveLength(1);
    openJevGate();
    await worker.settle();
    expect(jevCalls).toBe(1);
  });
});

describe("phones that do not follow the lane keep the waiting reply", () => {
  it("without laneFollow the upload's reply carries the lane even with an execution context", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": [{"key": "sea.colour", "value": "#d93025"}]}');
    const worker = makeExecutionContext();

    const { response, reply } = await postReport(env, token, "make the water red", "phone-7", { followsLane: false, context: worker.context });

    expect(response.status).toBe(201);
    expect(reply.lane).toBe("setting");
    expect(reply.message).toBe("Changed");
    expect(worker.pending).toHaveLength(0);
  });

  it("with laneFollow but no execution context the sort runs before the reply", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevLane = "code";

    const { reply } = await postReport(env, token, "add a chart", "phone-8", { followsLane: true });

    expect(reply.lane).toBe("code");
    expect(reply.status).toBe("queued");
  });
});

describe("the lane route", () => {
  it("finds only the caller's own report: another person's id is 404, a bad id 400", async () => {
    const env = makeEnv();
    const amogh = addSignedInUser(env, "amogh");
    const riya = addSignedInUser(env, "riya");
    jevLane = "code";
    await postReport(env, amogh, "add a chart", "phone-9", { followsLane: true });

    expect((await getLane(env, riya, "phone-9")).response.status).toBe(404);
    expect((await getLane(env, amogh, "not-sent-yet")).response.status).toBe(404);
    expect((await getLane(env, amogh, "bad%20id")).response.status).toBe(400);
    const noSession = await app.request("/repairs/lanes/phone-9", {}, env);
    expect(noSession.status).toBe(401);
  });

  it("a sort that never finished is put in the code lane, up a lane, with the founder's event", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevLane = "code";
    holdJev();
    const worker = makeExecutionContext();
    const { reply } = await postReport(env, token, "add a chart", "phone-10", { followsLane: true, context: worker.context });
    // The Worker was cut off: the row stays sorting, last touched two minutes ago
    const longAgo = new Date(Date.now() - 2 * 60 * 1000).toISOString();
    env.DB.execute("UPDATE repair_reports SET updated_at = ? WHERE id = ?", longAgo, reply.id);

    const lane = await getLane(env, token, "phone-10");

    expect(lane.reply.lane).toBe("code");
    expect(lane.reply.sortStatus).toBe("sorted");
    expect(lane.reply.status).toBe("queued");
    expect(String(reportRow(env, reply.id).sort_error)).toBe("sort did not finish");
    expect(founderEventCount(env, reply.id)).toBe(1);
    // The late sort finds the row placed and changes nothing
    openJevGate();
    await worker.settle();
    expect(founderEventCount(env, reply.id)).toBe(1);
  });

  it("a sort still inside its minute is left alone", () => {
    const now = Date.parse("2026-11-22T10:00:00.000Z");
    const recent = { sort_status: "sorting", updated_at: new Date(now - STUCK_SORT_MS + 1000).toISOString() };
    const old = { sort_status: "sorting", updated_at: new Date(now - STUCK_SORT_MS).toISOString() };
    const sorted = { sort_status: "sorted", updated_at: new Date(now - 10 * STUCK_SORT_MS).toISOString() };
    expect(isStuckSort(recent, now)).toBe(false);
    expect(isStuckSort(old, now)).toBe(true);
    expect(isStuckSort(sorted, now)).toBe(false);
  });

  it("a sort that throws after the reply goes up to code instead of staying sorting", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    jevLane = "setting";
    const workingBundles = env.BUNDLES;
    // The bucket fails every read once the report's files are stored (the setting lane reads it)
    const failingBundles = {
      put: workingBundles.put.bind(workingBundles),
      get: function failingGet() {
        return Promise.reject(new Error("R2 down"));
      },
    };
    const brokenEnv = { ...env, BUNDLES: failingBundles as unknown as R2Bucket };
    const worker = makeExecutionContext();
    const consoleSpy = vi.spyOn(console, "error").mockImplementation(function quiet() {});

    const { reply } = await postReport(brokenEnv as unknown as TestEnv, token, "make the water red", "phone-11", { followsLane: true, context: worker.context });
    await worker.settle();
    consoleSpy.mockRestore();

    const row = reportRow(env, reply.id);
    expect(row.sort_status).toBe("sorted");
    expect(row.lane).toBe("code");
    expect(row.status).toBe("queued");
    expect(String(row.sort_error)).toContain("R2 down");
    expect(founderEventCount(env, reply.id)).toBe(1);
  });
});
