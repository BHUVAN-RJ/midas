import { Hono } from "hono";
import type { Context } from "hono";
import { JESS_MODEL, MAX_SIDEKICKS, buildJessRequest, clockProblem, outcomeFromToolCall, parseSidekick, toolCallFromMessage } from "./jess";
import type { JessContext, JessOutcome, JessSidekick, ToolCall } from "./jess";
import { queueVoiceRepair } from "./repairs";
import { SIDEKICK_ID_PATTERN, assignedSidekickIds, currentAgentListing } from "./sidekicks";
import { MAX_TRANSCRIPT_LENGTH, MODEL_ATTEMPTS, OPENROUTER_URL, voiceCallSettings } from "./voice-route";

// POST /voice/jess (jess router, founder 2026-10-21): the phone sends the transcript, its clock and
// time zone, and for each Sidekick it can run tools for, its id and a small summary of its
// records (tools.js context()). The server reads each one's agent block from manifest.json of the
// version the user gets (their own copy, else the base; founder 2026-10-21: the phone no longer
// sends it), offers only Sidekicks assigned to the user whose version has tools.js, and checks
// the model's call against that manifest's inputSchema. Answers:
//   { status: "done", sidekickId, version, tool, input, logId }  the phone runs that version's
//                                                                 handler
//   { status: "repair", sidekickId, reportId, logId }   queued for the repair agent, no confirmation
//   { status: "not-done", reason, transcript, logId }   nothing changes; the home page card
// POST /voice/jess/outcome { logId, outcome, reason? } records what the phone did with a "done".
// Every attempt is written to voice_logs (migration 0007 columns) after the reply, as for
// /voice/reminder/parse. The sign-in check runs once, for every /voice path, in index.ts.

type JessBindings = {
  DB: D1Database;
  BUNDLES: R2Bucket;
  OPENROUTER_API_KEY?: string;
  RP_ID?: string;
};

type JessVariables = { userId: string };
type JessEnv = { Bindings: JessBindings; Variables: JessVariables };
type JessHonoContext = Context<JessEnv>;

const MAX_SHORT_FIELD_LENGTH = 80;
const MAX_REASON_LENGTH = 200;
const LOG_ID_PATTERN = /^[0-9a-f-]{36}$/;
const PHONE_OUTCOMES = new Set(["applied", "refused", "failed"]);

type AppInfo = { version: string | null; build: string | null; ios: string | null; device: string | null };
type ParsedJessRequest = { context: JessContext; app: AppInfo; listenMs: number | null };
// One Sidekick the phone can run tools for: its id and its tools.js context() of the records
type SentSidekick = { id: string; context: unknown };
type ParsedJessBody = { transcript: string; now: string; timeZone: string; locale?: string; sent: SentSidekick[]; app: AppInfo; listenMs: number | null };

type ModelStep = { step: "model"; attempt: number; ms: number; error: string | null };
type CheckStep = { step: "check"; ms: number };
type LogStep = ModelStep | CheckStep;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function shortText(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  return value.slice(0, MAX_SHORT_FIELD_LENGTH);
}

// The request body checked field by field; null when it cannot be used at all. Entries that are
// not a Sidekick id are left out rather than failing the whole request.
function parseJessBody(body: unknown): ParsedJessBody | null {
  if (!isPlainObject(body)) {
    return null;
  }
  const transcript = typeof body.transcript === "string" ? body.transcript.trim() : "";
  if (transcript.length === 0 || transcript.length > MAX_TRANSCRIPT_LENGTH) {
    return null;
  }
  if (clockProblem(body.now, body.timeZone) || !Array.isArray(body.sidekicks)) {
    return null;
  }
  const sent: SentSidekick[] = [];
  const seen = new Set<string>();
  for (const sentValue of body.sidekicks.slice(0, MAX_SIDEKICKS)) {
    if (!isPlainObject(sentValue) || typeof sentValue.id !== "string" || !SIDEKICK_ID_PATTERN.test(sentValue.id) || seen.has(sentValue.id)) {
      continue;
    }
    seen.add(sentValue.id);
    sent.push({ id: sentValue.id, context: sentValue.context ?? null });
  }
  if (sent.length === 0) {
    return null;
  }
  const appFields = isPlainObject(body.app) ? body.app : {};
  const app: AppInfo = {
    version: shortText(appFields.version),
    build: shortText(appFields.build),
    ios: shortText(appFields.ios),
    device: shortText(appFields.device),
  };
  const listenMs = Number.isInteger(body.listenMs) ? (body.listenMs as number) : null;
  return { transcript, now: body.now as string, timeZone: body.timeZone as string, locale: shortText(body.locale) ?? undefined, sent, app, listenMs };
}

