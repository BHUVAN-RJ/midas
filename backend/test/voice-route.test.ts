import { createHash } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import app from "../src/index";
import { VOICE_MODEL } from "../src/voice";
import { MODEL_TIMEOUT_MS, OPENROUTER_URL, voiceCallSettings } from "../src/voice-route";
import { formatVoiceLogRows, parseVoiceLogArgs, sinceToIso, voiceLogSql } from "../scripts/voice-log-tools.mjs";
import { makeMigratedD1 } from "./helpers/migrated-d1";

// POST /voice/reminder/parse (midas-intel docs/plans/2026-10-15-voice-action-button-brief.md, items
// 4 and 4a; founder 2026-10-19 for the log). Done when: a good reply resolves; a schema break or a
// failed check answers "not-done" with the transcript; a timeout is tried once more, then
// "not-done"; every attempt lands in voice_logs, after the reply (waitUntil); a failed log write
// still answers; the founder's log script reads only.

const API_KEY = "sk-or-test";
const NOW = "2026-10-19T16:00:00.000Z";
const ZONE = "America/Los_Angeles";
const LISTS = [{ id: "work", name: "Work" }, { id: "groceries", name: "Groceries" }];

type Db = ReturnType<typeof makeMigratedD1>;

function sha256Hex(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function makeEnv(withKey = true) {
  const env: { DB: Db; BUNDLES: object; OPENROUTER_API_KEY?: string } = { DB: makeMigratedD1(), BUNDLES: {} };
  if (withKey) {
    env.OPENROUTER_API_KEY = API_KEY;
  }
  return env;
}

function addSignedInUser(db: Db, userId: string): string {
  const token = `token-${userId}`;
  const farFuture = Date.now() + 60 * 60 * 1000;
  db.execute("INSERT INTO users (id, name, created_at) VALUES (?, ?, 'now')", userId, userId);
  db.execute("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, 'now', ?)", sha256Hex(token), userId, farFuture);
  return token;
}

// Collects what the route hands to waitUntil, as the Workers runtime would run it after the reply
function makeExecutionContext() {
  const pending: Promise<unknown>[] = [];
  function waitUntil(promise: Promise<unknown>) {
    pending.push(promise);
  }
  function passThroughOnException() {}
  async function settle() {
    await Promise.all(pending);
  }
  return { waitUntil, passThroughOnException, props: {}, pending, settle };
}

type RequestFields = Partial<{ transcript: unknown; now: unknown; timeZone: unknown; lists: unknown }>;

function parseBody(fields: RequestFields = {}) {
  return {
    transcript: "transcript" in fields ? fields.transcript : "Remind me to call Mom tomorrow at 6pm",
    now: "now" in fields ? fields.now : NOW,
    timeZone: "timeZone" in fields ? fields.timeZone : ZONE,
    locale: "en-US",
    lists: "lists" in fields ? fields.lists : LISTS,
    app: { version: "0.1.0", build: "3", ios: "26.1", device: "iPhone17,1" },
    listenMs: 2300,
  };
}

async function postParse(env: object, token: string | null, body: unknown, executionContext = makeExecutionContext()) {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token !== null) {
    headers.Authorization = `Bearer ${token}`;
  }
  const init = { method: "POST", headers, body: JSON.stringify(body) };
  const response = await app.request("/voice/reminder/parse", init, env, executionContext as unknown as ExecutionContext);
  await executionContext.settle();
  return response;
}

// The model's reply for "call Mom tomorrow at 6pm" as the strict schema shapes it
function modelReply(overrides: Record<string, unknown> = {}) {
  return {
    isReminder: true,
    title: "Call Mom",
    notes: null,
    whenKind: "absolute",
    minutesFromNow: null,
    daysFromNow: null,
    date: "2026-10-20",
    yearMissing: false,
    weekday: null,
    weekdayNext: false,
    time: "18:00",
    ampmStated: true,
    partOfDay: null,
    repeat: null,
    listId: null,
    whenText: "tomorrow at 6pm",
    confident: true,
    ...overrides,
  };
}

