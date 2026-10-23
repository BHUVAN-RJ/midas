import { Hono } from "hono";
import type { Context } from "hono";
import {
  VOICE_MODEL,
  buildOpenRouterRequest,
  parseModelContent,
  resolveReply,
} from "./voice";
import type { VoiceContext, VoiceList, VoiceOutcome } from "./voice";

// POST /voice/reminder/parse (midas-intel docs/plans/2026-10-15-voice-action-button-brief.md, item
// 4): the phone sends the transcript, its clock, time zone and the user's list names; the model
// classifies and copies (strict JSON, temperature 0, no data kept by the provider), the parse core
// in voice.ts works out every date and checks the result. The answer is "done" with the reminder,
// or "not-done" with the reason and the transcript; the phone saves nothing on "not-done".
//
// Every attempt is written to voice_logs (founder, 2026-10-19) after the reply is sent, so the log
// adds no delay; a failed log write never fails the request.

type VoiceBindings = {
  DB: D1Database;
  // OpenRouter key, a Worker secret (wrangler secret put OPENROUTER_API_KEY --env staging).
  OPENROUTER_API_KEY?: string;
  RP_ID?: string;
};

type VoiceVariables = { userId: string };
type VoiceEnv = { Bindings: VoiceBindings; Variables: VoiceVariables };
type VoiceContextHono = Context<VoiceEnv>;

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
export const MODEL_TIMEOUT_MS = 4000;
// The first call plus one retry (brief item 4: 4 s timeout, one retry)
export const MODEL_ATTEMPTS = 2;
export const MAX_TRANSCRIPT_LENGTH = 2000;
export const MAX_LISTS = 200;
export const MAX_LIST_NAME_LENGTH = 200;
const MAX_SHORT_FIELD_LENGTH = 80;

// Tests shorten the timeout here instead of waiting 4 s per call.
export const voiceCallSettings = { timeoutMs: MODEL_TIMEOUT_MS };

type ModelStep = { step: "model"; attempt: number; ms: number; error: string | null };
type ResolveStep = { step: "resolve"; ms: number };
type LogStep = ModelStep | ResolveStep;

type CallResult = { content: unknown; error: string | null; retryable: boolean; ms: number };

type AppInfo = { version: string | null; build: string | null; ios: string | null; device: string | null };

type ParsedRequest = { context: VoiceContext; app: AppInfo; listenMs: number | null };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function shortText(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  return value.slice(0, MAX_SHORT_FIELD_LENGTH);
}

function parseLists(value: unknown): VoiceList[] | null {
  if (!Array.isArray(value) || value.length > MAX_LISTS) {
    return null;
  }
  const lists: VoiceList[] = [];
  for (const entry of value) {
    if (!isPlainObject(entry) || typeof entry.id !== "string" || typeof entry.name !== "string") {
      return null;
    }
    if (entry.id.length === 0 || entry.id.length > MAX_LIST_NAME_LENGTH || entry.name.length > MAX_LIST_NAME_LENGTH) {
      return null;
    }
    lists.push({ id: entry.id, name: entry.name });
  }
  return lists;
}

// The request body checked field by field; null when it cannot be used at all
function parseRequestBody(body: unknown): ParsedRequest | null {
  if (!isPlainObject(body)) {
    return null;
  }
  const transcript = typeof body.transcript === "string" ? body.transcript.trim() : "";
  if (transcript.length === 0 || transcript.length > MAX_TRANSCRIPT_LENGTH) {
    return null;
  }
  const lists = parseLists(body.lists ?? []);
  if (lists === null || typeof body.now !== "string" || typeof body.timeZone !== "string") {
    return null;
  }
  const context: VoiceContext = {
    transcript,
    now: body.now,
    timeZone: body.timeZone,
    locale: shortText(body.locale) ?? undefined,
    lists,
  };
  const appFields = isPlainObject(body.app) ? body.app : {};
  const app: AppInfo = {
    version: shortText(appFields.version),
    build: shortText(appFields.build),
    ios: shortText(appFields.ios),
    device: shortText(appFields.device),
  };
  const listenMs = Number.isInteger(body.listenMs) ? (body.listenMs as number) : null;
  return { context, app, listenMs };
}

/* ---------- The model call ---------- */

// One call to OpenRouter; never throws. A timeout, a network error or a busy server may be tried
// again; any other answer is final.
async function callModelOnce(context: VoiceContext, apiKey: string): Promise<CallResult> {
  const body = buildOpenRouterRequest(context, { reasoning: "off" });
  const controller = new AbortController();
  function abortCall() {
    controller.abort();
  }
  const timer = setTimeout(abortCall, voiceCallSettings.timeoutMs);
  const startedAt = Date.now();
  try {
    const response = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        authorization: "Bearer " + apiKey,
        "content-type": "application/json",
        "x-title": "Midas voice reminders",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      const retryable = response.status === 429 || response.status >= 500;
      const errorText = await openRouterErrorText(response);
      return { content: null, error: errorText, retryable, ms: Date.now() - startedAt };
    }
    const payload = (await response.json()) as { choices?: Array<{ message?: { content?: unknown } }> };
    const firstChoice = payload.choices && payload.choices[0];
    const content = firstChoice && firstChoice.message ? firstChoice.message.content : null;
    return { content, error: null, retryable: false, ms: Date.now() - startedAt };
  } catch (error) {
    const timedOut = error instanceof Error && error.name === "AbortError";
    const reason = timedOut ? "timeout" : "network";
    return { content: null, error: reason, retryable: true, ms: Date.now() - startedAt };
  } finally {
    clearTimeout(timer);
  }
}

