import { createHash, generateKeyPairSync } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { ANSWER_WINDOW_MS, NOT_A_REQUEST_TEXT, SHELL_CANT_PUSH_TITLE } from "../src/repair-sort";
import { CHAT_URL, DECISIONS_URL } from "../src/repair-sort-model";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Repair lanes W2 (founder, 2026-11-13; docs/briefs/repair-lanes.md): a report is sorted before any
// runner can claim it, the phone hears { id, lane, question?, message? }, an ask-back answer sorts
// the same request again, a card unanswered for 2 minutes is dropped, shell_cant pushes the
// founder. OpenRouter is a stand-in (globalThis.fetch spied); APNs is a stand-in (PUSH_FETCH).

const RUNNER_TOKEN = "runner-secret-for-tests";
const FOUNDER = "founder";
const KEY_P8 = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const STROKES = JSON.stringify([[[150, 300, 0], [250, 400, 50]]]);

type Pushed = { url: string; body: Record<string, unknown> };

function makeEnv() {
  const pushes: Pushed[] = [];
  async function fakeApnsFetch(url: string, init: RequestInit): Promise<Response> {
    pushes.push({ url, body: JSON.parse(String(init.body)) });
    return new Response(null, { status: 200 });
  }
  const bundles = makeFakeR2({
    "sidekicks/hydration/current.json": JSON.stringify({ version: "v3", scriptHashes: [] }),
    "sidekicks/hydration/v3/manifest.json": JSON.stringify({ id: "hydration", name: "Water", agent: { description: "Daily water goal and reminders." } }),
  });
  const env = {
    DB: makeMigratedD1(),
    BUNDLES: bundles,
    REPAIR_RUNNER_TOKEN: RUNNER_TOKEN,
    OPENROUTER_API_KEY: "test-key",
    MAKE_FOUNDER_USER_ID: FOUNDER,
    APNS_KEY_P8: KEY_P8,
    APNS_KEY_ID: "KEY1234567",
    APNS_TEAM_ID: "ZQ2JPFYL98",
    PUSH_FETCH: fakeApnsFetch,
  };
  return { env, pushes };
}

type TestEnv = ReturnType<typeof makeEnv>["env"];

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

function addFounderDevice(env: TestEnv) {
  addSignedInUser(env, FOUNDER, []);
  env.DB.execute(
    "INSERT INTO push_devices (token, user_id, env, bundle_id, created_at, updated_at) VALUES (?, ?, 'sandbox', 'com.bhuvanrj.midas.test', 'then', 'then')",
    "a".repeat(64),
    FOUNDER,
  );
}

function makeForm(transcript: string, clientReportId?: string): FormData {
  const form = new FormData();
  form.set("sidekickId", "hydration");
  form.set("kind", "change");
  form.set("transcript", transcript);
  form.set("strokes", STROKES);
  if (clientReportId !== undefined) {
    form.set("clientReportId", clientReportId);
  }
  return form;
}

type Reply = { id: string; status: string; lane: string; question?: { text: string; options: Array<{ id: string; label: string; icon: string }> }; message?: string };

async function postReport(env: TestEnv, token: string, transcript: string, clientReportId?: string) {
  const response = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: makeForm(transcript, clientReportId) }, env);
  const reply = (await response.json()) as Reply;
  return { response, reply };
}

async function postAnswer(env: TestEnv, token: string, reportId: string, body: Record<string, unknown>) {
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  return app.request(`/repairs/${reportId}/answer`, { method: "POST", headers, body: JSON.stringify(body) }, env);
}

async function claim(env: TestEnv) {
  const headers = { Authorization: `Runner ${RUNNER_TOKEN}`, "Content-Type": "application/json" };
  return app.request("/repairs/jobs/claim", { method: "POST", headers, body: JSON.stringify({ runnerId: "mac-mini" }) }, env);
}

function reportRow(env: TestEnv, reportId: string): Record<string, unknown> {
  const rows = env.DB.query("SELECT * FROM repair_reports WHERE id = ?", reportId);
  expect(rows.length).toBe(1);
  return rows[0];
}

function founderEventCount(env: TestEnv, reportId: string): number {
  const rows = env.DB.query("SELECT id FROM repair_events WHERE report_id = ? AND audience = 'founder'", reportId);
  return rows.length;
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
}

// OpenRouter stand-in: each call takes the next planned answer for its URL.
type Plan = { jev: Array<{ lane: string; confidence: number; guesses?: Record<string, number> }>; haiku: string[] };
type ModelCall = { url: string; body: Record<string, unknown> };

let fetchSpy: ReturnType<typeof vi.spyOn>;
let plan: Plan;
let modelCalls: ModelCall[];

function planFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const url = String(input);
  const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
  modelCalls.push({ url, body });
  if (url === DECISIONS_URL) {
    const next = plan.jev.shift();
    if (next === undefined) {
      return Promise.resolve(jsonResponse({ error: { message: "no plan" } }, 500));
    }
    const payload = { answers: { lane: { choice: next.lane, confidence: next.confidence }, guess: { probabilities: next.guesses ?? {} } }, usage: { cost: 0.00003 } };
    return Promise.resolve(jsonResponse(payload));
  }
  if (url === CHAT_URL) {
    const content = plan.haiku.shift() ?? "";
    return Promise.resolve(jsonResponse({ choices: [{ message: { content } }], usage: { cost: 0.0001 } }));
  }
  return Promise.reject(new Error(`unexpected fetch ${url}`));
}

beforeEach(function spyOnFetch() {
  plan = { jev: [], haiku: [] };
  modelCalls = [];
  fetchSpy = vi.spyOn(globalThis, "fetch");
  fetchSpy.mockImplementation(planFetch);
});

afterEach(function restoreFetch() {
  fetchSpy.mockRestore();
  vi.useRealTimers();
});

describe("POST /repairs sorts before any runner can claim", () => {
  it("code: queued with the founder's event, the runner gets it, lane and cost stored", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    plan.jev.push({ lane: "code", confidence: 0.95 });

    const { response, reply } = await postReport(env, token, "add a weekly chart");

    expect(response.status).toBe(201);
    expect(reply.lane).toBe("code");
    expect(reply.status).toBe("queued");
    expect(reply.question).toBeUndefined();
    const row = reportRow(env, reply.id);
    expect(row.sort_status).toBe("sorted");
    expect(row.lane).toBe("code");
    expect(row.sort_confidence).toBe(0.95);
    expect(row.sort_model).toBe("typesafe/jev-1.14");
    expect(Number(row.sort_cost_usd)).toBeCloseTo(0.00003);
    expect(row.sort_latency_ms).not.toBeNull();
    expect(founderEventCount(env, reply.id)).toBe(1);
    const claimed = await claim(env);
    expect(claimed.status).toBe(200);
    const job = (await claimed.json()) as { id: string; sort: { lane: string } };
    expect(job.id).toBe(reply.id);
    expect(job.sort.lane).toBe("code");
  });

  it("the model reads the Sidekick's own name and description and the drawing outline", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    plan.jev.push({ lane: "code", confidence: 0.95 });

    await postReport(env, token, "add a weekly chart");

    const state = String(modelCalls[0].body.state);
    expect(state).toContain('"Water (Daily water goal and reminders.)"');
    expect(state).toContain("1 stroke(s) covering x 150–250, y 300–400");
  });

  it("ask_back: the card with 2-3 options, not claimable, no founder event", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    plan.jev.push({ lane: "ask_back", confidence: 0.9, guesses: { other_icon: 0.5, smaller: 0.3, bigger: 0.1 } });

    const { response, reply } = await postReport(env, token, "I hate this can you change this");

    expect(response.status).toBe(201);
    expect(reply.lane).toBe("ask_back");
    expect(reply.question?.text).toBe("What should it be?");
    const options = reply.question?.options ?? [];
    expect(options.length).toBeGreaterThanOrEqual(2);
    expect(options.length).toBeLessThanOrEqual(3);
    expect(options[0]).toEqual({ id: "other_icon", label: "Other icon", icon: "photo" });
    expect(options[1].id).toBe("smaller");
    expect(reply.message).toBeUndefined();
    expect(reportRow(env, reply.id).sort_status).toBe("asking");
    expect(founderEventCount(env, reply.id)).toBe(0);
    const claimed = await claim(env);
    expect(claimed.status).toBe(204);
  });

  it("not_a_request: the pill's line, no job", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    plan.jev.push({ lane: "not_a_request", confidence: 0.99 });

    const { reply } = await postReport(env, token, "how are you");

    expect(reply.lane).toBe("not_a_request");
    expect(reply.message).toBe(NOT_A_REQUEST_TEXT);
    expect(reply.message).toBe("Say or draw what to change.");
    expect(reply.status).toBe("received");
    expect(founderEventCount(env, reply.id)).toBe(0);
    expect((await claim(env)).status).toBe(204);
  });

  it("shell_cant: a line naming the Sidekick, a push to the founder, no job", async () => {
    const { env, pushes } = makeEnv();
    addFounderDevice(env);
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    plan.jev.push({ lane: "shell_cant", confidence: 0.9 });

    const { reply } = await postReport(env, token, "remind me every 20 minutes");

    expect(reply.lane).toBe("shell_cant");
    expect(reply.message).toBe("Water can't do that yet. Sent to Midas.");
    expect(pushes.length).toBe(1);
    const aps = pushes[0].body.aps as { alert: { title: string; body: string } };
    expect(aps.alert.title).toBe(SHELL_CANT_PUSH_TITLE);
    expect(aps.alert.body).toBe("Water: remind me every 20 minutes");
    expect(reportRow(env, reply.id).sort_alert).toBe("sent 1 of 1");
    expect((await claim(env)).status).toBe(204);
  });

  it("an OpenRouter error goes to code and the runner still gets it", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    // No planned answer: the stand-in answers 500.

    const { reply } = await postReport(env, token, "the button is broken");

    expect(reply.lane).toBe("code");
    expect(reportRow(env, reply.id).sort_error).toBe("jev: HTTP 500");
    expect((await claim(env)).status).toBe(200);
  });

  it("a retry of the same report gets the same reply, without sorting again", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    plan.jev.push({ lane: "ask_back", confidence: 0.9, guesses: { remove: 0.9 } });

    const first = await postReport(env, token, "change this", "phone-1");
    const second = await postReport(env, token, "change this", "phone-1");

    expect(second.response.status).toBe(200);
    expect(second.reply.id).toBe(first.reply.id);
    expect(second.reply.lane).toBe("ask_back");
    expect(second.reply.question).toEqual(first.reply.question);
    expect(modelCalls.length).toBe(1);
  });
});

