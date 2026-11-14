import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { CHAT_URL, DECISIONS_URL } from "../src/repair-sort-model";
import { settingCallSettings } from "../src/repair-setting-model";
import { makeFakeR2 } from "./helpers/fake-r2";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// Repair lanes W5, the setting lane (founder, 2026-11-13; docs/briefs/repair-lanes.md W5,
// docs/PRODUCT.md D1): a request the sort puts in lane `setting` is mapped by Haiku to { key, value }
// changes from the Sidekick's own catalogue, written to the person's settings:self (one op, checked
// against the copy's types), answered to the phone with no runner job; anything Haiku cannot map
// goes up to code. Undo puts the old values back. OpenRouter is a stand-in (globalThis.fetch spied).

const RUNNER_TOKEN = "runner-secret-for-tests";
// Water's real manifest, with its catalogue (sidekicks/hydration/manifest.json)
const HYDRATION_MANIFEST = readFileSync(new URL("../../sidekicks/hydration/manifest.json", import.meta.url), "utf8");
const MANIFEST_WITHOUT_CATALOGUE = (function manifestWithoutCatalogue() {
  const manifest = JSON.parse(HYDRATION_MANIFEST) as Record<string, unknown>;
  delete manifest.settings;
  return JSON.stringify(manifest);
})();

function makeEnv() {
  const bundles = makeFakeR2({
    "sidekicks/hydration/current.json": JSON.stringify({ version: "v3", scriptHashes: [] }),
    "sidekicks/hydration/v3/manifest.json": HYDRATION_MANIFEST,
    // riya runs her own repaired copy, made before the settings engine: no catalogue
    "sidekicks/hydration/users/riya/current.json": JSON.stringify({ version: "r1", scriptHashes: [] }),
    "sidekicks/hydration/users/riya/r1/manifest.json": MANIFEST_WITHOUT_CATALOGUE,
  });
  return { DB: makeMigratedD1(), BUNDLES: bundles, REPAIR_RUNNER_TOKEN: RUNNER_TOKEN, OPENROUTER_API_KEY: "test-key" };
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

function storeSettings(env: TestEnv, userId: string, value: Record<string, unknown>) {
  env.DB.execute(
    "INSERT INTO ops (op_id, user_id, sidekick_id, key, value, deleted, client_time, received_at) VALUES (?, ?, 'hydration', 'settings:self', ?, 0, 'then', 'then')",
    `phone-${Math.random().toString(36).slice(2, 12)}`,
    userId,
    JSON.stringify(value),
  );
}

function latestSettings(env: TestEnv, userId: string): Record<string, unknown> | null {
  const rows = env.DB.query("SELECT value FROM ops WHERE user_id = ? AND key = 'settings:self' ORDER BY seq DESC LIMIT 1", userId);
  return rows.length === 0 ? null : (JSON.parse(String(rows[0].value)) as Record<string, unknown>);
}

function settingsOpCount(env: TestEnv, userId: string): number {
  return env.DB.query("SELECT seq FROM ops WHERE user_id = ? AND key = 'settings:self'", userId).length;
}

function makeForm(transcript: string, clientReportId?: string): FormData {
  const form = new FormData();
  form.set("sidekickId", "hydration");
  form.set("kind", "change");
  form.set("transcript", transcript);
  form.set("strokes", JSON.stringify([[[150, 300, 0], [250, 400, 50]]]));
  if (clientReportId !== undefined) {
    form.set("clientReportId", clientReportId);
  }
  return form;
}

type Reply = { id: string; status: string; lane: string; message?: string; setting?: { changes: Array<{ key: string; label: string; value: unknown }> } };

async function postReport(env: TestEnv, token: string, transcript: string, clientReportId?: string) {
  const response = await app.request("/repairs", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: makeForm(transcript, clientReportId) }, env);
  const reply = (await response.json()) as Reply;
  return { response, reply };
}

async function postUndo(env: TestEnv, token: string, reportId: string) {
  return app.request(`/repairs/${reportId}/undo`, { method: "POST", headers: { Authorization: `Bearer ${token}` } }, env);
}

async function claim(env: TestEnv) {
  const headers = { Authorization: `Runner ${RUNNER_TOKEN}`, "Content-Type": "application/json" };
  return app.request("/repairs/jobs/claim", { method: "POST", headers, body: JSON.stringify({ runnerId: "mac-mini" }) }, env);
}

function reportRow(env: TestEnv, reportId: string): Record<string, unknown> {
  return env.DB.query("SELECT * FROM repair_reports WHERE id = ?", reportId)[0];
}