// OpenRouter explains a refusal in its JSON body (for example which parameter or data policy left no
// provider). Kept short so the log row stays small; never includes the request or the key.
export async function openRouterErrorText(response: Response): Promise<string> {
  const statusText = "HTTP " + response.status;
  let bodyText = "";
  try {
    bodyText = await response.text();
  } catch {
    return statusText;
  }
  let message = bodyText;
  try {
    const parsed = JSON.parse(bodyText) as { error?: { message?: unknown } };
    // JSON without an error message says nothing about the refusal: keep only the status.
    message = parsed && parsed.error && typeof parsed.error.message === "string" ? parsed.error.message : "";
  } catch {
    // Not JSON: keep the raw text.
  }
  const trimmed = message.replace(/\s+/g, " ").trim().slice(0, 300);
  return trimmed.length > 0 ? statusText + ": " + trimmed : statusText;
}

type ParseRun = { outcome: VoiceOutcome; rawReply: string | null; steps: LogStep[]; retries: number };

function notDoneOutcome(reason: "model-error" | "bad-reply", context: VoiceContext): VoiceOutcome {
  return { status: "not-done", reason, transcript: context.transcript };
}

function rawReplyText(content: unknown): string | null {
  if (content === null || content === undefined) {
    return null;
  }
  return typeof content === "string" ? content : JSON.stringify(content);
}

// The model, tried at most twice, then the parse core
async function runParse(context: VoiceContext, apiKey: string | undefined): Promise<ParseRun> {
  const steps: LogStep[] = [];
  if (apiKey === undefined || apiKey.length === 0) {
    steps.push({ step: "model", attempt: 1, ms: 0, error: "no key" });
    return { outcome: notDoneOutcome("model-error", context), rawReply: null, steps, retries: 0 };
  }
  let call: CallResult | null = null;
  let attempt = 0;
  while (attempt < MODEL_ATTEMPTS) {
    attempt += 1;
    call = await callModelOnce(context, apiKey);
    steps.push({ step: "model", attempt, ms: call.ms, error: call.error });
    if (!call.retryable) {
      break;
    }
  }
  const retries = attempt - 1;
  if (call === null || call.error !== null) {
    return { outcome: notDoneOutcome("model-error", context), rawReply: null, steps, retries };
  }
  const resolveStartedAt = Date.now();
  const parsed = parseModelContent(call.content);
  let outcome: VoiceOutcome;
  if ("problem" in parsed) {
    outcome = notDoneOutcome("bad-reply", context);
  } else {
    outcome = resolveReply(parsed.reply, context);
  }
  steps.push({ step: "resolve", ms: Date.now() - resolveStartedAt });
  return { outcome, rawReply: rawReplyText(call.content), steps, retries };
}

/* ---------- The log ---------- */

type LogEntry = {
  userId: string;
  createdAt: string;
  parsed: ParsedRequest;
  run: ParseRun;
  totalMs: number;
};

export async function writeVoiceLog(db: D1Database, entry: LogEntry): Promise<void> {
  const context = entry.parsed.context;
  const outcome = entry.run.outcome;
  const result = outcome.status === "done" ? JSON.stringify(outcome.reminder) : null;
  const reason = outcome.status === "not-done" ? outcome.reason : null;
  const app = entry.parsed.app;
  const statement = db.prepare(
    "INSERT INTO voice_logs (id, user_id, created_at, transcript, request_now, time_zone, locale, lists, model, raw_reply, status, result, reason, retries, steps, total_ms, listen_ms, app_version, app_build, ios_version, device) " +
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
  );
  const bound = statement.bind(
    crypto.randomUUID(),
    entry.userId,
    entry.createdAt,
    context.transcript,
    context.now,
    context.timeZone,
    context.locale ?? null,
    JSON.stringify(context.lists),
    VOICE_MODEL,
    entry.run.rawReply,
    outcome.status,
    result,
    reason,
    entry.run.retries,
    JSON.stringify(entry.run.steps),
    entry.totalMs,
    entry.parsed.listenMs,
    app.version,
    app.build,
    app.ios,
    app.device,
  );
  await bound.run();
}

// Never throws: a lost log row is reported in the Worker's own log, without the words
async function writeVoiceLogSafely(db: D1Database, entry: LogEntry): Promise<void> {
  try {
    await writeVoiceLog(db, entry);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("voice log write failed: " + message);
  }
}

// After the reply when the runtime allows it (waitUntil); otherwise before it, still never failing
async function scheduleAfterReply(c: VoiceContextHono, work: Promise<void>): Promise<void> {
  let executionContext: { waitUntil(promise: Promise<unknown>): void } | null = null;
  try {
    executionContext = c.executionCtx;
  } catch {
    executionContext = null;
  }
  if (executionContext !== null) {
    executionContext.waitUntil(work);
    return;
  }
  await work;
}

/* ---------- The route ---------- */

async function handleParse(c: VoiceContextHono) {
  const startedAt = Date.now();
  const createdAt = new Date(startedAt).toISOString();
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "body must be JSON" }, 400);
  }
  const parsed = parseRequestBody(body);
  if (parsed === null) {
    return c.json({ error: "transcript, now, timeZone and lists are required" }, 400);
  }
  const run = await runParse(parsed.context, c.env.OPENROUTER_API_KEY);
  const entry: LogEntry = { userId: c.get("userId"), createdAt, parsed, run, totalMs: Date.now() - startedAt };
  const response = c.json(run.outcome);
  await scheduleAfterReply(c, writeVoiceLogSafely(c.env.DB, entry));
  return response;
}

// Signed in only: index.ts checks the session for every /voice path, once
export const voiceRoutes = new Hono<VoiceEnv>();
voiceRoutes.post("/reminder/parse", handleParse);
