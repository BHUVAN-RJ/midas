// The sort step's model calls (repair lanes W2, founder 2026-11-13; docs/briefs/repair-lanes.md).
// Jev 1.14 (TypeSafe, through OpenRouter's Decisions API) reads the words and the drawing outline
// and picks a lane plus the likely card guesses. When Jev's confidence is below 0.7, Claude Haiku
// 5.5 (OpenRouter Chat Completions) decides with the same lanes and writes up to 3 guesses.
// Any timeout or error sends the request to `code`: up a lane, never down.
//
// This file imports nothing, so backend/scripts/sort-bench.mjs can load it with plain node and
// benchmark the exact code the Worker runs. Keep it free of imports and of TypeScript-only syntax
// node cannot strip (enums, namespaces, parameter properties).

export const JEV_MODEL = "typesafe/jev-1.14";
export const HAIKU_MODEL = "anthropic/claude-haiku-5.5";
export const DECISIONS_URL = "https://openrouter.ai/api/alpha/decisions";
export const CHAT_URL = "https://openrouter.ai/api/v1/chat/completions";
// Below this, Jev's lane is checked by Haiku (founder, 2026-11-13).
export const CONFIDENCE_FLOOR = 0.7;
// The lane every failure goes to.
export const FALLBACK_LANE = "code";

// Mutable so tests can shorten the wait; the Worker uses 6 s per call (brief W2).
export const sortCallSettings = { timeoutMs: 6000 };

export const LANE_IDS = ["ask_back", "not_a_request", "shell_cant", "jess_command", "setting", "look", "code"] as const;
export type Lane = (typeof LANE_IDS)[number];

// The lanes, worded exactly as in the 2026-11-13 benchmark (45/46 right). Changing a word here
// changes what the model answers: re-run scripts/sort-bench.mjs before and after.
export const LANES: Record<Lane, string> = {
  ask_back: "The person wants something changed, but the words and drawing do not say what it should become. Ask one question.",
  not_a_request: "Chat, a greeting, an apology, an insult or an accidental recording. Nothing to change.",
  shell_cant:
    "Needs something the page cannot do: a notification type (Time Sensitive, custom sound), phone sensors (gyroscope, camera), reminders more often than every 2 hours, Siri, Watch, Lock Screen.",
  jess_command: "Asks to do something with their data (add a reminder, log water, tick a to-do), not to change the app.",
  setting: "A look or visibility change of something already there: colour, size, show or hide, a date format, on or off.",
  look: "A small layout tweak no simple setting covers: spacing, padding, shape, position.",
  code: "A new feature, a new option, changed behaviour, or a bug to fix.",
};

export const GUESS_IDS = ["other_icon", "smaller", "bigger", "other_colour", "remove", "move", "other_words", "other_layout"] as const;
export type GuessId = (typeof GUESS_IDS)[number];

// What the card guesses can be, worded as in the benchmark (the model reads these).
export const GUESSES: Record<GuessId, string> = {
  other_icon: "A different icon or picture",
  smaller: "Make it smaller",
  bigger: "Make it bigger",
  other_colour: "A different colour",
  remove: "Remove or hide it",
  move: "Move it somewhere else",
  other_words: "Different words",
  other_layout: "A different shape or layout",
};

export type SortInput = {
  transcript: string;
  sidekickName: string;
  sidekickDescription: string | null;
  // The drawing in words: stroke count and the box it covers (describeStrokes).
  drawing: string;
  // The person's answer to the ask-back card, when this is a second sort of the same request.
  answer: string | null;
};

export type SortResult = {
  lane: Lane;
  // Jev's confidence in its lane (0..1); null when Jev gave no answer.
  confidence: number | null;
  // "typesafe/jev-1.14", or "typesafe/jev-1.14+anthropic/claude-haiku-5.5" when Haiku decided.
  model: string;
  // Card guesses, most likely first, at most 3.
  guesses: GuessId[];
  latencyMs: number;
  costUsd: number;
  // Why the request went to code without a model's say: "jev: timeout", "haiku: HTTP 500", ...
  error: string | null;
};

type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

const MAX_GUESSES = 3;

export function isLane(value: unknown): value is Lane {
  return typeof value === "string" && (LANE_IDS as readonly string[]).includes(value);
}

export function isGuessId(value: unknown): value is GuessId {
  return typeof value === "string" && (GUESS_IDS as readonly string[]).includes(value);
}

/* ---------- The drawing outline ---------- */

type Point = number[];

function isPoint(value: unknown): value is Point {
  return Array.isArray(value) && value.length >= 2 && typeof value[0] === "number" && typeof value[1] === "number";
}

