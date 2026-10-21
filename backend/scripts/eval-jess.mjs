// Golden-set eval for the jess router (midas-intel docs/plans/2026-10-21-jess-voice-router.md,
// founder 2026-10-21: DeepSeek v4 Flash only). Sends every sentence of jess-golden.json to
// deepseek/deepseek-v4-flash through OpenRouter with the same prompt and tools POST /voice/jess
// sends (src/jess.ts), checks the one tool call with the same code, and scores it: the right
// Sidekick and tool, the right arguments, the right date and time, or "repair", or "not done".
//
// Costs money. Run by hand only, by the founder, once:
//   cd backend && OPENROUTER_API_KEY=sk-or-... node scripts/eval-jess.mjs
// Options: --reasoning off|low|both (default off, as the route), --limit N, --concurrency N
//          (default 4), --only <id prefix>, --out <file prefix> (default ./jess-eval-<time>),
//          --timeout <seconds per call> (default 60).
// Writes <prefix>.md (the report) and <prefix>.json (every case, call and score).
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { CANNOT_ACT_TOOL, JESS_MODEL, REPAIR_TOOL, buildJessRequest, outcomeFromToolCall, parseSidekick, toolCallFromMessage, wireToolName } from "../src/jess.ts";
import { normaliseTitle } from "../src/voice.ts";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const GOLDEN_PATH = new URL("./jess-golden.json", import.meta.url);
const REPO_ROOT = join(fileURLToPath(new URL(".", import.meta.url)), "..", "..");
// deepseek/deepseek-v4-flash on OpenRouter, 2026-10-13, dollars per million tokens. Used only when
// OpenRouter's reply does not carry its own cost.
const PRICE_PER_MILLION = { input: 0.091, output: 0.182 };
const CALL_TIMEOUT_MS = 60000;
const CALL_ATTEMPTS = 2;

// Every field of a tool's "when" (manifest.json $defs.when); a case gives only the ones it says
const WHEN_DEFAULTS = {
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
  whenText: "",
};

/* ---------- The golden set ---------- */

export function loadGolden(path = GOLDEN_PATH) {
  const text = readFileSync(path, "utf8");
  return JSON.parse(text);
}

function agentOf(sidekickId, repoRoot) {
  const manifestText = readFileSync(join(repoRoot, "sidekicks", sidekickId, "manifest.json"), "utf8");
  return JSON.parse(manifestText).agent;
}

// The request context for a case: the golden context's Sidekicks with their agent blocks read
// from sidekicks/<id>/manifest.json, as the phone sends them
export function contextFor(golden, goldenCase, repoRoot = REPO_ROOT) {
  const shared = golden.contexts[goldenCase.ctx];
  if (!shared) {
    throw new Error("case " + goldenCase.id + " names no known context " + goldenCase.ctx);
  }
  const sidekicks = [];
  for (const sent of shared.sidekicks) {
    const parsed = parseSidekick({ ...sent, agent: agentOf(sent.id, repoRoot) });
    if (parsed === null) {
      throw new Error("context " + goldenCase.ctx + ": Sidekick " + sent.id + " cannot be offered");
    }
    sidekicks.push(parsed);
  }
  return { transcript: goldenCase.say, now: shared.now, timeZone: shared.timeZone, locale: shared.locale, sidekicks };
}

function findTool(toolName, context) {
  for (const sidekick of context.sidekicks) {
    for (const tool of sidekick.agent.tools) {
      if (tool.name === toolName) {
        return tool;
      }
    }
  }
  return null;
}

function typeAllowsNull(propertySchema) {
  const type = propertySchema.type;
  if (Array.isArray(type)) {
    return type.includes("null");
  }
  return Array.isArray(propertySchema.anyOf);
}