function founderEventCount(env: TestEnv, reportId: string): number {
  return env.DB.query("SELECT id FROM repair_events WHERE report_id = ? AND audience = 'founder'", reportId).length;
}

function keyOfChange(change: { key: string }): string {
  return change.key;
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
}

// OpenRouter stand-in: Jev always says lane setting; each chat call takes the next planned answer
let haikuAnswers: string[];
let chatPrompts: string[];
let fetchSpy: ReturnType<typeof vi.spyOn>;

function planFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const url = String(input);
  const body = JSON.parse(String(init?.body)) as { messages?: Array<{ content: string }> };
  if (url === DECISIONS_URL) {
    return Promise.resolve(jsonResponse({ answers: { lane: { choice: "setting", confidence: 0.95 }, guess: { probabilities: {} } }, usage: { cost: 0.00003 } }));
  }
  if (url === CHAT_URL) {
    chatPrompts.push(String(body.messages?.[0]?.content));
    const content = haikuAnswers.shift();
    if (content === "hang") {
      return new Promise(function neverAnswers(_resolve, reject) {
        init?.signal?.addEventListener("abort", function rejectOnAbort() {
          reject(new Error("aborted"));
        });
      });
    }
    return Promise.resolve(jsonResponse({ choices: [{ message: { content: content ?? "" } }], usage: { cost: 0.0001 } }));
  }
  return Promise.reject(new Error(`unexpected fetch ${url}`));
}

beforeEach(function spyOnFetch() {
  haikuAnswers = [];
  chatPrompts = [];
  fetchSpy = vi.spyOn(globalThis, "fetch");
  fetchSpy.mockImplementation(planFetch);
});

afterEach(function restoreFetch() {
  fetchSpy.mockRestore();
  settingCallSettings.timeoutMs = 6000;
});

describe("the setting lane: done in the Worker, no runner job", () => {
  it("a colour change writes settings:self, answers the phone, makes no job and no founder event", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": [{"key": "sea.colour", "value": "#1e6fd9"}]}');

    const { response, reply } = await postReport(env, token, "make the water blue");

    expect(response.status).toBe(201);
    expect(reply.lane).toBe("setting");
    expect(reply.status).toBe("received");
    expect(reply.message).toBe("Changed");
    expect(reply.setting).toEqual({ changes: [{ key: "sea.colour", label: "Sea (the rising water) colour", value: "#1E6FD9" }] });
    expect(latestSettings(env, "amogh")).toEqual({ $type: "hydration.settings", "sea.colour": "#1E6FD9" });
    const row = reportRow(env, reply.id);
    expect(row.lane).toBe("setting");
    expect(row.sort_status).toBe("sorted");
    expect(row.setting_version).toBe("v3");
    expect(JSON.parse(String(row.setting_changes))).toEqual([{ key: "sea.colour", label: "Sea (the rising water) colour", value: "#1E6FD9", previous: null }]);
    expect(Number(row.setting_cost_usd)).toBeCloseTo(0.0001);
    expect(founderEventCount(env, reply.id)).toBe(0);
    expect((await claim(env)).status).toBe(204);
  });

  it("a hide keeps every other field the page keeps in settings:self", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    storeSettings(env, "amogh", { $type: "hydration.settings", "sea.colour": "#1E6FD9", "week.size": "l" });
    haikuAnswers.push('{"changes": [{"key": "streak.show", "value": false}]}');

    const { reply } = await postReport(env, token, "remove the streak");

    expect(reply.lane).toBe("setting");
    expect(latestSettings(env, "amogh")).toEqual({ $type: "hydration.settings", "sea.colour": "#1E6FD9", "week.size": "l", "streak.show": false });
  });

  it("Haiku reads the Sidekick's catalogue with the person's values now, and their words", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    storeSettings(env, "amogh", { $type: "hydration.settings", "amount.size": "l" });
    haikuAnswers.push('{"changes": [{"key": "amount.size", "value": "xl"}]}');

    await postReport(env, token, "make the number even bigger");

    expect(chatPrompts.length).toBe(1);
    expect(chatPrompts[0]).toContain("make the number even bigger");
    expect(chatPrompts[0]).toContain("- amount.size | Today's amount size | one of s, m, l, xl | now l");
    expect(chatPrompts[0]).toContain("- sea.colour | Sea (the rising water) colour | a colour #RRGGBB | now #5E9FA8");
  });

  it("two changes in one request are written as one op", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": [{"key": "amount.colour", "value": "#1E6FD9"}, {"key": "amount.size", "value": "l"}]}');

    const { reply } = await postReport(env, token, "make the number blue and bigger");

    const changes = reply.setting?.changes ?? [];
    const keys = changes.map(keyOfChange);
    expect(keys).toEqual(["amount.colour", "amount.size"]);
    expect(settingsOpCount(env, "amogh")).toBe(1);
  });

  it("a retry of the same report answers the stored result and writes nothing again", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": [{"key": "sea.colour", "value": "#1E6FD9"}]}');
    const first = await postReport(env, token, "make the water blue", "phone-report-1");

    const again = await postReport(env, token, "make the water blue", "phone-report-1");

    expect(again.reply.id).toBe(first.reply.id);
    expect(again.reply.lane).toBe("setting");
    expect(again.reply.setting).toEqual(first.reply.setting);
    expect(chatPrompts.length).toBe(1);
    expect(settingsOpCount(env, "amogh")).toBe(1);
  });
});