// The Sidekicks offered to the model: each one the phone sent that is assigned to the user, with
// the name, version and agent block of the version the user gets. One whose manifest has no
// usable agent block, or whose version has no tools.js, is left out; the others still work.
export async function offeredSidekicks(env: { DB: D1Database; BUNDLES: R2Bucket }, userId: string, sent: SentSidekick[]): Promise<JessSidekick[]> {
  const assigned = new Set(await assignedSidekickIds(env.DB, userId));
  const sidekicks: JessSidekick[] = [];
  for (const sentSidekick of sent) {
    if (!assigned.has(sentSidekick.id)) {
      continue;
    }
    const listing = await currentAgentListing(env.BUNDLES, sentSidekick.id, userId);
    if (listing === null) {
      continue;
    }
    const sidekick = parseSidekick({ id: sentSidekick.id, name: listing.name, version: listing.version, agent: listing.agent, context: sentSidekick.context });
    if (sidekick !== null) {
      sidekicks.push(sidekick);
    }
  }
  return sidekicks;
}

/* ---------- The model call ---------- */

type CallResult = { call: ToolCall | null; rawReply: string | null; error: string | null; retryable: boolean; ms: number };

// One call to OpenRouter; never throws. A timeout, a network error or a busy server may be tried
// again; any other answer is final.
async function callModelOnce(context: JessContext, apiKey: string): Promise<CallResult> {
  const body = buildJessRequest(context, { reasoning: "off" });
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
        "x-title": "Midas jess",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      const retryable = response.status === 429 || response.status >= 500;
      return { call: null, rawReply: null, error: "HTTP " + response.status, retryable, ms: Date.now() - startedAt };
    }
    const payload = (await response.json()) as { choices?: Array<{ message?: unknown }> };
    const firstChoice = payload.choices && payload.choices[0];
    const message = firstChoice ? firstChoice.message : null;
    const call = toolCallFromMessage(message);
    const rawReply = call === null ? JSON.stringify(message ?? null) : JSON.stringify(call);
    return { call, rawReply, error: null, retryable: false, ms: Date.now() - startedAt };
  } catch (error) {
    const timedOut = error instanceof Error && error.name === "AbortError";
    return { call: null, rawReply: null, error: timedOut ? "timeout" : "network", retryable: true, ms: Date.now() - startedAt };
  } finally {
    clearTimeout(timer);
  }
}

type JessRun = { outcome: JessOutcome; rawReply: string | null; steps: LogStep[]; retries: number };

function modelErrorOutcome(context: JessContext): JessOutcome {
  return { status: "not-done", reason: "model-error", transcript: context.transcript };
}