function openRouterAnswer(content: unknown, status = 200): Response {
  const payload = { choices: [{ message: { content }, finish_reason: "stop" }], usage: { prompt_tokens: 800, completion_tokens: 80 } };
  return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
}

// A call that only ends when the route gives up on it
function hangingCall(_url: unknown, init?: RequestInit): Promise<Response> {
  return new Promise(function waitForAbort(_resolve, reject) {
    const signal = init?.signal;
    function rejectAsAborted() {
      const abortError = new Error("aborted");
      abortError.name = "AbortError";
      reject(abortError);
    }
    signal?.addEventListener("abort", rejectAsAborted);
  });
}

function voiceLogRows(db: Db) {
  return db.query("SELECT * FROM voice_logs ORDER BY created_at");
}

let fetchMock: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  fetchMock = vi.spyOn(globalThis, "fetch");
  voiceCallSettings.timeoutMs = 40;
});

afterEach(() => {
  fetchMock.mockRestore();
  voiceCallSettings.timeoutMs = MODEL_TIMEOUT_MS;
  vi.restoreAllMocks();
});

describe("POST /voice/reminder/parse", () => {
  it("resolves a good reply into a reminder and logs the whole attempt", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    const replyText = JSON.stringify(modelReply());
    fetchMock.mockResolvedValue(openRouterAnswer(replyText));

    const response = await postParse(env, token, parseBody());
    expect(response.status).toBe(200);
    const answer = (await response.json()) as Record<string, any>;
    expect(answer.status).toBe("done");
    expect(answer.reminder).toMatchObject({ title: "Call Mom", date: "2026-10-20", time: "18:00", allDay: false, at: "2026-10-21T01:00:00.000Z", timeZone: ZONE, list: null, repeat: null });

    // The call: strict JSON, temperature 0, providers that keep no data, the key as a bearer
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [calledUrl, calledInit] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(calledUrl).toBe(OPENROUTER_URL);
    expect((calledInit.headers as Record<string, string>).authorization).toBe(`Bearer ${API_KEY}`);
    const sentBody = JSON.parse(String(calledInit.body));
    expect(sentBody.model).toBe(VOICE_MODEL);
    expect(sentBody.temperature).toBe(0);
    expect(sentBody.response_format.type).toBe("json_schema");
    expect(sentBody.response_format.json_schema.strict).toBe(true);
    expect(sentBody.provider).toMatchObject({ data_collection: "deny", require_parameters: true });
    expect(sentBody.messages[1].content).toContain("call Mom tomorrow at 6pm");

    const rows = voiceLogRows(env.DB);
    expect(rows).toHaveLength(1);
    const row = rows[0];
    expect(row.user_id).toBe("user-1");
    expect(row.transcript).toBe("Remind me to call Mom tomorrow at 6pm");
    expect(row.request_now).toBe(NOW);
    expect(row.time_zone).toBe(ZONE);
    expect(row.locale).toBe("en-US");
    expect(JSON.parse(String(row.lists))).toEqual(LISTS);
    expect(row.model).toBe(VOICE_MODEL);
    expect(row.raw_reply).toBe(replyText);
    expect(row.status).toBe("done");
    expect(JSON.parse(String(row.result))).toEqual(answer.reminder);
    expect(row.reason).toBeNull();
    expect(row.retries).toBe(0);
    const steps = JSON.parse(String(row.steps));
    expect(steps.map((step: { step: string }) => step.step)).toEqual(["model", "resolve"]);
    expect(steps[0].error).toBeNull();
    expect(typeof row.total_ms).toBe("number");
    expect(row.listen_ms).toBe(2300);
    expect(row.app_version).toBe("0.1.0");
    expect(row.app_build).toBe("3");
    expect(row.ios_version).toBe("26.1");
    expect(row.device).toBe("iPhone17,1");
  });

  it("writes the log through waitUntil, after the reply", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockResolvedValue(openRouterAnswer(JSON.stringify(modelReply())));
    const executionContext = makeExecutionContext();
    const init = { method: "POST", headers: { "content-type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify(parseBody()) };

    const response = await app.request("/voice/reminder/parse", init, env, executionContext as unknown as ExecutionContext);
    expect(response.status).toBe(200);
    expect(executionContext.pending).toHaveLength(1);
    await executionContext.settle();
    expect(voiceLogRows(env.DB)).toHaveLength(1);
  });

  it("answers not-done for a schema break, keeps the transcript, does not retry, and logs the raw reply", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    const broken = JSON.stringify({ isReminder: true, title: "Call Mom" });
    fetchMock.mockResolvedValue(openRouterAnswer(broken));

    const response = await postParse(env, token, parseBody());
    const answer = (await response.json()) as Record<string, unknown>;
    expect(answer).toEqual({ status: "not-done", reason: "bad-reply", transcript: "Remind me to call Mom tomorrow at 6pm" });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    const rows = voiceLogRows(env.DB);
    expect(rows).toHaveLength(1);
    expect(rows[0].status).toBe("not-done");
    expect(rows[0].reason).toBe("bad-reply");
    expect(rows[0].raw_reply).toBe(broken);
    expect(rows[0].result).toBeNull();
  });

  it("answers not-done for text that is not JSON", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockResolvedValue(openRouterAnswer("Sure! Here is your reminder."));

    const answer = (await (await postParse(env, token, parseBody())).json()) as Record<string, unknown>;
    expect(answer.status).toBe("not-done");
    expect(answer.reason).toBe("bad-reply");
    expect(voiceLogRows(env.DB)[0].raw_reply).toBe("Sure! Here is your reminder.");
  });

  it("answers not-done when a check fails: the model was not confident", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockResolvedValue(openRouterAnswer(JSON.stringify(modelReply({ confident: false }))));

    const answer = (await (await postParse(env, token, parseBody({ transcript: "Remind me about the thing with Sam" }))).json()) as Record<string, unknown>;
    expect(answer).toEqual({ status: "not-done", reason: "not-confident", transcript: "Remind me about the thing with Sam" });
    const row = voiceLogRows(env.DB)[0];
    expect(row.reason).toBe("not-confident");
    expect(row.transcript).toBe("Remind me about the thing with Sam");
  });

  it("answers not-done when a check fails: a time already past today", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    // 08:00 today said at 09:00 with "today": not moved to tomorrow (founder, 2026-10-16)
    const reply = modelReply({ date: "2026-10-19", time: "08:00", whenText: "today at 8am" });
    fetchMock.mockResolvedValue(openRouterAnswer(JSON.stringify(reply)));

    const answer = (await (await postParse(env, token, parseBody({ transcript: "Remind me to call Mom today at 8am" }))).json()) as Record<string, unknown>;
    expect(answer.status).toBe("not-done");
    expect(answer.reason).toBe("past");
    expect(voiceLogRows(env.DB)[0].reason).toBe("past");
  });

  it("tries a timed-out call once more, then answers not-done, logging both calls", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockImplementation(hangingCall);

    const answer = (await (await postParse(env, token, parseBody())).json()) as Record<string, unknown>;
    expect(answer).toEqual({ status: "not-done", reason: "model-error", transcript: "Remind me to call Mom tomorrow at 6pm" });
    expect(fetchMock).toHaveBeenCalledTimes(2);

    const row = voiceLogRows(env.DB)[0];
    expect(row.status).toBe("not-done");
    expect(row.reason).toBe("model-error");
    expect(row.retries).toBe(1);
    expect(row.raw_reply).toBeNull();
    const steps = JSON.parse(String(row.steps));
    expect(steps).toHaveLength(2);
    expect(steps[0]).toMatchObject({ step: "model", attempt: 1, error: "timeout" });
    expect(steps[1]).toMatchObject({ step: "model", attempt: 2, error: "timeout" });
  });

  it("uses the retry's answer when only the first call timed out", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockImplementationOnce(hangingCall);
    fetchMock.mockResolvedValueOnce(openRouterAnswer(JSON.stringify(modelReply())));

    const answer = (await (await postParse(env, token, parseBody())).json()) as Record<string, unknown>;
    expect(answer.status).toBe("done");
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(voiceLogRows(env.DB)[0].retries).toBe(1);
  });

  it("retries a busy server (500) but not a refused request (400)", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockResolvedValueOnce(openRouterAnswer(null, 500));
    fetchMock.mockResolvedValueOnce(openRouterAnswer(JSON.stringify(modelReply())));
    const retried = (await (await postParse(env, token, parseBody())).json()) as Record<string, unknown>;
    expect(retried.status).toBe("done");
    expect(fetchMock).toHaveBeenCalledTimes(2);

    fetchMock.mockReset();
    fetchMock.mockResolvedValue(openRouterAnswer(null, 400));
    const refused = (await (await postParse(env, token, parseBody())).json()) as Record<string, unknown>;
    expect(refused.status).toBe("not-done");
    expect(refused.reason).toBe("model-error");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const rows = voiceLogRows(env.DB);
    expect(rows).toHaveLength(2);
    expect(JSON.parse(String(rows[1].steps))[0].error).toBe("HTTP 400");
  });

  it("answers not-done without calling anyone when no key is set, and still logs", async () => {
    const env = makeEnv(false);
    const token = addSignedInUser(env.DB, "user-1");

    const answer = (await (await postParse(env, token, parseBody())).json()) as Record<string, unknown>;
    expect(answer.status).toBe("not-done");
    expect(answer.reason).toBe("model-error");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(voiceLogRows(env.DB)).toHaveLength(1);
  });

  it("still answers when the log write fails, and reports it without the words", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    const workingDb = env.DB;
    function prepareFailingLog(sql: string) {
      if (sql.includes("INSERT INTO voice_logs")) {
        throw new Error("D1 is down");
      }
      return workingDb.prepare(sql);
    }
    const failingDb = { ...workingDb, prepare: prepareFailingLog };
    const failingEnv = { ...env, DB: failingDb };
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    fetchMock.mockResolvedValue(openRouterAnswer(JSON.stringify(modelReply())));

    const response = await postParse(failingEnv, token, parseBody());
    expect(response.status).toBe(200);
    const answer = (await response.json()) as Record<string, unknown>;
    expect(answer.status).toBe("done");
    expect(voiceLogRows(workingDb)).toHaveLength(0);
    expect(errorSpy).toHaveBeenCalledTimes(1);
    expect(String(errorSpy.mock.calls[0][0])).toContain("voice log write failed");
    expect(String(errorSpy.mock.calls[0][0])).not.toContain("call Mom");
  });

  it("still answers when no execution context is there to wait on", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockResolvedValue(openRouterAnswer(JSON.stringify(modelReply())));
    const init = { method: "POST", headers: { "content-type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify(parseBody()) };

    const response = await app.request("/voice/reminder/parse", init, env);
    expect(response.status).toBe(200);
    expect(voiceLogRows(env.DB)).toHaveLength(1);
  });

  it("needs a session and logs nothing without one", async () => {
    const env = makeEnv();
    addSignedInUser(env.DB, "user-1");
    const noToken = await postParse(env, null, parseBody());
    expect(noToken.status).toBe(401);
    const wrongToken = await postParse(env, "token-nobody", parseBody());
    expect(wrongToken.status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(voiceLogRows(env.DB)).toHaveLength(0);
  });

  it("refuses a body it cannot use, before calling the model", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    const badBodies = [
      parseBody({ transcript: "" }),
      parseBody({ transcript: "   " }),
      parseBody({ transcript: "x".repeat(2001) }),
      parseBody({ transcript: 42 }),
      parseBody({ now: 5 }),
      parseBody({ timeZone: null }),
      parseBody({ lists: "work" }),
      parseBody({ lists: [{ id: "work" }] }),
    ];
    for (const body of badBodies) {
      const response = await postParse(env, token, body);
      expect(response.status).toBe(400);
    }
    expect(fetchMock).not.toHaveBeenCalled();
    expect(voiceLogRows(env.DB)).toHaveLength(0);
  });

  it("passes the user's list names to the model and resolves a named list", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockResolvedValue(openRouterAnswer(JSON.stringify(modelReply({ title: "Bananas", listId: "groceries", date: null, time: null, whenKind: "none", whenText: "", ampmStated: false }))));

    const answer = (await (await postParse(env, token, parseBody({ transcript: "Add bananas to groceries" }))).json()) as Record<string, any>;
    expect(answer.status).toBe("done");
    expect(answer.reminder).toMatchObject({ title: "Bananas", list: "groceries", at: null, date: null });
    const sentBody = JSON.parse(String((fetchMock.mock.calls[0] as [string, RequestInit])[1].body));
    expect(sentBody.messages[0].content).toContain("groceries  Groceries");
    expect(sentBody.response_format.json_schema.schema.properties.listId.enum).toEqual(["work", "groceries", null]);
  });
});

