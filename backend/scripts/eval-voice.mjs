// Golden-set eval for voice reminders (midas-intel docs/plans/2026-10-13-voice-reminders-v1.md,
// section 7; founder 2026-10-15: DeepSeek only). Sends every sentence of voice-golden.json to
// deepseek/deepseek-v4-flash through OpenRouter, resolves the reply with the real parse core
// (src/voice.ts) and scores it against the expected result.
//
// Costs money. Run by hand only, by the founder:
//   cd backend && OPENROUTER_API_KEY=sk-or-... node scripts/eval-voice.mjs --reasoning both
// Options: --reasoning off|low|both (default both), --limit N, --concurrency N (default 4),
//          --only <id prefix>, --out <file prefix> (default ./voice-eval-<time>),
//          --timeout <seconds per call> (default 60).
// Writes <prefix>.md (the report) and <prefix>.json (every case, reply and score).
//
// Free, no key: --replay <earlier .json> re-scores the replies an earlier run got with the
// current parse core, without calling the model.
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import {
  VOICE_MODEL,
  buildOpenRouterRequest,
  normaliseTitle,
  outcomeFromModelContent,
  parseJsonObjectText,
  weekdayOf,
} from "../src/voice.ts";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const GOLDEN_PATH = new URL("./voice-golden.json", import.meta.url);
// deepseek/deepseek-v4-flash on OpenRouter, 2026-10-13, dollars per million tokens. Used only when
// OpenRouter's reply does not carry its own cost.
const PRICE_PER_MILLION = { input: 0.091, output: 0.182 };
// The 2026-10-16 run lost 63 reasoning-low calls to a 20 s limit while the rest took under 3 s;
// the limit is now 60 s and a timed-out or 429/5xx call is tried once more.
const CALL_TIMEOUT_MS = 60000;
const CALL_ATTEMPTS = 2;

const REPLY_DEFAULTS = {
  isReminder: true,
  notes: null,
  minutesFromNow: null,
  daysFromNow: null,
  date: null,
  yearMissing: false,
  weekday: null,
  weekdayNext: false,
  time: null,
  ampmStated: false,
  partOfDay: null,
  repeat: null,
  listId: null,
  whenText: "",
  confident: true,
};

/* ---------- The golden set ---------- */

export function loadGolden(path = GOLDEN_PATH) {
  const text = readFileSync(path, "utf8");
  return JSON.parse(text);
}

function deriveWhenKind(reply) {
  if (reply.minutesFromNow !== null || reply.daysFromNow !== null) {
    return "relative";
  }
  const saysWhen = reply.date !== null || reply.weekday !== null || reply.time !== null || reply.partOfDay !== null;
  return saysWhen ? "absolute" : "none";
}

function fullRepeat(repeat) {
  if (repeat === null || repeat === undefined) {
    return null;
  }
  return { every: repeat.every, interval: repeat.interval ?? 1, weekdays: repeat.weekdays ?? [] };
}

// The ideal model reply for a case: the defaults, the case's own fields, the expected title
export function idealReplyFor(goldenCase) {
  const expectedTitle = goldenCase.expect.title ?? "";
  const reply = { ...REPLY_DEFAULTS, title: expectedTitle, ...goldenCase.reply };
  reply.repeat = fullRepeat(reply.repeat);
  if (reply.whenKind === undefined) {
    reply.whenKind = deriveWhenKind(reply);
  }
  return reply;
}

export function contextFor(golden, goldenCase) {
  const shared = golden.contexts[goldenCase.ctx];
  if (!shared) {
    throw new Error("case " + goldenCase.id + " names no known context " + goldenCase.ctx);
  }
  return { ...shared, transcript: goldenCase.say };
}

/* ---------- Scoring ---------- */

function expectsNotDone(expect) {
  return expect.status === "not-done";
}

// The page's cleanRepeat shape, so { every: "day", interval: 1 } equals { every: "day" }. A weekly
// repeat with no weekdays repeats on its start date's weekday, as the page reads it, so it equals
// the same repeat with that weekday written out.
function canonicalRepeat(repeat, startDate) {
  if (repeat === null || repeat === undefined) {
    return "null";
  }
  const canonical = { every: repeat.every };
  if (repeat.interval !== undefined && repeat.interval > 1) {
    canonical.interval = repeat.interval;
  }
  if (repeat.every === "week") {
    const hasWeekdays = Array.isArray(repeat.weekdays) && repeat.weekdays.length > 0;
    if (hasWeekdays) {
      const sortedDays = [...new Set(repeat.weekdays)];
      sortedDays.sort(compareNumbers);
      canonical.weekdays = sortedDays;
    } else if (startDate) {
      canonical.weekdays = [weekdayOf(startDate)];
    }
  }
  return JSON.stringify(canonical);
}