describe("POST /repairs/:id/answer", () => {
  async function askedReport(env: TestEnv, token: string): Promise<Reply> {
    plan.jev.push({ lane: "ask_back", confidence: 0.9, guesses: { other_icon: 0.5, smaller: 0.3 } });
    const { reply } = await postReport(env, token, "I hate this can you change this");
    expect(reply.lane).toBe("ask_back");
    return reply;
  }

  it("a tapped option joins the same request, which is sorted again and queued", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    const asked = await askedReport(env, token);
    plan.jev.push({ lane: "code", confidence: 0.9 });

    const response = await postAnswer(env, token, asked.id, { optionId: "other_icon" });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ lane: "code" });
    expect(String(modelCalls[1].body.state)).toContain('they answered: "Other icon"');
    const row = reportRow(env, asked.id);
    expect(row.sort_answer).toBe("Other icon");
    expect(row.status).toBe("queued");
    expect(Number(row.sort_cost_usd)).toBeCloseTo(0.00006);
    const claimed = await claim(env);
    const job = (await claimed.json()) as { id: string; sort: { answer: string } };
    expect(job.id).toBe(asked.id);
    expect(job.sort.answer).toBe("Other icon");
  });

  it("said words work too, and a second ask_back is read as code (up, never down)", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    const asked = await askedReport(env, token);
    plan.jev.push({ lane: "ask_back", confidence: 0.9 });

    const response = await postAnswer(env, token, asked.id, { text: "a glass instead" });

    expect(await response.json()).toEqual({ lane: "code" });
    expect(reportRow(env, asked.id).sort_answer).toBe("a glass instead");
  });

  it("an option that was not on the card, or an empty body, is refused", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    const asked = await askedReport(env, token);

    expect((await postAnswer(env, token, asked.id, { optionId: "move" })).status).toBe(400);
    expect((await postAnswer(env, token, asked.id, {})).status).toBe(400);
    expect(reportRow(env, asked.id).sort_status).toBe("asking");
  });

  it("another person cannot answer; a card already answered is 409", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    const otherToken = addSignedInUser(env, "riya", ["hydration"]);
    const asked = await askedReport(env, token);

    expect((await postAnswer(env, otherToken, asked.id, { optionId: "smaller" })).status).toBe(404);
    plan.jev.push({ lane: "setting", confidence: 0.9 });
    expect((await postAnswer(env, token, asked.id, { optionId: "smaller" })).status).toBe(200);
    expect((await postAnswer(env, token, asked.id, { optionId: "smaller" })).status).toBe(409);
  });

  it("a card unanswered for 2 minutes is dropped and logged; a late answer gets 410", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    const asked = await askedReport(env, token);
    const logSpy = vi.spyOn(console, "log");
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + ANSWER_WINDOW_MS + 1000);

    const response = await postAnswer(env, token, asked.id, { optionId: "other_icon" });

    expect(response.status).toBe(410);
    expect(reportRow(env, asked.id).sort_status).toBe("dropped");
    const logged = JSON.stringify(logSpy.mock.calls);
    expect(logged).toContain("repair-question-dropped");
    expect(logged).toContain(asked.id);
    logSpy.mockRestore();
  });

  it("the runner's poll drops stale cards too; a fresh card stays", async () => {
    const { env } = makeEnv();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    const asked = await askedReport(env, token);

    await claim(env);
    expect(reportRow(env, asked.id).sort_status).toBe("asking");

    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + ANSWER_WINDOW_MS + 1000);
    await claim(env);
    expect(reportRow(env, asked.id).sort_status).toBe("dropped");
  });
});

describe("the shell_cant line without a manifest", () => {
  it("never shows the raw Sidekick id", async () => {
    const { env } = makeEnv();
    env.BUNDLES = makeFakeR2();
    const token = addSignedInUser(env, "amogh", ["hydration"]);
    plan.jev.push({ lane: "shell_cant", confidence: 0.9 });

    const { reply } = await postReport(env, token, "remind me every 20 minutes");

    expect(reply.message).toBe("Can't do that yet. Sent to Midas.");
  });
});