// Where the drawing is, in words: number of strokes and the box they cover on the phone's screen.
// Strokes are the phone's JSON: [[[x, y, t], ...], ...]. No picture is sent (founder, 2026-11-13).
export function describeStrokes(strokesJson: string | null): string {
  if (strokesJson === null) {
    return "no drawing";
  }
  let strokes: unknown;
  try {
    strokes = JSON.parse(strokesJson);
  } catch {
    return "no drawing";
  }
  if (!Array.isArray(strokes)) {
    return "no drawing";
  }
  const xs: number[] = [];
  const ys: number[] = [];
  for (const stroke of strokes) {
    if (!Array.isArray(stroke)) {
      continue;
    }
    for (const point of stroke) {
      if (isPoint(point)) {
        xs.push(point[0]);
        ys.push(point[1]);
      }
    }
  }
  if (xs.length === 0) {
    return "no drawing (empty)";
  }
  const left = Math.round(Math.min(...xs));
  const right = Math.round(Math.max(...xs));
  const top = Math.round(Math.min(...ys));
  const bottom = Math.round(Math.max(...ys));
  return `${strokes.length} stroke(s) covering x ${left}–${right}, y ${top}–${bottom} on a 402×874 screen`;
}

/* ---------- The state both models read ---------- */

export function stateText(input: SortInput): string {
  const description = input.sidekickDescription === null ? "" : ` (${input.sidekickDescription})`;
  const sidekick = `${input.sidekickName}${description}`;
  const said = `A person is using the Midas app "${sidekick}". They opened repair mode, may have drawn on the screen, and said: "${input.transcript}". Drawing: ${input.drawing}.`;
  if (input.answer === null) {
    return said;
  }
  // The second sort: the answer to the card joins the same request.
  return `${said} Asked "What should it be?", they answered: "${input.answer}".`;
}

export function buildJevRequest(input: SortInput): Record<string, unknown> {
  return {
    model: JEV_MODEL,
    state: stateText(input),
    questions: {
      lane: { type: "choice", instructions: "What should happen with this repair request?", criteria: LANES },
      guess: { type: "choice", instructions: "If the person wants something changed but did not say into what, what most likely?", criteria: GUESSES },
    },
  };
}

function laneLines(): string {
  const lines: string[] = [];
  for (const laneId of LANE_IDS) {
    lines.push(`- ${laneId}: ${LANES[laneId]}`);
  }
  return lines.join("\n");
}

function guessLines(): string {
  const lines: string[] = [];
  for (const guessId of GUESS_IDS) {
    lines.push(`- ${guessId}: ${GUESSES[guessId]}`);
  }
  return lines.join("\n");
}

export function buildHaikuRequest(input: SortInput): Record<string, unknown> {
  const instructions =
    `${stateText(input)}\n\nPick the lane:\n${laneLines()}` +
    `\n\nAlso pick up to 3 likely guesses for what they want, from:\n${guessLines()}` +
    `\n\nAnswer only JSON: {"lane": "...", "guesses": ["..."]}`;
  return {
    model: HAIKU_MODEL,
    max_tokens: 2000,
    messages: [{ role: "user", content: instructions }],
    response_format: { type: "json_object" },
    reasoning: { effort: "low", exclude: true },
    usage: { include: true },
  };
}

/* ---------- One call, with the 6 s limit ---------- */

type CallOutcome = { json: Record<string, unknown> | null; error: string | null; ms: number };

