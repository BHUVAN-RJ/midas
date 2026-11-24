import { createHash } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { ANSWER_WINDOW_MS } from "../src/repair-sort";
import { DECISIONS_URL } from "../src/repair-sort-model";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Unclear code requests become a question, never a refusal (founder, 2026-11-23; docs/PRODUCT.md
// main 130a76a; job 08b4244b). The runner posts the repair agent's question to POST /repairs/:id/ask;
// the report becomes lane ask_back with the card the phone already reads from
// GET /repairs/lanes/:clientReportId; the answer goes straight back to the code lane with
// sort_answer set (never sorted again, never unclear), and the next claim carries it.

const RUNNER_TOKEN = "runner-secret-for-tests";
const STROKES = JSON.stringify([[[67, 250, 0], [383, 513, 50]]]);
const RUNNER_HEADERS = { Authorization: `Runner ${RUNNER_TOKEN}`, "Content-Type": "application/json" };
const AGENT_OPTIONS = [
  { label: "Drag to Reorder", kind: "move" },
  { label: "Move to Another Day", kind: "move" },
  { label: "Move the New Button", kind: "move" },
];

function makeEnv() {
  const bundles = makeFakeR2({
    "sidekicks/reminders/current.json": JSON.stringify({ version: "v3", scriptHashes: [] }),
    "sidekicks/reminders/v3/manifest.json": JSON.stringify({ id: "reminders", name: "Reminders", agent: { description: "Reminders." } }),
  });
  return { DB: makeMigratedD1(), BUNDLES: bundles, REPAIR_RUNNER_TOKEN: RUNNER_TOKEN, OPENROUTER_API_KEY: "test-key" };
}

type TestEnv = ReturnType<typeof makeEnv>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function addSignedInUser(env: TestEnv, userId: string): string {
  const token = `token-${userId}`;
  env.DB.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  env.DB.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, Date.now() + 3600000);
  env.DB.execute("INSERT INTO assignments (user_id, sidekick_id, assigned_at) VALUES (?, 'reminders', 'now')", userId);
  return token;
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
}

let fetchSpy: ReturnType<typeof vi.spyOn>;
let modelCalls: string[];

// The sort sends every request to code (Jev sure), so the agent is what asks
function sortSaysCode(input: RequestInfo | URL): Promise<Response> {
  const url = String(input);
  modelCalls.push(url);
  if (url === DECISIONS_URL) {
    return Promise.resolve(jsonResponse({ answers: { lane: { choice: "code", confidence: 0.95 }, guess: { probabilities: {} } }, usage: { cost: 0.00003 } }));
  }
  return Promise.reject(new Error(`unexpected fetch ${url}`));
}

beforeEach(function spyOnFetch() {
  modelCalls = [];
  fetchSpy = vi.spyOn(globalThis, "fetch");
  fetchSpy.mockImplementation(sortSaysCode);
});

afterEach(function restoreFetch() {
  fetchSpy.mockRestore();
  vi.useRealTimers();
});

async function sendReport(env: TestEnv, token: string, clientReportId: string): Promise<string> {
  const form = new FormData();
  form.set("sidekickId", "reminders");
  form.set("kind", "unknown");
  form.set("transcript", "That I can move around everywhere");
  form.set("strokes", STROKES);
  form.set("clientReportId", clientReportId);
  const response = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form }, env);
  const reply = (await response.json()) as { id: string; lane: string };
  expect(reply.lane).toBe("code");
  return reply.id;
}

async function claim(env: TestEnv) {
  return app.request("/repairs/jobs/claim", { method: "POST", headers: RUNNER_HEADERS, body: JSON.stringify({ runnerId: "mac-mini" }) }, env);
}

async function ask(env: TestEnv, reportId: string, body: Record<string, unknown>) {
  return app.request(`/repairs/${reportId}/ask`, { method: "POST", headers: RUNNER_HEADERS, body: JSON.stringify(body) }, env);
}

async function lane(env: TestEnv, token: string, clientReportId: string) {
  const response = await app.request(`/repairs/lanes/${clientReportId}`, { headers: { Authorization: `Bearer ${token}` } }, env);
  return (await response.json()) as { status: string; sortStatus: string; lane: string; question?: { text: string; options: Array<{ id: string; label: string; icon: string }> } };
}

async function answer(env: TestEnv, token: string, reportId: string, body: Record<string, unknown>) {
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  return app.request(`/repairs/${reportId}/answer`, { method: "POST", headers, body: JSON.stringify(body) }, env);
}

function reportRow(env: TestEnv, reportId: string): Record<string, unknown> {
  return env.DB.query("SELECT * FROM repair_reports WHERE id = ?", reportId)[0];
}

async function runningReport(env: TestEnv, token: string, clientReportId: string): Promise<string> {
  const reportId = await sendReport(env, token, clientReportId);
  const claimed = await claim(env);
  expect(claimed.status).toBe(200);
  expect(reportRow(env, reportId).status).toBe("running");
  return reportId;
}