function compareNumbers(first, second) {
  return first - second;
}

function sameNotes(expected, actual) {
  const expectedText = normaliseTitle(expected ?? "");
  const actualText = normaliseTitle(actual ?? "");
  return expectedText === actualText;
}

// One case's score. "exact" is date, time, repeat and list all equal (section 7); the title is
// compared after normalising; notes are reported but not part of exact.
export function scoreCase(expect, outcome) {
  if (expectsNotDone(expect)) {
    const isNotDone = outcome.status === "not-done";
    const reasonMatches = isNotDone && outcome.reason === expect.reason;
    return {
      kind: "not-done",
      exact: isNotDone,
      title: isNotDone,
      notes: true,
      pass: isNotDone,
      reasonMatches,
      wrongFields: isNotDone ? [] : ["status"],
    };
  }
  if (outcome.status !== "done") {
    return {
      kind: "done",
      exact: false,
      title: false,
      notes: false,
      pass: false,
      reasonMatches: false,
      wrongFields: ["status:" + outcome.reason],
    };
  }
  const reminder = outcome.reminder;
  const wrongFields = [];
  if ((expect.date ?? null) !== reminder.date) {
    wrongFields.push("date");
  }
  if ((expect.time ?? null) !== reminder.time) {
    wrongFields.push("time");
  }
  if (canonicalRepeat(expect.repeat, expect.date) !== canonicalRepeat(reminder.repeat, reminder.date)) {
    wrongFields.push("repeat");
  }
  if ((expect.list ?? null) !== reminder.list) {
    wrongFields.push("list");
  }
  const exact = wrongFields.length === 0;
  const titleMatches = normaliseTitle(expect.title ?? "") === normaliseTitle(reminder.title);
  if (!titleMatches) {
    wrongFields.push("title");
  }
  const notesMatch = sameNotes(expect.notes, reminder.notes);
  return {
    kind: "done",
    exact,
    title: titleMatches,
    notes: notesMatch,
    pass: exact && titleMatches,
    reasonMatches: true,
    wrongFields,
  };
}

/* ---------- Calling the model ---------- */

function costOf(usage) {
  if (!usage) {
    return null;
  }
  if (typeof usage.cost === "number") {
    return usage.cost;
  }
  const inputTokens = usage.prompt_tokens ?? 0;
  const outputTokens = usage.completion_tokens ?? 0;
  const inputCost = (inputTokens * PRICE_PER_MILLION.input) / 1e6;
  const outputCost = (outputTokens * PRICE_PER_MILLION.output) / 1e6;
  return inputCost + outputCost;
}

function isRetryable(call) {
  if (call.ok) {
    return false;
  }
  if (call.error === "timeout" || call.error.startsWith("network")) {
    return true;
  }
  const status = Number(call.error.replace("HTTP ", ""));
  return status === 429 || status >= 500;
}

// What OpenRouter said about the call, kept in the report to tell a slow provider from a long think
function callDetails(payload, choice) {
  const usage = payload.usage ?? {};
  const completionDetails = usage.completion_tokens_details ?? {};
  return {
    provider: payload.provider ?? null,
    finishReason: choice ? choice.finish_reason ?? null : null,
    reasoningTokens: completionDetails.reasoning_tokens ?? null,
    completionTokens: usage.completion_tokens ?? null,
  };
}

// One call to OpenRouter, tried again once when it times out or the server is busy; never throws
export async function callModel({ context, reasoning, apiKey, fetchImpl, clock, model, timeoutMs = CALL_TIMEOUT_MS }) {
  let call = null;
  let totalCost = 0;
  for (let attempt = 1; attempt <= CALL_ATTEMPTS; attempt += 1) {
    call = await callModelOnce({ context, reasoning, apiKey, fetchImpl, clock, model, timeoutMs });
    call.attempts = attempt;
    totalCost += costOf(call.usage) ?? 0;
    if (!isRetryable(call)) {
      break;
    }
  }
  call.cost = totalCost;
  return call;
}