function fullWhen(when) {
  const merged = { ...WHEN_DEFAULTS, ...when };
  if (merged.repeat !== null) {
    merged.repeat = { every: merged.repeat.every, interval: merged.repeat.interval ?? 1, weekdays: merged.repeat.weekdays ?? [] };
  }
  if (merged.whenKind === undefined) {
    const relative = merged.minutesFromNow !== null || merged.daysFromNow !== null;
    const saysWhen = merged.date !== null || merged.weekday !== null || merged.time !== null || merged.partOfDay !== null || merged.repeat !== null;
    merged.whenKind = relative ? "relative" : saysWhen ? "absolute" : "none";
  }
  return merged;
}

// The arguments the model should send for a Sidekick tool: the case's own, every other required
// field null (or false for a flag), and a when with every field filled
function idealArguments(tool, args) {
  const filled = {};
  const properties = tool.inputSchema.properties ?? {};
  for (const name of Object.keys(properties)) {
    if (Object.hasOwn(args, name)) {
      filled[name] = args[name];
    } else if (properties[name].type === "boolean") {
      filled[name] = false;
    } else if (typeAllowsNull(properties[name])) {
      filled[name] = null;
    }
  }
  const whenField = tool._meta ? tool._meta["midas/when"] : undefined;
  if (typeof whenField === "string" && filled[whenField] !== null && filled[whenField] !== undefined) {
    filled[whenField] = fullWhen(filled[whenField]);
  }
  return filled;
}

// The one tool call the model should make for a case, as { name, argumentsText }
export function idealCallFor(goldenCase, context) {
  const call = goldenCase.call;
  if (call.tool === REPAIR_TOOL || call.tool === CANNOT_ACT_TOOL) {
    return { name: wireToolName(call.tool), argumentsText: JSON.stringify(call.args) };
  }
  const tool = findTool(call.tool, context);
  if (tool === null) {
    throw new Error("case " + goldenCase.id + " calls " + call.tool + ", which its context does not offer");
  }
  return { name: wireToolName(call.tool), argumentsText: JSON.stringify(idealArguments(tool, call.args ?? {})) };
}

/* ---------- Scoring ---------- */

function compareNumbers(first, second) {
  return first - second;
}

// { every: "day", interval: 1 } equals { every: "day" }; weekdays in order
function canonicalRepeat(repeat) {
  if (repeat === null || repeat === undefined) {
    return "null";
  }
  const canonical = { every: repeat.every };
  if (repeat.interval !== undefined && repeat.interval > 1) {
    canonical.interval = repeat.interval;
  }
  if (Array.isArray(repeat.weekdays) && repeat.weekdays.length > 0) {
    const days = [...new Set(repeat.weekdays)];
    days.sort(compareNumbers);
    canonical.weekdays = days;
  }
  return JSON.stringify(canonical);
}

function sameText(expected, actual) {
  if (typeof expected !== "string" || typeof actual !== "string") {
    return expected === actual;
  }
  return normaliseTitle(expected) === normaliseTitle(actual);
}

function sameWhen(expected, actual) {
  if (expected === null) {
    return actual === null || actual === undefined;
  }
  if (actual === null || actual === undefined) {
    return false;
  }
  const sameDate = (expected.date ?? null) === actual.date;
  const sameTime = (expected.time ?? null) === actual.time;
  const sameRepeat = canonicalRepeat(expected.repeat) === canonicalRepeat(actual.repeat);
  return sameDate && sameTime && sameRepeat;
}

// Fields of a done case: every field the case names must match; the title (or name) is scored
// on its own, as wording differs more than meaning
const TITLE_FIELDS = ["title", "name"];