// The model, tried at most twice, then the checks
export async function runJess(context: JessContext, apiKey: string | undefined): Promise<JessRun> {
  const steps: LogStep[] = [];
  if (apiKey === undefined || apiKey.length === 0) {
    steps.push({ step: "model", attempt: 1, ms: 0, error: "no key" });
    return { outcome: modelErrorOutcome(context), rawReply: null, steps, retries: 0 };
  }
  let result: CallResult | null = null;
  let attempt = 0;
  while (attempt < MODEL_ATTEMPTS) {
    attempt += 1;
    result = await callModelOnce(context, apiKey);
    steps.push({ step: "model", attempt, ms: result.ms, error: result.error });
    if (!result.retryable) {
      break;
    }
  }
  const retries = attempt - 1;
  if (result === null || result.error !== null) {
    return { outcome: modelErrorOutcome(context), rawReply: null, steps, retries };
  }
  const checkStartedAt = Date.now();
  const outcome = outcomeFromToolCall(result.call, context);
  steps.push({ step: "check", ms: Date.now() - checkStartedAt });
  return { outcome, rawReply: result.rawReply, steps, retries };
}

/* ---------- The log ---------- */

type JessLogEntry = {
  logId: string;
  userId: string;
  createdAt: string;
  parsed: ParsedJessRequest;
  run: JessRun;
  reportId: string | null;
  totalMs: number;
};

// What the log keeps of the Sidekicks offered: id, version and tool count, never the context
function sidekicksSummary(sidekicks: JessSidekick[]): string {
  const summary: Array<{ id: string; version: string | null; tools: number }> = [];
  for (const sidekick of sidekicks) {
    summary.push({ id: sidekick.id, version: sidekick.version, tools: sidekick.agent.tools.length });
  }
  return JSON.stringify(summary);
}

function chosenTool(outcome: JessOutcome): { sidekickId: string | null; tool: string | null; toolInput: string | null } {
  if (outcome.status === "done") {
    return { sidekickId: outcome.sidekickId, tool: outcome.tool, toolInput: JSON.stringify(outcome.input) };
  }
  if (outcome.status === "repair") {
    return { sidekickId: outcome.sidekickId, tool: "midas.repair_request", toolInput: JSON.stringify({ kind: outcome.kind }) };
  }
  return { sidekickId: null, tool: null, toolInput: null };
}

export async function writeJessLog(db: D1Database, entry: JessLogEntry): Promise<void> {
  const context = entry.parsed.context;
  const outcome = entry.run.outcome;
  const chosen = chosenTool(outcome);
  const status = outcome.status === "not-done" ? "not-done" : "done";
  const reason = outcome.status === "not-done" ? outcome.reason : null;
  const result = outcome.status === "repair" ? JSON.stringify({ reportId: entry.reportId }) : chosen.toolInput;
  const app = entry.parsed.app;
  const statement = db.prepare(
    "INSERT INTO voice_logs (id, user_id, created_at, transcript, request_now, time_zone, locale, lists, model, raw_reply, status, result, reason, retries, steps, total_ms, listen_ms, app_version, app_build, ios_version, device, endpoint, sidekick_id, tool, tool_input) " +
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'jess', ?, ?, ?)",
  );
  const bound = statement.bind(
    entry.logId,
    entry.userId,
    entry.createdAt,
    context.transcript,
    context.now,
    context.timeZone,
    context.locale ?? null,
    sidekicksSummary(context.sidekicks),
    JESS_MODEL,
    entry.run.rawReply,
    status,
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
    chosen.sidekickId,
    chosen.tool,
    chosen.toolInput,
  );
  await bound.run();
}

// Never throws: a lost log row is reported in the Worker's own log, without the words
async function writeJessLogSafely(db: D1Database, entry: JessLogEntry): Promise<void> {
  try {
    await writeJessLog(db, entry);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("jess log write failed: " + message);
  }
}