// One call to OpenRouter; never throws. The body is never logged (section 4).
async function callModelOnce({ context, reasoning, apiKey, fetchImpl, clock, model, timeoutMs }) {
  const body = buildOpenRouterRequest(context, { model, reasoning });
  const controller = new AbortController();
  const timer = setTimeout(abortCall, timeoutMs);
  function abortCall() {
    controller.abort();
  }
  const startedAt = clock();
  try {
    const response = await fetchImpl(OPENROUTER_URL, {
      method: "POST",
      headers: {
        authorization: "Bearer " + apiKey,
        "content-type": "application/json",
        "x-title": "Midas voice eval",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const latencyMs = clock() - startedAt;
    if (!response.ok) {
      return { ok: false, error: "HTTP " + response.status, latencyMs, content: null, usage: null, details: null };
    }
    const payload = await response.json();
    const choice = payload.choices && payload.choices[0];
    const content = choice && choice.message ? choice.message.content : null;
    return { ok: true, error: null, latencyMs, content, usage: payload.usage ?? null, details: callDetails(payload, choice) };
  } catch (error) {
    const latencyMs = clock() - startedAt;
    const reason = error && error.name === "AbortError" ? "timeout" : "network: " + String(error && error.message);
    return { ok: false, error: reason, latencyMs, content: null, usage: null, details: null };
  } finally {
    clearTimeout(timer);
  }
}

/* ---------- The run ---------- */

// Runs `worker` over `items` with at most `limit` in flight, keeping the input order
async function mapWithConcurrency(items, limit, worker) {
  const results = new Array(items.length);
  let nextIndex = 0;
  async function runLane() {
    while (nextIndex < items.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await worker(items[index], index);
    }
  }
  const lanes = [];
  const laneCount = Math.max(1, Math.min(limit, items.length));
  for (let lane = 0; lane < laneCount; lane += 1) {
    lanes.push(runLane());
  }
  await Promise.all(lanes);
  return results;
}

// The reply as stored in the report: the parsed object, or the raw text when it is not JSON
function storedReply(content) {
  if (typeof content !== "string") {
    return null;
  }
  const parsed = parseJsonObjectText(content);
  return parsed === undefined ? content : parsed;
}

// One case's result from the model's text (null when the call failed)
function resultFor(golden, goldenCase, call) {
  const context = contextFor(golden, goldenCase);
  let outcome;
  if (call.ok) {
    outcome = outcomeFromModelContent(call.content, context);
  } else {
    outcome = { status: "not-done", reason: "model-error", transcript: context.transcript };
  }
  return {
    id: goldenCase.id,
    say: goldenCase.say,
    expect: goldenCase.expect,
    ideal: idealReplyFor(goldenCase),
    reply: call.ok ? storedReply(call.content) : null,
    outcome,
    score: scoreCase(goldenCase.expect, outcome),
    latencyMs: call.latencyMs,
    cost: call.cost ?? null,
    error: call.error,
    attempts: call.attempts ?? 1,
    details: call.details ?? null,
  };
}

export async function runEval({ golden, reasoning, apiKey, fetchImpl, clock = defaultClock, concurrency = 4, model = VOICE_MODEL, cases, timeoutMs }) {
  const selected = cases ?? golden.cases;
  async function evaluateCase(goldenCase) {
    const context = contextFor(golden, goldenCase);
    const call = await callModel({ context, reasoning, apiKey, fetchImpl, clock, model, timeoutMs });
    return resultFor(golden, goldenCase, call);
  }
  const results = await mapWithConcurrency(selected, concurrency, evaluateCase);
  return { model, reasoning, results, summary: summarise(results) };
}

// An earlier run's replies, scored again with the current parse core and golden set; no calls.
// A case the earlier run did not have, or whose call failed, stays a model error.
export function replayRun(golden, previousRun) {
  const previousById = new Map();
  for (const previous of previousRun.results) {
    previousById.set(previous.id, previous);
  }
  const results = [];
  for (const goldenCase of golden.cases) {
    const previous = previousById.get(goldenCase.id);
    if (previous === undefined) {
      continue;
    }
    const hadReply = previous.reply !== null && previous.reply !== undefined;
    const content = typeof previous.reply === "string" ? previous.reply : JSON.stringify(previous.reply);
    const call = {
      ok: hadReply,
      content: hadReply ? content : null,
      error: hadReply ? null : previous.error ?? "no reply",
      latencyMs: previous.latencyMs,
      cost: previous.cost,
      attempts: previous.attempts ?? 1,
      details: previous.details ?? null,
    };
    results.push(resultFor(golden, goldenCase, call));
  }
  return { model: previousRun.model, reasoning: previousRun.reasoning, results, summary: summarise(results) };
}

function defaultClock() {
  return performance.now();
}

/* ---------- Summary and report ---------- */

// Nearest-rank percentile of a list of numbers; null for an empty list
export function percentile(values, fraction) {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values];
  sorted.sort(compareNumbers);
  const rank = Math.ceil(fraction * sorted.length);
  const index = Math.min(sorted.length - 1, Math.max(0, rank - 1));
  return sorted[index];
}

function rate(count, total) {
  return total === 0 ? 0 : count / total;
}

export function summarise(results) {
  const total = results.length;
  let exact = 0;
  let titles = 0;
  let notes = 0;
  let passes = 0;
  let errors = 0;
  let retried = 0;
  let reasonMatches = 0;
  let notDoneCases = 0;
  let totalCost = 0;
  const latencies = [];
  const wrongFieldCounts = {};
  for (const result of results) {
    const score = result.score;
    exact += score.exact ? 1 : 0;
    titles += score.title ? 1 : 0;
    notes += score.notes ? 1 : 0;
    passes += score.pass ? 1 : 0;
    if (score.kind === "not-done") {
      notDoneCases += 1;
      reasonMatches += score.reasonMatches ? 1 : 0;
    }
    if ((result.attempts ?? 1) > 1) {
      retried += 1;
    }
    if (result.error) {
      errors += 1;
    } else {
      latencies.push(result.latencyMs);
    }
    totalCost += result.cost ?? 0;
    for (const field of score.wrongFields) {
      const fieldName = field.startsWith("status") ? "status" : field;
      wrongFieldCounts[fieldName] = (wrongFieldCounts[fieldName] ?? 0) + 1;
    }
  }
  return {
    total,
    exactRate: rate(exact, total),
    titleRate: rate(titles, total),
    notesRate: rate(notes, total),
    passRate: rate(passes, total),
    notDoneReasonRate: rate(reasonMatches, notDoneCases),
    errors,
    retried,
    p50Ms: percentile(latencies, 0.5),
    p95Ms: percentile(latencies, 0.95),
    totalCost,
    costPerReminder: total === 0 ? 0 : totalCost / total,
    wrongFieldCounts,
  };
}

function percent(fraction) {
  return (fraction * 100).toFixed(1) + "%";
}

function formatMs(milliseconds) {
  return milliseconds === null ? "n/a" : Math.round(milliseconds) + " ms";
}

function formatRunSection(run) {
  const summary = run.summary;
  const lines = [
    "## " + run.model + ", reasoning " + run.reasoning,
    "",
    "| Measure | Value |",
    "|---|---|",
    "| Cases | " + summary.total + " |",
    "| Exact (date, time, repeat, list) | " + percent(summary.exactRate) + " |",
    "| Title after normalising | " + percent(summary.titleRate) + " |",
    "| Exact and title (pass) | " + percent(summary.passRate) + " |",
    "| Notes | " + percent(summary.notesRate) + " |",
    "| Not-done cases with the expected reason | " + percent(summary.notDoneReasonRate) + " |",
    "| Calls failed (HTTP, timeout) | " + summary.errors + " |",
    "| Calls tried a second time | " + (summary.retried ?? 0) + " |",
    "| Latency p50 / p95 | " + formatMs(summary.p50Ms) + " / " + formatMs(summary.p95Ms) + " |",
    "| Cost, total / per reminder | $" + summary.totalCost.toFixed(4) + " / $" + summary.costPerReminder.toFixed(6) + " |",
    "",
  ];
  const fieldNames = Object.keys(summary.wrongFieldCounts);
  if (fieldNames.length > 0) {
    const fieldParts = [];
    for (const fieldName of fieldNames) {
      fieldParts.push(fieldName + " " + summary.wrongFieldCounts[fieldName]);
    }
    lines.push("Wrong fields: " + fieldParts.join(", ") + ".", "");
  }
  const failures = [];
  for (const result of run.results) {
    if (!result.score.pass) {
      failures.push(result);
    }
  }
  if (failures.length > 0) {
    lines.push("| Case | Sentence | Wrong | Got |", "|---|---|---|---|");
    for (const failure of failures) {
      lines.push("| " + failure.id + " | " + failure.say + " | " + failure.score.wrongFields.join(", ") + " | " + describeOutcome(failure) + " |");
    }
    lines.push("");
  }
  return lines.join("\n");
}

// "provider X, finish length, 900 reasoning tokens" when the call did not end normally
function describeCall(result) {
  const details = result.details;
  if (!details || details.finishReason === "stop" || details.finishReason === null) {
    return "";
  }
  const parts = ["finish " + details.finishReason];
  if (details.provider) {
    parts.unshift("provider " + details.provider);
  }
  if (details.reasoningTokens !== null) {
    parts.push(details.reasoningTokens + " reasoning tokens");
  }
  return " (" + parts.join(", ") + ")";
}

function describeOutcome(result) {
  const outcome = result.outcome;
  if (outcome.status === "not-done") {
    return "not done: " + outcome.reason + (result.error ? " (" + result.error + ")" : "") + describeCall(result);
  }
  const reminder = outcome.reminder;
  const repeatText = reminder.repeat ? " " + JSON.stringify(reminder.repeat) : "";
  const listText = reminder.list ? " " + reminder.list : "";
  return reminder.title + " / " + (reminder.date ?? "no date") + " " + (reminder.time ?? "all-day") + repeatText + listText;
}

export function formatReport(runs, startedAtIso) {
  const sections = ["# Voice reminders golden-set eval", "", "Run " + startedAtIso + ". Bar to ship: proposal 98% exact; the founder sets it.", ""];
  for (const run of runs) {
    sections.push(formatRunSection(run));
  }
  return sections.join("\n");
}

/* ---------- Command line ---------- */

export function parseArgs(argv) {
  const options = { reasoning: "both", limit: null, concurrency: 4, only: null, out: null, replay: null, timeoutMs: CALL_TIMEOUT_MS };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (flag === "--reasoning") {
      options.reasoning = value;
      index += 1;
    } else if (flag === "--limit") {
      options.limit = Number(value);
      index += 1;
    } else if (flag === "--concurrency") {
      options.concurrency = Number(value);
      index += 1;
    } else if (flag === "--only") {
      options.only = value;
      index += 1;
    } else if (flag === "--out") {
      options.out = value;
      index += 1;
    } else if (flag === "--replay") {
      options.replay = value;
      index += 1;
    } else if (flag === "--timeout") {
      options.timeoutMs = Number(value) * 1000;
      index += 1;
    } else {
      throw new Error("unknown option " + flag);
    }
  }
  if (!["off", "low", "both"].includes(options.reasoning)) {
    throw new Error("--reasoning is off, low or both");
  }
  if (!(options.timeoutMs > 0)) {
    throw new Error("--timeout is a number of seconds");
  }
  return options;
}

function selectCases(golden, options) {
  let cases = golden.cases;
  if (options.only) {
    const matching = [];
    for (const goldenCase of cases) {
      if (goldenCase.id.startsWith(options.only)) {
        matching.push(goldenCase);
      }
    }
    cases = matching;
  }
  if (options.limit) {
    cases = cases.slice(0, options.limit);
  }
  return cases;
}

function writeReport(prefix, runs, startedAtIso) {
  writeFileSync(prefix + ".md", formatReport(runs, startedAtIso));
  writeFileSync(prefix + ".json", JSON.stringify({ startedAt: startedAtIso, runs }, null, 2));
}

function replayMain(options, startedAtIso) {
  const golden = loadGolden();
  const previousText = readFileSync(options.replay, "utf8");
  const previous = JSON.parse(previousText);
  const runs = [];
  for (const previousRun of previous.runs) {
    runs.push(replayRun(golden, previousRun));
  }
  const stamp = startedAtIso.replace(/[:.]/g, "-");
  const prefix = options.out ?? "voice-replay-" + stamp;
  writeReport(prefix, runs, startedAtIso + " (replay of " + previous.startedAt + ", no calls)");
  return { prefix, runs };
}

export async function main(argv, environment, fetchImpl) {
  const options = parseArgs(argv);
  const startedAtIso = new Date().toISOString();
  if (options.replay) {
    return replayMain(options, startedAtIso);
  }
  const apiKey = environment.OPENROUTER_API_KEY;
  if (!apiKey) {
    throw new Error("OPENROUTER_API_KEY is not set");
  }
  const golden = loadGolden();
  const cases = selectCases(golden, options);
  const modes = options.reasoning === "both" ? ["off", "low"] : [options.reasoning];
  const runs = [];
  for (const reasoning of modes) {
    const run = await runEval({ golden, reasoning, apiKey, fetchImpl, concurrency: options.concurrency, cases, timeoutMs: options.timeoutMs });
    runs.push(run);
  }
  const stamp = startedAtIso.replace(/[:.]/g, "-");
  const prefix = options.out ?? "voice-eval-" + stamp;
  writeReport(prefix, runs, startedAtIso);
  return { prefix, runs };
}

const isDirectRun = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isDirectRun) {
  try {
    const finished = await main(process.argv.slice(2), process.env, fetch);
    for (const run of finished.runs) {
      const summary = run.summary;
      console.log("reasoning " + run.reasoning + ": exact " + percent(summary.exactRate) + ", pass " + percent(summary.passRate) + ", p50 " + formatMs(summary.p50Ms) + ", p95 " + formatMs(summary.p95Ms) + ", $" + summary.totalCost.toFixed(4));
    }
    console.log("report: " + finished.prefix + ".md");
  } catch (error) {
    console.error(String(error && error.message));
    process.exitCode = 1;
  }
}