describe("the setting lane goes up to code when it cannot do the request", () => {
  async function expectUpToCode(env: TestEnv, token: string, words: string, problemPart: string) {
    const { reply } = await postReport(env, token, words);
    expect(reply.lane).toBe("code");
    expect(reply.status).toBe("queued");
    expect(reply.setting).toBeUndefined();
    const row = reportRow(env, reply.id);
    expect(String(row.setting_problem)).toContain(problemPart);
    expect(row.setting_changes).toBeNull();
    expect(founderEventCount(env, reply.id)).toBe(1);
    expect(settingsOpCount(env, String(row.user_id))).toBe(0);
    const claimed = await claim(env);
    expect(claimed.status).toBe(200);
  }

  it("no setting does it", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": []}');
    await expectUpToCode(env, token, "make the water sparkle", "no setting does it");
  });

  it("a value the catalogue does not offer", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": [{"key": "amount.size", "value": "huge"}]}');
    await expectUpToCode(env, token, "make the number huge", "amount.size");
  });

  it("a key the catalogue does not have", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": [{"key": "sparkle.show", "value": true}]}');
    await expectUpToCode(env, token, "add sparkles", "not a setting");
  });

  it("Haiku does not answer in time", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    settingCallSettings.timeoutMs = 50;
    haikuAnswers.push("hang");
    await expectUpToCode(env, token, "make the water blue", "timeout");
  });

  it("a copy made before the settings engine has no catalogue: no model call", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "riya");
    await expectUpToCode(env, token, "make the water blue", "no settings catalogue");
    expect(chatPrompts.length).toBe(0);
  });
});

describe("POST /repairs/:id/undo", () => {
  it("puts the old value back and keeps what changed since", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    storeSettings(env, "amogh", { $type: "hydration.settings", "sea.colour": "#2F9E44" });
    haikuAnswers.push('{"changes": [{"key": "sea.colour", "value": "#1E6FD9"}]}');
    const { reply } = await postReport(env, token, "make the water blue");
    storeSettings(env, "amogh", { $type: "hydration.settings", "sea.colour": "#1E6FD9", "help.show": false });

    const response = await postUndo(env, token, reply.id);

    expect(response.status).toBe(200);
    const undone = (await response.json()) as Reply;
    expect(undone.message).toBe("Undone");
    expect(undone.setting?.changes).toEqual([{ key: "sea.colour", label: "Sea (the rising water) colour", value: "#2F9E44" }]);
    expect(latestSettings(env, "amogh")).toEqual({ $type: "hydration.settings", "sea.colour": "#2F9E44", "help.show": false });
    expect(reportRow(env, reply.id).setting_undone_at).not.toBeNull();
  });

  it("a setting the person never had is removed, so the page is as built again", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    haikuAnswers.push('{"changes": [{"key": "streak.show", "value": false}]}');
    const { reply } = await postReport(env, token, "hide the streak");

    await postUndo(env, token, reply.id);

    expect(latestSettings(env, "amogh")).toEqual({ $type: "hydration.settings" });
  });

  it("only once, only the reporter, only a setting", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env, "amogh");
    const otherToken = addSignedInUser(env, "zoe");
    haikuAnswers.push('{"changes": [{"key": "streak.show", "value": false}]}');
    const { reply } = await postReport(env, token, "hide the streak");
    haikuAnswers.push('{"changes": []}');
    const upToCode = await postReport(env, token, "add sparkles");

    expect((await postUndo(env, otherToken, reply.id)).status).toBe(404);
    expect((await postUndo(env, token, upToCode.reply.id)).status).toBe(409);
    expect((await postUndo(env, token, reply.id)).status).toBe(200);
    expect((await postUndo(env, token, reply.id)).status).toBe(409);
    expect(settingsOpCount(env, "amogh")).toBe(2);
  });
});