async function scheduleAfterReply(c: JessHonoContext, work: Promise<void>): Promise<void> {
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

/* ---------- The routes ---------- */

function versionOf(sidekicks: JessSidekick[], sidekickId: string): string | null {
  for (const sidekick of sidekicks) {
    if (sidekick.id === sidekickId) {
      return sidekick.version;
    }
  }
  return null;
}

async function handleJess(c: JessHonoContext) {
  const startedAt = Date.now();
  const createdAt = new Date(startedAt).toISOString();
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "body must be JSON" }, 400);
  }
  const parsedBody = parseJessBody(body);
  if (parsedBody === null) {
    return c.json({ error: "transcript, now, timeZone and at least one Sidekick are required" }, 400);
  }
  const userId = c.get("userId");
  const sidekicks = await offeredSidekicks(c.env, userId, parsedBody.sent);
  const context: JessContext = { transcript: parsedBody.transcript, now: parsedBody.now, timeZone: parsedBody.timeZone, locale: parsedBody.locale, sidekicks };
  const parsed: ParsedJessRequest = { context, app: parsedBody.app, listenMs: parsedBody.listenMs };
  // Nothing to offer: not done without calling the model, and logged like any other attempt
  let run: JessRun;
  if (sidekicks.length === 0) {
    run = { outcome: { status: "not-done", reason: "no-tools", transcript: context.transcript }, rawReply: null, steps: [], retries: 0 };
  } else {
    run = await runJess(context, c.env.OPENROUTER_API_KEY);
  }
  const logId = crypto.randomUUID();
  let reply: Record<string, unknown>;
  let reportId: string | null = null;
  if (run.outcome.status === "repair") {
    reportId = await queueVoiceRepair(c.env.DB, {
      userId,
      sidekickId: run.outcome.sidekickId,
      kind: run.outcome.kind,
      transcript: run.outcome.request,
      bundleVersion: versionOf(parsed.context.sidekicks, run.outcome.sidekickId),
      device: parsed.app.device,
      iosVersion: parsed.app.ios,
      appVersion: parsed.app.version,
      appBuild: parsed.app.build,
    });
    if (reportId === null) {
      run.outcome = { status: "not-done", reason: "unknown-sidekick", transcript: parsed.context.transcript };
    }
  }
  if (run.outcome.status === "repair") {
    reply = { status: "repair", sidekickId: run.outcome.sidekickId, reportId, logId };
  } else if (run.outcome.status === "done") {
    // The version whose manifest the call was checked against: the phone runs that version's tools.js
    reply = { ...run.outcome, version: versionOf(sidekicks, run.outcome.sidekickId), logId };
  } else {
    reply = { ...run.outcome, logId };
  }
  const entry: JessLogEntry = { logId, userId, createdAt, parsed, run, reportId, totalMs: Date.now() - startedAt };
  const response = c.json(reply);
  await scheduleAfterReply(c, writeJessLogSafely(c.env.DB, entry));
  return response;
}

// What the phone did with a "done": applied, or refused/failed with the Sidekick's reason. Only
// the user's own log row is touched, once.
async function handleOutcome(c: JessHonoContext) {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "body must be JSON" }, 400);
  }
  if (!isPlainObject(body) || typeof body.logId !== "string" || !LOG_ID_PATTERN.test(body.logId)) {
    return c.json({ error: "logId is required" }, 400);
  }
  if (typeof body.outcome !== "string" || !PHONE_OUTCOMES.has(body.outcome)) {
    return c.json({ error: "outcome must be applied, refused or failed" }, 400);
  }
  let phoneOutcome = body.outcome;
  if (body.outcome !== "applied" && typeof body.reason === "string" && body.reason.length > 0) {
    phoneOutcome = `${body.outcome}:${body.reason.slice(0, MAX_REASON_LENGTH)}`;
  }
  const statement = c.env.DB.prepare("UPDATE voice_logs SET phone_outcome = ? WHERE id = ? AND user_id = ? AND phone_outcome IS NULL");
  const result = await statement.bind(phoneOutcome, body.logId, c.get("userId")).run();
  if ((result.meta?.changes ?? 0) === 0) {
    return c.json({ error: "no such attempt" }, 404);
  }
  return c.json({ ok: true });
}

export const jessRoutes = new Hono<JessEnv>();
jessRoutes.post("/", handleJess);
jessRoutes.post("/outcome", handleOutcome);