describe("voice-log.mjs helpers (founder's reader)", () => {
  const now = new Date("2026-10-19T12:00:00.000Z");

  it("reads --failed, --since and --limit, and refuses anything else", () => {
    expect(parseVoiceLogArgs(["--env", "staging"], now)).toEqual({ options: { failed: false, since: null, limit: 50 } });
    expect(parseVoiceLogArgs(["--env", "live", "--failed", "--since", "24h", "--limit", "5"], now)).toEqual({ options: { failed: true, since: "2026-10-18T12:00:00.000Z", limit: 5 } });
    expect(parseVoiceLogArgs(["--since", "2026-10-19"], now)).toEqual({ options: { failed: false, since: "2026-10-19T00:00:00.000Z", limit: 50 } });
    expect(parseVoiceLogArgs(["--since", "yesterday"], now)).toHaveProperty("problem");
    expect(parseVoiceLogArgs(["--limit", "0"], now)).toHaveProperty("problem");
    expect(parseVoiceLogArgs(["--everything"], now)).toHaveProperty("problem");
    expect(sinceToIso("7d", now)).toBe("2026-10-12T12:00:00.000Z");
  });

  it("builds a read-only query that the filters narrow", () => {
    const plain = voiceLogSql({ failed: false, since: null, limit: 50 });
    expect(plain).toMatch(/^SELECT /);
    expect(plain).not.toContain("WHERE");
    expect(plain).toContain("ORDER BY created_at DESC LIMIT 50");
    const narrowed = voiceLogSql({ failed: true, since: "2026-10-18T12:00:00.000Z", limit: 5 });
    expect(narrowed).toContain("WHERE status = 'not-done' AND created_at >= '2026-10-18T12:00:00.000Z'");
    expect(narrowed).toContain("LIMIT 5");
  });

  it("runs its query against the real table: --failed keeps only the not-done rows", async () => {
    const env = makeEnv();
    const token = addSignedInUser(env.DB, "user-1");
    fetchMock.mockResolvedValueOnce(openRouterAnswer(JSON.stringify(modelReply())));
    fetchMock.mockResolvedValueOnce(openRouterAnswer(JSON.stringify(modelReply({ confident: false }))));
    await postParse(env, token, parseBody());
    await postParse(env, token, parseBody({ transcript: "Remind me about the thing with Sam" }));

    const allRows = env.DB.query(voiceLogSql({ failed: false, since: null, limit: 50 }));
    expect(allRows).toHaveLength(2);
    const failedRows = env.DB.query(voiceLogSql({ failed: true, since: null, limit: 50 }));
    expect(failedRows).toHaveLength(1);
    expect(failedRows[0].transcript).toBe("Remind me about the thing with Sam");

    const text = formatVoiceLogRows(allRows);
    expect(text).toContain('said: "Remind me to call Mom tomorrow at 6pm"');
    expect(text).toContain("done: Call Mom, 2026-10-20 18:00");
    expect(text).toContain("not done: not-confident");
    expect(formatVoiceLogRows([])).toBe("no voice log rows");
  });
});