function scoreDone(expect, outcome) {
  if (outcome.status !== "done") {
    const got = outcome.status === "repair" ? "repair" : "not-done:" + outcome.reason;
    return { pass: false, title: false, wrongFields: ["status:" + got] };
  }
  if (outcome.tool !== expect.tool) {
    return { pass: false, title: false, wrongFields: ["tool:" + outcome.tool] };
  }
  const wrongFields = [];
  let titleMatches = true;
  for (const [field, expected] of Object.entries(expect.input ?? {})) {
    const actual = outcome.input[field];
    if (field === "when") {
      if (!sameWhen(expected, actual)) {
        wrongFields.push("when");
      }
    } else if (TITLE_FIELDS.includes(field)) {
      titleMatches = sameText(expected, actual);
    } else if (!sameText(expected, actual)) {
      wrongFields.push(field);
    }
  }
  return { pass: wrongFields.length === 0, title: titleMatches, wrongFields: titleMatches ? wrongFields : [...wrongFields, "title"] };
}

// One case's score. pass: the right outcome (tool and every named argument but the title, or
// repair of the right Sidekick, or not done); title is scored apart; reasonMatches says whether
// a repair's kind or a not-done reason is the expected one.
export function scoreCase(expect, outcome) {
  if (expect.status === "not-done") {
    const isNotDone = outcome.status === "not-done";
    return { kind: "not-done", pass: isNotDone, title: true, reasonMatches: isNotDone && outcome.reason === expect.reason, wrongFields: isNotDone ? [] : ["status:" + outcome.status] };
  }
  if (expect.status === "repair") {
    const isRepair = outcome.status === "repair" && outcome.sidekickId === expect.sidekick;
    return { kind: "repair", pass: isRepair, title: true, reasonMatches: isRepair && outcome.kind === expect.kind, wrongFields: isRepair ? [] : ["status:" + outcome.status] };
  }
  const score = scoreDone(expect, outcome);
  return { kind: "done", pass: score.pass, title: score.title, reasonMatches: true, wrongFields: score.wrongFields };
}

/* ---------- Calling the model ---------- */