// POSTs JSON to OpenRouter; never throws. A timeout, a network error, a non-2xx answer or a body
// that is not JSON comes back as an error in words.
async function postJson(fetchImpl: FetchLike, url: string, apiKey: string, body: Record<string, unknown>): Promise<CallOutcome> {
  const controller = new AbortController();
  function abortCall() {
    controller.abort();
  }
  const timer = setTimeout(abortCall, sortCallSettings.timeoutMs);
  const startedAt = Date.now();
  try {
    const response = await fetchImpl(url, {
      method: "POST",
      headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json", "x-title": "Midas repair sort" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      return { json: null, error: `HTTP ${response.status}`, ms: Date.now() - startedAt };
    }
    const json = (await response.json()) as Record<string, unknown>;
    return { json, error: null, ms: Date.now() - startedAt };
  } catch (error) {
    const timedOut = controller.signal.aborted;
    const reason = timedOut ? "timeout" : error instanceof Error ? error.message.slice(0, 120) : "network";
    return { json: null, error: reason, ms: Date.now() - startedAt };
  } finally {
    clearTimeout(timer);
  }
}

function costOf(json: Record<string, unknown> | null): number {
  const usage = json?.usage as { cost?: unknown } | undefined;
  return typeof usage?.cost === "number" ? usage.cost : 0;
}

/* ---------- Reading the answers ---------- */

type JevAnswer = { lane: Lane; confidence: number; guesses: GuessId[] };

function compareByProbability(probabilities: Record<string, number>) {
  return function byProbabilityDescending(left: string, right: string): number {
    return probabilities[right] - probabilities[left];
  };
}

// Guess ids ordered by Jev's probability, best first; unknown ids are dropped.
export function rankedGuesses(probabilities: unknown): GuessId[] {
  if (typeof probabilities !== "object" || probabilities === null) {
    return [];
  }
  const table = probabilities as Record<string, number>;
  const knownIds = Object.keys(table).filter(isGuessId);
  knownIds.sort(compareByProbability(table));
  return knownIds;
}

export function readJevAnswer(json: Record<string, unknown> | null): JevAnswer | null {
  const answers = json?.answers as Record<string, { choice?: unknown; confidence?: unknown; probabilities?: unknown }> | undefined;
  const laneAnswer = answers?.lane;
  if (laneAnswer === undefined || !isLane(laneAnswer.choice) || typeof laneAnswer.confidence !== "number") {
    return null;
  }
  const guessAnswer = answers?.guess;
  const guesses = rankedGuesses(guessAnswer?.probabilities);
  return { lane: laneAnswer.choice, confidence: laneAnswer.confidence, guesses };
}

type HaikuAnswer = { lane: Lane; guesses: GuessId[] };

// Haiku answers JSON text; some providers put it in the reasoning field only.
export function readHaikuAnswer(json: Record<string, unknown> | null): HaikuAnswer | null {
  const choices = json?.choices as Array<{ message?: { content?: unknown; reasoning?: unknown } }> | undefined;
  const message = choices?.[0]?.message;
  const content = typeof message?.content === "string" && message.content.length > 0 ? message.content : message?.reasoning;
  if (typeof content !== "string") {
    return null;
  }
  const jsonText = content.slice(content.indexOf("{"), content.lastIndexOf("}") + 1);
  let parsed: { lane?: unknown; guesses?: unknown };
  try {
    parsed = JSON.parse(jsonText);
  } catch {
    return null;
  }
  if (!isLane(parsed.lane)) {
    return null;
  }
  const rawGuesses = Array.isArray(parsed.guesses) ? parsed.guesses : [];
  const guesses = rawGuesses.filter(isGuessId).slice(0, MAX_GUESSES);
  return { lane: parsed.lane, guesses };
}

// Haiku's guesses first, then Jev's, no repeats, at most 3.
function mergeGuesses(first: GuessId[], second: GuessId[]): GuessId[] {
  const merged: GuessId[] = [];
  for (const guessId of first.concat(second)) {
    if (!merged.includes(guessId) && merged.length < MAX_GUESSES) {
      merged.push(guessId);
    }
  }
  return merged;
}

/* ---------- The sort ---------- */

// Jev first; Haiku when Jev is unsure. Never throws; every failure is lane `code`.
export async function sortRequest(input: SortInput, apiKey: string | undefined, fetchImpl: FetchLike): Promise<SortResult> {
  if (apiKey === undefined || apiKey.length === 0) {
    return { lane: FALLBACK_LANE, confidence: null, model: "none", guesses: [], latencyMs: 0, costUsd: 0, error: "no OPENROUTER_API_KEY" };
  }
  const jevCall = await postJson(fetchImpl, DECISIONS_URL, apiKey, buildJevRequest(input));
  const jevAnswer = readJevAnswer(jevCall.json);
  const jevCost = costOf(jevCall.json);
  if (jevAnswer === null) {
    const jevError = jevCall.error ?? "unreadable answer";
    return { lane: FALLBACK_LANE, confidence: null, model: JEV_MODEL, guesses: [], latencyMs: jevCall.ms, costUsd: jevCost, error: `jev: ${jevError}` };
  }
  const jevTopGuesses = jevAnswer.guesses.slice(0, MAX_GUESSES);
  if (jevAnswer.confidence >= CONFIDENCE_FLOOR) {
    return { lane: jevAnswer.lane, confidence: jevAnswer.confidence, model: JEV_MODEL, guesses: jevTopGuesses, latencyMs: jevCall.ms, costUsd: jevCost, error: null };
  }

  const haikuCall = await postJson(fetchImpl, CHAT_URL, apiKey, buildHaikuRequest(input));
  const haikuAnswer = readHaikuAnswer(haikuCall.json);
  const bothModels = `${JEV_MODEL}+${HAIKU_MODEL}`;
  const latencyMs = jevCall.ms + haikuCall.ms;
  const costUsd = jevCost + costOf(haikuCall.json);
  if (haikuAnswer === null) {
    const haikuError = haikuCall.error ?? "unreadable answer";
    return { lane: FALLBACK_LANE, confidence: jevAnswer.confidence, model: bothModels, guesses: jevTopGuesses, latencyMs, costUsd, error: `haiku: ${haikuError}` };
  }
  const guesses = mergeGuesses(haikuAnswer.guesses, jevAnswer.guesses);
  return { lane: haikuAnswer.lane, confidence: jevAnswer.confidence, model: bothModels, guesses, latencyMs, costUsd, error: null };
}