describe("POST /repairs/:id/ask: the agent's question becomes the question card", () => {
  it("the running job becomes ask_back with its question and options; no runner can claim it", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const reportId = await runningReport(env, token, "phone-ask-1");

    const response = await ask(env, reportId, { question: "What should move?", options: AGENT_OPTIONS, summary: "unclear" });

    expect(response.status).toBe(200);
    const reply = (await response.json()) as { lane: string; question: { text: string; options: Array<{ id: string; label: string; icon: string }> } };
    expect(reply.lane).toBe("ask_back");
    expect(reply.question.text).toBe("What should move?");
    expect(reply.question.options).toEqual([
      { id: "option-1", label: "Drag to Reorder", icon: "arrow.up.and.down.and.arrow.left.and.right" },
      { id: "option-2", label: "Move to Another Day", icon: "arrow.up.and.down.and.arrow.left.and.right" },
      { id: "option-3", label: "Move the New Button", icon: "arrow.up.and.down.and.arrow.left.and.right" },
    ]);
    const row = reportRow(env, reportId);
    expect(row.status).toBe("received");
    expect(row.lane).toBe("ask_back");
    expect(row.sort_status).toBe("asking");
    expect(row.lease_until).toBeNull();
    expect((await claim(env)).status).toBe(204);
  });

  it("the phone's lane follow reads it exactly like a sort-time ask_back", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const reportId = await runningReport(env, token, "phone-ask-2");
    expect((await lane(env, token, "phone-ask-2")).lane).toBe("code");

    await ask(env, reportId, { question: "What should move?", options: AGENT_OPTIONS });

    const followed = await lane(env, token, "phone-ask-2");
    expect(followed.lane).toBe("ask_back");
    expect(followed.sortStatus).toBe("asking");
    expect(followed.status).toBe("received");
    expect(followed.question?.text).toBe("What should move?");
    expect(followed.question?.options.map(function labelOf(option) { return option.label; })).toEqual(["Drag to Reorder", "Move to Another Day", "Move the New Button"]);
  });

  it("the answer goes straight back to code with the answer, never sorted again, and the claim carries the question", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const reportId = await runningReport(env, token, "phone-ask-3");
    await ask(env, reportId, { question: "What should move?", options: AGENT_OPTIONS });
    const callsBefore = modelCalls.length;

    const response = await answer(env, token, reportId, { optionId: "option-1" });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ lane: "code" });
    expect(modelCalls.length).toBe(callsBefore);
    const row = reportRow(env, reportId);
    expect(row.status).toBe("queued");
    expect(row.lane).toBe("code");
    expect(row.sort_status).toBe("sorted");
    expect(row.sort_answer).toBe("Drag to Reorder");
    expect((await lane(env, token, "phone-ask-3")).lane).toBe("code");
    const claimed = await claim(env);
    expect(claimed.status).toBe(200);
    const job = (await claimed.json()) as { id: string; sort: { answer: string; question: string; lane: string } };
    expect(job.id).toBe(reportId);
    expect(job.sort.answer).toBe("Drag to Reorder");
    expect(job.sort.question).toBe("What should move?");
    expect(job.sort.lane).toBe("code");
    // A second answer finds no question waiting
    expect((await answer(env, token, reportId, { optionId: "option-2" })).status).toBe(409);
  });

  it("said words answer it too", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const reportId = await runningReport(env, token, "phone-ask-4");
    await ask(env, reportId, { question: "What should move?", options: AGENT_OPTIONS });

    expect(await (await answer(env, token, reportId, { text: "drag them up and down" })).json()).toEqual({ lane: "code" });
    expect(reportRow(env, reportId).sort_answer).toBe("drag them up and down");
  });

  it("a job that already carries an answer is never asked again", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const reportId = await runningReport(env, token, "phone-ask-5");
    await ask(env, reportId, { question: "What should move?", options: AGENT_OPTIONS });
    await answer(env, token, reportId, { optionId: "option-1" });
    await claim(env);

    const again = await ask(env, reportId, { question: "Where should it go?", options: AGENT_OPTIONS });

    expect(again.status).toBe(409);
    const row = reportRow(env, reportId);
    expect(row.status).toBe("running");
    expect(row.lane).toBe("code");
  });

  it("category labels are not options: fewer than 2 concrete ones is refused and the job keeps running", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const reportId = await runningReport(env, token, "phone-ask-6");

    const response = await ask(env, reportId, { question: "What should change?", options: [{ label: "Other Layout" }, { label: "Drag to Reorder" }] });

    expect(response.status).toBe(400);
    expect((await ask(env, reportId, { question: "", options: AGENT_OPTIONS })).status).toBe(400);
    expect(reportRow(env, reportId).status).toBe("running");
  });

  it("only from a running job, only by the runner, and a cancelled one answers cancelled", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const queuedId = await sendReport(env, token, "phone-ask-7");
    expect((await ask(env, queuedId, { question: "What should move?", options: AGENT_OPTIONS })).status).toBe(409);
    const asUser = await app.request(`/repairs/${queuedId}/ask`, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ question: "Q?", options: AGENT_OPTIONS }) }, env);
    expect(asUser.status).toBe(401);
    await claim(env);
    await app.request("/repairs/phone-ask-7/cancel", { method: "POST", headers: { Authorization: `Bearer ${token}` } }, env);
    const cancelled = await ask(env, queuedId, { question: "What should move?", options: AGENT_OPTIONS });
    expect(cancelled.status).toBe(409);
    expect(await cancelled.json()).toMatchObject({ cancelled: true });
  });

  it("left unanswered for 2 minutes it is dropped, as every question card is", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const reportId = await runningReport(env, token, "phone-ask-8");
    await ask(env, reportId, { question: "What should move?", options: AGENT_OPTIONS });
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + ANSWER_WINDOW_MS + 1000);

    expect((await answer(env, token, reportId, { optionId: "option-1" })).status).toBe(410);
    expect(reportRow(env, reportId).sort_status).toBe("dropped");
  });
});