function costOf(usage) {
  if (!usage) {
    return null;
  }
  if (typeof usage.cost === "number") {
    return usage.cost;
  }
  const inputCost = ((usage.prompt_tokens ?? 0) * PRICE_PER_MILLION.input) / 1e6;
  const outputCost = ((usage.completion_tokens ?? 0) * PRICE_PER_MILLION.output) / 1e6;
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

// One call to OpenRouter; never throws. Returns the tool call the model made, if any.
async function callModelOnce({ context, reasoning, apiKey, fetchImpl, clock, model, timeoutMs }) {
  const body = buildJessRequest(context, { model, reasoning });
  const controller = new AbortController();
  const timer = setTimeout(abortCall, timeoutMs);
  function abortCall() {
    controller.abort();
  }
  const startedAt = clock();
  try {
    const response = await fetchImpl(OPENROUTER_URL, {
      method: "POST",
      headers: { authorization: "Bearer " + apiKey, "content-type": "application/json", "x-title": "Midas jess eval" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const latencyMs = clock() - startedAt;
    if (!response.ok) {
      return { ok: false, error: "HTTP " + response.status, latencyMs, toolCall: null, usage: null };
    }
    const payload = await response.json();
    const choice = payload.choices && payload.choices[0];
    const toolCall = choice && choice.message ? toolCallFromMessage(choice.message) : null;
    return { ok: true, error: null, latencyMs, toolCall, usage: payload.usage ?? null };
  } catch (error) {
    const latencyMs = clock() - startedAt;
    const reason = error && error.name === "AbortError" ? "timeout" : "network: " + String(error && error.message);
    return { ok: false, error: reason, latencyMs, toolCall: null, usage: null };
  } finally {
    clearTimeout(timer);
  }
}

// One call, tried again once when it times out or the server is busy
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

function resultFor(goldenCase, context, call) {
  let outcome;
  if (call.ok) {
    outcome = outcomeFromToolCall(call.toolCall, context);
  } else {
    outcome = { status: "not-done", reason: "model-error", transcript: context.transcript };
  }
  return {
    id: goldenCase.id,
    say: goldenCase.say,
    expect: goldenCase.expect,
    toolCall: call.toolCall,
    outcome,
    score: scoreCase(goldenCase.expect, outcome),
    latencyMs: call.latencyMs,
    cost: call.cost ?? null,
    error: call.error,
    attempts: call.attempts ?? 1,
  };
}

function defaultClock() {
  return performance.now();
}

export async function runEval({ golden, reasoning, apiKey, fetchImpl, clock = defaultClock, concurrency = 4, model = JESS_MODEL, cases, timeoutMs, repoRoot = REPO_ROOT }) {
  const selected = cases ?? golden.cases;
  async function evaluateCase(goldenCase) {
    const context = contextFor(golden, goldenCase, repoRoot);
    const call = await callModel({ context, reasoning, apiKey, fetchImpl, clock, model, timeoutMs });
    return resultFor(goldenCase, context, call);
  }
  const results = await mapWithConcurrency(selected, concurrency, evaluateCase);
  return { model, reasoning, results, summary: summarise(results) };
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

function emptyKindCounts() {
  return { cases: 0, passes: 0, reasonMatches: 0 };
}

export function summarise(results) {
  const byKind = { done: emptyKindCounts(), repair: emptyKindCounts(), "not-done": emptyKindCounts() };
  let passes = 0;
  let titles = 0;
  let errors = 0;
  let retried = 0;
  let wrongActions = 0;
  let totalCost = 0;
  const latencies = [];
  for (const result of results) {
    const score = result.score;
    const counts = byKind[score.kind];
    counts.cases += 1;
    counts.passes += score.pass ? 1 : 0;
    counts.reasonMatches += score.reasonMatches ? 1 : 0;
    passes += score.pass ? 1 : 0;
    titles += score.title ? 1 : 0;
    // The costly mistake: something was changed or sent to repair that should not have been
    if (!score.pass && result.outcome.status !== "not-done") {
      wrongActions += 1;
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
  }
  const total = results.length;
  return {
    total,
    passRate: rate(passes, total),
    titleRate: rate(titles, total),
    doneRate: rate(byKind.done.passes, byKind.done.cases),
    repairRate: rate(byKind.repair.passes, byKind.repair.cases),
    notDoneRate: rate(byKind["not-done"].passes, byKind["not-done"].cases),
    notDoneReasonRate: rate(byKind["not-done"].reasonMatches, byKind["not-done"].cases),
    wrongActions,
    errors,
    retried,
    p50Ms: percentile(latencies, 0.5),
    p95Ms: percentile(latencies, 0.95),
    totalCost,
    costPerSentence: total === 0 ? 0 : totalCost / total,
  };
}

function percent(fraction) {
  return (fraction * 100).toFixed(1) + "%";
}

function formatMs(milliseconds) {
  return milliseconds === null ? "n/a" : Math.round(milliseconds) + " ms";
}

function describeOutcome(outcome) {
  if (outcome.status === "not-done") {
    return "not done: " + outcome.reason;
  }
  if (outcome.status === "repair") {
    return "repair " + outcome.sidekickId + " (" + outcome.kind + ")";
  }
  return outcome.tool + " " + JSON.stringify(outcome.input);
}

function formatRunSection(run) {
  const summary = run.summary;
  const lines = [
    "## " + run.model + ", reasoning " + run.reasoning,
    "",
    "| Measure | Value |",
    "|---|---|",
    "| Sentences | " + summary.total + " |",
    "| Right outcome (pass) | " + percent(summary.passRate) + " |",
    "| Done cases: right tool, arguments and when | " + percent(summary.doneRate) + " |",
    "| Repair cases: sent to the right Sidekick | " + percent(summary.repairRate) + " |",
    "| Not-done cases: nothing changed | " + percent(summary.notDoneRate) + " |",
    "| Not-done cases with the expected reason | " + percent(summary.notDoneReasonRate) + " |",
    "| Title or name as expected | " + percent(summary.titleRate) + " |",
    "| Wrong action taken (changed or sent when it should not) | " + summary.wrongActions + " |",
    "| Calls failed (HTTP, timeout) | " + summary.errors + " |",
    "| Calls tried a second time | " + summary.retried + " |",
    "| Latency p50 / p95 | " + formatMs(summary.p50Ms) + " / " + formatMs(summary.p95Ms) + " |",
    "| Cost, total / per sentence | $" + summary.totalCost.toFixed(4) + " / $" + summary.costPerSentence.toFixed(6) + " |",
    "",
  ];
  const failures = [];
  for (const result of run.results) {
    if (!result.score.pass || !result.score.title) {
      failures.push(result);
    }
  }
  if (failures.length > 0) {
    lines.push("| Case | Sentence | Wrong | Got |", "|---|---|---|---|");
    for (const failure of failures) {
      // A pipe inside the cell would end it
      const got = describeOutcome(failure.outcome);
      const gotCell = got.replaceAll("|", "/");
      lines.push("| " + failure.id + " | " + failure.say + " | " + failure.score.wrongFields.join(", ") + " | " + gotCell + " |");
    }
    lines.push("");
  }
  return lines.join("\n");
}

export function formatReport(runs, startedAtIso) {
  const sections = ["# jess router golden-set eval", "", "Run " + startedAtIso + ". The founder sets the bar to ship.", ""];
  for (const run of runs) {
    sections.push(formatRunSection(run));
  }
  return sections.join("\n");
}

/* ---------- Command line ---------- */

export function parseArgs(argv) {
  const options = { reasoning: "off", limit: null, concurrency: 4, only: null, out: null, timeoutMs: CALL_TIMEOUT_MS };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (flag === "--reasoning") {
      options.reasoning = value;
    } else if (flag === "--limit") {
      options.limit = Number(value);
    } else if (flag === "--concurrency") {
      options.concurrency = Number(value);
    } else if (flag === "--only") {
      options.only = value;
    } else if (flag === "--out") {
      options.out = value;
    } else if (flag === "--timeout") {
      options.timeoutMs = Number(value) * 1000;
    } else {
      throw new Error("unknown option " + flag);
    }
    index += 1;
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

export async function main(argv, environment, fetchImpl) {
  const options = parseArgs(argv);
  const apiKey = environment.OPENROUTER_API_KEY;
  if (!apiKey) {
    throw new Error("OPENROUTER_API_KEY is not set");
  }
  const startedAtIso = new Date().toISOString();
  const golden = loadGolden();
  const cases = selectCases(golden, options);
  const modes = options.reasoning === "both" ? ["off", "low"] : [options.reasoning];
  const runs = [];
  for (const reasoning of modes) {
    const run = await runEval({ golden, reasoning, apiKey, fetchImpl, concurrency: options.concurrency, cases, timeoutMs: options.timeoutMs });
    runs.push(run);
  }
  const stamp = startedAtIso.replace(/[:.]/g, "-");
  const prefix = options.out ?? "jess-eval-" + stamp;
  writeFileSync(prefix + ".md", formatReport(runs, startedAtIso));
  writeFileSync(prefix + ".json", JSON.stringify({ startedAt: startedAtIso, runs }, null, 2));
  return { prefix, runs };
}

const isDirectRun = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isDirectRun) {
  try {
    const finished = await main(process.argv.slice(2), process.env, fetch);
    for (const run of finished.runs) {
      const summary = run.summary;
      console.log("reasoning " + run.reasoning + ": pass " + percent(summary.passRate) + ", wrong actions " + summary.wrongActions + ", p50 " + formatMs(summary.p50Ms) + ", p95 " + formatMs(summary.p95Ms) + ", $" + summary.totalCost.toFixed(4));
    }
    console.log("report: " + finished.prefix + ".md");
  } catch (error) {
    console.error(String(error && error.message));
    process.exitCode = 1;
  }
}
